"""
LiveKit JWT minter.

LiveKit accepts standard HS256 JWTs signed with the project's API secret. We
sign tokens server-side and hand them to the client just-in-time so the
secret never leaves the backend.

Token shape:
    iss = api_key
    sub = identity (user-stable string)
    nbf = now
    exp = now + ttl
    video = {
        roomJoin: true,
        room: <room_name>,
        canSubscribe: bool,
        canPublish: bool,
        canPublishData: bool,
    }
    name (optional): human-readable label shown in the call UI
    metadata (optional): JSON string with app-specific role/context

Reference: https://docs.livekit.io/realtime/concepts/authentication/
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from typing import Optional

from jose import jwt

from app.core.config import settings


class LiveKitNotConfiguredError(RuntimeError):
    """Raised when a token is requested but credentials are missing."""


@dataclass
class LiveKitGrant:
    """LiveKit `video` grant block — what the participant is allowed to do."""
    can_subscribe: bool = True
    can_publish: bool = False
    can_publish_data: bool = True

    def to_payload(self, room_name: str) -> dict:
        return {
            "roomJoin": True,
            "room": room_name,
            "canSubscribe": self.can_subscribe,
            "canPublish": self.can_publish,
            "canPublishData": self.can_publish_data,
        }


@dataclass
class MintedToken:
    token: str
    livekit_url: str
    identity: str
    room_name: str
    expires_at: datetime
    grant: LiveKitGrant
    metadata: dict = field(default_factory=dict)


class LiveKitTokenService:
    @staticmethod
    def is_configured() -> bool:
        return bool(
            settings.LIVEKIT_URL
            and settings.LIVEKIT_API_KEY
            and settings.LIVEKIT_API_SECRET
        )

    @staticmethod
    def mint(
        *,
        identity: str,
        room_name: str,
        grant: LiveKitGrant,
        display_name: Optional[str] = None,
        metadata: Optional[dict] = None,
        ttl_seconds: Optional[int] = None,
    ) -> MintedToken:
        if not LiveKitTokenService.is_configured():
            raise LiveKitNotConfiguredError("LIVEKIT_URL/API_KEY/API_SECRET missing")

        now = datetime.now(timezone.utc)
        ttl = ttl_seconds or settings.LIVEKIT_TOKEN_TTL_SECONDS
        exp = now + timedelta(seconds=ttl)

        payload: dict = {
            "iss": settings.LIVEKIT_API_KEY,
            "sub": identity,
            "nbf": int(now.timestamp()),
            "exp": int(exp.timestamp()),
            "video": grant.to_payload(room_name),
        }
        if display_name:
            payload["name"] = display_name
        if metadata:
            payload["metadata"] = json.dumps(metadata, separators=(",", ":"))

        token = jwt.encode(payload, settings.LIVEKIT_API_SECRET, algorithm="HS256")

        return MintedToken(
            token=token,
            livekit_url=settings.LIVEKIT_URL,
            identity=identity,
            room_name=room_name,
            expires_at=exp,
            grant=grant,
            metadata=metadata or {},
        )
