"""
Script per popolare database con dati di test
"""
import asyncio
import json
import uuid
from datetime import datetime, timedelta
from urllib import error as urlerror
from urllib import request as urlrequest
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

import asyncpg
from app.core.security import get_password_hash
from app.core.config import settings


async def ensure_supabase_auth_user(email: str, password: str, full_name: str):
    """Create or update a Supabase Auth user via admin API."""
    if not settings.SUPABASE_URL or not settings.SUPABASE_SERVICE_ROLE_KEY:
        print(f"⚠️ Supabase auth skip per {email}: config mancante")
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

    def _create_user():
        req = urlrequest.Request(
            f"{settings.SUPABASE_URL}/auth/v1/admin/users",
            data=json.dumps(payload).encode("utf-8"),
            headers=headers,
            method="POST",
        )
        with urlrequest.urlopen(req, timeout=20) as response:
            raw = response.read()
            return json.loads(raw.decode("utf-8")) if raw else {}

    try:
        user = await asyncio.to_thread(_create_user)
        print(f"✅ Supabase auth user pronto: {email} ({user.get('id', 'n/a')})")
    except urlerror.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="ignore")
        lowered = body.lower()
        if exc.code in (400, 422) and ("already" in lowered or "exists" in lowered or "registered" in lowered):
            print(f"ℹ️ Supabase auth user già presente: {email}")
        else:
            print(f"⚠️ Errore creazione Supabase auth user {email}: HTTP {exc.code} {body}")
    except Exception as exc:
        print(f"⚠️ Errore creazione Supabase auth user {email}: {exc}")


