"""
Hub Worker Service - v2
Worker passivo che interroga l'Hub per job da eseguire.
Integra coda job con limiti di concorrenza e scansioni periodiche.
"""

import os
import json
import asyncio
import base64
import hashlib
import logging
from datetime import datetime
from pathlib import Path
from typing import Optional, Dict, Any, List

import httpx

from .job_queue import JobQueue, Job, JobDirection
from .filesystem_service import FilesystemService


class HubWorkerService:
    """
    Worker passivo per l'Hub centralizzato.
    
    Funzionamento:
    1. Poll periodico per job pendenti
    2. Esecuzione job con coda e limiti concorrenza
    3. Scansioni periodiche cartelle attive (ogni 4 ore)
    4. Report completamento/errore all'Hub
    """
    
    POLL_INTERVAL = 10  # secondi tra poll job
    
    # Path consentiti per operazioni file (configurabili)
    ALLOWED_BASE_PATHS: List[str] = []
    
    def __init__(
        self,
        hub_url: str,
        filesystem_service: FilesystemService,
        job_queue: JobQueue,
        logger: logging.Logger,
        scan_interval: int = 4 * 60 * 60,  # 4 ore default
        allowed_paths: Optional[List[str]] = None
    ):
        self.hub_url = hub_url.rstrip('/')
        self.filesystem_service = filesystem_service
        self.job_queue = job_queue
        self.logger = logger
        self.scan_interval = scan_interval
        
        # Configura path consentiti
        if allowed_paths:
            self.ALLOWED_BASE_PATHS = [str(Path(p).resolve()) for p in allowed_paths]
        
        self._running = False
        self._client: Optional[httpx.AsyncClient] = None
    
    def _validate_path(self, path_str: str) -> Path:
        """
        Valida un path per prevenire path traversal e accesso a directory non autorizzate.
        
        Raises:
            ValueError: se il path contiene pattern pericolosi
            PermissionError: se il path è fuori dalle directory consentite
        """
        # Normalizza e risolvi il path
        try:
            path = Path(path_str).resolve()
        except Exception as e:
            raise ValueError(f"Path non valido: {path_str}") from e
        
        # Blocca pattern pericolosi
        dangerous_patterns = ['..', '~', '$', '`', ';', '|', '&', '\x00']
        for pattern in dangerous_patterns:
            if pattern in path_str:
                self.logger.warning(f"SECURITY: Path traversal attempt blocked: {path_str}")
                raise ValueError(f"Path contiene pattern non consentito: {pattern}")
        
        # Verifica che sia sotto uno dei path consentiti (se configurati)
        if self.ALLOWED_BASE_PATHS:
            path_resolved = str(path)
            is_allowed = any(
                path_resolved.startswith(allowed) 
                for allowed in self.ALLOWED_BASE_PATHS
            )
            if not is_allowed:
                self.logger.warning(f"SECURITY: Path access denied (not in allowed paths): {path_str}")
                raise PermissionError(f"Path non consentito: {path_str}")
        
        return path
    
    def _safe_relative_path(self, file_path: Path, base_path: Path) -> str:
        """Calcola path relativo in modo sicuro"""
        try:
            return str(file_path.relative_to(base_path))
        except ValueError:
            # File non è sotto base_path - possibile path traversal
            self.logger.warning(f"SECURITY: relative_to failed - {file_path} not under {base_path}")
            raise ValueError(f"File non sotto il path base: {file_path}")
        
    async def start(self):
        """Avvia il worker loop"""
        self._running = True
        self._client = httpx.AsyncClient(timeout=60.0)
        
        self.logger.info(f"Hub Worker started. Polling {self.hub_url}")
        
        # Avvia task paralleli
        await asyncio.gather(
            self._job_poll_loop(),
            self._periodic_scan_loop(),
            return_exceptions=True
        )
    
    async def stop(self):
        """Ferma il worker"""
        self._running = False
        if self._client:
            await self._client.aclose()
        self.logger.info("Hub Worker stopped")
    
    # MARK: - Main Loops
    
    async def _job_poll_loop(self):
        """Loop principale per polling job"""
        while self._running:
            try:
                await self._process_pending_jobs()
            except Exception as e:
                self.logger.error(f"Error in job poll loop: {e}")
            
            await asyncio.sleep(self.POLL_INTERVAL)
    
    async def _periodic_scan_loop(self):
        """Loop scansioni periodiche (ogni 4 ore)"""
        while self._running:
            try:
                await self._run_periodic_scans()
            except Exception as e:
                self.logger.error(f"Error in periodic scan: {e}")
            
            # Attendi intervallo scan
            await asyncio.sleep(self.scan_interval)
    
    # MARK: - Job Processing
    
    async def _process_pending_jobs(self):
        """Processa job pendenti dall'Hub"""
        try:
            # Richiedi max job in base alla capacità
            max_jobs = self.job_queue.max_concurrent - self.job_queue.active_count
            if max_jobs <= 0:
                return
            
            jobs = await self._get_pending_jobs(limit=max_jobs)
            
            if not jobs:
                return
            
            self.logger.info(f"Found {len(jobs)} pending jobs")
            
            # Avvia job in parallelo (rispettando limiti coda)
            tasks = []
            for job_data in jobs:
                if not self._running:
                    break
                
                # Determina direzione
                job_type = job_data.get('type', '')
                direction = JobDirection.UPLOAD if job_type in ['importFolder', 'importFile'] else JobDirection.DOWNLOAD
                
                job = Job(
                    id=job_data['id'],
                    type=job_type,
                    direction=direction,
                    payload=job_data.get('payload', {}),
                    priority=job_data.get('priority', 0)
                )
                
                # Esegui tramite coda
                task = asyncio.create_task(
                    self.job_queue.execute(job, self._execute_job_handler)
                )
                tasks.append(task)
            
            # Attendi completamento tutti i job
            if tasks:
                await asyncio.gather(*tasks, return_exceptions=True)
                
        except httpx.RequestError as e:
            self.logger.warning(f"Failed to fetch pending jobs: {e}")
    
    async def _execute_job_handler(self, job: Job):
        """Handler esecuzione singolo job"""
        self.logger.info(f"Executing job {job.id} (type: {job.type})")
        
        try:
            # Marca come in progress
            await self._start_job(job.id)
            
            # Parse payload
            payload = job.payload
            if isinstance(payload, str):
                payload = json.loads(payload)
            
            # Esegui in base al tipo
            if job.type == 'importFolder':
                await self._execute_import_folder(job.id, payload)
            elif job.type == 'importFile':
                await self._execute_import_file(job.id, payload)
            elif job.type == 'exportFile':
                await self._execute_export_file(job.id, payload)
            elif job.type == 'deleteFile':
                await self._execute_delete_file(job.id, payload)
            elif job.type == 'renameFile':
                await self._execute_rename_file(job.id, payload)
            elif job.type == 'scanLegacy':
                await self._execute_scan_legacy(job.id, payload)
            elif job.type == 'updateSyncAgent':
                await self._execute_update_sync_agent(job.id, payload)
            else:
                raise ValueError(f"Unknown job type: {job.type}")
            
            # Marca come completato
            await self._complete_job(job.id)
            self.logger.info(f"Job {job.id} completed successfully")
            
        except Exception as e:
            self.logger.error(f"Job {job.id} failed: {e}")
            await self._fail_job(job.id, str(e))
    
    # MARK: - Periodic Scans
    
    async def _run_periodic_scans(self):
        """Esegue scansioni periodiche sulle cartelle attive"""
        try:
            folders = await self._get_active_folders()
            
            if not folders:
                self.logger.debug("No active folders to scan")
                return
            
            self.logger.info(f"Starting periodic scan of {len(folders)} folders")
            
            for folder in folders:
                if not self._running:
                    break
                
                sinistro_ref = folder.get('sinistroRef')
                legacy_path = folder.get('legacyPath')
                
                if sinistro_ref and legacy_path:
                    try:
                        changes = await self._scan_folder(sinistro_ref, legacy_path)
                        if changes:
                            await self._report_changes_to_hub(sinistro_ref, changes)
                    except Exception as e:
                        self.logger.warning(f"Scan failed for {sinistro_ref}: {e}")
                
                # Pausa tra cartelle
                await asyncio.sleep(10)
            
            self.logger.info("Periodic scan completed")
            
        except Exception as e:
            self.logger.error(f"Error in periodic scans: {e}")
    
    async def _scan_folder(self, sinistro_ref: str, legacy_path: str) -> List[Dict]:
        """Scansiona una singola cartella e rileva cambiamenti"""
        path = Path(legacy_path)
        if not path.exists():
            return []
        
        files = []
        for root, dirs, filenames in os.walk(path):
            for filename in filenames:
                if filename.startswith('.'):
                    continue
                
                file_path = Path(root) / filename
                try:
                    stat = file_path.stat()
                    files.append({
                        'path': str(file_path),
                        'relativePath': str(file_path.relative_to(path)),
                        'size': stat.st_size,
                        'modifiedAt': datetime.fromtimestamp(stat.st_mtime).isoformat()
                    })
                except Exception:
                    pass
        
        return files
    
    async def _report_changes_to_hub(self, sinistro_ref: str, files: List[Dict]):
        """Invia risultato scansione all'Hub"""
        scan_result = {
            'sinistroRef': sinistro_ref,
            'scannedAt': datetime.now().isoformat(),
            'files': files
        }
        
        url = f"{self.hub_url}/syncagent/scan-result"
        response = await self._client.post(url, json=scan_result)
        response.raise_for_status()
        
        result = response.json()
        self.logger.info(f"Scan reported for {sinistro_ref}: {result.get('changes', 0)} changes detected")
    
    async def on_demand_scan(self, sinistro_ref: str, legacy_path: str) -> List[Dict]:
        """Scansione on-demand (chiamata da Hub o client)"""
        self.logger.info(f"On-demand scan requested for {sinistro_ref}")
        changes = await self._scan_folder(sinistro_ref, legacy_path)
        if changes:
            await self._report_changes_to_hub(sinistro_ref, changes)
        return changes
    
    # MARK: - Job Execution Methods
    
    async def _execute_import_folder(self, job_id: str, payload: Dict):
        """Import cartella sinistro da legacy a Vault"""
        data = payload.get('data', payload)
        sinistro_ref = data.get('sinistroRef')
        legacy_path_str = data.get('legacyPath')
        
        if not sinistro_ref or not legacy_path_str:
            raise ValueError("Missing sinistroRef or legacyPath")
        
        # Validazione sicurezza path
        legacy_path = self._validate_path(legacy_path_str)
        if not legacy_path.exists():
            raise FileNotFoundError(f"Legacy path not found: {legacy_path}")
        
        # Scansiona e carica tutti i file
        files_uploaded = 0
        for root, dirs, files in os.walk(legacy_path):
            for filename in files:
                if filename.startswith('.'):
                    continue
                
                file_path = Path(root) / filename
                relative_path = file_path.relative_to(legacy_path)
                folder = str(relative_path.parent) if relative_path.parent != Path('.') else 'documenti'
                
                try:
                    await self._upload_file_to_vault(job_id, sinistro_ref, folder, file_path)
                    files_uploaded += 1
                except Exception as e:
                    self.logger.warning(f"Failed to upload {file_path}: {e}")
        
        self.logger.info(f"Imported {files_uploaded} files for {sinistro_ref}")
    
    async def _execute_import_file(self, job_id: str, payload: Dict):
        """Import singolo file da legacy a Vault"""
        data = payload.get('data', payload)
        sinistro_ref = data.get('sinistroRef')
        legacy_path_str = data.get('legacyPath')
        target_folder = data.get('targetFolder', 'documenti')
        
        if not sinistro_ref or not legacy_path_str:
            raise ValueError("Missing sinistroRef or legacyPath")
        
        # Validazione sicurezza path
        file_path = self._validate_path(legacy_path_str)
        if not file_path.exists():
            raise FileNotFoundError(f"File not found: {legacy_path_str}")
        
        await self._upload_file_to_vault(job_id, sinistro_ref, target_folder, file_path)
    
    async def _execute_export_file(self, job_id: str, payload: Dict):
        """Export file da Vault a legacy"""
        data = payload.get('data', payload)
        vault_file_id = data.get('vaultFileId')
        legacy_path_str = data.get('legacyPath')
        
        if not vault_file_id or not legacy_path_str:
            raise ValueError("Missing vaultFileId or legacyPath")
        
        # Validazione sicurezza path
        dest_path = self._validate_path(legacy_path_str)
        
        # Scarica file dal Vault
        url = f"{self.hub_url}/vault/files/{vault_file_id}/download"
        response = await self._client.get(url)
        response.raise_for_status()
        
        # Crea directory se non esiste
        dest_path.parent.mkdir(parents=True, exist_ok=True)
        
        # Scrivi file
        with open(dest_path, 'wb') as f:
            f.write(response.content)
        
        # Registra nel manifest
        checksum = hashlib.sha256(response.content).hexdigest()
        await self._record_export(legacy_path, vault_file_id, checksum, len(response.content))
        
        self.logger.info(f"Exported {vault_file_id} to {legacy_path}")
    
    async def _execute_delete_file(self, job_id: str, payload: Dict):
        """Elimina file da legacy"""
        data = payload.get('data', payload)
        legacy_path_str = data.get('legacyPath')
        
        if not legacy_path_str:
            raise ValueError("Missing legacyPath")
        
        # Validazione sicurezza path
        file_path = self._validate_path(legacy_path_str)
        
        if file_path.exists():
            file_path.unlink()
            self.logger.info(f"Deleted {legacy_path_str}")
        else:
            self.logger.warning(f"File already deleted: {legacy_path_str}")
    
    async def _execute_rename_file(self, job_id: str, payload: Dict):
        """Rinomina file su legacy"""
        data = payload.get('data', payload)
        old_path_str = data.get('oldPath')
        new_path_str = data.get('newPath')
        
        if not old_path_str or not new_path_str:
            raise ValueError("Missing oldPath or newPath")
        
        # Validazione sicurezza path (entrambi i path)
        old_file = self._validate_path(old_path_str)
        new_file = self._validate_path(new_path_str)
        
        if not old_file.exists():
            raise FileNotFoundError(f"File not found: {old_path_str}")
        
        new_file.parent.mkdir(parents=True, exist_ok=True)
        old_file.rename(new_file)
        
        self.logger.info(f"Renamed {old_path} to {new_path}")
    
    async def _execute_scan_legacy(self, job_id: str, payload: Dict):
        """Scansiona cartella legacy e riporta cambiamenti"""
        data = payload.get('data', payload)
        sinistro_ref = data.get('sinistroRef')
        legacy_path = data.get('legacyPath')
        
        if not sinistro_ref or not legacy_path:
            raise ValueError("Missing sinistroRef or legacyPath")
        
        changes = await self._scan_folder(sinistro_ref, legacy_path)
        await self._report_changes_to_hub(sinistro_ref, changes)
    
    async def _execute_update_sync_agent(self, job_id: str, payload: Dict):
        """Riceve e salva file di aggiornamento del sync agent"""
        import shutil
        
        data = payload.get('data', payload)
        changed_files = data.get('changedFiles', [])
        source_base_path = data.get('sourceBasePath', '')
        target_install_path = data.get('targetInstallPath', '')
        
        if not target_install_path:
            # Usa la directory corrente come fallback
            target_install_path = str(Path(__file__).parent.parent)
        
        target_path = Path(target_install_path)
        target_path.mkdir(parents=True, exist_ok=True)
        
        self.logger.info(f"Updating sync agent: {len(changed_files)} files to {target_install_path}")
        
        files_updated = 0
        
        for file_rel_path in changed_files:
            try:
                # Scarica il file dall'Hub
                file_data = await self._download_update_file(file_rel_path)
                
                if file_data:
                    target_file = target_path / file_rel_path
                    target_file.parent.mkdir(parents=True, exist_ok=True)
                    
                    # Backup file esistente
                    if target_file.exists():
                        backup_file = target_file.with_suffix(target_file.suffix + '.bak')
                        shutil.copy(target_file, backup_file)
                        self.logger.debug(f"Backed up: {target_file} -> {backup_file}")
                    
                    # Scrivi il nuovo file
                    with open(target_file, 'wb') as f:
                        f.write(file_data)
                    
                    files_updated += 1
                    self.logger.debug(f"Updated file: {target_file}")
                    
            except Exception as e:
                self.logger.warning(f"Failed to update {file_rel_path}: {e}")
        
        self.logger.info(f"Sync agent update completed: {files_updated}/{len(changed_files)} files updated")
        
        # Notifica l'Hub che i file sono stati trasferiti
        await self._notify_update_complete(files_updated)
    
    async def _download_update_file(self, file_path: str) -> Optional[bytes]:
        """Scarica un file di aggiornamento dall'Hub"""
        try:
            url = f"{self.hub_url}/internal/updates/file"
            response = await self._client.get(url, params={'path': file_path})
            
            if response.status_code == 200:
                return response.content
            else:
                self.logger.warning(f"Failed to download update file {file_path}: {response.status_code}")
                return None
                
        except Exception as e:
            self.logger.error(f"Error downloading update file {file_path}: {e}")
            return None
    
    async def _notify_update_complete(self, files_count: int):
        """Notifica l'Hub che l'aggiornamento è stato completato"""
        try:
            url = f"{self.hub_url}/internal/updates/sync-agent-ready"
            response = await self._client.post(url, json={'files_updated': files_count})
            response.raise_for_status()
        except Exception as e:
            self.logger.warning(f"Failed to notify update complete: {e}")
    
    # MARK: - Hub API Helpers
    
    async def _get_pending_jobs(self, limit: int = 4) -> List[Dict]:
        """Ottiene job pendenti dall'Hub"""
        url = f"{self.hub_url}/jobs/pending?worker=syncagent&limit={limit}"
        response = await self._client.get(url)
        response.raise_for_status()
        return response.json()
    
    async def _get_active_folders(self) -> List[Dict]:
        """Ottiene lista cartelle attive da monitorare"""
        url = f"{self.hub_url}/syncagent/active-folders"
        response = await self._client.get(url)
        response.raise_for_status()
        return response.json()
    
    async def _start_job(self, job_id: str):
        """Marca job come in progress"""
        url = f"{self.hub_url}/jobs/{job_id}/start"
        response = await self._client.post(url)
        response.raise_for_status()
    
    async def _complete_job(self, job_id: str):
        """Marca job come completato"""
        url = f"{self.hub_url}/jobs/{job_id}/complete"
        response = await self._client.post(url)
        response.raise_for_status()
    
    async def _fail_job(self, job_id: str, message: str):
        """Marca job come fallito"""
        url = f"{self.hub_url}/jobs/{job_id}/fail"
        response = await self._client.post(url, json={'message': message})
        response.raise_for_status()
    
    async def _upload_file_to_vault(self, job_id: str, sinistro_ref: str, folder: str, file_path: Path):
        """Carica file nel Vault tramite l'Hub"""
        with open(file_path, 'rb') as f:
            data = f.read()
        
        payload = {
            'filename': file_path.name,
            'folder': folder,
            'data': base64.b64encode(data).decode('utf-8'),
            'mimeType': self._guess_mime_type(file_path.name)
        }
        
        url = f"{self.hub_url}/jobs/{job_id}/upload"
        response = await self._client.post(url, json=payload)
        response.raise_for_status()
        
        # Registra nel manifest
        checksum = hashlib.sha256(data).hexdigest()
        vault_file = response.json()
        await self._record_import(str(file_path), vault_file.get('id'), checksum, len(data), file_path.stat().st_mtime)
        
        return vault_file
    
    async def _record_import(self, legacy_path: str, vault_file_id: str, checksum: str, size: int, modified_at: float):
        """Registra import nel manifest"""
        url = f"{self.hub_url}/manifest/record-import"
        response = await self._client.post(url, json={
            'legacyPath': legacy_path,
            'vaultFileId': vault_file_id,
            'checksum': checksum,
            'size': size,
            'modifiedAt': datetime.fromtimestamp(modified_at).isoformat()
        })
        response.raise_for_status()
    
    async def _record_export(self, legacy_path: str, vault_file_id: str, checksum: str, size: int):
        """Registra export nel manifest"""
        url = f"{self.hub_url}/manifest/record-export"
        response = await self._client.post(url, json={
            'legacyPath': legacy_path,
            'vaultFileId': vault_file_id,
            'checksum': checksum,
            'size': size
        })
        response.raise_for_status()
    
    def _guess_mime_type(self, filename: str) -> str:
        """Indovina MIME type da estensione"""
        ext = filename.rsplit('.', 1)[-1].lower() if '.' in filename else ''
        mime_types = {
            'pdf': 'application/pdf',
            'doc': 'application/msword',
            'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            'xls': 'application/vnd.ms-excel',
            'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            'jpg': 'image/jpeg',
            'jpeg': 'image/jpeg',
            'png': 'image/png',
            'gif': 'image/gif',
            'txt': 'text/plain',
            'html': 'text/html',
            'zip': 'application/zip',
            'p7m': 'application/pkcs7-mime',
        }
        return mime_types.get(ext, 'application/octet-stream')
