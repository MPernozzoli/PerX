"""
Tenant settings routes
"""
import asyncio
from datetime import datetime, timezone
import json
from urllib import error as urlerror
from urllib import request as urlrequest
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db
from app.core.security import get_password_hash
from app.core.security import get_current_active_user
from app.models.role import Role, user_roles
from app.models.tenant import Tenant, TenantPortalDomain
from app.models.user import User
from app.schemas.tenant_settings import (
    TenantAIKeysResponse,
    TenantAISettingsPayload,
    TenantMailSettingsPayload,
    TenantSettingsResponse,
    TenantUserCreateRequest,
    TenantUserInviteResponse,
    TenantUserResponse,
    TenantUserUpdateRequest,
)
from app.services.user_email_service import (
    ensure_personal_email,
    ensure_professional_email,
    get_user_aliases,
    set_professional_email,
)

router = APIRouter()


def _default_cat_settings() -> dict:
    return {
        "enabled": True,
        "planner": {
            "route_generation_hour": 9,
            "route_review_window_minutes": 60,
            "availability_slot_minutes": 120,
            "availability_tolerance_percent": 50,
            "max_outside_zone_kilometers": 50,
        },
        "technicians": [
            {
                "id": "cat-modena",
                "display_name": "CAT Modena Nord",
                "email": "cat.modena@tenant.it",
                "latitude": 44.6471,
                "longitude": 10.9252,
                "comune": "Modena",
                "provincia": "MO",
                "regione": "Emilia-Romagna",
                "assigned_municipalities": ["Modena", "Carpi"],
                "note": "Presidio principale",
            },
            {
                "id": "cat-sassuolo",
                "display_name": "CAT Area Ceramiche",
                "email": "cat.sassuolo@tenant.it",
                "latitude": 44.5432,
                "longitude": 10.7841,
                "comune": "Sassuolo",
                "provincia": "MO",
                "regione": "Emilia-Romagna",
                "assigned_municipalities": ["Sassuolo", "Rubiera"],
                "note": "Supporto sud-ovest",
            },
        ],
        "municipalities": [
            {
                "id": "modena",
                "comune": "Modena",
                "provincia": "MO",
                "regione": "Emilia-Romagna",
                "latitude": 44.6471,
                "longitude": 10.9252,
                "assigned_cat_emails": ["cat.modena@tenant.it"],
                "priority": 1,
            },
            {
                "id": "carpi",
                "comune": "Carpi",
                "provincia": "MO",
                "regione": "Emilia-Romagna",
                "latitude": 44.7824,
                "longitude": 10.8777,
                "assigned_cat_emails": ["cat.modena@tenant.it"],
                "priority": 1,
            },
            {
                "id": "sassuolo",
                "comune": "Sassuolo",
                "provincia": "MO",
                "regione": "Emilia-Romagna",
                "latitude": 44.5432,
                "longitude": 10.7841,
                "assigned_cat_emails": ["cat.sassuolo@tenant.it"],
                "priority": 2,
            },
            {
                "id": "rubiera",
                "comune": "Rubiera",
                "provincia": "RE",
                "regione": "Emilia-Romagna",
                "latitude": 44.6511,
                "longitude": 10.7812,
                "assigned_cat_emails": ["cat.sassuolo@tenant.it"],
                "priority": 2,
            },
        ],
    }


def _default_provider_settings() -> dict:
    return {
        "map_provider": "google_maps",
        "maps_api_key": "",
        "routing_provider": "google_routes",
        "routing_api_key": "",
        "geocoding_provider": "google_geocoding",
        "geocoding_api_key": "",
        "messaging_provider": "twilio",
        "messaging_api_key": "",
    }


def _default_ai_settings() -> dict:
    return {
        "openai_api_key": "",
        "openai_model": "gpt-4o",
        "anthropic_api_key": "",
        "anthropic_model": "claude-opus-4-7",
    }