async def seed_tenant_and_users(pool: asyncpg.Pool):
    """Crea tenant demo e utenti di test"""
    
    tenant_id = str(uuid.uuid4())
    platform_tenant_id = str(uuid.uuid4())
    platform_admin_id = str(uuid.uuid4())
    
    async with pool.acquire() as conn:
        await conn.execute("""
            INSERT INTO tenants (id, name, slug, created_at)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT (slug) DO NOTHING
        """, platform_tenant_id, "Pynk Studio", "pynkstudio", datetime.utcnow())

        existing_platform_tenant_id = await conn.fetchval("""
            SELECT id FROM tenants WHERE slug = $1
        """, "pynkstudio")
        if existing_platform_tenant_id:
            platform_tenant_id = existing_platform_tenant_id

        platform_admin_password_hash = get_password_hash(settings.APP_ADMIN_DEFAULT_PASSWORD)
        await conn.execute("""
            INSERT INTO users (id, tenant_id, email, full_name, password_hash, is_active, is_platform_admin, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            ON CONFLICT (email) DO UPDATE
            SET tenant_id = EXCLUDED.tenant_id,
                full_name = EXCLUDED.full_name,
                is_active = EXCLUDED.is_active,
                is_platform_admin = EXCLUDED.is_platform_admin,
                password_hash = EXCLUDED.password_hash
        """, platform_admin_id, platform_tenant_id, settings.APP_ADMIN_EMAIL, settings.APP_ADMIN_FULL_NAME, platform_admin_password_hash, True, True, datetime.utcnow())

        # Crea tenant
        await conn.execute("""
            INSERT INTO tenants (id, name, slug, created_at)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT (slug) DO NOTHING
        """, tenant_id, "Demo Tenant", "demo", datetime.utcnow())

        existing_tenant_id = await conn.fetchval("""
            SELECT id FROM tenants WHERE slug = $1
        """, "demo")
        if existing_tenant_id:
            tenant_id = existing_tenant_id
        
        # Crea ruoli
        admin_role_id = str(uuid.uuid4())
        perito_role_id = str(uuid.uuid4())
        cat_role_id = str(uuid.uuid4())
        
        await conn.execute("""
            INSERT INTO roles (id, tenant_id, name, description)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT DO NOTHING
        """, admin_role_id, tenant_id, "admin_tenant", "Amministratore tenant")
        
        await conn.execute("""
            INSERT INTO roles (id, tenant_id, name, description)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT DO NOTHING
        """, perito_role_id, tenant_id, "perito", "Perito")

        await conn.execute("""
            INSERT INTO roles (id, tenant_id, name, description)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT DO NOTHING
        """, cat_role_id, tenant_id, "cat", "Tecnico CAT")

        existing_admin_role_id = await conn.fetchval("""
            SELECT id FROM roles WHERE tenant_id = $1 AND name = $2 LIMIT 1
        """, tenant_id, "admin_tenant")
        if existing_admin_role_id:
            admin_role_id = existing_admin_role_id

        existing_perito_role_id = await conn.fetchval("""
            SELECT id FROM roles WHERE tenant_id = $1 AND name = $2 LIMIT 1
        """, tenant_id, "perito")
        if existing_perito_role_id:
            perito_role_id = existing_perito_role_id

        existing_cat_role_id = await conn.fetchval("""
            SELECT id FROM roles WHERE tenant_id = $1 AND name = $2 LIMIT 1
        """, tenant_id, "cat")
        if existing_cat_role_id:
            cat_role_id = existing_cat_role_id
        
        # Crea utenti
        admin_user_id = str(uuid.uuid4())
        perito_user_id = str(uuid.uuid4())
        cat_user_id = str(uuid.uuid4())
        
        admin_password_hash = get_password_hash("admin123")
        perito_password_hash = get_password_hash("perito123")
        cat_password_hash = get_password_hash("cat123")
        
        await conn.execute("""
            INSERT INTO users (id, tenant_id, email, full_name, password_hash, is_active, is_platform_admin, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            ON CONFLICT (email) DO UPDATE
            SET tenant_id = EXCLUDED.tenant_id,
                full_name = EXCLUDED.full_name,
                password_hash = EXCLUDED.password_hash,
                is_active = EXCLUDED.is_active,
                is_platform_admin = EXCLUDED.is_platform_admin
        """, admin_user_id, tenant_id, "admin@demo.com", "Admin Demo", admin_password_hash, True, False, datetime.utcnow())
        
        await conn.execute("""
            INSERT INTO users (id, tenant_id, email, full_name, password_hash, is_active, is_platform_admin, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            ON CONFLICT (email) DO UPDATE
            SET tenant_id = EXCLUDED.tenant_id,
                full_name = EXCLUDED.full_name,
                password_hash = EXCLUDED.password_hash,
                is_active = EXCLUDED.is_active,
                is_platform_admin = EXCLUDED.is_platform_admin
        """, perito_user_id, tenant_id, "perito@demo.com", "Perito Demo", perito_password_hash, True, False, datetime.utcnow())

        await conn.execute("""
            INSERT INTO users (id, tenant_id, email, full_name, password_hash, is_active, is_platform_admin, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            ON CONFLICT (email) DO UPDATE
            SET tenant_id = EXCLUDED.tenant_id,
                full_name = EXCLUDED.full_name,
                password_hash = EXCLUDED.password_hash,
                is_active = EXCLUDED.is_active,
                is_platform_admin = EXCLUDED.is_platform_admin
        """, cat_user_id, tenant_id, "cat@demo.com", "CAT Demo", cat_password_hash, True, False, datetime.utcnow())

        existing_admin_user_id = await conn.fetchval("""
            SELECT id FROM users WHERE email = $1
        """, "admin@demo.com")
        if existing_admin_user_id:
            admin_user_id = existing_admin_user_id

        existing_perito_user_id = await conn.fetchval("""
            SELECT id FROM users WHERE email = $1
        """, "perito@demo.com")
        if existing_perito_user_id:
            perito_user_id = existing_perito_user_id

        existing_cat_user_id = await conn.fetchval("""
            SELECT id FROM users WHERE email = $1
        """, "cat@demo.com")
        if existing_cat_user_id:
            cat_user_id = existing_cat_user_id
        
        # Assegna ruoli
        await conn.execute("""
            INSERT INTO user_roles (user_id, role_id)
            VALUES ($1, $2)
            ON CONFLICT DO NOTHING
        """, admin_user_id, admin_role_id)
        
        await conn.execute("""
            INSERT INTO user_roles (user_id, role_id)
            VALUES ($1, $2)
            ON CONFLICT DO NOTHING
        """, perito_user_id, perito_role_id)

        await conn.execute("""
            INSERT INTO user_roles (user_id, role_id)
            VALUES ($1, $2)
            ON CONFLICT DO NOTHING
        """, cat_user_id, cat_role_id)
        
        print(f"✅ Creato/aggiornato admin piattaforma: {settings.APP_ADMIN_EMAIL} / {settings.APP_ADMIN_DEFAULT_PASSWORD}")
        print(f"✅ Creato tenant: {tenant_id}")
        print(f"   Admin: admin@demo.com / admin123")
        print(f"   Perito: perito@demo.com / perito123")
        print(f"   CAT: cat@demo.com / cat123")

        await ensure_supabase_auth_user(
            settings.APP_ADMIN_EMAIL,
            settings.APP_ADMIN_DEFAULT_PASSWORD,
            settings.APP_ADMIN_FULL_NAME,
        )
        await ensure_supabase_auth_user("admin@demo.com", "admin123", "Admin Demo")
        await ensure_supabase_auth_user("perito@demo.com", "perito123", "Perito Demo")
        await ensure_supabase_auth_user("cat@demo.com", "cat123", "CAT Demo")
        
        return tenant_id, admin_user_id, perito_user_id


