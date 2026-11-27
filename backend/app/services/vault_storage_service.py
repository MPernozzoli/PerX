"""
Vault binary storage adapter.

The cloud API remains the source of truth for metadata/audit, while the real
file content can live either on local disk (dev fallback) or on a Mac Mini NAS
reachable through a small internal HTTP API, or on S3-compatible object storage
(AWS S3 eu-south-1 in produzione, moto server in sviluppo). Il provider S3 e' predisposto
ma NON attivo finche' VAULT_STORAGE_PROVIDER non viene impostato a "s3".
"""
from __future__ import annotations

import base64
import hashlib
import asyncio
import mimetypes
import os
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional

import httpx

from app.core.config import settings


@dataclass
class StoredBlob:
    relative_path: str
    size_bytes: int
    checksum_sha256: str
    mime_type: Optional[str] = None


SHA256_METADATA_KEY = "sha256"


class S3ObjectStore:
    """Wrapper sincrono minimale su boto3 per un bucket + prefisso.

    Le chiamate sono bloccanti: VaultStorageService le esegue con asyncio.to_thread.
    Le credenziali arrivano dalla catena standard AWS (mai da settings/repo).
    """

    def __init__(
        self,
        *,
        bucket: str,
        region: str = "eu-south-1",
        endpoint_url: Optional[str] = None,
        prefix: str = "",
        force_path_style: bool = False,
        client: Any = None,
    ) -> None:
        if not (bucket or "").strip():
            raise RuntimeError("S3 vault storage provider requires VAULT_S3_BUCKET")
        self.bucket = bucket.strip()
        self.region = region
        self.endpoint_url = endpoint_url or None
        self.prefix = (prefix or "").strip().strip("/")
        self.force_path_style = force_path_style
        self._client = client

    @property
    def client(self) -> Any:
        if self._client is None:
            import boto3
            from botocore.config import Config

            config = Config(
                region_name=self.region,
                signature_version="s3v4",
                s3={"addressing_style": "path" if self.force_path_style else "auto"},
                retries={"max_attempts": 5, "mode": "standard"},
            )
            self._client = boto3.client(
                "s3",
                region_name=self.region,
                endpoint_url=self.endpoint_url,
                config=config,
            )
        return self._client

    def key(self, relative_path: str) -> str:
        clean = relative_path.lstrip("/")
        return f"{self.prefix}/{clean}" if self.prefix else clean

    @staticmethod
    def _is_missing(exc: Exception) -> bool:
        from botocore.exceptions import ClientError

        if not isinstance(exc, ClientError):
            return False
        code = str(exc.response.get("Error", {}).get("Code", ""))
        return code in {"404", "NoSuchKey", "NotFound", "NoSuchBucket"}

    def head(self, relative_path: str) -> Optional[dict]:
        try:
            return self.client.head_object(Bucket=self.bucket, Key=self.key(relative_path))
        except Exception as exc:  # noqa: BLE001
            if self._is_missing(exc):
                return None
            raise

    def exists(self, relative_path: str) -> bool:
        return self.head(relative_path) is not None

    def put(self, relative_path: str, content: bytes, *, mime_type: Optional[str], checksum: str) -> None:
        self.client.put_object(
            Bucket=self.bucket,
            Key=self.key(relative_path),
            Body=content,
            ContentType=mime_type or "application/octet-stream",
            ServerSideEncryption="AES256",
            Metadata={SHA256_METADATA_KEY: checksum},
        )

    def get(self, relative_path: str) -> bytes:
        try:
            response = self.client.get_object(Bucket=self.bucket, Key=self.key(relative_path))
        except Exception as exc:  # noqa: BLE001
            if self._is_missing(exc):
                raise FileNotFoundError(relative_path) from exc
            raise
        return response["Body"].read()

    def copy(self, source: str, destination: str, *, overwrite: bool) -> None:
        if not self.exists(source):
            raise FileNotFoundError(source)
        if not overwrite and self.exists(destination):
            raise FileExistsError(destination)
        self.client.copy_object(
            Bucket=self.bucket,
            Key=self.key(destination),
            CopySource={"Bucket": self.bucket, "Key": self.key(source)},
            ServerSideEncryption="AES256",
            MetadataDirective="COPY",
        )

    def delete(self, relative_path: str, *, missing_ok: bool) -> None:
        if not missing_ok and not self.exists(relative_path):
            raise FileNotFoundError(relative_path)
        self.client.delete_object(Bucket=self.bucket, Key=self.key(relative_path))

    def presign_get(
        self,
        relative_path: str,
        *,
        ttl: int,
        file_name: Optional[str] = None,
        mime_type: Optional[str] = None,
    ) -> str:
        params: dict[str, Any] = {"Bucket": self.bucket, "Key": self.key(relative_path)}
        if file_name:
            safe = file_name.replace('"', "")
            params["ResponseContentDisposition"] = f'attachment; filename="{safe}"'
        if mime_type:
            params["ResponseContentType"] = mime_type
        return self.client.generate_presigned_url("get_object", Params=params, ExpiresIn=ttl)


