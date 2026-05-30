"""
Security helpers dedicated to the insured portal.
"""
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import hashlib
import re
import secrets

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db
from app.models.portal import PortalClaimAccess

portal_bearer_scheme = HTTPBearer(auto_error=False)


@dataclass
class PortalSessionContext:
    tenant_id: str
    claim_id: str
    portal_access_id: str
    role: str


def normalize_email(value: str | None) -> str | None:
    if not value:
        return None
    return value.strip().lower()


def normalize_person_name(value: str | None) -> str | None:
    if not value:
        return None
    normalized = re.sub(r"\s+", " ", value).strip().upper()
    return normalized or None


def normalize_phone_number(value: str | None) -> str | None:
    if not value:
        return None
    candidate = value.strip()
    if candidate.startswith("00"):
        candidate = f"+{candidate[2:]}"
    if candidate.startswith("+"):
        digits = re.sub(r"\D", "", candidate[1:])
        return f"+{digits}" if digits else None
    digits = re.sub(r"\D", "", candidate)
    return digits or None


def normalize_tax_code(value: str | None) -> str | None:
    if not value:
        return None
    normalized = re.sub(r"[^A-Za-z0-9]", "", value).upper()
    return normalized or None


def hash_secret(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def generate_magic_token() -> str:
    return secrets.token_urlsafe(32)


def generate_otp_code() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def create_portal_session_token(
    tenant_id: str,
    claim_id: str,
    portal_access_id: str,
    role: str,
    *,
    remember_me: bool = False,
) -> tuple[str, int]:
    if remember_me:
        expires_in = settings.PORTAL_SESSION_REMEMBER_ME_DAYS * 24 * 60 * 60
    else:
        expires_in = settings.PORTAL_SESSION_EXPIRE_MINUTES * 60
    expire = datetime.now(timezone.utc) + timedelta(seconds=expires_in)
    payload = {
        "sub": portal_access_id,
        "tenant_id": tenant_id,
        "claim_id": claim_id,
        "role": role,
        "scope": "portal",
        "exp": expire,
    }
    token = jwt.encode(
        payload,
        settings.PORTAL_TOKEN_SECRET or settings.SECRET_KEY,
        algorithm=settings.ALGORITHM,
    )
    return token, expires_in


async def get_current_portal_session(
    credentials: HTTPAuthorizationCredentials | None = Depends(portal_bearer_scheme),
    db: AsyncSession = Depends(get_db),
) -> PortalSessionContext:
    if not credentials or credentials.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Portal authentication required",
        )

    try:
        payload = jwt.decode(
            credentials.credentials,
            settings.PORTAL_TOKEN_SECRET or settings.SECRET_KEY,
            algorithms=[settings.ALGORITHM],
        )
    except JWTError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid portal session",
        ) from exc

    if payload.get("scope") != "portal":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid portal session scope",
        )

    access_id = payload.get("sub")
    claim_id = payload.get("claim_id")
    tenant_id = payload.get("tenant_id")
    role = payload.get("role") or "insured"
    if not access_id or not claim_id or not tenant_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Malformed portal session",
        )

    access_result = await db.execute(
        select(PortalClaimAccess).where(
            PortalClaimAccess.id == access_id,
            PortalClaimAccess.claim_id == claim_id,
            PortalClaimAccess.tenant_id == tenant_id,
            PortalClaimAccess.status == "active",
        )
    )
    if not access_result.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Portal access revoked or unavailable",
        )

    return PortalSessionContext(
        tenant_id=tenant_id,
        claim_id=claim_id,
        portal_access_id=access_id,
        role=role,
    )
