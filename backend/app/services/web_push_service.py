"""
Web Push delivery for the insured portal (VAPID).
"""
from __future__ import annotations

import json
import logging
from dataclasses import dataclass

try:
    from pywebpush import WebPushException, webpush
except Exception:  # pragma: no cover - libreria opzionale in fase di build
    webpush = None  # type: ignore[assignment]
    WebPushException = Exception  # type: ignore[assignment,misc]

from app.core.config import settings

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class WebPushResult:
    success: bool
    status_code: int | None = None
    gone: bool = False
    error: str | None = None


class WebPushService:
    @staticmethod
    def is_configured() -> bool:
        return bool(
            settings.PORTAL_VAPID_PUBLIC_KEY
            and settings.PORTAL_VAPID_PRIVATE_KEY
            and webpush is not None
        )

    @staticmethod
    def send(
        *,
        endpoint: str,
        p256dh: str,
        auth: str,
        title: str,
        body: str,
        url: str | None = None,
        tag: str | None = None,
        data: dict | None = None,
    ) -> WebPushResult:
        if not WebPushService.is_configured():
            return WebPushResult(success=False, error="web_push_not_configured")

        payload = {
            "title": title,
            "body": body,
            "url": url,
            "tag": tag,
            "data": data or {},
        }
        subscription_info = {
            "endpoint": endpoint,
            "keys": {"p256dh": p256dh, "auth": auth},
        }
        try:
            response = webpush(
                subscription_info=subscription_info,
                data=json.dumps(payload),
                vapid_private_key=settings.PORTAL_VAPID_PRIVATE_KEY,
                vapid_claims={"sub": settings.PORTAL_VAPID_SUBJECT},
            )
            return WebPushResult(success=True, status_code=getattr(response, "status_code", 200))
        except WebPushException as exc:  # type: ignore[misc]
            status_code = getattr(getattr(exc, "response", None), "status_code", None)
            gone = status_code in {404, 410}
            logger.warning(
                "Web push delivery failed (endpoint=%s status=%s gone=%s)",
                endpoint[:64],
                status_code,
                gone,
            )
            return WebPushResult(
                success=False,
                status_code=status_code,
                gone=gone,
                error=str(exc),
            )
        except Exception as exc:  # pragma: no cover
            logger.exception("Unexpected web push error")
            return WebPushResult(success=False, error=str(exc))
