"""
Deployment host routing resolution for Vercel middleware/proxy.
"""
from __future__ import annotations

from fastapi import APIRouter, Header, HTTPException, Query, status
from sqlalchemy import text

from app.core.config import settings
from app.core.database import AsyncSessionLocal

router = APIRouter()


def _normalize_hostname(hostname: str) -> str:
    value = hostname.strip().lower().removeprefix("https://").removeprefix("http://").split("/", 1)[0].split("?", 1)[0]
    if ":" in value and not value.startswith("["):
        value = value.rsplit(":", 1)[0]
    return value.rstrip(".")


@router.get("/resolve-host")
async def resolve_host_route(
    host: str = Query(...),
    x_perx_routing_secret: str | None = Header(default=None),
):
    if settings.ROUTING_RESOLVE_SECRET and x_perx_routing_secret != settings.ROUTING_RESOLVE_SECRET:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid routing secret")

    hostname = _normalize_hostname(host)
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            text(
                """
                SELECT dr.*, t.slug AS tenant_slug, t.name AS tenant_name
                FROM domain_routes dr
                LEFT JOIN tenants t ON t.id = dr.tenant_id
                WHERE dr.hostname = :hostname AND dr.is_active = true
                LIMIT 1
                """
            ),
            {"hostname": hostname},
        )
        route = result.mappings().first()
        if route:
            return {
                "found": True,
                "hostname": hostname,
                "app": route["app"],
                "tenant_id": route.get("tenant_id"),
                "tenant_slug": route.get("tenant_slug"),
                "tenant_name": route.get("tenant_name"),
                "destination_url": route.get("destination_url"),
            }

        if hostname.startswith("assicurati."):
            tenant_domain = hostname.removeprefix("assicurati.")
            tenant_result = await db.execute(
                text(
                    """
                    SELECT t.id, t.slug, t.name
                    FROM tenant_portal_domains d
                    JOIN tenants t ON t.id = d.tenant_id
                    WHERE d.domain = :domain
                    LIMIT 1
                    """
                ),
                {"domain": tenant_domain},
            )
            tenant = tenant_result.mappings().first()
            if tenant:
                return {
                    "found": True,
                    "hostname": hostname,
                    "app": "insured_portal",
                    "tenant_id": tenant["id"],
                    "tenant_slug": tenant["slug"],
                    "tenant_name": tenant["name"],
                    "tenant_domain": tenant_domain,
                    "destination_url": None,
                }

    return {"found": False, "hostname": hostname, "app": "insured_portal", "destination_url": None}
