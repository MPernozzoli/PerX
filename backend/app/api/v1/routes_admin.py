"""
Platform-admin routes
"""
import json
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import delete, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_platform_admin
from app.models.tenant import Tenant, TenantPortalDomain
from app.models.user import User
from app.schemas.admin import AdminUserResponse, DomainRouteResponse, DomainRouteUpsert, TenantResponse, TenantUpsert
from app.schemas.tenant_settings import TenantMailSettingsPayload, TenantSettingsResponse
from app.api.v1.routes_tenants import _normalize_portal_domains, _normalized_settings

router = APIRouter()


@router.get("/tenants", response_model=list[TenantResponse])
async def list_tenants(
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_platform_admin)
):
    result = await db.execute(select(Tenant).order_by(Tenant.name.asc()))
    return [TenantResponse.model_validate(item) for item in result.scalars().all()]


def _normalize_slug(slug: str) -> str:
    return slug.strip().lower().replace(" ", "-")


async def _ensure_unique_tenant_slug(db: AsyncSession, slug: str, tenant_id: str | None = None) -> None:
    query = select(Tenant).where(Tenant.slug == slug)
    if tenant_id:
        query = query.where(Tenant.id != tenant_id)
    result = await db.execute(query)
    if result.scalar_one_or_none() is not None:
        raise HTTPException(status_code=409, detail="Tenant slug already exists")


@router.post("/tenants", response_model=TenantResponse, status_code=status.HTTP_201_CREATED)
async def create_tenant(
    payload: TenantUpsert,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_platform_admin),
):
    slug = _normalize_slug(payload.slug)
    if not slug:
        raise HTTPException(status_code=400, detail="Tenant slug non valido")
    await _ensure_unique_tenant_slug(db, slug)

    tenant = Tenant(
        id=str(uuid.uuid4()),
        name=payload.name.strip(),
        slug=slug,
        settings_json=payload.settings_json or {},
    )
    db.add(tenant)
    await db.commit()
    await db.refresh(tenant)
    return TenantResponse.model_validate(tenant)


@router.put("/tenants/{tenant_id}", response_model=TenantResponse)
async def update_tenant(
    tenant_id: str,
    payload: TenantUpsert,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_platform_admin),
):
    result = await db.execute(select(Tenant).where(Tenant.id == tenant_id))
    tenant = result.scalar_one_or_none()
    if tenant is None:
        raise HTTPException(status_code=404, detail="Tenant not found")

    slug = _normalize_slug(payload.slug)
    if not slug:
        raise HTTPException(status_code=400, detail="Tenant slug non valido")
    await _ensure_unique_tenant_slug(db, slug, tenant_id=tenant.id)

    tenant.name = payload.name.strip()
    tenant.slug = slug
    if payload.settings_json is not None:
        tenant.settings_json = payload.settings_json
    await db.commit()
    await db.refresh(tenant)
    return TenantResponse.model_validate(tenant)


@router.get("/tenants/{tenant_id}/settings", response_model=TenantSettingsResponse)
async def get_tenant_settings(
    tenant_id: str,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_platform_admin),
):
    result = await db.execute(select(Tenant).where(Tenant.id == tenant_id))
    tenant = result.scalar_one_or_none()
    if tenant is None:
        raise HTTPException(status_code=404, detail="Tenant not found")
    settings = _normalized_settings(tenant, include_provider_secrets=True)
    return TenantSettingsResponse(tenant_id=tenant.id, **settings)


@router.put("/tenants/{tenant_id}/settings", response_model=TenantSettingsResponse)
async def update_tenant_settings(
    tenant_id: str,
    payload: TenantMailSettingsPayload,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_platform_admin),
):
    result = await db.execute(select(Tenant).where(Tenant.id == tenant_id))
    tenant = result.scalar_one_or_none()
    if tenant is None:
        raise HTTPException(status_code=404, detail="Tenant not found")

    slug = _normalize_slug(payload.tenant_slug)
    if not slug:
        raise HTTPException(status_code=400, detail="Tenant slug non valido")
    await _ensure_unique_tenant_slug(db, slug, tenant_id=tenant.id)

    tenant.name = payload.tenant_name.strip()
    tenant.slug = slug
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
    if payload.provider_settings is not None:
        updated_settings["provider_settings"] = payload.provider_settings.model_dump()

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
    settings = _normalized_settings(tenant, include_provider_secrets=True)
    return TenantSettingsResponse(tenant_id=tenant.id, **settings)


