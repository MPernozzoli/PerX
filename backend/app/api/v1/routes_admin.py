"""
Platform-admin routes
"""
import json

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_platform_admin
from app.models.tenant import Tenant
from app.models.user import User
from app.schemas.admin import AdminUserResponse, DomainRouteResponse, DomainRouteUpsert, TenantResponse

router = APIRouter()


@router.get("/tenants", response_model=list[TenantResponse])
async def list_tenants(
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_platform_admin)
):
    result = await db.execute(select(Tenant).order_by(Tenant.name.asc()))
    return [TenantResponse.model_validate(item) for item in result.scalars().all()]


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


async def _domain_route_response(row) -> DomainRouteResponse:
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
    return [await _domain_route_response(row) for row in result.mappings().all()]


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
    return await _domain_route_response(data)


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
    data["tenant_name"] = None
    return await _domain_route_response(data)


@router.delete("/domain-routes/{route_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_domain_route(
    route_id: str,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_platform_admin),
):
    await db.execute(text("DELETE FROM domain_routes WHERE id = :route_id"), {"route_id": route_id})
    await db.commit()
