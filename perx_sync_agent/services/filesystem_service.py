from __future__ import annotations

import hashlib
import shutil
import tempfile
import zipfile
from datetime import datetime
from pathlib import Path
from typing import Dict, Iterable, Tuple, List

from fastapi import UploadFile
from models import ClaimId, ClaimFileEntry, ClaimMetadataResponse, MonitoringEntry, UserId


class FilesystemService:
    """Operazioni su filesystem del gestionale."""

    def __init__(self, root_path: Path, user_mapping: Dict[str, str]):
        self.root_path = Path(root_path)
        self.user_mapping = user_mapping or {}

    def resolve_claim_path(self, user_id: UserId, claim_id: ClaimId, path_hint: str | None = None) -> Path:
        base = self.user_mapping.get(user_id, "")
        candidate = self.root_path / base / claim_id
        if path_hint:
            candidate = self.root_path / base / path_hint
        return candidate.resolve()

    def ensure_claim_dir(self, path: Path) -> None:
        path.mkdir(parents=True, exist_ok=True)

    def scan_metadata(self, entry: MonitoringEntry) -> ClaimMetadataResponse:
        total_files = 0
        total_bytes = 0
        directory_count = 0
        files: List[ClaimFileEntry] = []
        directories: List[str] = []

        root = Path(entry.root_path)
        if not root.exists():
            self.ensure_claim_dir(root)

        for item in root.rglob("*"):
            if item.is_dir():
                directory_count += 1
                try:
                    rel = item.relative_to(root).as_posix()
                    if rel and rel != ".":
                        directories.append(rel)
                except Exception:
                    pass
                continue

            try:
                st = item.stat()
            except OSError:
                continue

            total_files += 1
            total_bytes += int(st.st_size)

            try:
                rel_file = item.relative_to(root).as_posix()
            except Exception:
                rel_file = item.name

            # md5 a chunk (evita RAM alta su file grossi)
            md5 = hashlib.md5()
            try:
                with item.open("rb") as f:
                    for chunk in iter(lambda: f.read(1024 * 1024), b""):
                        md5.update(chunk)
                digest = md5.hexdigest()
            except OSError:
                digest = ""

            try:
                # Invia sempre con timezone UTC per compatibilità client Swift
                modified_at = datetime.utcfromtimestamp(st.st_mtime).replace(tzinfo=None)
                # Serializza come ISO8601 con Z (UTC)
                # Nota: Pydantic serializza datetime come ISO8601, ma senza timezone se tzinfo=None
                # Quindi aggiungiamo Z manualmente nella serializzazione o usiamo datetime.utcnow() con timezone
                from datetime import timezone
                modified_at = datetime.fromtimestamp(st.st_mtime, tz=timezone.utc)
            except Exception:
                modified_at = None

            files.append(
                ClaimFileEntry(
                    relativePath=rel_file,
                    size=int(st.st_size),
                    md5=digest,
                    modifiedAt=modified_at,
                )
            )

        relative_root = str(root.relative_to(self.root_path))
        return ClaimMetadataResponse(
            user_id=entry.user_id,
            claim_id=entry.claim_id,
            total_files=total_files,
            total_bytes=total_bytes,
            directory_count=directory_count,
            relative_root=relative_root,
            files=files,
            directories=directories,
        )

    def create_zip_stream(self, entry: MonitoringEntry) -> Tuple[Path, Iterable[bytes]]:
        """
        Crea un archivio zip temporaneo e restituisce path + generator per lo streaming.
        """
        root = Path(entry.root_path)
        if not root.exists():
            self.ensure_claim_dir(root)

        # Preferisci una temp directory locale e stabile su Windows, con fallback
        preferred_base = Path("C:/Temp/perx_sync")
        try:
            preferred_base.mkdir(parents=True, exist_ok=True)
            temp_base = preferred_base
        except OSError:
            temp_base = Path(tempfile.gettempdir()) / "perx_sync"
            temp_base.mkdir(parents=True, exist_ok=True)
        temp_dir = Path(tempfile.mkdtemp(prefix="perx_", dir=str(temp_base)))
        zip_path = temp_dir / f"{entry.claim_id}.zip"

        with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_STORED) as zipf:
            for file_path in root.rglob("*"):
                if file_path.is_file():
                    arcname = file_path.relative_to(root)
                    zipf.write(file_path, arcname.as_posix())

        def iterator(chunk_size: int = 1024 * 1024 * 4) -> Iterable[bytes]:
            try:
                with zip_path.open("rb") as f:
                    while True:
                        chunk = f.read(chunk_size)
                        if not chunk:
                            break
                        yield chunk
            finally:
                # Cleanup sempre, anche se il client interrompe lo streaming (GeneratorExit)
                try:
                    zip_path.unlink(missing_ok=True)
                except OSError:
                    pass
                try:
                    shutil.rmtree(temp_dir, ignore_errors=True)
                except OSError:
                    pass

        return zip_path, iterator()

    async def save_uploads(self, entry: MonitoringEntry, files: Iterable[UploadFile], subpath: str | None = None) -> Dict[str, str]:
        """
        Salva i file caricati rispettando eventuale sottocartella.
        Ritorna mappa filename -> path salvato.
        """
        root = Path(entry.root_path)
        self.ensure_claim_dir(root)
        dest_base = root / subpath if subpath else root
        dest_base.mkdir(parents=True, exist_ok=True)

        saved: Dict[str, str] = {}
        for upload in files:
            if upload.filename is None:
                continue

            # Supporta path relativi e previene traversal.
            normalized = upload.filename.replace("\\", "/").lstrip("/")
            safe_rel = Path(*[p for p in normalized.split("/") if p not in ("", ".", "..")])
            if safe_rel.as_posix() in ("", "."):
                continue

            target = dest_base / safe_rel
            try:
                dest_resolved = dest_base.resolve()
                target_resolved = target.resolve()
                if not str(target_resolved).startswith(str(dest_resolved)):
                    continue
            except Exception:
                continue

            target.parent.mkdir(parents=True, exist_ok=True)

            # Scrittura a chunk (evita caricare interi PDF/JPG in RAM).
            with target.open("wb") as f:
                while True:
                    chunk = await upload.read(1024 * 1024)  # 1MB
                    if not chunk:
                        break
                    f.write(chunk)
            try:
                await upload.close()
            except Exception:
                pass

            saved[upload.filename] = str(target)
        return saved

    def ensure_directories(self, entry: MonitoringEntry, directories: List[str], subpath: str | None = None) -> Dict[str, str]:
        """
        Crea directory (incluse vuote) sotto la root del sinistro.
        Ritorna mappa input_dir -> path creato.
        """
        root = Path(entry.root_path)
        self.ensure_claim_dir(root)
        dest_base = root / subpath if subpath else root
        dest_base.mkdir(parents=True, exist_ok=True)

        created: Dict[str, str] = {}
        for d in directories or []:
            if not d:
                continue
            normalized = str(d).replace("\\", "/").strip().lstrip("/")
            safe_rel = Path(*[p for p in normalized.split("/") if p not in ("", ".", "..")])
            if safe_rel.as_posix() in (".", ""):
                continue

            target = dest_base / safe_rel
            try:
                dest_resolved = dest_base.resolve()
                target_resolved = target.resolve()
                if not str(target_resolved).startswith(str(dest_resolved)):
                    continue
            except Exception:
                continue

            target.mkdir(parents=True, exist_ok=True)
            created[d] = str(target)

        return created