@router.get("/users", response_model=list[AdminUserResponse])
async def list_users(
    tenant_id: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_platform_admin)
):
    query = select(User).order_by(User.email.asc())
    if tenant_id:
        query = query.where(User.tenant_id == tenant_id)

    result = await db.execute(query)
    return [AdminUserResponse.model_validate(item) for item in result.scalars().all()]


def _normalize_hostname(hostname: str) -> str:
    value = hostname.strip().lower().removeprefix("https://").removeprefix("http://").split("/", 1)[0].split("?", 1)[0]
    if ":" in value and not value.startswith("["):
        value = value.rsplit(":", 1)[0]
    return value.rstrip(".")


def _domain_route_response(row) -> DomainRouteResponse:
    mapping = dict(row)
    return DomainRouteResponse(
        id=mapping["id"],
        hostname=mapping["hostname"],
        app=mapping["app"],
        tenant_id=mapping.get("tenant_id"),
        tenant_name=mapping.get("tenant_name"),
        destination_url=mapping.get("destination_url"),
        is_active=mapping["is_active"],
        notes=mapping.get("notes"),
        metadata_json=mapping.get("metadata_json") or {},
    )


@router.get("/domain-routes", response_model=list[DomainRouteResponse])
async def list_domain_routes(
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_platform_admin),
):
    result = await db.execute(
        text(
            """
            SELECT dr.*, t.name AS tenant_name
            FROM domain_routes dr
            LEFT JOIN tenants t ON t.id = dr.tenant_id
            ORDER BY dr.hostname ASC
            """
        )
    )
    return [_domain_route_response(row) for row in result.mappings().all()]


@router.post("/domain-routes", response_model=DomainRouteResponse, status_code=status.HTTP_201_CREATED)
async def create_domain_route(
    payload: DomainRouteUpsert,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_platform_admin),
):
    hostname = _normalize_hostname(payload.hostname)
    if not hostname:
        raise HTTPException(status_code=400, detail="Hostname non valido")

    result = await db.execute(
        text(
            """
            INSERT INTO domain_routes
              (hostname, app, tenant_id, destination_url, is_active, notes, metadata_json)
            VALUES
              (:hostname, :app, :tenant_id, :destination_url, :is_active, :notes, cast(:metadata_json as jsonb))
            RETURNING *
            """
        ),
        {
            "hostname": hostname,
            "app": payload.app,
            "tenant_id": payload.tenant_id,
            "destination_url": payload.destination_url,
            "is_active": payload.is_active,
            "notes": payload.notes,
            "metadata_json": json.dumps(payload.metadata_json or {}, ensure_ascii=False),
        },
    )
    await db.commit()
    row = result.mappings().one()
    tenant = None
    if row.get("tenant_id"):
        tenant_result = await db.execute(select(Tenant).where(Tenant.id == row["tenant_id"]))
        tenant = tenant_result.scalar_one_or_none()
    data = dict(row)
    data["tenant_name"] = tenant.name if tenant else None
    return _domain_route_response(data)


@router.put("/domain-routes/{route_id}", response_model=DomainRouteResponse)
async def update_domain_route(
    route_id: str,
    payload: DomainRouteUpsert,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_platform_admin),
):
    hostname = _normalize_hostname(payload.hostname)
    result = await db.execute(
        text(
            """
            UPDATE domain_routes
            SET hostname = :hostname,
                app = :app,
                tenant_id = :tenant_id,
                destination_url = :destination_url,
                is_active = :is_active,
                notes = :notes,
                metadata_json = cast(:metadata_json as jsonb),
                updated_at = now()
            WHERE id = :route_id
            RETURNING *
            """
        ),
        {
            "route_id": route_id,
            "hostname": hostname,
            "app": payload.app,
            "tenant_id": payload.tenant_id,
            "destination_url": payload.destination_url,
            "is_active": payload.is_active,
            "notes": payload.notes,
            "metadata_json": json.dumps(payload.metadata_json or {}, ensure_ascii=False),
        },
    )
    row = result.mappings().first()
    if row is None:
        raise HTTPException(status_code=404, detail="Domain route not found")
    await db.commit()
    data = dict(row)
    tenant = None
    if data.get("tenant_id"):
        tenant_result = await db.execute(select(Tenant).where(Tenant.id == data["tenant_id"]))
        tenant = tenant_result.scalar_one_or_none()
    data["tenant_name"] = tenant.name if tenant else None
    return _domain_route_response(data)


@router.delete("/domain-routes/{route_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_domain_route(
    route_id: str,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_platform_admin),
):
    result = await db.execute(text("DELETE FROM domain_routes WHERE id = :route_id"), {"route_id": route_id})
    if result.rowcount == 0:
        raise HTTPException(status_code=404, detail="Domain route not found")
    await db.commit()