async def seed_sample_claims(pool: asyncpg.Pool, tenant_id: str, user_id: str):
    """Crea alcuni sinistri di esempio"""
    
    claims = [
        {
            "external_ref": "SIN-2024-001",
            "numero_sinistro": "12345/2024",
            "compagnia": "Allianz",
            "stato_corrente": "SV001",  # da scaricare
            "created_at": datetime.utcnow() - timedelta(days=5),
        },
        {
            "external_ref": "SIN-2024-002",
            "numero_sinistro": "12346/2024",
            "compagnia": "Generali",
            "stato_corrente": "SV012",  # in gestione
            "created_at": datetime.utcnow() - timedelta(days=10),
        },
        {
            "external_ref": "SIN-2024-003",
            "numero_sinistro": "12347/2024",
            "compagnia": "Unipol",
            "stato_corrente": "SV090",  # chiusa
            "created_at": datetime.utcnow() - timedelta(days=30),
            "closed_at": datetime.utcnow() - timedelta(days=2),
        },
    ]
    
    async with pool.acquire() as conn:
        for claim_data in claims:
            claim_id = str(uuid.uuid4())
            
            await conn.execute("""
                INSERT INTO claims (
                    id, tenant_id, external_ref, numero_sinistro, compagnia,
                    stato_corrente, closed_at, created_at, updated_at, version, priority
                ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
                ON CONFLICT DO NOTHING
            """,
                claim_id, tenant_id,
                claim_data["external_ref"],
                claim_data["numero_sinistro"],
                claim_data["compagnia"],
                claim_data["stato_corrente"],
                claim_data.get("closed_at"),
                claim_data["created_at"],
                datetime.utcnow(),
                1,  # version
                0   # priority
            )
    
    print(f"✅ Creati {len(claims)} sinistri di esempio")


async def main():
    import sys
    
    if len(sys.argv) < 2:
        print("Usage: python scripts/seed_data.py <postgres_url>")
        sys.exit(1)
    
    postgres_url = sys.argv[1]

    # asyncpg does not accept `ssl=require` as a libpq-style runtime param in the DSN.
    # Normalize it into a dedicated connect kwarg for Supabase-hosted Postgres.
    parsed = urlsplit(postgres_url)
    query_params = dict(parse_qsl(parsed.query, keep_blank_values=True))
    ssl_mode = query_params.pop("ssl", None) or query_params.pop("sslmode", None)
    normalized_url = urlunsplit(
        parsed._replace(query=urlencode(query_params))
    )

    connect_kwargs = {}
    if ssl_mode:
        connect_kwargs["ssl"] = ssl_mode

    pool = await asyncpg.create_pool(normalized_url, **connect_kwargs)
    
    try:
        tenant_id, admin_id, perito_id = await seed_tenant_and_users(pool)
        await seed_sample_claims(pool, tenant_id, admin_id)
        print("\n✅ Seed completato!")
    finally:
        await pool.close()


if __name__ == "__main__":
    asyncio.run(main())
