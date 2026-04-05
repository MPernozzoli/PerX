"""
Tenant settings routes
"""
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_active_user
from app.models.role import Role, user_roles
from app.models.tenant import Tenant
from app.models.user import User
from app.schemas.tenant_settings import TenantMailSettingsPayload, TenantSettingsResponse

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

    return {
        "tenant_name": tenant.name,
        "tenant_slug": tenant.slug,
        "internal_domains": settings.get("internal_domains", []),
        "internal_emails": settings.get("internal_emails", []),
        "system_emails": settings.get("system_emails", []),
        "secretariat_emails": settings.get("secretariat_emails", []),
        "claim_garanzie": garanzie,
        "default_claim_garanzia": default_garanzia,
        "cat_settings": cat_settings,
        "provider_settings": provider_settings if include_provider_secrets else None,
    }


async def _is_tenant_admin(db: AsyncSession, user: User) -> bool:
    result = await db.execute(
        select(Role.name)
        .select_from(user_roles.join(Role, user_roles.c.role_id == Role.id))
        .where(user_roles.c.user_id == user.id)
    )
    role_names = {row[0] for row in result.all()}
    return "admin_tenant" in role_names or "admin" in role_names


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

    updated_settings = {
        **dict(tenant.settings_json or {}),
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

    tenant.settings_json = updated_settings

    await db.commit()
    await db.refresh(tenant)

    settings = _normalized_settings(tenant, include_provider_secrets=current_user.is_platform_admin)
    return TenantSettingsResponse(tenant_id=tenant.id, **settings)
