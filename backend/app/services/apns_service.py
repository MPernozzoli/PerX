"""
APNs (Apple Push Notifications) sender.

Uses provider authentication tokens (ES256 JWT signed with a .p8 key) and
HTTP/2 to talk to the Apple Push Notification service.

Supports two payload types:
  * Standard "alert" notifications for visible push (messages, emails).
  * "voip" notifications for incoming-call delivery; iOS will wake the PerX Lite
    app and we are expected to immediately raise a CallKit incoming call.

Requires `h2` installed alongside httpx (httpx supports HTTP/2 when the extra
is present). Add `h2` to backend/requirements.txt.

Configuration via Settings:
  APNS_KEY_ID, APNS_TEAM_ID, APNS_KEY_PATH (.p8), APNS_BUNDLE_ID,
  APNS_VOIP_BUNDLE_ID, APNS_USE_SANDBOX
"""
from __future__ import annotations

import logging
import time
import uuid
from pathlib import Path
from typing import Any, Optional

import httpx
from jose import jwt

from app.core.config import settings


logger = logging.getLogger(__name__)

_PRODUCTION_HOST = "https://api.push.apple.com"
_SANDBOX_HOST = "https://api.sandbox.push.apple.com"


class APNsConfigurationError(RuntimeError):
    pass


class APNsService:
    def __init__(self) -> None:
        self._cached_token: Optional[str] = None
        self._cached_token_at: float = 0.0
        self._client: Optional[httpx.AsyncClient] = None

    def _require_config(self) -> None:
        missing = [
            name for name, val in (
                ("APNS_KEY_ID", settings.APNS_KEY_ID),
                ("APNS_TEAM_ID", settings.APNS_TEAM_ID),
            ) if not val
        ]
        if not settings.APNS_KEY_PEM and not settings.APNS_KEY_PATH:
            missing.append("APNS_KEY_PEM or APNS_KEY_PATH")
        if missing:
            raise APNsConfigurationError(f"APNs not configured, missing: {', '.join(missing)}")

    def _host(self) -> str:
        return _SANDBOX_HOST if settings.APNS_USE_SANDBOX else _PRODUCTION_HOST

    def _provider_token(self) -> str:
        # APNs tokens are valid up to 60 minutes; refresh every 40 minutes.
        now = time.time()
        if self._cached_token and (now - self._cached_token_at) < 40 * 60:
            return self._cached_token

        self._require_config()
        if settings.APNS_KEY_PEM:
            private_key = settings.APNS_KEY_PEM
            if "\\n" in private_key and "\n" not in private_key:
                private_key = private_key.replace("\\n", "\n")
        else:
            key_path = Path(settings.APNS_KEY_PATH)  # type: ignore[arg-type]
            if not key_path.is_file():
                raise APNsConfigurationError(f"APNs key file not found: {key_path}")
            private_key = key_path.read_text()
        token = jwt.encode(
            {"iss": settings.APNS_TEAM_ID, "iat": int(now)},
            private_key,
            algorithm="ES256",
            headers={"kid": settings.APNS_KEY_ID, "alg": "ES256"},
        )
        self._cached_token = token
        self._cached_token_at = now
        return token

    async def _get_client(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(http2=True, timeout=10.0)
        return self._client

    async def send(
        self,
        device_token: str,
        payload: dict[str, Any],
        *,
        push_type: str = "alert",  # "alert" | "voip" | "background"
        bundle_id: Optional[str] = None,
        priority: int = 10,
        collapse_id: Optional[str] = None,
        expiration: Optional[int] = None,
    ) -> bool:
        """
        Send a single push. Returns True on 2xx, False otherwise. Never raises
        on delivery errors — caller decides whether to retry or invalidate the
        token (a 410 means the device unregistered).
        """
        try:
            self._require_config()
        except APNsConfigurationError as e:
            logger.warning("APNs send skipped: %s", e)
            return False

        topic = bundle_id
        if topic is None:
            if push_type == "voip":
                topic = settings.APNS_VOIP_BUNDLE_ID or (
                    f"{settings.APNS_BUNDLE_ID}.voip" if settings.APNS_BUNDLE_ID else None
                )
            else:
                topic = settings.APNS_BUNDLE_ID
        if not topic:
            logger.warning("APNs send skipped: no bundle id (push_type=%s)", push_type)
            return False

        url = f"{self._host()}/3/device/{device_token}"
        headers = {
            "authorization": f"bearer {self._provider_token()}",
            "apns-topic": topic,
            "apns-push-type": push_type,
            "apns-priority": str(priority),
            "apns-id": str(uuid.uuid4()),
        }
        if collapse_id:
            headers["apns-collapse-id"] = collapse_id
        if expiration is not None:
            headers["apns-expiration"] = str(expiration)

        try:
            client = await self._get_client()
            response = await client.post(url, headers=headers, json=payload)
        except Exception as e:
            logger.exception("APNs transport error: %s", e)
            return False

        if 200 <= response.status_code < 300:
            return True

        # 410 → token invalid, caller should remove it
        body = response.text[:500] if response.content else ""
        logger.warning(
            "APNs send failed: status=%d token=%s… body=%s",
            response.status_code,
            device_token[:8],
            body,
        )
        return False

    async def send_incoming_call(
        self,
        device_token: str,
        *,
        session_id: str,
        caller_name: str,
        caller_handle: str,
        has_video: bool = False,
    ) -> bool:
        """
        VoIP push for CallKit. iOS will wake PerX Lite which MUST report a
        new incoming call to CallKit immediately.
        """
        payload = {
            "session_id": session_id,
            "caller_name": caller_name,
            "caller_handle": caller_handle,
            "has_video": has_video,
        }
        return await self.send(
            device_token,
            payload,
            push_type="voip",
            priority=10,
        )

    async def send_alert(
        self,
        device_token: str,
        *,
        title: str,
        body: str,
        data: Optional[dict[str, Any]] = None,
        sound: str = "default",
        category: Optional[str] = None,
        thread_id: Optional[str] = None,
    ) -> bool:
        aps: dict[str, Any] = {
            "alert": {"title": title, "body": body},
            "sound": sound,
        }
        if category:
            aps["category"] = category
        if thread_id:
            aps["thread-id"] = thread_id
        payload = {"aps": aps}
        if data:
            payload.update(data)
        return await self.send(device_token, payload, push_type="alert", priority=10)

    async def aclose(self) -> None:
        if self._client is not None:
            await self._client.aclose()
            self._client = None


apns_service = APNsService()