def _normalized_settings(tenant: Tenant, include_provider_secrets: bool) -> dict:
    settings = tenant.settings_json or {}
    garanzie = [
        value.strip()
        for value in settings.get("claim_garanzie", ["Fenomeno Elettrico"])
        if isinstance(value, str) and value.strip()
    ]
    if "Fenomeno Elettrico" not in garanzie:
        garanzie.insert(0, "Fenomeno Elettrico")
    default_garanzia = settings.get("default_claim_garanzia", "Fenomeno Elettrico")
    if not isinstance(default_garanzia, str) or not default_garanzia.strip():
        default_garanzia = "Fenomeno Elettrico"
    if default_garanzia not in garanzie:
        default_garanzia = "Fenomeno Elettrico"

    cat_settings = settings.get("cat_settings", _default_cat_settings())
    if not isinstance(cat_settings, dict):
        cat_settings = _default_cat_settings()

    provider_settings = settings.get("provider_settings", _default_provider_settings())
    if not isinstance(provider_settings, dict):
        provider_settings = _default_provider_settings()

    ai_settings = settings.get("ai_settings", _default_ai_settings())
    if not isinstance(ai_settings, dict):
        ai_settings = _default_ai_settings()

    return {
        "tenant_name": tenant.name,
        "tenant_slug": tenant.slug,
        "portal_domains": settings.get("portal_domains", []),
        "internal_domains": settings.get("internal_domains", []),
        "internal_emails": settings.get("internal_emails", []),
        "system_emails": settings.get("system_emails", []),
        "secretariat_emails": settings.get("secretariat_emails", []),
        "claim_garanzie": garanzie,
        "default_claim_garanzia": default_garanzia,
        "cat_settings": cat_settings,
        "provider_settings": provider_settings if include_provider_secrets else None,
        "ai_settings": ai_settings if include_provider_secrets else None,
    }


def _normalize_portal_domain(value: str) -> str | None:
    candidate = value.strip().lower()
    candidate = candidate.replace("https://", "").replace("http://", "")
    candidate = candidate.split("/", 1)[0].split("?", 1)[0].strip().rstrip(".")
    if not candidate:
        return None
    if candidate.startswith("assicurati."):
        candidate = candidate[len("assicurati."):]
    return candidate or None


def _normalize_portal_domains(values: list[str]) -> list[str]:
    normalized: list[str] = []
    for value in values:
        domain = _normalize_portal_domain(value)
        if domain and domain not in normalized:
            normalized.append(domain)
    return normalized


async def _is_tenant_admin(db: AsyncSession, user: User) -> bool:
    result = await db.execute(
        select(Role.name)
        .select_from(user_roles.join(Role, user_roles.c.role_id == Role.id))
        .where(user_roles.c.user_id == user.id)
    )
    role_names = {row[0] for row in result.all()}
    return "admin_tenant" in role_names or "admin" in role_names


ROLE_MAP_FROM_APP = {
    "admin": "admin_tenant",
    "direttore": "direttore",
    "capoTeam": "capoTeam",
    "gestore": "gestore",
    "perito": "perito",
    "cat": "cat",
    "segreteria": "segreteria",
}


ROLE_MAP_TO_APP = {
    "admin_tenant": "admin",
    "admin": "admin",
    "direttore": "direttore",
    "capoTeam": "capoTeam",
    "gestore": "gestore",
    "perito": "perito",
    "expert": "perito",
    "cat": "cat",
    "segreteria": "segreteria",
}


async def _fetch_role_names(db: AsyncSession, user_id: str) -> list[str]:
    result = await db.execute(
        select(Role.name)
        .select_from(user_roles.join(Role, user_roles.c.role_id == Role.id))
        .where(user_roles.c.user_id == user_id)
    )
    mapped: list[str] = []
    for row in result.all():
        app_name = ROLE_MAP_TO_APP.get(row[0])
        if app_name and app_name not in mapped:
            mapped.append(app_name)
    return mapped


async def _ensure_roles(db: AsyncSession, user: User, app_role_names: list[str]) -> None:
    normalized = []
    for name in app_role_names:
        mapped = ROLE_MAP_FROM_APP.get(name)
        if mapped and mapped not in normalized:
            normalized.append(mapped)

    await db.execute(user_roles.delete().where(user_roles.c.user_id == user.id))

    for name in normalized:
        result = await db.execute(select(Role).where(Role.tenant_id == user.tenant_id, Role.name == name))
        role = result.scalar_one_or_none()
        if role is None:
            role = Role(
                id=str(uuid.uuid4()),
                tenant_id=user.tenant_id,
                name=name,
                description=f"Ruolo {name}",
            )
            db.add(role)
            await db.flush()
        await db.execute(user_roles.insert().values(user_id=user.id, role_id=role.id))


async def _tenant_user_response(db: AsyncSession, user: User) -> TenantUserResponse:
    role_names = await _fetch_role_names(db, user.id)
    aliases = await get_user_aliases(db, user)
    settings_json = dict(user.settings_json or {})
    return TenantUserResponse(
        id=user.id,
        tenant_id=user.tenant_id,
        personal_email=user.personal_email or user.email,
        professional_email=user.professional_email,
        email_aliases=aliases,
        first_name=user.first_name or "",
        last_name=user.last_name or "",
        full_name=user.full_name,
        job_title=user.job_title,
        phone_number=user.phone_number,
        contract_type=user.contract_type,
        roles=role_names,
        is_active=user.is_active,
        invite_status=settings_json.get("invite_status"),
        invited_at=settings_json.get("invited_at"),
        last_login_at=user.last_login_at.isoformat() if user.last_login_at else None,
    )


