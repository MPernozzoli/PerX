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


def _normalized_settings(tenant: Tenant) -> dict:
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
    return {
        "tenant_name": tenant.name,
        "tenant_slug": tenant.slug,
        "internal_domains": settings.get("internal_domains", []),
        "internal_emails": settings.get("internal_emails", []),
        "system_emails": settings.get("system_emails", []),
        "secretariat_emails": settings.get("secretariat_emails", []),
        "claim_garanzie": garanzie,
        "default_claim_garanzia": default_garanzia,
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
    settings = _normalized_settings(tenant)
    return TenantSettingsResponse(tenant_id=tenant.id, **settings)


@router.put("/me/settings", response_model=TenantSettingsResponse)
async def update_my_tenant_settings(
    payload: TenantMailSettingsPayload,
    tenant_id: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    tenant = await _resolve_target_tenant(db, current_user, tenant_id)

    tenant.name = payload.tenant_name
    tenant.slug = payload.tenant_slug
    tenant.settings_json = {
        "internal_domains": payload.internal_domains,
        "internal_emails": [str(value) for value in payload.internal_emails],
        "system_emails": [str(value) for value in payload.system_emails],
        "secretariat_emails": [str(value) for value in payload.secretariat_emails],
        "claim_garanzie": payload.claim_garanzie or ["Fenomeno Elettrico"],
        "default_claim_garanzia": payload.default_claim_garanzia or "Fenomeno Elettrico",
    }

    await db.commit()
    await db.refresh(tenant)

    settings = _normalized_settings(tenant)
    return TenantSettingsResponse(tenant_id=tenant.id, **settings)
