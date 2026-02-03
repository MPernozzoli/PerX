"""
Script per popolare database con dati di test
"""
import asyncio
import uuid
from datetime import datetime, timedelta

import asyncpg
from app.core.security import get_password_hash


async def seed_tenant_and_users(pool: asyncpg.Pool):
    """Crea tenant demo e utenti di test"""
    
    tenant_id = str(uuid.uuid4())
    
    async with pool.acquire() as conn:
        # Crea tenant
        await conn.execute("""
            INSERT INTO tenants (id, name, slug, created_at)
            VALUES ($1, $2, $3, $4)
        """, tenant_id, "Demo Tenant", "demo", datetime.utcnow())
        
        # Crea ruoli
        admin_role_id = str(uuid.uuid4())
        perito_role_id = str(uuid.uuid4())
        
        await conn.execute("""
            INSERT INTO roles (id, tenant_id, name, description)
            VALUES ($1, $2, $3, $4)
        """, admin_role_id, tenant_id, "admin_tenant", "Amministratore tenant")
        
        await conn.execute("""
            INSERT INTO roles (id, tenant_id, name, description)
            VALUES ($1, $2, $3, $4)
        """, perito_role_id, tenant_id, "perito", "Perito")
        
        # Crea utenti
        admin_user_id = str(uuid.uuid4())
        perito_user_id = str(uuid.uuid4())
        
        admin_password_hash = get_password_hash("admin123")
        perito_password_hash = get_password_hash("perito123")
        
        await conn.execute("""
            INSERT INTO users (id, tenant_id, email, full_name, password_hash, is_active, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
        """, admin_user_id, tenant_id, "admin@demo.com", "Admin Demo", admin_password_hash, True, datetime.utcnow())
        
        await conn.execute("""
            INSERT INTO users (id, tenant_id, email, full_name, password_hash, is_active, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
        """, perito_user_id, tenant_id, "perito@demo.com", "Perito Demo", perito_password_hash, True, datetime.utcnow())
        
        # Assegna ruoli
        await conn.execute("""
            INSERT INTO user_roles (user_id, role_id)
            VALUES ($1, $2)
        """, admin_user_id, admin_role_id)
        
        await conn.execute("""
            INSERT INTO user_roles (user_id, role_id)
            VALUES ($1, $2)
        """, perito_user_id, perito_role_id)
        
        print(f"✅ Creato tenant: {tenant_id}")
        print(f"   Admin: admin@demo.com / admin123")
        print(f"   Perito: perito@demo.com / perito123")
        
        return tenant_id, admin_user_id, perito_user_id


async def seed_sample_claims(pool: asyncpg.Pool, tenant_id: str, user_id: str):
    """Crea alcuni sinistri di esempio"""
    
    claims = [
        {
            "external_ref": "SIN-2024-001",
            "numero_sinistro": "12345/2024",
            "compagnia": "Allianz",
            "stato_corrente": "SV001",  # da scaricare
            "nome_assicurato": "Mario Rossi",
            "email_assicurato": "mario.rossi@example.com",
            "data_sinistro": datetime.utcnow() - timedelta(days=5),
        },
        {
            "external_ref": "SIN-2024-002",
            "numero_sinistro": "12346/2024",
            "compagnia": "Generali",
            "stato_corrente": "SV012",  # in gestione
            "nome_assicurato": "Luigi Bianchi",
            "email_assicurato": "luigi.bianchi@example.com",
            "data_sinistro": datetime.utcnow() - timedelta(days=10),
            "data_assegnazione": datetime.utcnow() - timedelta(days=8),
        },
        {
            "external_ref": "SIN-2024-003",
            "numero_sinistro": "12347/2024",
            "compagnia": "Unipol",
            "stato_corrente": "SV090",  # chiusa
            "nome_assicurato": "Anna Verdi",
            "email_assicurato": "anna.verdi@example.com",
            "data_sinistro": datetime.utcnow() - timedelta(days=30),
            "closed_at": datetime.utcnow() - timedelta(days=2),
        },
    ]
    
    async with pool.acquire() as conn:
        for claim_data in claims:
            claim_id = str(uuid.uuid4())
            
            await conn.execute("""
                INSERT INTO claims (
                    id, tenant_id, external_ref, numero_sinistro, compagnia,
                    stato_corrente, nome_assicurato, email_assicurato,
                    data_sinistro, data_assegnazione, closed_at,
                    created_at, version, priority
                ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
            """,
                claim_id, tenant_id,
                claim_data["external_ref"],
                claim_data["numero_sinistro"],
                claim_data["compagnia"],
                claim_data["stato_corrente"],
                claim_data["nome_assicurato"],
                claim_data["email_assicurato"],
                claim_data["data_sinistro"],
                claim_data.get("data_assegnazione"),
                claim_data.get("closed_at"),
                datetime.utcnow(),
                1,  # version
                0   # priority
            )
            
            # Crea evento iniziale
            event_id = str(uuid.uuid4())
            await conn.execute("""
                INSERT INTO claim_events (
                    id, tenant_id, claim_id, event_type, event_time,
                    actor_user_id, data_json, source
                ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            """,
                event_id, tenant_id, claim_id, "claim_created",
                datetime.utcnow(), user_id,
                {"stato": claim_data["stato_corrente"]},
                "seed"
            )
    
    print(f"✅ Creati {len(claims)} sinistri di esempio")


async def main():
    import sys
    from app.core.config import settings
    
    if len(sys.argv) < 2:
        print("Usage: python scripts/seed_data.py <postgres_url>")
        sys.exit(1)
    
    postgres_url = sys.argv[1]
    
    pool = await asyncpg.create_pool(postgres_url)
    
    try:
        tenant_id, admin_id, perito_id = await seed_tenant_and_users(pool)
        await seed_sample_claims(pool, tenant_id, admin_id)
        print("\n✅ Seed completato!")
    finally:
        await pool.close()


if __name__ == "__main__":
    asyncio.run(main())

