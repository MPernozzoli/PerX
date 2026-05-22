"""
Unified login invitation routes.
"""
import hashlib
import secrets
import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import delete, insert, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db
from app.core.security import get_current_platform_admin
from app.models.invitation import UserInvitation
from app.models.role import Role, user_roles
from app.models.tenant import Tenant
from app.models.user import User
from app.schemas.invitation import (
    InvitationAccept,
    InvitationAcceptResponse,
    InvitationCreate,
    InvitationCreateResponse,
    InvitationPublicResponse,
)

router = APIRouter()


def _normalize_email(value: str) -> str:
    return value.strip().lower()


def _token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _invite_url(token: str) -> str:
    return f"{settings.LOGIN_PUBLIC_URL.rstrip('/')}/invite/{token}"


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


async def _get_invitation_by_token(db: AsyncSession, token: str) -> UserInvitation:
    result = await db.execute(select(UserInvitation).where(UserInvitation.token_hash == _token_hash(token)))
    invitation = result.scalar_one_or_none()
    if invitation is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invitation not found")
    return invitation


async def _expire_if_needed(db: AsyncSession, invitation: UserInvitation) -> None:
    expires_at = invitation.expires_at
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    if invitation.status == "pending" and expires_at <= _utcnow():
        invitation.status = "expired"
        await db.commit()


async def _ensure_roles(db: AsyncSession, tenant_id: str, role_names: list[str]) -> list[Role]:
    roles: list[Role] = []
    for raw_name in role_names:
        name = raw_name.strip()
        if not name:
            continue
        result = await db.execute(select(Role).where(Role.tenant_id == tenant_id, Role.name == name))
        role = result.scalar_one_or_none()
        if role is None:
            role = Role(id=str(uuid.uuid4()), tenant_id=tenant_id, name=name)
            db.add(role)
            await db.flush()
        roles.append(role)
    return roles


async def _replace_user_roles(db: AsyncSession, user_id: str, roles: list[Role]) -> None:
    if not roles:
        return
    await db.execute(delete(user_roles).where(user_roles.c.user_id == user_id))
    for role in roles:
        await db.execute(insert(user_roles).values(user_id=user_id, role_id=role.id))


@router.post("", response_model=InvitationCreateResponse, status_code=status.HTTP_201_CREATED)
async def create_invitation(
    payload: InvitationCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_platform_admin),
):
    tenant = await db.get(Tenant, payload.tenant_id)
    if tenant is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Tenant not found")

    personal_email = _normalize_email(str(payload.personal_email))
    result = await db.execute(
        select(User).where(
            (User.personal_email == personal_email)
            | (User.email == personal_email)
            | (User.professional_email == personal_email)
        )
    )
    user = result.scalar_one_or_none()

    if user and user.is_active and user.idp_subject:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="User is already active in unified login",
        )

    if user is None:
        user = User(
            id=str(uuid.uuid4()),
            tenant_id=payload.tenant_id,
            email=personal_email,
            personal_email=personal_email,
            full_name=payload.full_name.strip(),
            is_active=False,
        )
        db.add(user)
        await db.flush()
    else:
        user.tenant_id = payload.tenant_id
        user.personal_email = personal_email
        user.email = user.email or personal_email
        user.full_name = payload.full_name.strip()

    roles = await _ensure_roles(db, payload.tenant_id, payload.roles)
    await _replace_user_roles(db, user.id, roles)

    token = secrets.token_urlsafe(32)
    invitation = UserInvitation(
        id=str(uuid.uuid4()),
        tenant_id=payload.tenant_id,
        user_id=user.id,
        personal_email=personal_email,
        token_hash=_token_hash(token),
        status="pending",
        expires_at=_utcnow() + timedelta(hours=payload.expires_in_hours),
        created_by_user_id=current_user.id,
        metadata_json=payload.metadata_json or {},
    )
    db.add(invitation)
    await db.commit()
    await db.refresh(invitation)

    return InvitationCreateResponse(
        id=invitation.id,
        user_id=user.id,
        tenant_id=invitation.tenant_id,
        personal_email=invitation.personal_email,
        status=invitation.status,
        expires_at=invitation.expires_at,
        invite_url=_invite_url(token),
    )


@router.get("/{token}", response_model=InvitationPublicResponse)
async def get_invitation(token: str, db: AsyncSession = Depends(get_db)):
    invitation = await _get_invitation_by_token(db, token)
    await _expire_if_needed(db, invitation)
    if invitation.status != "pending":
        raise HTTPException(status_code=status.HTTP_410_GONE, detail=f"Invitation is {invitation.status}")

    user = await db.get(User, invitation.user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invitation user not found")

    return InvitationPublicResponse(
        id=invitation.id,
        tenant_id=invitation.tenant_id,
        personal_email=invitation.personal_email,
        full_name=user.full_name,
        status=invitation.status,
        expires_at=invitation.expires_at,
    )


@router.post("/{token}/accept", response_model=InvitationAcceptResponse)
async def accept_invitation(
    token: str,
    payload: InvitationAccept,
    db: AsyncSession = Depends(get_db),
):
    invitation = await _get_invitation_by_token(db, token)
    await _expire_if_needed(db, invitation)
    if invitation.status != "pending":
        raise HTTPException(status_code=status.HTTP_410_GONE, detail=f"Invitation is {invitation.status}")

    idp_subject = payload.idp_subject.strip()
    result = await db.execute(select(User).where(User.idp_subject == idp_subject, User.id != invitation.user_id))
    existing_idp_user = result.scalar_one_or_none()
    if existing_idp_user is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Identity is already linked to another user")

    user = await db.get(User, invitation.user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invitation user not found")

    user.idp_subject = idp_subject
    user.is_active = True
    if payload.professional_email is not None:
        user.professional_email = _normalize_email(str(payload.professional_email))

    invitation.status = "accepted"
    invitation.accepted_at = _utcnow()
    await db.commit()
    await db.refresh(user)

    return InvitationAcceptResponse(
        user_id=user.id,
        tenant_id=user.tenant_id,
        personal_email=user.personal_email or user.email,
        professional_email=user.professional_email,
        status=invitation.status,
    )
