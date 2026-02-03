"""
Job Queue con limiti di concorrenza per SyncAgent
Max 4 job simultanei, max 2 per direzione (upload/download)
"""

import asyncio
from dataclasses import dataclass
from enum import Enum
from typing import Callable, Any, Optional
from datetime import datetime


class JobDirection(Enum):
    UPLOAD = "upload"      # Verso Vault (import da FS Legacy)
    DOWNLOAD = "download"  # Da Vault (export verso FS Legacy)


@dataclass
class Job:
    id: str
    type: str
    direction: JobDirection
    payload: dict
    priority: int = 0
    created_at: datetime = None
    
    def __post_init__(self):
        if self.created_at is None:
            self.created_at = datetime.now()
    
    @property
    def is_upload(self) -> bool:
        return self.direction == JobDirection.UPLOAD


class JobQueue:
    """
    Gestisce coda job con limiti:
    - Max 4 job simultanei totali
    - Max 2 upload (verso Vault)
    - Max 2 download (da Vault)
    """
    
    def __init__(
        self,
        max_concurrent: int = 4,
        max_upload: int = 2,
        max_download: int = 2
    ):
        self.max_concurrent = max_concurrent
        self.max_upload = max_upload
        self.max_download = max_download
        
        # Semafori per controllo concorrenza
        self.total_sem = asyncio.Semaphore(max_concurrent)
        self.upload_sem = asyncio.Semaphore(max_upload)
        self.download_sem = asyncio.Semaphore(max_download)
        
        # Tracking
        self._active_jobs: dict[str, Job] = {}
        self._queue: list[Job] = []
        self._lock = asyncio.Lock()
    
    @property
    def active_count(self) -> int:
        return len(self._active_jobs)
    
    @property
    def queue_size(self) -> int:
        return len(self._queue)
    
    @property
    def upload_count(self) -> int:
        return sum(1 for j in self._active_jobs.values() if j.is_upload)
    
    @property
    def download_count(self) -> int:
        return sum(1 for j in self._active_jobs.values() if not j.is_upload)
    
    async def enqueue(self, job: Job):
        """Aggiunge job alla coda (ordinata per priorità)"""
        async with self._lock:
            self._queue.append(job)
            self._queue.sort(key=lambda j: -j.priority)  # Alta priorità prima
    
    async def execute(self, job: Job, handler: Callable[[Job], Any]) -> Any:
        """
        Esegue job rispettando i limiti di concorrenza.
        Blocca finché non c'è uno slot disponibile.
        """
        direction_sem = self.upload_sem if job.is_upload else self.download_sem
        
        # Acquisisci slot totale
        async with self.total_sem:
            # Acquisisci slot direzione
            async with direction_sem:
                # Traccia job attivo
                self._active_jobs[job.id] = job
                
                try:
                    result = await handler(job)
                    return result
                finally:
                    # Rimuovi da attivi
                    self._active_jobs.pop(job.id, None)
    
    async def execute_with_retry(
        self,
        job: Job,
        handler: Callable[[Job], Any],
        max_retries: int = 3,
        retry_delay: float = 5.0
    ) -> tuple[bool, Any]:
        """Esegue job con retry automatico"""
        last_error = None
        
        for attempt in range(max_retries):
            try:
                result = await self.execute(job, handler)
                return True, result
            except Exception as e:
                last_error = e
                if attempt < max_retries - 1:
                    await asyncio.sleep(retry_delay * (attempt + 1))
        
        return False, last_error
    
    def can_accept(self, direction: JobDirection) -> bool:
        """Verifica se c'è spazio per un nuovo job"""
        if self.active_count >= self.max_concurrent:
            return False
        
        if direction == JobDirection.UPLOAD:
            return self.upload_count < self.max_upload
        else:
            return self.download_count < self.max_download
    
    def get_status(self) -> dict:
        """Restituisce stato attuale della coda"""
        return {
            "active": self.active_count,
            "queued": self.queue_size,
            "uploads": self.upload_count,
            "downloads": self.download_count,
            "max_concurrent": self.max_concurrent,
            "max_upload": self.max_upload,
            "max_download": self.max_download
        }
