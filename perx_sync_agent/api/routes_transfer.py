from __future__ import annotations

from datetime import datetime
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import FileResponse
from starlette.background import BackgroundTask

from api import get_filesystem_service, get_registry
from models import ClaimMetadataResponse, GenericResponse
from services.auth_service import get_token
from services.filesystem_service import FilesystemService
from services.monitoring_registry import MonitoringRegistry

router = APIRouter(prefix="/api/claims", tags=["transfer"])


def _safe_join_under_root(root: Path, rel: str) -> Path:
    """
    Normalizza un path relativo (query param) e impedisce path traversal.
    Ritorna un Path risolto, garantito sotto root.
    """
    normalized = str(rel).replace("\\", "/").lstrip("/")
    safe_rel = Path(*[p for p in normalized.split("/") if p not in ("", ".", "..")])
    if safe_rel.as_posix() in ("", "."):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Percorso file non valido")

    root_resolved = root.resolve()
    target = (root / safe_rel).resolve()

    try:
        target.relative_to(root_resolved)
    except ValueError:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Accesso negato")

    return target


@router.get("/{claim_id}/metadata", response_model=ClaimMetadataResponse)
def metadata(
    claim_id: str,
    user_id: str,
    token: str = Depends(get_token),
    registry: MonitoringRegistry = Depends(get_registry),
    fs_service: FilesystemService = Depends(get_filesystem_service),
):
    entry = registry.get(user_id, claim_id)
    if not entry:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Sinistro non monitorato")
    return fs_service.scan_metadata(entry)


@router.get("/{claim_id}/download")
def download(
    claim_id: str,
    user_id: str,
    file: Optional[str] = None,  # se presente, download file singolo
    token: str = Depends(get_token),
    registry: MonitoringRegistry = Depends(get_registry),
    fs_service: FilesystemService = Depends(get_filesystem_service),
):
    entry = registry.get(user_id, claim_id)
    if not entry:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Sinistro non monitorato")

    root = Path(entry.root_path)

    # Header utili contro proxy/trasformazioni (rari, ma quando succedono “corrompono”)
    common_headers = {
        "Cache-Control": "no-store, no-transform",
        "Pragma": "no-cache",
    }

    # 1) Download file singolo
    if file:
        file_path = _safe_join_under_root(root, file)

        if not file_path.exists() or not file_path.is_file():
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="File non trovato")

        registry.update_last_sync(user_id, claim_id, when=datetime.utcnow())

        # Determina media_type basato sull'estensione per file comuni
        media_type = "application/octet-stream"
        suffix_lower = file_path.suffix.lower()
        if suffix_lower in (".jpg", ".jpeg"):
            media_type = "image/jpeg"
        elif suffix_lower == ".png":
            media_type = "image/png"
        elif suffix_lower == ".pdf":
            media_type = "application/pdf"
        elif suffix_lower in (".gif", ".bmp", ".tiff", ".webp"):
            media_type = f"image/{suffix_lower[1:]}"

        # FileResponse gestisce Content-Length e invio stabile
        # Usa mode="rb" implicitamente per garantire lettura binaria
        return FileResponse(
            path=str(file_path),
            filename=file_path.name,
            media_type=media_type,
            headers={
                **common_headers,
                "Content-Length": str(file_path.stat().st_size),
            },
        )

    # 2) Download ZIP completo
    zip_path, _iterator = fs_service.create_zip_stream(entry)
    registry.update_last_sync(user_id, claim_id, when=datetime.utcnow())

    # Cleanup dopo che la response è terminata (anche con proxy/buffer)
    def _cleanup_zip(p: Path) -> None:
        try:
            # zip_path è in una temp dir; filesystem_service già mette lo zip lì
            # Qui cancelliamo sia lo zip che la cartella padre.
            parent = p.parent
            try:
                p.unlink(missing_ok=True)
            except Exception:
                pass
            try:
                # rimuove la temp dir che contiene lo zip
                import shutil
                shutil.rmtree(parent, ignore_errors=True)
            except Exception:
                pass
        except Exception:
            pass

    task = BackgroundTask(_cleanup_zip, zip_path)

    return FileResponse(
        path=str(zip_path),
        filename=f"{claim_id}.zip",
        media_type="application/zip",
        headers=common_headers,
        background=task,
    )


@router.delete("/{claim_id}/files", response_model=GenericResponse)
def delete_file(
    claim_id: str,
    user_id: str,
    file: str,
    token: str = Depends(get_token),
    registry: MonitoringRegistry = Depends(get_registry),
    fs_service: FilesystemService = Depends(get_filesystem_service),
):
    """Elimina un file dalla cartella del sinistro. Usato per sincronizzare eliminazioni locali."""
    entry = registry.get(user_id, claim_id)
    if not entry:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Sinistro non monitorato")
    root = Path(entry.root_path)
    target = _safe_join_under_root(root, file)
    if not target.is_file():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="File non trovato")
    try:
        target.unlink(missing_ok=True)
    except OSError as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))
    return GenericResponse(success=True, message="File eliminato", details=None)