async def _send_supabase_invite(personal_email: str) -> tuple[str, str | None]:
    if not settings.SUPABASE_URL or not settings.SUPABASE_SERVICE_ROLE_KEY:
        return "not_configured", "Supabase service role key is not configured"

    body = json.dumps({
        "email": personal_email,
        "data": {},
        "redirect_to": settings.APP_PUBLIC_URL,
    }).encode("utf-8")
    req = urlrequest.Request(
        f"{settings.SUPABASE_URL}/auth/v1/invite",
        data=body,
        headers={
            "apikey": settings.SUPABASE_SERVICE_ROLE_KEY,
            "Authorization": f"Bearer {settings.SUPABASE_SERVICE_ROLE_KEY}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        method="POST",
    )
    try:
        await asyncio.to_thread(lambda: urlrequest.urlopen(req, timeout=20).read())
        return "sent", None
    except urlerror.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="ignore")
        return "failed", detail or f"HTTP {exc.code}"
    except urlerror.URLError as exc:
        return "failed", str(exc)


async def _resolve_target_tenant(
    db: AsyncSession,
    current_user: User,
    tenant_id: str | None
) -> Tenant:
    target_tenant_id = current_user.tenant_id

    if tenant_id:
        if current_user.is_platform_admin:
            target_tenant_id = tenant_id
        elif tenant_id != current_user.tenant_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Tenant access denied"
            )

    if not current_user.is_platform_admin and not await _is_tenant_admin(db, current_user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Tenant admin access required"
        )

    result = await db.execute(select(Tenant).where(Tenant.id == target_tenant_id))
    tenant = result.scalar_one_or_none()
    if tenant is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Tenant not found")
    return tenant


