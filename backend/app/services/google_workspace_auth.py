"""Scambio del login Google (Supabase PKCE) e custodia del token della casella."""
from __future__ import annotations

import base64
import hashlib
import json
import uuid

from cryptography.fernet import Fernet, InvalidToken
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.email import Mailbox

GOOGLE_WORKSPACE_SCOPES: tuple[str, ...] = (
    "openid",
    "email",
    "profile",
    "https://www.googleapis.com/auth/gmail.modify",
    "https://www.googleapis.com/auth/gmail.settings.basic",
    "https://www.googleapis.com/auth/calendar.events",
)


def google_workspace_scope_string() -> str:
    return " ".join(GOOGLE_WORKSPACE_SCOPES)


def _fernet() -> Fernet:
    digest = hashlib.sha256(settings.SECRET_KEY.encode("utf-8")).digest()
    return Fernet(base64.urlsafe_b64encode(digest))


def seal_google_tokens(*, refresh_token: str | None, access_token: str | None) -> str:
    payload = json.dumps(
        {"refresh_token": refresh_token or "", "access_token": access_token or ""},
        separators=(",", ":"),
    ).encode("utf-8")
    return _fernet().encrypt(payload).decode("utf-8")


def open_google_tokens(sealed: str) -> dict[str, str]:
    raw = _fernet().decrypt(sealed.encode("utf-8"))
    data = json.loads(raw.decode("utf-8"))
    if not isinstance(data, dict):
        raise InvalidToken()
    return {
        "refresh_token": str(data.get("refresh_token") or ""),
        "access_token": str(data.get("access_token") or ""),
    }


async def store_google_mailbox_tokens(
    db: AsyncSession,
    *,
    tenant_id: str,
    email: str,
    refresh_token: str | None,
    access_token: str | None,
) -> None:
    if not refresh_token and not access_token:
        return
    result = await db.execute(
        select(Mailbox).where(
            Mailbox.tenant_id == tenant_id,
            Mailbox.provider == "gmail",
            Mailbox.email_address == email,
        )
    )
    mailbox = result.scalar_one_or_none()
    if mailbox is not None and not refresh_token and mailbox.oauth_token_ref:
        try:
            previous = open_google_tokens(mailbox.oauth_token_ref)
        except (InvalidToken, json.JSONDecodeError, ValueError):
            previous = {}
        refresh_token = previous.get("refresh_token") or None
    if not refresh_token and not access_token:
        return
    sealed = seal_google_tokens(refresh_token=refresh_token, access_token=access_token)
    if mailbox is None:
        mailbox = Mailbox(
            id=str(uuid.uuid4()),
            tenant_id=tenant_id,
            label="Google Workspace",
            provider="gmail",
            email_address=email,
            auth_type="oauth",
            oauth_token_ref=sealed,
            active="true",
            settings_json={"source": "supabase-google"},
        )
        db.add(mailbox)
        return
    mailbox.auth_type = "oauth"
    mailbox.oauth_token_ref = sealed
    mailbox.active = "true"
    current = dict(mailbox.settings_json or {})
    current["source"] = "supabase-google"
    mailbox.settings_json = current
