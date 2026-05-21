"""
Client for the external CAT Dispatcher service.
"""
from __future__ import annotations

from urllib.parse import urljoin

import httpx
from fastapi import HTTPException, status

from app.core.config import settings


class CatDispatcherService:
    @staticmethod
    def _functions_base_url() -> str:
        raw_base_url = (settings.CATDISPATCHER_BASE_URL or "").strip()
        if not raw_base_url:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="CAT Dispatcher integration is not configured",
            )

        base_url = raw_base_url.rstrip("/")
        if base_url.endswith("/functions/v1"):
            return f"{base_url}/"
        return f"{base_url}/functions/v1/"

    @staticmethod
    def _headers() -> dict[str, str]:
        api_key = (settings.CATDISPATCHER_API_KEY or "").strip()
        if not api_key:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="CAT Dispatcher API key is not configured",
            )

        return {
            "Content-Type": "application/json",
            "Accept": "application/json",
            "X-Catdispatcher-Api-Key": api_key,
        }

    @classmethod
    async def post(cls, function_name: str, payload: dict) -> dict:
        url = urljoin(cls._functions_base_url(), function_name)
        try:
            async with httpx.AsyncClient(timeout=settings.CATDISPATCHER_TIMEOUT_SECONDS) as client:
                response = await client.post(url, headers=cls._headers(), json=payload)
        except httpx.TimeoutException as exc:
            raise HTTPException(
                status_code=status.HTTP_504_GATEWAY_TIMEOUT,
                detail="CAT Dispatcher did not respond in time",
            ) from exc
        except httpx.HTTPError as exc:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=f"CAT Dispatcher request failed: {exc}",
            ) from exc

        try:
            data = response.json()
        except ValueError as exc:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="CAT Dispatcher returned a non-JSON response",
            ) from exc

        if response.status_code >= 400:
            detail = data.get("error") or data.get("detail") or data
            raise HTTPException(status_code=response.status_code, detail=detail)

        if not isinstance(data, dict):
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="CAT Dispatcher returned an invalid payload",
            )

        return data