class VaultStorageService:
    _s3_store: Optional[S3ObjectStore] = None
    _s3_store_key: Optional[tuple] = None
    _s3_lock = threading.Lock()

    @staticmethod
    def provider_name() -> str:
        provider = settings.VAULT_STORAGE_PROVIDER.strip().lower()
        return provider or "local"

    @classmethod
    def s3_store(cls) -> S3ObjectStore:
        """Store S3 lazy e cachato; si ricrea se cambia la configurazione."""
        key = (
            settings.VAULT_S3_BUCKET,
            settings.VAULT_S3_REGION,
            settings.VAULT_S3_ENDPOINT_URL,
            settings.VAULT_S3_PREFIX,
            settings.VAULT_S3_FORCE_PATH_STYLE,
        )
        with cls._s3_lock:
            if cls._s3_store is None or cls._s3_store_key != key:
                cls._s3_store = S3ObjectStore(
                    bucket=settings.VAULT_S3_BUCKET or "",
                    region=settings.VAULT_S3_REGION,
                    endpoint_url=settings.VAULT_S3_ENDPOINT_URL,
                    prefix=settings.VAULT_S3_PREFIX,
                    force_path_style=settings.VAULT_S3_FORCE_PATH_STYLE,
                )
                cls._s3_store_key = key
            return cls._s3_store

    @classmethod
    def reset_s3_store(cls) -> None:
        with cls._s3_lock:
            cls._s3_store = None
            cls._s3_store_key = None

    @classmethod
    def supports_presigned_downloads(cls) -> bool:
        return cls.provider_name() == "s3"

    @classmethod
    async def generate_download_url(
        cls,
        relative_path: str,
        ttl: Optional[int] = None,
        *,
        file_name: Optional[str] = None,
        mime_type: Optional[str] = None,
    ) -> Optional[str]:
        """URL presigned di download (solo provider S3, altrimenti None)."""
        if cls.provider_name() != "s3":
            return None
        store = cls.s3_store()
        expires = int(ttl or settings.VAULT_S3_PRESIGNED_URL_TTL_SECONDS)
        return await asyncio.to_thread(
            store.presign_get, relative_path, ttl=expires, file_name=file_name, mime_type=mime_type
        )

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
        if cls.provider_name() == "s3":
            return  # su S3 non esistono cartelle reali: i prefissi nascono con gli oggetti
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

        if cls.provider_name() == "s3":
            resolved_mime = cls.guess_mime_type(os.path.basename(relative_path), mime_type)
            await asyncio.to_thread(
                cls.s3_store().put, relative_path, content, mime_type=resolved_mime, checksum=checksum
            )
            return StoredBlob(
                relative_path=relative_path,
                size_bytes=len(content),
                checksum_sha256=checksum,
                mime_type=resolved_mime,
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

        if cls.provider_name() == "s3":
            return await asyncio.to_thread(cls.s3_store().get, relative_path)

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

        if cls.provider_name() == "s3":
            await asyncio.to_thread(
                cls.s3_store().copy, source_relative_path, destination_relative_path, overwrite=overwrite
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

        if cls.provider_name() == "s3":
            store = cls.s3_store()

            def _move() -> None:
                if source_relative_path == destination_relative_path:
                    if not store.exists(source_relative_path):
                        raise FileNotFoundError(source_relative_path)
                    return
                store.copy(source_relative_path, destination_relative_path, overwrite=overwrite)
                store.delete(source_relative_path, missing_ok=True)

            await asyncio.to_thread(_move)
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

        if cls.provider_name() == "s3":
            await asyncio.to_thread(cls.s3_store().delete, relative_path, missing_ok=missing_ok)
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
