"""
Bootstrap the minimal single-tenant V1 database state.

Run after Alembic migrations:
    python scripts/bootstrap_single_tenant.py
"""

from __future__ import annotations

import asyncio
import json
import os
import uuid
from datetime import datetime
from urllib import error as urlerror
from urllib import request as urlrequest

import asyncpg

from app.core.config import settings
from app.core.security import get_password_hash


ROLE_DEFINITIONS = {
    "admin_tenant": "Amministratore tenant",
    "direttore": "Direttore",
    "capoTeam": "Capo team",
    "gestore": "Gestore",
    "perito": "Perito",
    "cat": "Tecnico CAT",
    "segreteria": "Segreteria",
}


def _asyncpg_database_url() -> str:
    url = settings.DATABASE_URL
    return url.replace("postgresql+asyncpg://", "postgresql://", 1)


def _tenant_id() -> str:
    return settings.SINGLE_TENANT_ID.strip() or "perx-single-tenant"


def _tenant_name() -> str:
    return settings.SINGLE_TENANT_NAME.strip() or settings.PLATFORM_TENANT_NAME


def _tenant_slug() -> str:
    return (settings.SINGLE_TENANT_SLUG.strip() or settings.PLATFORM_TENANT_SLUG).lower()


def _admin_email() -> str:
    return (settings.SINGLE_TENANT_ADMIN_EMAIL or settings.APP_ADMIN_EMAIL).strip().lower()


def _admin_full_name() -> str:
    return (settings.SINGLE_TENANT_ADMIN_FULL_NAME or settings.APP_ADMIN_FULL_NAME).strip()


def _admin_password() -> str:
    return settings.SINGLE_TENANT_ADMIN_PASSWORD or settings.APP_ADMIN_DEFAULT_PASSWORD


def _domain_from_email(email: str) -> str | None:
    if "@" not in email:
        return None
    return email.rsplit("@", 1)[1].strip().lower() or None


def _default_settings() -> dict:
    admin_email = _admin_email()
    default_from = (settings.RESEND_DEFAULT_FROM_EMAIL or admin_email).strip().lower()
    internal_domains = []
    for email in (admin_email, default_from):
        domain = _domain_from_email(email)
        if domain and domain not in internal_domains:
            internal_domains.append(domain)

    return {
        "portal_domains": [],
        "internal_domains": internal_domains,
        "internal_emails": [admin_email],
        "system_emails": [admin_email],
        "secretariat_emails": [],
        "claim_garanzie": ["Fenomeno Elettrico"],
        "default_claim_garanzia": "Fenomeno Elettrico",
        "cat_settings": {
            "enabled": False,
            "planner": {
                "route_generation_hour": 9,
                "route_review_window_minutes": 60,
                "availability_slot_minutes": 120,
                "availability_tolerance_percent": 50,
                "max_outside_zone_kilometers": 50,
            },
            "technicians": [],
            "municipalities": [],
        },
        "provider_settings": {
            "map_provider": "google_maps",
            "maps_api_key": "",
            "routing_provider": "google_routes",
            "routing_api_key": "",
            "geocoding_provider": "google_geocoding",
            "geocoding_api_key": "",
            "messaging_provider": "twilio",
            "messaging_api_key": "",
        },
        "ai_settings": {
            "openai_api_key": os.environ.get("OPENAI_API_KEY", ""),
            "openai_model": os.environ.get("OPENAI_MODEL", "gpt-4o"),
            "anthropic_api_key": os.environ.get("ANTHROPIC_API_KEY", ""),
            "anthropic_model": os.environ.get("ANTHROPIC_MODEL", "claude-opus-4-7"),
        },
    }


def _merged_settings(existing: dict | None) -> dict:
    defaults = _default_settings()
    if isinstance(existing, str):
        existing = json.loads(existing) if existing.strip() else {}
    current = dict(existing or {})
    merged = {**defaults, **current}
    for nested_key in ("cat_settings", "provider_settings", "ai_settings"):
        merged[nested_key] = {
            **defaults.get(nested_key, {}),
            **(current.get(nested_key) or {}),
        }
    return merged


