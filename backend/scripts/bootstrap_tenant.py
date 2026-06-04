"""
Bootstrap or update a PerX tenant in a multi-tenant database.

Example:
    TENANT_ADMIN_PASSWORD='replace-me' python scripts/bootstrap_tenant.py \
      --tenant-id randa-srl \
      --name "Randa SRL" \
      --slug randa \
      --admin-email info@randapro.it \
      --admin-full-name "Randa SRL Admin" \
      --portal-domain assicurati.randapro.it \
      --internal-domain randapro.it \
      --email-domain randapro.it
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import ssl
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from urllib import error as urlerror
from urllib import request as urlrequest
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

import asyncpg

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

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


def _asyncpg_connection_params() -> tuple[str, dict]:
    url = settings.DATABASE_URL.replace("postgresql+asyncpg://", "postgresql://", 1)
    parsed = urlsplit(url)
    query = dict(parse_qsl(parsed.query, keep_blank_values=True))
    ssl_mode = query.pop("ssl", None) or query.pop("sslmode", None)
    normalized = urlunsplit((parsed.scheme, parsed.netloc, parsed.path, urlencode(query), parsed.fragment))
    if not ssl_mode or ssl_mode.lower() in {"false", "disable"}:
        return normalized, {}
    ssl_context = ssl.create_default_context()
    ssl_context.check_hostname = False
    ssl_context.verify_mode = ssl.CERT_NONE
    return normalized, {"ssl": ssl_context}


def _normalize_domain(value: str) -> str:
    return value.strip().lower().replace("https://", "").replace("http://", "").strip("/")


def _default_settings(args: argparse.Namespace) -> dict:
    admin_email = args.admin_email.lower()
    return {
        "portal_domains": args.portal_domain,
        "internal_domains": args.internal_domain,
        "internal_emails": [admin_email],
        "system_emails": [admin_email],
        "secretariat_emails": [admin_email],
        "claim_garanzie": ["Fenomeno Elettrico", "Property"],
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
        "video_inspection_settings": {
            "enabled": False,
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
            "openai_api_key": "",
            "openai_model": "gpt-4o",
            "anthropic_api_key": "",
            "anthropic_model": "claude-opus-4-7",
        },
        "branding": {
            "primary_color": "#08275d",
        },
    }


def _merge_settings(existing: dict | str | None, defaults: dict) -> dict:
    if isinstance(existing, str):
        existing = json.loads(existing) if existing.strip() else {}
    current = dict(existing or {})
    merged = {**defaults, **current}
    for key in (
        "cat_settings",
        "video_inspection_settings",
        "provider_settings",
        "ai_settings",
        "branding",
    ):
        merged[key] = {**defaults.get(key, {}), **(current.get(key) or {})}
    return merged


async def _ensure_supabase_auth_user(email: str, password: str, full_name: str) -> None:
    if not settings.FF_CLOUD_AUTH_ENABLED:
        return
    if not settings.SUPABASE_URL or not settings.SUPABASE_SERVICE_ROLE_KEY:
        raise RuntimeError("Supabase auth is enabled but service credentials are missing")

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
    role_id = await conn.fetchval(
        "SELECT id FROM roles WHERE tenant_id = $1 AND name = $2 LIMIT 1",
        tenant_id,
        name,
    )
    if role_id:
        return role_id

    role_id = str(uuid.uuid4())
    await conn.execute(
        "INSERT INTO roles (id, tenant_id, name, description) VALUES ($1, $2, $3, $4)",
        role_id,
        tenant_id,
        name,
        description,
    )
    return role_id


async def bootstrap(args: argparse.Namespace) -> None:
    admin_email = args.admin_email.strip().lower()
    admin_password = os.environ.get("TENANT_ADMIN_PASSWORD", "")
    if not admin_password:
        raise RuntimeError("TENANT_ADMIN_PASSWORD is required")

    args.portal_domain = [_normalize_domain(value) for value in args.portal_domain]
    args.internal_domain = [_normalize_domain(value) for value in args.internal_domain]
    args.email_domain = _normalize_domain(args.email_domain) if args.email_domain else None
    defaults = _default_settings(args)
    first_name, _, last_name = args.admin_full_name.strip().partition(" ")

    database_url, connection_kwargs = _asyncpg_connection_params()
    conn = await asyncpg.connect(database_url, **connection_kwargs)
    try:
        async with conn.transaction():
            existing_tenant = await conn.fetchrow(
                "SELECT id, settings_json FROM tenants WHERE id = $1 OR slug = $2 LIMIT 1",
                args.tenant_id,
                args.slug,
            )
            if existing_tenant:
                tenant_id = existing_tenant["id"]
                settings_json = _merge_settings(existing_tenant["settings_json"], defaults)
                await conn.execute(
                    """
                    UPDATE tenants
                    SET name = $2, slug = $3, settings_json = CAST($4 AS json)
                    WHERE id = $1
                    """,
                    tenant_id,
                    args.name,
                    args.slug,
                    json.dumps(settings_json),
                )
            else:
                tenant_id = args.tenant_id
                await conn.execute(
                    """
                    INSERT INTO tenants (id, name, slug, settings_json, created_at)
                    VALUES ($1, $2, $3, CAST($4 AS json), $5)
                    """,
                    tenant_id,
                    args.name,
                    args.slug,
                    json.dumps(defaults),
                    datetime.now(timezone.utc),
                )

            await conn.execute("DELETE FROM tenant_portal_domains WHERE tenant_id = $1", tenant_id)
            for index, domain in enumerate(args.portal_domain):
                await conn.execute(
                    """
                    INSERT INTO tenant_portal_domains (id, tenant_id, domain, is_primary, created_at)
                    VALUES ($1, $2, $3, $4, $5)
                    """,
                    str(uuid.uuid4()),
                    tenant_id,
                    domain,
                    index == 0,
                    datetime.now(timezone.utc),
                )

            if args.email_domain:
                await conn.execute(
                    """
                    INSERT INTO tenant_email_domains
                      (id, tenant_id, domain, provider, inbound_enabled, outbound_enabled,
                       catch_all_enabled, status, settings_json, created_at)
                    VALUES
                      ($1, $2, $3, 'resend', 'true', 'true', 'true', 'pending', CAST($4 AS json), $5)
                    ON CONFLICT (domain) DO UPDATE
                    SET tenant_id = EXCLUDED.tenant_id,
                        settings_json = EXCLUDED.settings_json
                    """,
                    str(uuid.uuid4()),
                    tenant_id,
                    args.email_domain,
                    json.dumps({"bootstrap": "bootstrap_tenant.py"}),
                    datetime.now(timezone.utc),
                )

            admin_hash = get_password_hash(admin_password)
            admin_id = await conn.fetchval(
                "SELECT id FROM users WHERE personal_email = $1 OR email = $1 LIMIT 1",
                admin_email,
            )
            if admin_id:
                await conn.execute(
                    """
                    UPDATE users
                    SET tenant_id = $2, email = $3, personal_email = $3, full_name = $4,
                        first_name = $5, last_name = $6, password_hash = $7,
                        is_active = true, is_platform_admin = false
                    WHERE id = $1
                    """,
                    admin_id,
                    tenant_id,
                    admin_email,
                    args.admin_full_name,
                    first_name or args.admin_full_name,
                    last_name,
                    admin_hash,
                )
            else:
                admin_id = str(uuid.uuid4())
                await conn.execute(
                    """
                    INSERT INTO users
                      (id, tenant_id, email, personal_email, full_name, first_name, last_name,
                       password_hash, is_active, is_platform_admin, settings_json, created_at)
                    VALUES
                      ($1, $2, $3, $3, $4, $5, $6, $7, true, false, CAST('{}' AS json), $8)
                    """,
                    admin_id,
                    tenant_id,
                    admin_email,
                    args.admin_full_name,
                    first_name or args.admin_full_name,
                    last_name,
                    admin_hash,
                    datetime.now(timezone.utc),
                )

            admin_role_id = None
            for role_name, description in ROLE_DEFINITIONS.items():
                role_id = await _ensure_role(conn, tenant_id, role_name, description)
                if role_name == "admin_tenant":
                    admin_role_id = role_id
            await conn.execute(
                "INSERT INTO user_roles (user_id, role_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
                admin_id,
                admin_role_id,
            )

        await _ensure_supabase_auth_user(admin_email, admin_password, args.admin_full_name)
        print("Tenant bootstrap completed")
        print(f"tenant: {args.name} ({args.slug}) id={tenant_id}")
        print(f"admin: {admin_email}")
    finally:
        await conn.close()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Bootstrap or update a PerX tenant")
    parser.add_argument("--tenant-id", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--slug", required=True)
    parser.add_argument("--admin-email", required=True)
    parser.add_argument("--admin-full-name", required=True)
    parser.add_argument("--portal-domain", action="append", default=[])
    parser.add_argument("--internal-domain", action="append", default=[])
    parser.add_argument("--email-domain")
    return parser.parse_args()


if __name__ == "__main__":
    asyncio.run(bootstrap(parse_args()))
