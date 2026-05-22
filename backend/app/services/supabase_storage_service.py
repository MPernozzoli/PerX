"""
Supabase Storage adapter for portal photo uploads.

Files uploaded here are accessible to the Mac Mini worker via signed URLs
embedded in the ai_asset_photo_analysis process job input.
"""
from __future__ import annotations

import hashlib
import mimetypes
import os
from dataclasses import dataclass
from typing import Optional

import httpx

from app.core.config import settings


@dataclass
class SupabaseBlob:
    bucket: str
    storage_path: str
    size_bytes: int
    checksum_sha256: str
    mime_type: Optional[str] = None


class SupabaseStorageService:
    @staticmethod
    def _base_url() -> str:
        url = (settings.SUPABASE_URL or "").rstrip("/")
        return f"{url}/storage/v1"

    @staticmethod
    def _service_key() -> str:
        key = (settings.SUPABASE_SERVICE_ROLE_KEY or "").strip()
        if not key:
            raise RuntimeError("SUPABASE_SERVICE_ROLE_KEY is not configured")
        return key

    @staticmethod
    def _bucket() -> str:
        return settings.SUPABASE_STORAGE_BUCKET or "perx-portal-uploads"

    @staticmethod
    def is_configured() -> bool:
        return bool(
            (settings.SUPABASE_URL or "").strip()
            and (settings.SUPABASE_SERVICE_ROLE_KEY or "").strip()
        )

    @classmethod
    def _headers(cls) -> dict:
        return {
            "Authorization": f"Bearer {cls._service_key()}",
            "apikey": cls._service_key(),
        }

    @classmethod
    def build_object_path(cls, tenant_id: str, claim_ref: str, document_id: str, filename: str) -> str:
        safe_name = os.path.basename(filename).replace(" ", "_")
        return f"portal/{tenant_id}/{claim_ref}/{document_id}_{safe_name}"

    @classmethod
    async def upload(
        cls,
        *,
        object_path: str,
        content: bytes,
        mime_type: Optional[str] = None,
    ) -> SupabaseBlob:
        bucket = cls._bucket()
        mime = mime_type or mimetypes.guess_type(object_path)[0] or "application/octet-stream"
        checksum = hashlib.sha256(content).hexdigest()

        async with httpx.AsyncClient(timeout=httpx.Timeout(60.0, connect=10.0)) as client:
            resp = await client.post(
                f"{cls._base_url()}/object/{bucket}/{object_path}",
                headers={**cls._headers(), "Content-Type": mime, "x-upsert": "true"},
                content=content,
            )
            resp.raise_for_status()

        return SupabaseBlob(
            bucket=bucket,
            storage_path=object_path,
            size_bytes=len(content),
            checksum_sha256=checksum,
            mime_type=mime,
        )

    @classmethod
    async def create_signed_url(cls, object_path: str, expires_in_seconds: int = 86400) -> str:
        """Returns a signed download URL valid for expires_in_seconds (default 24h)."""
        bucket = cls._bucket()
        async with httpx.AsyncClient(timeout=httpx.Timeout(15.0)) as client:
            resp = await client.post(
                f"{cls._base_url()}/object/sign/{bucket}/{object_path}",
                headers={**cls._headers(), "Content-Type": "application/json"},
                json={"expiresIn": expires_in_seconds},
            )
            resp.raise_for_status()
            data = resp.json()

        signed_url = data.get("signedURL") or data.get("signedUrl") or ""
        if not signed_url:
            raise RuntimeError(f"Supabase did not return a signed URL for {object_path}")

        supabase_url = (settings.SUPABASE_URL or "").rstrip("/")
        if signed_url.startswith("/"):
            return f"{supabase_url}{signed_url}"
        return signed_url