@router.get("/me/settings", response_model=TenantSettingsResponse)
async def get_my_tenant_settings(
    tenant_id: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    tenant = await _resolve_target_tenant(db, current_user, tenant_id)
    settings = _normalized_settings(tenant, include_provider_secrets=current_user.is_platform_admin)
    return TenantSettingsResponse(tenant_id=tenant.id, **settings)


@router.get("/me/ai-keys", response_model=TenantAIKeysResponse)
async def get_my_tenant_ai_keys(
    tenant_id: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """Returns AI API keys for the authenticated user's tenant. All tenant members can read."""
    tenant = await _resolve_target_tenant(db, current_user, tenant_id)
    settings = tenant.settings_json or {}
    ai = settings.get("ai_settings", _default_ai_settings())
    if not isinstance(ai, dict):
        ai = _default_ai_settings()
    return TenantAIKeysResponse(
        openai_api_key=ai.get("openai_api_key", ""),
        openai_model=ai.get("openai_model", "gpt-4o"),
        anthropic_api_key=ai.get("anthropic_api_key", ""),
        anthropic_model=ai.get("anthropic_model", "claude-opus-4-7"),
    )


@router.put("/me/settings", response_model=TenantSettingsResponse)
async def update_my_tenant_settings(
    payload: TenantMailSettingsPayload,
    tenant_id: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    tenant = await _resolve_target_tenant(db, current_user, tenant_id)

    if payload.provider_settings is not None and not current_user.is_platform_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Provider settings can only be managed by platform admin",
        )

    tenant.name = payload.tenant_name
    tenant.slug = payload.tenant_slug
    portal_domains = _normalize_portal_domains(payload.portal_domains)

    updated_settings = {
        **dict(tenant.settings_json or {}),
        "portal_domains": portal_domains,
        "internal_domains": payload.internal_domains,
        "internal_emails": [str(value) for value in payload.internal_emails],
        "system_emails": [str(value) for value in payload.system_emails],
        "secretariat_emails": [str(value) for value in payload.secretariat_emails],
        "claim_garanzie": payload.claim_garanzie or ["Fenomeno Elettrico"],
        "default_claim_garanzia": payload.default_claim_garanzia or "Fenomeno Elettrico",
        "cat_settings": payload.cat_settings.model_dump(),
    }
    if current_user.is_platform_admin and payload.provider_settings is not None:
        updated_settings["provider_settings"] = payload.provider_settings.model_dump()
    if current_user.is_platform_admin and payload.ai_settings is not None:
        updated_settings["ai_settings"] = payload.ai_settings.model_dump()

    tenant.settings_json = updated_settings
    await db.execute(delete(TenantPortalDomain).where(TenantPortalDomain.tenant_id == tenant.id))
    for index, domain in enumerate(portal_domains):
        db.add(
            TenantPortalDomain(
                id=str(uuid.uuid4()),
                tenant_id=tenant.id,
                domain=domain,
                is_primary=index == 0,
            )
        )

    await db.commit()
    await db.refresh(tenant)

    settings = _normalized_settings(tenant, include_provider_secrets=current_user.is_platform_admin)
    return TenantSettingsResponse(tenant_id=tenant.id, **settings)


@router.get("/me/users", response_model=list[TenantUserResponse])
async def list_tenant_users(
    tenant_id: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    tenant = await _resolve_target_tenant(db, current_user, tenant_id)
    result = await db.execute(
        select(User)
        .where(User.tenant_id == tenant.id)
        .order_by(User.full_name.asc(), User.email.asc())
    )
    users = result.scalars().all()
    return [await _tenant_user_response(db, user) for user in users]


@router.post("/me/users", response_model=TenantUserInviteResponse, status_code=status.HTTP_201_CREATED)
async def create_tenant_user(
    payload: TenantUserCreateRequest,
    tenant_id: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    tenant = await _resolve_target_tenant(db, current_user, tenant_id)
    personal_email = str(payload.personal_email).lower()

    existing = await db.execute(
        select(User).where((User.personal_email == personal_email) | (User.email == personal_email))
    )
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Personal email already exists")

    full_name = f"{payload.first_name.strip()} {payload.last_name.strip()}".strip()
    user = User(
        id=str(uuid.uuid4()),
        tenant_id=tenant.id,
        email=personal_email,
        personal_email=personal_email,
        full_name=full_name,
        first_name=payload.first_name.strip(),
        last_name=payload.last_name.strip(),
        job_title=payload.job_title,
        phone_number=payload.phone_number,
        contract_type=payload.contract_type,
        password_hash=get_password_hash(str(uuid.uuid4())),
        is_active=True,
        is_platform_admin=False,
        settings_json={},
    )
    db.add(user)
    await db.flush()
    await _ensure_roles(db, user, payload.roles)
    await ensure_professional_email(db, user, payload.roles)

    invite_status = "not_sent"
    invite_error = None
    if payload.send_invite:
        invite_status, invite_error = await _send_supabase_invite(personal_email)

    metadata = dict(user.settings_json or {})
    metadata["invite_status"] = invite_status
    metadata["invited_at"] = datetime.now(timezone.utc).isoformat() if invite_status == "sent" else None
    if invite_error:
        metadata["invite_error"] = invite_error
    user.settings_json = metadata

    await db.commit()
    await db.refresh(user)
    return TenantUserInviteResponse(
        user=await _tenant_user_response(db, user),
        invite_status=invite_status,
        invite_error=invite_error,
    )


@router.put("/me/users/{user_id}", response_model=TenantUserResponse)
async def update_tenant_user(
    user_id: str,
    payload: TenantUserUpdateRequest,
    tenant_id: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    tenant = await _resolve_target_tenant(db, current_user, tenant_id)
    result = await db.execute(select(User).where(User.id == user_id, User.tenant_id == tenant.id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    user.first_name = payload.first_name.strip()
    user.last_name = payload.last_name.strip()
    user.full_name = f"{user.first_name} {user.last_name}".strip()
    user.job_title = payload.job_title
    user.phone_number = payload.phone_number
    user.contract_type = payload.contract_type
    user.is_active = payload.is_active

    await _ensure_roles(db, user, payload.roles)
    if payload.professional_email:
        await set_professional_email(db, user, str(payload.professional_email), source="admin")
    else:
        await ensure_professional_email(db, user, payload.roles)

    await db.commit()
    await db.refresh(user)
    return await _tenant_user_response(db, user)


@router.post("/me/users/{user_id}/invite", response_model=TenantUserInviteResponse)
async def resend_tenant_user_invite(
    user_id: str,
    tenant_id: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    tenant = await _resolve_target_tenant(db, current_user, tenant_id)
    result = await db.execute(select(User).where(User.id == user_id, User.tenant_id == tenant.id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    await ensure_personal_email(db, user)
    invite_status, invite_error = await _send_supabase_invite(user.personal_email or user.email)
    metadata = dict(user.settings_json or {})
    metadata["invite_status"] = invite_status
    metadata["invited_at"] = datetime.now(timezone.utc).isoformat() if invite_status == "sent" else metadata.get("invited_at")
    if invite_error:
        metadata["invite_error"] = invite_error
    else:
        metadata.pop("invite_error", None)
    user.settings_json = metadata

    await db.commit()
    await db.refresh(user)
    return TenantUserInviteResponse(
        user=await _tenant_user_response(db, user),
        invite_status=invite_status,
        invite_error=invite_error,
    )