async def _ensure_supabase_auth_user(email: str, password: str, full_name: str) -> None:
    if not settings.FF_CLOUD_AUTH_ENABLED:
        return
    if not settings.SUPABASE_URL or not settings.SUPABASE_SERVICE_ROLE_KEY:
        print("WARN: Supabase auth enabled but SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY is missing")
        return

    payload = {
        "email": email,
        "password": password,
        "email_confirm": True,
        "user_metadata": {"full_name": full_name},
    }
    headers = {
        "apikey": settings.SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {settings.SUPABASE_SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
    }

    def _request() -> None:
        req = urlrequest.Request(
            f"{settings.SUPABASE_URL}/auth/v1/admin/users",
            data=json.dumps(payload).encode("utf-8"),
            headers=headers,
            method="POST",
        )
        with urlrequest.urlopen(req, timeout=20) as response:
            response.read()

    try:
        await asyncio.to_thread(_request)
        print(f"Supabase auth user ready: {email}")
    except urlerror.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="ignore").lower()
        if exc.code in (400, 422) and any(token in body for token in ("already", "exists", "registered")):
            print(f"Supabase auth user already exists: {email}")
            return
        raise


async def _ensure_role(conn: asyncpg.Connection, tenant_id: str, name: str, description: str) -> str:
    existing = await conn.fetchval(
        "SELECT id FROM roles WHERE tenant_id = $1 AND name = $2 LIMIT 1",
        tenant_id,
        name,
    )
    if existing:
        return existing

    role_id = str(uuid.uuid4())
    await conn.execute(
        """
        INSERT INTO roles (id, tenant_id, name, description)
        VALUES ($1, $2, $3, $4)
        """,
        role_id,
        tenant_id,
        name,
        description,
    )
    return role_id


async def bootstrap() -> None:
    tenant_id = _tenant_id()
    tenant_name = _tenant_name()
    tenant_slug = _tenant_slug()
    admin_email = _admin_email()
    admin_full_name = _admin_full_name()
    admin_password = _admin_password()
    first_name, _, last_name = admin_full_name.partition(" ")

    conn = await asyncpg.connect(_asyncpg_database_url())
    try:
        existing_tenant = await conn.fetchrow(
            "SELECT id, settings_json FROM tenants WHERE id = $1 OR slug = $2 LIMIT 1",
            tenant_id,
            tenant_slug,
        )
        if existing_tenant:
            tenant_id = existing_tenant["id"]
            settings_json = _merged_settings(existing_tenant["settings_json"])
            await conn.execute(
                """
                UPDATE tenants
                SET name = $2, slug = $3, settings_json = CAST($4 AS json)
                WHERE id = $1
                """,
                tenant_id,
                tenant_name,
                tenant_slug,
                json.dumps(settings_json),
            )
        else:
            await conn.execute(
                """
                INSERT INTO tenants (id, name, slug, settings_json, created_at)
                VALUES ($1, $2, $3, CAST($4 AS json), $5)
                """,
                tenant_id,
                tenant_name,
                tenant_slug,
                json.dumps(_default_settings()),
                datetime.utcnow(),
            )

        admin_hash = get_password_hash(admin_password)
        admin_id = await conn.fetchval("SELECT id FROM users WHERE email = $1", admin_email)
        if admin_id:
            await conn.execute(
                """
                UPDATE users
                SET tenant_id = $2,
                    personal_email = $3,
                    full_name = $4,
                    first_name = $5,
                    last_name = $6,
                    password_hash = $7,
                    is_active = true,
                    is_platform_admin = true
                WHERE id = $1
                """,
                admin_id,
                tenant_id,
                admin_email,
                admin_full_name,
                first_name or admin_full_name,
                last_name,
                admin_hash,
            )
        else:
            admin_id = str(uuid.uuid4())
            await conn.execute(
                """
                INSERT INTO users
                  (id, tenant_id, email, personal_email, full_name, first_name, last_name,
                   password_hash, is_active, is_platform_admin, created_at)
                VALUES
                  ($1, $2, $3, $3, $4, $5, $6, $7, true, true, $8)
                """,
                admin_id,
                tenant_id,
                admin_email,
                admin_full_name,
                first_name or admin_full_name,
                last_name,
                admin_hash,
                datetime.utcnow(),
            )

        admin_role_id = None
        for role_name, description in ROLE_DEFINITIONS.items():
            role_id = await _ensure_role(conn, tenant_id, role_name, description)
            if role_name == "admin_tenant":
                admin_role_id = role_id

        if admin_role_id:
            await conn.execute(
                """
                INSERT INTO user_roles (user_id, role_id)
                VALUES ($1, $2)
                ON CONFLICT DO NOTHING
                """,
                admin_id,
                admin_role_id,
            )

        await _ensure_supabase_auth_user(admin_email, admin_password, admin_full_name)

        print("Single-tenant bootstrap completed")
        print(f"tenant: {tenant_name} ({tenant_slug}) id={tenant_id}")
        print(f"admin: {admin_email}")
    finally:
        await conn.close()


if __name__ == "__main__":
    asyncio.run(bootstrap())
