"""
Vault binary storage adapter.

The cloud API remains the source of truth for metadata/audit, while the real
file content can live either on local disk (dev fallback) or on a Mac Mini NAS
reachable through a small internal HTTP API.
"""
from __future__ import annotations

import base64
import hashlib
import mimetypes
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import httpx

from app.core.config import settings


@dataclass
class StoredBlob:
    relative_path: str
    size_bytes: int
    checksum_sha256: str
    mime_type: Optional[str] = None


class VaultStorageService:
    @staticmethod
    def provider_name() -> str:
        provider = settings.VAULT_STORAGE_PROVIDER.strip().lower()
        return provider or "local"

    @staticmethod
    def storage_root() -> Path:
        root = settings.VAULT_STORAGE_ROOT.strip() or "/tmp/perx-hub-compat"
        path = Path(root)
        path.mkdir(parents=True, exist_ok=True)
        return path

    @staticmethod
    def build_relative_path(tenant_id: str, claim_ref: str, folder: str, file_name: str) -> str:
        clean_folder = folder.strip().strip("/")
        base = f"tenants/{tenant_id}/sinistri/{claim_ref}"
        return f"{base}/{clean_folder}/{file_name}" if clean_folder else f"{base}/{file_name}"

    @staticmethod
    def build_version_relative_path(
        tenant_id: str,
        claim_ref: str,
        document_id: str,
        version_no: int,
        file_name: str,
    ) -> str:
        return (
            f"tenants/{tenant_id}/sinistri/{claim_ref}/PerX-cache/versioning/"
            f"{document_id}/v{version_no}_{file_name}"
        )

    @staticmethod
    def build_trash_relative_path(tenant_id: str, claim_ref: str, trash_name: str) -> str:
        return f"tenants/{tenant_id}/sinistri/{claim_ref}/PerX-cache/cestino/{trash_name}"

    @staticmethod
    def guess_mime_type(file_name: str, provided: Optional[str] = None) -> str:
        return provided or mimetypes.guess_type(file_name)[0] or "application/octet-stream"

    @staticmethod
    def compute_checksum(content: bytes) -> str:
        return hashlib.sha256(content).hexdigest()

    @classmethod
    async def ensure_claim_folder(cls, tenant_id: str, claim_ref: str) -> None:
        if cls.provider_name() == "mac_mini":
            await cls._remote_post(
                "/internal/storage/claims/ensure",
                {"tenantId": tenant_id, "claimRef": claim_ref},
            )
            return
        for folder in ["da_mail", "da_whatsapp", "documenti", "perizia", "atti", "gestione", "_export", "PerX-cache/cestino", "PerX-cache/versioning"]:
            target = cls.storage_root() / cls.build_relative_path(tenant_id, claim_ref, folder, ".keep")
            target.parent.mkdir(parents=True, exist_ok=True)
            if not target.exists():
                target.write_bytes(b"")

    @classmethod
    async def upload_bytes(
        cls,
        *,
        tenant_id: str,
        claim_ref: str,
        relative_path: str,
        content: bytes,
        mime_type: Optional[str] = None,
    ) -> StoredBlob:
        checksum = cls.compute_checksum(content)
        if cls.provider_name() == "mac_mini":
            payload = {
                "tenantId": tenant_id,
                "claimRef": claim_ref,
                "relativePath": relative_path,
                "data": base64.b64encode(content).decode("utf-8"),
                "mimeType": mime_type,
            }
            response = await cls._remote_post("/internal/storage/files/upload", payload)
            return StoredBlob(
                relative_path=response.get("relativePath", relative_path),
                size_bytes=int(response.get("sizeBytes", len(content))),
                checksum_sha256=response.get("checksumSHA256", checksum),
                mime_type=cls.guess_mime_type(os.path.basename(relative_path), mime_type),
            )

        target = cls.storage_root() / relative_path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
        return StoredBlob(
            relative_path=relative_path,
            size_bytes=len(content),
            checksum_sha256=checksum,
            mime_type=cls.guess_mime_type(os.path.basename(relative_path), mime_type),
        )

    @classmethod
    async def download_bytes(cls, relative_path: str) -> bytes:
        if cls.provider_name() == "mac_mini":
            response = await cls._remote_post("/internal/storage/files/download", {"relativePath": relative_path})
            encoded = response.get("data")
            if not encoded:
                raise FileNotFoundError(relative_path)
            return base64.b64decode(encoded.encode("utf-8"))

        target = cls.storage_root() / relative_path
        if not target.exists():
            raise FileNotFoundError(relative_path)
        return target.read_bytes()

    @classmethod
    async def copy_file(cls, source_relative_path: str, destination_relative_path: str, overwrite: bool = False) -> None:
        if cls.provider_name() == "mac_mini":
            await cls._remote_post(
                "/internal/storage/files/copy",
                {
                    "sourcePath": source_relative_path,
                    "destinationPath": destination_relative_path,
                    "overwrite": overwrite,
                },
            )
            return

        source = cls.storage_root() / source_relative_path
        destination = cls.storage_root() / destination_relative_path
        if not source.exists():
            raise FileNotFoundError(source_relative_path)
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists():
            if not overwrite:
                raise FileExistsError(destination_relative_path)
            destination.unlink()
        destination.write_bytes(source.read_bytes())

    @classmethod
    async def move_file(cls, source_relative_path: str, destination_relative_path: str, overwrite: bool = False) -> None:
        if cls.provider_name() == "mac_mini":
            await cls._remote_post(
                "/internal/storage/files/move",
                {
                    "sourcePath": source_relative_path,
                    "destinationPath": destination_relative_path,
                    "overwrite": overwrite,
                },
            )
            return

        source = cls.storage_root() / source_relative_path
        destination = cls.storage_root() / destination_relative_path
        if not source.exists():
            raise FileNotFoundError(source_relative_path)
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists():
            if not overwrite:
                raise FileExistsError(destination_relative_path)
            destination.unlink()
        source.replace(destination)

    @classmethod
    async def delete_file(cls, relative_path: str, missing_ok: bool = True) -> None:
        if cls.provider_name() == "mac_mini":
            await cls._remote_post(
                "/internal/storage/files/delete",
                {"relativePath": relative_path, "missingOk": missing_ok},
            )
            return

        target = cls.storage_root() / relative_path
        if target.exists():
            target.unlink()
        elif not missing_ok:
            raise FileNotFoundError(relative_path)

    @classmethod
    async def _remote_post(cls, path: str, payload: dict) -> dict:
        base_url = (settings.MAC_MINI_STORAGE_URL or "").strip().rstrip("/")
        token = (settings.MAC_MINI_STORAGE_TOKEN or "").strip()
        if not base_url or not token:
            raise RuntimeError("Mac Mini storage provider is not configured")

        headers = {
            "X-PerX-Storage-Token": token,
            "Content-Type": "application/json",
        }
        timeout = httpx.Timeout(60.0, connect=10.0)
        async with httpx.AsyncClient(timeout=timeout) as client:
            response = await client.post(f"{base_url}{path}", headers=headers, json=payload)
        response.raise_for_status()
        if not response.content:
            return {}
        return response.json()
