"""
Script per popolare database con dati di test
"""
import asyncio
import json
import random
import uuid
from datetime import datetime, time, timedelta
from decimal import Decimal, ROUND_HALF_UP
from urllib import error as urlerror
from urllib import request as urlrequest
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

import asyncpg
from app.core.security import get_password_hash
from app.core.config import settings
from app.core.claim_status import LEGACY_SV_TO_SLUG, ClaimStatus


def _slug_for_legacy_state(state_id: str | None) -> str | None:
    """Map legacy SVxxx code (used throughout this seed script's internal
    state graph) to the canonical slug expected by the runtime."""
    if state_id is None:
        return None
    mapping = LEGACY_SV_TO_SLUG.get(state_id)
    return mapping[0] if mapping else ClaimStatus.ISTRUZIONE.value


def _substati_for_legacy_state(state_id: str | None) -> list[dict]:
    if state_id is None:
        return []
    mapping = LEGACY_SV_TO_SLUG.get(state_id)
    if not mapping or not mapping[1]:
        return []
    return [{"tag": mapping[1], "source": "system", "added_at": "1970-01-01T00:00:00Z"}]


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

        cat_settings_payload = {
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
                    "id": "cat-demo-modena",
                    "display_name": "CAT Demo",
                    "email": "cat@demo.com",
                    "latitude": 44.6471,
                    "longitude": 10.9252,
                    "comune": "Modena",
                    "provincia": "MO",
                    "regione": "Emilia-Romagna",
                    "assigned_municipalities": ["Modena", "Carpi", "Sassuolo", "Rubiera"],
                    "note": "Tecnico demo per test workflow CAT",
                }
            ],
            "municipalities": [
                {
                    "id": "modena",
                    "comune": "Modena",
                    "provincia": "MO",
                    "regione": "Emilia-Romagna",
                    "latitude": 44.6471,
                    "longitude": 10.9252,
                    "assigned_cat_emails": ["cat@demo.com"],
                    "priority": 1,
                },
                {
                    "id": "carpi",
                    "comune": "Carpi",
                    "provincia": "MO",
                    "regione": "Emilia-Romagna",
                    "latitude": 44.7824,
                    "longitude": 10.8777,
                    "assigned_cat_emails": ["cat@demo.com"],
                    "priority": 1,
                },
                {
                    "id": "sassuolo",
                    "comune": "Sassuolo",
                    "provincia": "MO",
                    "regione": "Emilia-Romagna",
                    "latitude": 44.5432,
                    "longitude": 10.7841,
                    "assigned_cat_emails": ["cat@demo.com"],
                    "priority": 2,
                },
                {
                    "id": "rubiera",
                    "comune": "Rubiera",
                    "provincia": "RE",
                    "regione": "Emilia-Romagna",
                    "latitude": 44.6511,
                    "longitude": 10.7812,
                    "assigned_cat_emails": ["cat@demo.com"],
                    "priority": 2,
                },
            ],
        }

        await conn.execute("""
            UPDATE tenants
            SET settings_json = (
                COALESCE(settings_json::jsonb, '{}'::jsonb) || jsonb_build_object('cat_settings', $2::jsonb)
            )::json
            WHERE id = $1
        """, tenant_id, json.dumps(cat_settings_payload))

        await conn.execute("""
            DELETE FROM user_work_schedules
            WHERE tenant_id = $1 AND user_id = $2 AND metadata_json->>'seeded_by' = 'demo_cat_seed'
        """, tenant_id, cat_user_id)

        for weekday, start_time, end_time in [
            (0, time(9, 0), time(11, 0)),
            (0, time(11, 0), time(13, 0)),
            (0, time(14, 0), time(16, 0)),
            (1, time(9, 0), time(11, 0)),
            (1, time(11, 0), time(13, 0)),
            (1, time(14, 0), time(16, 0)),
            (2, time(9, 0), time(11, 0)),
            (2, time(11, 0), time(13, 0)),
            (2, time(14, 0), time(16, 0)),
            (3, time(9, 0), time(11, 0)),
            (3, time(11, 0), time(13, 0)),
            (3, time(14, 0), time(16, 0)),
            (4, time(9, 0), time(11, 0)),
            (4, time(11, 0), time(13, 0)),
            (4, time(14, 0), time(16, 0)),
        ]:
            await conn.execute("""
                INSERT INTO user_work_schedules (
                    id, tenant_id, user_id, weekday, start_time, end_time,
                    location, slot_type, effective_from, effective_to, metadata_json
                )
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11::jsonb)
                ON CONFLICT DO NOTHING
            """,
                str(uuid.uuid4()),
                tenant_id,
                cat_user_id,
                weekday,
                start_time,
                end_time,
                "onsite",
                "work",
                None,
                None,
                json.dumps({"seeded_by": "demo_cat_seed", "place": "onsite"})
            )
        
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
        
        return tenant_id, admin_user_id, perito_user_id, cat_user_id


DEMO_SEED_VERSION = "demo_fe_2026_v1"
DEMO_CLAIM_COUNT = 100
DEMO_NAMESPACE = uuid.UUID("d6ce04a7-e9cf-475f-bf8e-2e66e9d04d62")
DEMO_GARANZIA = "Fenomeno Elettrico"

FULMINAZIONE_VALUES = [
    "Non effettuata",
    "Positiva",
    "Negativa",
    "CESI - Negativo",
    "CESI - Positivo entro 1KM",
    "CESI - Positivo entro 3KM",
    "CESI - Positivo entro 5KM",
    "CESI - Positivo entro 10KM",
]

POSITIVE_DEFINITIONS = [
    "CONCORDATO CON ATTO DI LIQUIDAZIONE AMICHEVOLE con BONIFICO BANCARIO",
    "CONCORDATO CON ATTO DI LIQUIDAZIONE AMICHEVOLE con ASSEGNO",
    "CONCORDATO CON ATTO DI LIQUIDAZIONE AMICHEVOLE (Non liquidabile dallo Studio peritale)",
    "CONCORDATO VERBALMENTE con BONIFICO BANCARIO",
    "CONCORDATO VERBALMENTE con ASSEGNO",
    "CONCORDATO VERBALMENTE (Non liquidabile dallo Studio peritale)",
    "CONCORDATO CON ATTO DI ACCERTAMENTO DI DANNO",
    "CONCORDATO CON ATTO DI ACCERTAMENTO CON RISERVA",
    "NON CONCORDATO (Danno indennizzabile ma stima non concordata)",
]

NEGATIVE_DEFINITIONS = [
    "NON CONCORDATO (ved. NOTE)",
    "NON CONCORDATO (NO Fenomeno elettrico)",
    "NON CONCORDATO (NO residui)",
    "NON CONCORDATO (Sotto franchigia)",
    "NON CONCORDATO (Garanzie non operanti)",
    "NON CONCORDATO (Ubicazione del sinistro non assicurata)",
]

COMPANY_PROFILES = [
    {
        "gruppo": "Gruppo Generali",
        "compagnia": "Generali Italia",
        "area": "Nord Est",
        "divisione": "Retail Danni",
        "agenzia_prefix": "GEN",
        "agenzia_city": "Padova",
    },
    {
        "gruppo": "Gruppo Unipol",
        "compagnia": "UnipolSai Assicurazioni",
        "area": "Nord Ovest",
        "divisione": "Privati",
        "agenzia_prefix": "UNI",
        "agenzia_city": "Milano",
    },
    {
        "gruppo": "Allianz",
        "compagnia": "Allianz Next",
        "area": "Centro",
        "divisione": "Property",
        "agenzia_prefix": "ALL",
        "agenzia_city": "Roma",
    },
    {
        "gruppo": "Zurich",
        "compagnia": "Zurich Insurance Europe",
        "area": "Nord Est",
        "divisione": "Casa",
        "agenzia_prefix": "ZUR",
        "agenzia_city": "Verona",
    },
    {
        "gruppo": "Reale Group",
        "compagnia": "Reale Mutua",
        "area": "Nord Ovest",
        "divisione": "Famiglie",
        "agenzia_prefix": "REA",
        "agenzia_city": "Torino",
    },
    {
        "gruppo": "Vittoria Assicurazioni",
        "compagnia": "Vittoria Assicurazioni",
        "area": "Nord",
        "divisione": "Abitazione",
        "agenzia_prefix": "VIT",
        "agenzia_city": "Brescia",
    },
    {
        "gruppo": "AXA",
        "compagnia": "AXA Assicurazioni",
        "area": "Centro",
        "divisione": "Casa e Famiglia",
        "agenzia_prefix": "AXA",
        "agenzia_city": "Firenze",
    },
    {
        "gruppo": "Groupama",
        "compagnia": "Groupama Assicurazioni",
        "area": "Sud",
        "divisione": "Mass Market",
        "agenzia_prefix": "GRP",
        "agenzia_city": "Bari",
    },
    {
        "gruppo": "Sara",
        "compagnia": "Sara Assicurazioni",
        "area": "Centro Sud",
        "divisione": "Protezione Casa",
        "agenzia_prefix": "SAR",
        "agenzia_city": "Napoli",
    },
    {
        "gruppo": "HDI",
        "compagnia": "HDI Assicurazioni",
        "area": "Nord Est",
        "divisione": "Abitazione",
        "agenzia_prefix": "HDI",
        "agenzia_city": "Bologna",
    },
]

FIRST_NAMES = [
    "Marco", "Luca", "Giulia", "Sara", "Andrea", "Elena", "Paolo", "Francesca", "Davide",
    "Chiara", "Matteo", "Federica", "Stefano", "Martina", "Giorgio", "Valentina", "Alessio",
    "Silvia", "Riccardo", "Laura", "Fabio", "Michela", "Tommaso", "Ilaria",
]

LAST_NAMES = [
    "Rossi", "Bianchi", "Esposito", "Romano", "Colombo", "Ricci", "Marino", "Greco", "Bruno",
    "Gallo", "Conti", "De Luca", "Mancini", "Costa", "Giordano", "Rizzo", "Lombardi",
    "Moretti", "Barbieri", "Fontana", "Santoro", "Mariani", "Ferri", "Leone",
]

STREETS = [
    "Via Verdi", "Via Roma", "Via delle Magnolie", "Via Galileo Galilei", "Via Don Minzoni",
    "Viale Europa", "Via dei Tigli", "Via Carducci", "Via della Resistenza", "Via Dante Alighieri",
]

CITIES = [
    ("Milano", "MI"), ("Roma", "RM"), ("Torino", "TO"), ("Bologna", "BO"), ("Padova", "PD"),
    ("Verona", "VR"), ("Brescia", "BS"), ("Firenze", "FI"), ("Modena", "MO"), ("Bari", "BA"),
    ("Napoli", "NA"), ("Parma", "PR"), ("Treviso", "TV"), ("Vicenza", "VI"), ("Bergamo", "BG"),
]

ASSET_CATALOG = [
    ("TV OLED 55\"", "elettronica", 1250),
    ("TV LED 43\"", "elettronica", 620),
    ("PC fisso gaming", "informatica", 1580),
    ("Notebook professionale", "informatica", 1140),
    ("Frigorifero combinato", "elettrodomestici", 980),
    ("Forno elettrico", "elettrodomestici", 540),
    ("Piano induzione", "elettrodomestici", 760),
    ("Lavatrice", "elettrodomestici", 690),
    ("Asciugatrice", "elettrodomestici", 650),
    ("Caldaia murale", "impianto", 1680),
    ("Pompa di calore", "impianto", 3240),
    ("Impianto fotovoltaico inverter", "impianto", 2890),
    ("Impianto d'allarme", "impianto", 970),
    ("Router e mesh Wi-Fi", "rete", 330),
    ("Videocitofono", "impianto", 420),
    ("Condizionatore split", "impianto", 1180),
    ("Centrale termoregolazione", "impianto", 840),
    ("Server NAS", "informatica", 780),
    ("Monitor professionale", "elettronica", 460),
    ("Cancello automatico centralina", "impianto", 910),
]

STATE_DISTRIBUTION = [
    "SV001",
    "SV001",
    "SV001",
    "SV001",
    "SV001",
    "SV001",
    "SV001",
    "SV001",
    "SV002",
    "SV002",
    "SV002",
    "SV002",
    "SV002",
    "SV002",
    "SV002",
    "SV002",
    "SV002",
    "SV002",
    "SV002",
    "SV010",
    "SV010",
    "SV010",
    "SV010",
    "SV010",
    "SV010",
    "SV010",
    "SV010",
    "SV010",
    "SV010",
    "SV010",
    "SV010",
    "SV010",
    "SV010",
    "SV010",
    "SV003",
    "SV003",
    "SV003",
    "SV003",
    "SV003",
    "SV003",
    "SV003",
    "SV003",
    "SV003",
    "SV003",
    "SV003",
    "SV003",
    "SV003",
    "SV003",
    "SV005",
    "SV005",
    "SV005",
    "SV005",
    "SV004",
    "SV004",
    "SV004",
    "SV004",
    "SV004",
    "SV014",
    "SV014",
    "SV014",
    "SV012",
    "SV012",
    "SV012",
    "SV012",
    "SV012",
    "SV012",
    "SV012",
    "SV012",
    "SV012",
    "SV012",
    "SV012",
    "SV011",
    "SV011",
    "SV011",
    "SV011",
    "SV011",
    "SV013",
    "SV013",
    "SV013",
    "SV022",
    "SV022",
    "SV022",
    "SV022",
    "SV023",
    "SV023",
    "SV023",
    "SV050",
    "SV050",
    "SV051",
    "SV051",
    "SV020",
    "SV020",
    "SV021",
    "SV021",
    "SV030",
    "SV031",
    "SV032",
    "SV033",
    "SV090",
    "SV091",
]

CLAIM_COLUMNS = [
    "id",
    "tenant_id",
    "external_ref",
    "numero_sinistro",
    "compagnia",
    "stato_corrente",
    "stato_substati",
    "created_at",
    "updated_at",
    "closed_at",
    "priority",
    "version",
    "agenzia",
    "codice_agenzia",
    "email_agenzia",
    "telefono_agenzia",
    "nome_assicurato",
    "email_assicurato",
    "telefono_assicurato",
    "indirizzo_assicurato",
    "nome_contraente",
    "email_contraente",
    "telefono_contraente",
    "indirizzo_contraente",
    "nome_danneggiato",
    "email_danneggiato",
    "telefono_danneggiato",
    "indirizzo_danneggiato",
    "data_sinistro",
    "data_denuncia",
    "data_incarico",
    "data_apertura_gestione",
    "data_assegnazione",
    "data_invio_atto",
    "data_ritorno_atto",
    "data_revoca",
    "data_sopralluogo",
    "richiesta",
    "liquidato",
    "danno_accertato",
    "danno_accertato_netto",
    "stima_danno",
    "numero_polizza",
    "tipo_polizza",
    "divisione_compagnia",
    "garanzia",
    "iban",
    "sinistro_collegato",
    "id_sinistro_collegato",
    "sopralluogo",
    "giustificativi",
    "foto",
    "oltre_dieci_beni",
    "concordata",
    "negativa",
    "ubicazione_validata",
    "fulminazione",
    "gruppo",
    "area",
    "complessita",
    "definizione",
    "propensione_perito",
    "ubicazione_note",
    "cartella",
    "owner_email",
    "metadata_json",
]


def quantize_euro(value: float | None) -> Decimal | None:
    if value is None:
        return None
    return Decimal(str(value)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def serialize_json(value):
    if value is None:
        return None
    return json.dumps(value, ensure_ascii=False)


def pick_weighted(rng: random.Random, options: list[tuple[str, int]]) -> str:
    total_weight = sum(weight for _, weight in options)
    threshold = rng.randint(1, total_weight)
    cumulative = 0
    for value, weight in options:
        cumulative += weight
        if threshold <= cumulative:
            return value
    return options[-1][0]


def shuffled_distribution(rng: random.Random, values: list[str | int]) -> list[str | int]:
    result = list(values)
    rng.shuffle(result)
    return result


def complexity_label(base_level: str, mode: str | None, goods_count: int) -> str:
    if mode == "documentale":
        return f"{base_level} documentale"
    if mode == "videoperizia":
        return f"{base_level} videoperizia"
    if mode == "no_residui":
        return f"{base_level} no residui"
    if goods_count >= 6 and base_level == "Media":
        return "Alta tradizionale multi-bene"
    if goods_count >= 4 and base_level == "Bassa":
        return "Media tradizionale"
    if mode == "tradizionale" and base_level in {"Alta", "Molto Alta"}:
        return f"{base_level} tradizionale"
    return base_level


def mode_for_state(state_id: str, goods_count: int, base_level: str, rng: random.Random) -> str:
    if state_id in {"SV002", "SV010", "SV011", "SV022", "SV023"}:
        return "documentale"
    if state_id in {"SV004", "SV013", "SV014"}:
        return "videoperizia"
    if state_id == "SV005":
        return "no_residui"
    if state_id in {"SV050", "SV051"}:
        return "tradizionale"
    if goods_count <= 2 and base_level == "Bassa" and rng.random() < 0.60:
        return "documentale"
    if goods_count >= 4 or base_level in {"Alta", "Molto Alta"}:
        return "tradizionale"
    if rng.random() < 0.12:
        return "videoperizia"
    return "tradizionale" if rng.random() < 0.45 else "documentale"


def final_state_path(state_id: str, mode: str, definition: str | None) -> list[str]:
    if state_id == "SV001":
        return ["SV001"]
    if state_id == "SV002":
        return ["SV001", "SV002"]
    if state_id == "SV003":
        return ["SV001", "SV003"]
    if state_id == "SV004":
        return ["SV001", "SV004"]
    if state_id == "SV005":
        return ["SV001", "SV005"]
    if state_id == "SV010":
        return ["SV001", "SV002", "SV010"]
    if state_id == "SV011":
        return ["SV001", "SV002", "SV010", "SV011"]
    if state_id == "SV012":
        if mode == "documentale":
            return ["SV001", "SV002", "SV010", "SV011", "SV012"]
        if mode == "no_residui":
            return ["SV001", "SV005", "SV012"]
        return ["SV001", "SV003", "SV012"]
    if state_id == "SV013":
        return ["SV001", "SV004", "SV013"]
    if state_id == "SV014":
        return ["SV001", "SV004", "SV014"]
    if state_id == "SV020":
        if mode == "documentale":
            return ["SV001", "SV002", "SV010", "SV011", "SV020"]
        return ["SV001", "SV003", "SV012", "SV020"]
    if state_id == "SV021":
        if mode == "documentale":
            return ["SV001", "SV002", "SV010", "SV011", "SV021"]
        return ["SV001", "SV003", "SV012", "SV021"]
    if state_id == "SV022":
        return ["SV001", "SV002", "SV010", "SV022"]
    if state_id == "SV023":
        return ["SV001", "SV002", "SV010", "SV023"]
    if state_id == "SV030":
        return ["SV001", "SV003", "SV012", "SV021", "SV030"]
    if state_id == "SV031":
        return ["SV001", "SV003", "SV012", "SV020", "SV031"]
    if state_id == "SV032":
        return ["SV001", "SV003", "SV012", "SV020", "SV031", "SV032"]
    if state_id == "SV033":
        return ["SV001", "SV003", "SV012", "SV020", "SV031", "SV033"]
    if state_id == "SV050":
        return ["SV001", "SV003", "SV050"]
    if state_id == "SV051":
        return ["SV001", "SV003", "SV050", "SV051"]
    if state_id == "SV090":
        if definition and definition.startswith("NON CONCORDATO"):
            return ["SV001", "SV003", "SV012", "SV021", "SV030", "SV090"]
        if definition and "VERBALMENTE" in definition:
            return ["SV001", "SV003", "SV012", "SV020", "SV031", "SV033", "SV090"]
        return ["SV001", "SV003", "SV012", "SV020", "SV031", "SV032", "SV090"]
    if state_id == "SV091":
        return ["SV001", "SV003", "SV012", "SV020", "SV031", "SV032", "SV090", "SV091"]
    return ["SV001", state_id]


def has_liquidation(definition: str | None) -> bool:
    if not definition:
        return False
    upper = definition.upper()
    if "ATTO DI ACCERTAMENTO" in upper:
        return False
    if "DANNO INDENNIZZABILE" in upper:
        return True
    if upper.startswith("NON CONCORDATO"):
        return False
    return upper.startswith("CONCORDATO")


def choose_definition(state_id: str, mode: str, fulminazione: str, rng: random.Random) -> str | None:
    if state_id not in {"SV020", "SV021", "SV030", "SV031", "SV032", "SV033", "SV090", "SV091"}:
        return None

    positive_hint = fulminazione in {
        "Positiva",
        "CESI - Positivo entro 1KM",
        "CESI - Positivo entro 3KM",
        "CESI - Positivo entro 5KM",
        "CESI - Positivo entro 10KM",
    }
    negative_hint = fulminazione in {"Negativa", "CESI - Negativo"}

    if state_id in {"SV021", "SV030"}:
        if negative_hint or mode == "no_residui":
            if mode == "no_residui":
                return "NON CONCORDATO (NO residui)"
            return rng.choice([
                "NON CONCORDATO (NO Fenomeno elettrico)",
                "NON CONCORDATO (Garanzie non operanti)",
                "NON CONCORDATO (Sotto franchigia)",
                "NON CONCORDATO (ved. NOTE)",
            ])
        return "NON CONCORDATO (Danno indennizzabile ma stima non concordata)"

    if state_id == "SV033":
        return rng.choice([
            "CONCORDATO VERBALMENTE con BONIFICO BANCARIO",
            "CONCORDATO VERBALMENTE con ASSEGNO",
            "CONCORDATO VERBALMENTE (Non liquidabile dallo Studio peritale)",
        ])

    if state_id in {"SV020", "SV031", "SV032"}:
        if positive_hint or fulminazione == "Non effettuata":
            return rng.choice([
                "CONCORDATO CON ATTO DI LIQUIDAZIONE AMICHEVOLE con BONIFICO BANCARIO",
                "CONCORDATO CON ATTO DI LIQUIDAZIONE AMICHEVOLE con ASSEGNO",
                "CONCORDATO CON ATTO DI LIQUIDAZIONE AMICHEVOLE (Non liquidabile dallo Studio peritale)",
                "CONCORDATO CON ATTO DI ACCERTAMENTO DI DANNO",
                "CONCORDATO CON ATTO DI ACCERTAMENTO CON RISERVA",
            ])
        return rng.choice([
            "NON CONCORDATO (NO Fenomeno elettrico)",
            "NON CONCORDATO (Garanzie non operanti)",
            "NON CONCORDATO (Ubicazione del sinistro non assicurata)",
        ])

    if state_id in {"SV090", "SV091"}:
        if negative_hint:
            return rng.choice(NEGATIVE_DEFINITIONS)
        if positive_hint:
            return rng.choice(POSITIVE_DEFINITIONS)
        return rng.choice(POSITIVE_DEFINITIONS + NEGATIVE_DEFINITIONS)

    return None


def build_goods(index: int, goods_count: int, rng: random.Random) -> list[dict]:
    goods = []
    for offset in range(goods_count):
        asset_name, category, base_value = ASSET_CATALOG[(index + offset * 3) % len(ASSET_CATALOG)]
        age_years = rng.randint(1, 9)
        replacement_value = round(base_value * rng.uniform(0.92, 1.18), 2)
        damage_ratio = rng.uniform(0.35, 0.88)
        goods.append({
            "nome": asset_name,
            "categoria": category,
            "anzianita_anni": age_years,
            "valore_sostituzione": replacement_value,
            "danno_stimato": round(replacement_value * damage_ratio, 2),
            "esito": "danneggiato" if damage_ratio > 0.50 else "parzialmente danneggiato",
        })
    return goods


def compute_amounts(goods: list[dict], definition: str | None, final_state: str, rng: random.Random) -> dict:
    total_damage = sum(item["danno_stimato"] for item in goods)
    base_richiesta = total_damage * rng.uniform(1.05, 1.32)
    danno_accertato = total_damage * rng.uniform(0.88, 1.03)
    danno_accertato_netto = danno_accertato * rng.uniform(0.84, 0.96)
    stima_danno = danno_accertato * rng.uniform(0.95, 1.05)

    liquidato = None
    if has_liquidation(definition) and final_state in {"SV032", "SV033", "SV090", "SV091"}:
        liquidato = stima_danno * rng.uniform(0.90, 1.00)
    elif has_liquidation(definition) and final_state in {"SV020", "SV021", "SV030", "SV031"}:
        liquidato = None

    if definition and "ATTO DI ACCERTAMENTO" in definition.upper():
        liquidato = None

    return {
        "richiesta": quantize_euro(base_richiesta),
        "danno_accertato": quantize_euro(danno_accertato),
        "danno_accertato_netto": quantize_euro(danno_accertato_netto),
        "stima_danno": quantize_euro(stima_danno),
        "liquidato": quantize_euro(liquidato),
    }


def build_timeline(
    created_at: datetime,
    state_path: list[str],
    mode: str,
    rng: random.Random,
) -> tuple[list[dict], dict]:
    timeline = []
    current_at = created_at
    tracked_dates = {
        "data_apertura_gestione": None,
        "data_assegnazione": None,
        "data_invio_atto": None,
        "data_ritorno_atto": None,
        "data_sopralluogo": None,
        "closed_at": None,
    }

    for position, state_id in enumerate(state_path):
        if position == 0:
            changed_at = created_at
            from_state = None
        else:
            gap_days = rng.randint(1, 5)
            if state_id in {"SV030", "SV031", "SV032", "SV033", "SV090", "SV091"}:
                gap_days = rng.randint(1, 8)
            current_at += timedelta(days=gap_days, hours=rng.randint(1, 8))
            changed_at = current_at
            from_state = state_path[position - 1]

        if state_id in {"SV011", "SV012", "SV013"} and tracked_dates["data_apertura_gestione"] is None:
            tracked_dates["data_apertura_gestione"] = changed_at
        if state_id in {"SV003", "SV010", "SV011", "SV012", "SV013", "SV020", "SV021"} and tracked_dates["data_assegnazione"] is None:
            tracked_dates["data_assegnazione"] = changed_at
        if state_id in {"SV030", "SV031"} and tracked_dates["data_invio_atto"] is None:
            tracked_dates["data_invio_atto"] = changed_at
        if state_id == "SV032" and tracked_dates["data_ritorno_atto"] is None:
            tracked_dates["data_ritorno_atto"] = changed_at
        if state_id in {"SV050", "SV051"} and tracked_dates["data_sopralluogo"] is None:
            tracked_dates["data_sopralluogo"] = changed_at
        if state_id == "SV090":
            tracked_dates["closed_at"] = changed_at

        timeline.append({
            "state_id": state_id,
            "from_state": from_state,
            "changed_at": changed_at,
        })

    if mode == "tradizionale" and tracked_dates["data_sopralluogo"] is None:
        reference_date = tracked_dates["data_assegnazione"] or created_at
        tracked_dates["data_sopralluogo"] = reference_date + timedelta(days=rng.randint(2, 6))

    return timeline, tracked_dates


def choose_assignee(
    state_id: str,
    mode: str,
    base_level: str,
    goods_count: int,
    users: dict[str, dict],
    rng: random.Random,
) -> dict | None:
    if state_id == "SV001" and rng.random() < 0.70:
        return None
    if state_id in {"SV002"} and rng.random() < 0.35:
        return None
    if mode in {"documentale", "no_residui"} and goods_count <= 2 and rng.random() < 0.22:
        return users["cat"]
    if base_level in {"Alta", "Molto Alta"} and rng.random() < 0.22:
        return users["admin"]
    return users["perito"]


def person_record(index: int, rng: random.Random) -> dict:
    first = FIRST_NAMES[index % len(FIRST_NAMES)]
    last = LAST_NAMES[(index * 3) % len(LAST_NAMES)]
    city, province = CITIES[index % len(CITIES)]
    civico = rng.randint(4, 97)
    phone_suffix = 100000 + index
    email_local = f"{first}.{last}".replace(" ", "").lower()
    return {
        "full_name": f"{first} {last}",
        "email": f"{email_local}{index}@maildemo.it",
        "phone": f"+39 3{rng.randint(20, 49)} {phone_suffix}",
        "address": f"{STREETS[(index * 2) % len(STREETS)]}, {civico}, {city} ({province})",
    }


def build_diary_entries(
    claim_id: str,
    tenant_id: str,
    user_id: str | None,
    external_ref: str,
    final_state: str,
    mode: str,
    fulminazione: str,
    definition: str | None,
    goods: list[dict],
    timeline: list[dict],
) -> list[dict]:
    entries = []
    happened_base = timeline[0]["changed_at"]

    entries.append({
        "id": str(uuid.uuid5(DEMO_NAMESPACE, f"{claim_id}:diary:0")),
        "tenant_id": tenant_id,
        "claim_id": claim_id,
        "entry_type": "note",
        "title": "Denuncia acquisita",
        "body_text": (
            f"Denuncia demo FE acquisita per il sinistro {external_ref}. "
            f"Beni dichiarati: {len(goods)}. "
            f"Tipologie principali: {', '.join(item['nome'] for item in goods[:3])}."
        ),
        "visibility": "internal",
        "happened_at": happened_base,
        "created_at": happened_base,
        "created_by_user_id": user_id,
        "metadata_json": {"seed_origin": DEMO_SEED_VERSION, "numero_beni": len(goods)},
    })

    middle_at = timeline[min(1, len(timeline) - 1)]["changed_at"]
    if mode == "documentale":
        body = "Richiesta documentazione inviata e primi riscontri acquisiti in modalità documentale."
    elif mode == "videoperizia":
        body = "Videoperizia programmata con assicurato per verifica residui e prova funzionale."
    elif mode == "no_residui":
        body = "Cliente riferisce beni già sostituiti o smaltiti; caso trattato come no residui."
    else:
        body = "Sopralluogo tradizionale pianificato con raccolta foto e verifica impianto."

    entries.append({
        "id": str(uuid.uuid5(DEMO_NAMESPACE, f"{claim_id}:diary:1")),
        "tenant_id": tenant_id,
        "claim_id": claim_id,
        "entry_type": "activity",
        "title": "Istruttoria peritale",
        "body_text": f"{body} Esito fulminazione: {fulminazione}.",
        "visibility": "internal",
        "happened_at": middle_at,
        "created_at": middle_at,
        "created_by_user_id": user_id,
        "metadata_json": {"seed_origin": DEMO_SEED_VERSION, "modalita": mode},
    })

    if definition:
        last_at = timeline[-1]["changed_at"]
        entries.append({
            "id": str(uuid.uuid5(DEMO_NAMESPACE, f"{claim_id}:diary:2")),
            "tenant_id": tenant_id,
            "claim_id": claim_id,
            "entry_type": "outcome",
            "title": "Esito perizia",
            "body_text": (
                f"Determinazione proposta: {definition}. "
                f"Stato finale demo: {final_state}."
            ),
            "visibility": "internal",
            "happened_at": last_at,
            "created_at": last_at,
            "created_by_user_id": user_id,
            "metadata_json": {"seed_origin": DEMO_SEED_VERSION, "state": final_state},
        })

    return entries


def build_claim_record(
    index: int,
    year_prefix: str,
    claim_id: str,
    tenant_id: str,
    users: dict[str, dict],
    state_id: str,
    base_level: str,
    goods_count: int,
    fulminazione: str,
    company_profile: dict,
    rng: random.Random,
) -> dict:
    riferimento = f"{year_prefix}{index:05d}"
    person = person_record(index, rng)
    contraente = person_record(index + 37, rng)
    danneggiato = person if rng.random() < 0.82 else person_record(index + 71, rng)
    mode = mode_for_state(state_id, goods_count, base_level, rng)
    complexity = complexity_label(base_level, mode, goods_count)
    definition = choose_definition(state_id, mode, fulminazione, rng)
    goods = build_goods(index, goods_count, rng)
    amounts = compute_amounts(goods, definition, state_id, rng)
    state_path = final_state_path(state_id, mode, definition)

    minimum_age_days = max(7, len(state_path) * 6 + 4)
    created_at = datetime.utcnow() - timedelta(days=rng.randint(minimum_age_days, minimum_age_days + 160), hours=rng.randint(0, 23))
    data_sinistro = created_at - timedelta(days=rng.randint(0, 4), hours=rng.randint(1, 12))
    data_denuncia = data_sinistro + timedelta(days=rng.randint(0, 2), hours=rng.randint(2, 10))
    data_incarico = data_denuncia + timedelta(hours=rng.randint(4, 36))

    timeline, tracked_dates = build_timeline(created_at, state_path, mode, rng)
    assignee = choose_assignee(state_id, mode, base_level, goods_count, users, rng)
    owner_email = assignee["email"] if assignee else None
    assignment_time = tracked_dates["data_assegnazione"] or data_incarico
    if assignee and tracked_dates["data_assegnazione"] is None:
        tracked_dates["data_assegnazione"] = assignment_time

    polizza_type = rng.choice(["Casa", "Condominio", "Impresa Artigiana", "Ufficio"])
    codice_agenzia = f"{company_profile['agenzia_prefix']}-{year_prefix}{(index % 17) + 1:03d}"
    agenzia = f"Agenzia {company_profile['compagnia']} {company_profile['agenzia_city']}"
    definizione_upper = definition.upper() if definition else ""
    is_concordata = bool(definition and definition.startswith("CONCORDATO"))
    is_negativa = bool(definition and not has_liquidation(definition))
    ubicazione_validata = "UBICAZIONE" not in definizione_upper
    ubicazione_note = None
    if not ubicazione_validata:
        ubicazione_note = "Ubicazione indicata in denuncia non coerente con rischio assicurato."
    elif rng.random() < 0.12:
        ubicazione_note = "Impianto con scaricatori non documentati; verifica demandata a relazione tecnica."

    metadata_json = {
        "seed_origin": DEMO_SEED_VERSION,
        "numero_beni": goods_count,
        "beni": goods,
        "mode": mode,
        "base_complexity": base_level,
        "final_state": state_id,
        "fulminazione": fulminazione,
        "demo_scope": "tenant-demo",
    }

    claim = {
        "id": claim_id,
        "tenant_id": tenant_id,
        "external_ref": riferimento,
        "numero_sinistro": f"{company_profile['agenzia_prefix']}/{year_prefix}/{index:05d}",
        "compagnia": company_profile["compagnia"],
        "stato_corrente": _slug_for_legacy_state(state_id),
        "stato_substati": _substati_for_legacy_state(state_id),
        "created_at": created_at,
        "updated_at": timeline[-1]["changed_at"],
        "closed_at": tracked_dates["closed_at"],
        "priority": rng.randint(0, 4),
        "version": 1,
        "agenzia": agenzia,
        "codice_agenzia": codice_agenzia,
        "email_agenzia": f"{codice_agenzia.lower().replace('-', '')}@agenziademo.it",
        "telefono_agenzia": f"+39 0{rng.randint(10, 59)} {rng.randint(2000000, 9999999)}",
        "nome_assicurato": person["full_name"],
        "email_assicurato": person["email"],
        "telefono_assicurato": person["phone"],
        "indirizzo_assicurato": person["address"],
        "nome_contraente": contraente["full_name"],
        "email_contraente": contraente["email"],
        "telefono_contraente": contraente["phone"],
        "indirizzo_contraente": contraente["address"],
        "nome_danneggiato": danneggiato["full_name"],
        "email_danneggiato": danneggiato["email"],
        "telefono_danneggiato": danneggiato["phone"],
        "indirizzo_danneggiato": danneggiato["address"],
        "data_sinistro": data_sinistro,
        "data_denuncia": data_denuncia,
        "data_incarico": data_incarico,
        "data_apertura_gestione": tracked_dates["data_apertura_gestione"],
        "data_assegnazione": tracked_dates["data_assegnazione"],
        "data_invio_atto": tracked_dates["data_invio_atto"],
        "data_ritorno_atto": tracked_dates["data_ritorno_atto"],
        "data_revoca": None,
        "data_sopralluogo": tracked_dates["data_sopralluogo"],
        "richiesta": amounts["richiesta"],
        "liquidato": amounts["liquidato"],
        "danno_accertato": amounts["danno_accertato"],
        "danno_accertato_netto": amounts["danno_accertato_netto"],
        "stima_danno": amounts["stima_danno"],
        "numero_polizza": f"{company_profile['agenzia_prefix']}-FE-{year_prefix}{(index % 12) + 1:02d}-{10000 + index}",
        "tipo_polizza": polizza_type,
        "divisione_compagnia": company_profile["divisione"],
        "garanzia": DEMO_GARANZIA,
        "iban": bool(has_liquidation(definition) and rng.random() < 0.72),
        "sinistro_collegato": False,
        "id_sinistro_collegato": None,
        "sopralluogo": mode == "tradizionale",
        "giustificativi": bool(goods_count <= 2 or rng.random() < 0.64),
        "foto": bool(rng.random() < 0.92),
        "oltre_dieci_beni": goods_count > 10,
        "concordata": is_concordata,
        "negativa": is_negativa,
        "ubicazione_validata": ubicazione_validata,
        "fulminazione": fulminazione,
        "gruppo": company_profile["gruppo"],
        "area": company_profile["area"],
        "complessita": complexity,
        "definizione": definition,
        "propensione_perito": pick_weighted(rng, [("Rapida", 55), ("Standard", 30), ("Analitica", 15)]),
        "ubicazione_note": ubicazione_note,
        "cartella": f"demo/{riferimento}",
        "owner_email": owner_email,
        "metadata_json": metadata_json,
        "timeline": timeline,
        "assignee": assignee,
        "assignment_time": assignment_time if assignee else None,
    }

    diary_entries = build_diary_entries(
        claim_id=claim_id,
        tenant_id=tenant_id,
        user_id=assignee["id"] if assignee else users["admin"]["id"],
        external_ref=riferimento,
        final_state=state_id,
        mode=mode,
        fulminazione=fulminazione,
        definition=definition,
        goods=goods,
        timeline=timeline,
    )
    claim["diary_entries"] = diary_entries
    return claim


async def table_exists(conn: asyncpg.Connection, table_name: str) -> bool:
    return bool(await conn.fetchval(
        """
        SELECT EXISTS (
            SELECT 1
            FROM information_schema.tables
            WHERE table_schema = 'public' AND table_name = $1
        )
        """,
        table_name,
    ))


async def insert_claim_rows(conn: asyncpg.Connection, claims: list[dict]):
    placeholders = ", ".join(f"${index}" for index in range(1, len(CLAIM_COLUMNS) + 1))
    update_columns = [column for column in CLAIM_COLUMNS if column != "id"]
    update_clause = ", ".join(f"{column} = EXCLUDED.{column}" for column in update_columns)
    query = f"""
        INSERT INTO claims ({", ".join(CLAIM_COLUMNS)})
        VALUES ({placeholders})
        ON CONFLICT (id) DO UPDATE
        SET {update_clause}
    """
    rows = []
    for claim in claims:
        row = []
        for column in CLAIM_COLUMNS:
            value = claim[column]
            if column in ("metadata_json", "stato_substati"):
                value = serialize_json(value)
            row.append(value)
        rows.append(tuple(row))
    await conn.executemany(query, rows)


async def cleanup_related_rows(
    conn: asyncpg.Connection,
    claim_ids: list[str],
    available_tables: dict[str, bool],
):
    if not claim_ids:
        return
    if available_tables.get("claim_assignments"):
        await conn.execute("DELETE FROM claim_assignments WHERE claim_id = ANY($1::text[])", claim_ids)
    if available_tables.get("claim_states"):
        await conn.execute("DELETE FROM claim_states WHERE claim_id = ANY($1::text[])", claim_ids)
    if available_tables.get("claim_events"):
        await conn.execute("DELETE FROM claim_events WHERE claim_id = ANY($1::text[])", claim_ids)
    if available_tables.get("claim_diary_entries"):
        await conn.execute("DELETE FROM claim_diary_entries WHERE claim_id = ANY($1::text[])", claim_ids)


async def seed_related_rows(
    conn: asyncpg.Connection,
    tenant_id: str,
    claims: list[dict],
    available_tables: dict[str, bool],
):
    assignment_rows = []
    state_rows = []
    event_rows = []
    diary_rows = []

    for claim in claims:
        actor_user_id = claim["assignee"]["id"] if claim["assignee"] else None
        claim_id = claim["id"]
        riferimento = claim["external_ref"]

        if available_tables.get("claim_states"):
            for offset, timeline_item in enumerate(claim["timeline"]):
                state_rows.append((
                    str(uuid.uuid5(DEMO_NAMESPACE, f"{claim_id}:state:{offset}")),
                    tenant_id,
                    claim_id,
                    _slug_for_legacy_state(timeline_item["from_state"]) if timeline_item["from_state"] else None,
                    _slug_for_legacy_state(timeline_item["state_id"]),
                    actor_user_id,
                    timeline_item["changed_at"],
                    "Seed demo FE",
                    serialize_json({"seed_origin": DEMO_SEED_VERSION}),
                ))

        if available_tables.get("claim_events"):
            event_rows.append((
                str(uuid.uuid5(DEMO_NAMESPACE, f"{claim_id}:event:claim_created")),
                tenant_id,
                claim_id,
                "claim_created",
                claim["created_at"],
                actor_user_id,
                serialize_json({
                    "seed_origin": DEMO_SEED_VERSION,
                    "external_ref": riferimento,
                    "stato": claim["stato_corrente"],
                }),
                "system",
            ))

            if claim["assignee"]:
                event_rows.append((
                    str(uuid.uuid5(DEMO_NAMESPACE, f"{claim_id}:event:assigned")),
                    tenant_id,
                    claim_id,
                    "assigned",
                    claim["assignment_time"],
                    claim["assignee"]["id"],
                    serialize_json({
                        "seed_origin": DEMO_SEED_VERSION,
                        "assignee_user_id": claim["assignee"]["id"],
                        "assignee_email": claim["assignee"]["email"],
                    }),
                    "system",
                ))

            for offset, timeline_item in enumerate(claim["timeline"]):
                if timeline_item["from_state"] is None:
                    continue
                event_rows.append((
                    str(uuid.uuid5(DEMO_NAMESPACE, f"{claim_id}:event:state:{offset}")),
                    tenant_id,
                    claim_id,
                    "state_changed",
                    timeline_item["changed_at"],
                    actor_user_id,
                    serialize_json({
                        "seed_origin": DEMO_SEED_VERSION,
                        "from": timeline_item["from_state"],
                        "to": timeline_item["state_id"],
                    }),
                    "system",
                ))

        if available_tables.get("claim_assignments") and claim["assignee"]:
            assignment_rows.append((
                str(uuid.uuid5(DEMO_NAMESPACE, f"{claim_id}:assignment")),
                tenant_id,
                claim_id,
                claim["assignee"]["id"],
                claim["assignee"]["id"],
                claim["assignment_time"],
                None,
                "Assegnazione seed demo FE",
            ))

        if available_tables.get("claim_diary_entries"):
            for diary in claim["diary_entries"]:
                diary_rows.append((
                    diary["id"],
                    diary["tenant_id"],
                    diary["claim_id"],
                    diary["entry_type"],
                    diary["title"],
                    diary["body_text"],
                    diary["visibility"],
                    diary["happened_at"],
                    diary["created_at"],
                    diary["created_by_user_id"],
                    serialize_json(diary["metadata_json"]),
                ))

    if assignment_rows:
        await conn.executemany(
            """
            INSERT INTO claim_assignments (
                id, tenant_id, claim_id, assignee_user_id, assigned_by_user_id,
                assigned_at, unassigned_at, reason
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            """,
            assignment_rows,
        )

    if state_rows:
        await conn.executemany(
            """
            INSERT INTO claim_states (
                id, tenant_id, claim_id, from_state, to_state,
                changed_by_user_id, changed_at, reason, payload_json
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
            """,
            state_rows,
        )

    if event_rows:
        await conn.executemany(
            """
            INSERT INTO claim_events (
                id, tenant_id, claim_id, event_type, event_time,
                actor_user_id, data_json, source
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            """,
            event_rows,
        )

    if diary_rows:
        await conn.executemany(
            """
            INSERT INTO claim_diary_entries (
                id, tenant_id, claim_id, entry_type, title, body_text,
                visibility, happened_at, created_at, created_by_user_id, metadata_json
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
            """,
            diary_rows,
        )


async def seed_sample_claims(
    pool: asyncpg.Pool,
    tenant_id: str,
    admin_user_id: str,
    perito_user_id: str,
    cat_user_id: str,
):
    """Crea circa cento sinistri demo Fenomeno Elettrico per il tenant demo."""

    rng = random.Random(2600001)
    year_prefix = f"{datetime.utcnow().year % 100:02d}"

    goods_distribution = shuffled_distribution(
        rng,
        [1] * 46 + [2] * 34 + [3] * 7 + [4] * 4 + [5] * 3 + [6] * 2 + [8] * 1 + [11] * 1 + [12] * 1 + [15] * 1,
    )
    complexity_distribution = shuffled_distribution(
        rng,
        ["Bassa"] * 80 + ["Media"] * 15 + ["Alta"] * 4 + ["Molto Alta"] * 1,
    )
    fulminazione_distribution = shuffled_distribution(
        rng,
        ["Non effettuata"] * 28
        + ["Positiva"] * 22
        + ["Negativa"] * 12
        + ["CESI - Negativo"] * 9
        + ["CESI - Positivo entro 1KM"] * 8
        + ["CESI - Positivo entro 3KM"] * 8
        + ["CESI - Positivo entro 5KM"] * 7
        + ["CESI - Positivo entro 10KM"] * 6,
    )
    state_distribution = shuffled_distribution(rng, STATE_DISTRIBUTION)

    users = {
        "admin": {"id": admin_user_id, "email": "admin@demo.com"},
        "perito": {"id": perito_user_id, "email": "perito@demo.com"},
        "cat": {"id": cat_user_id, "email": "cat@demo.com"},
    }

    external_refs = [f"{year_prefix}{index:05d}" for index in range(1, DEMO_CLAIM_COUNT + 1)]

    async with pool.acquire() as conn:
        available_tables = {
            "claim_assignments": await table_exists(conn, "claim_assignments"),
            "claim_states": await table_exists(conn, "claim_states"),
            "claim_events": await table_exists(conn, "claim_events"),
            "claim_diary_entries": await table_exists(conn, "claim_diary_entries"),
        }

        existing_rows = await conn.fetch(
            """
            SELECT id, external_ref
            FROM claims
            WHERE tenant_id = $1 AND external_ref = ANY($2::text[])
            """,
            tenant_id,
            external_refs,
        )
        existing_ids = {row["external_ref"]: row["id"] for row in existing_rows}

        claims = []
        for index in range(1, DEMO_CLAIM_COUNT + 1):
            claim_id = existing_ids.get(external_refs[index - 1]) or str(
                uuid.uuid5(DEMO_NAMESPACE, f"demo-claim:{tenant_id}:{external_refs[index - 1]}")
            )
            company_profile = COMPANY_PROFILES[(index - 1) % len(COMPANY_PROFILES)]
            claims.append(
                build_claim_record(
                    index=index,
                    year_prefix=year_prefix,
                    claim_id=claim_id,
                    tenant_id=tenant_id,
                    users=users,
                    state_id=state_distribution[index - 1],
                    base_level=complexity_distribution[index - 1],
                    goods_count=int(goods_distribution[index - 1]),
                    fulminazione=str(fulminazione_distribution[index - 1]),
                    company_profile=company_profile,
                    rng=rng,
                )
            )

        for pair_start in (12, 27, 44, 58, 73, 91):
            if pair_start < len(claims):
                claims[pair_start]["sinistro_collegato"] = True
                claims[pair_start]["id_sinistro_collegato"] = claims[pair_start - 1]["external_ref"]

        claim_ids = [claim["id"] for claim in claims]

        async with conn.transaction():
            await cleanup_related_rows(conn, claim_ids, available_tables)
            await insert_claim_rows(conn, claims)
            await seed_related_rows(conn, tenant_id, claims, available_tables)

    complexity_summary: dict[str, int] = {}
    fulminazione_summary: dict[str, int] = {}
    goods_summary = {"1 bene": 0, "2 beni": 0, "3-4 beni": 0, "5-10 beni": 0, ">10 beni": 0}

    for claim in claims:
        base_label = claim["complessita"].split()[0]
        complexity_summary[base_label] = complexity_summary.get(base_label, 0) + 1
        fulminazione_summary[claim["fulminazione"]] = fulminazione_summary.get(claim["fulminazione"], 0) + 1
        goods_count = claim["metadata_json"]["numero_beni"]
        if goods_count == 1:
            goods_summary["1 bene"] += 1
        elif goods_count == 2:
            goods_summary["2 beni"] += 1
        elif goods_count <= 4:
            goods_summary["3-4 beni"] += 1
        elif goods_count <= 10:
            goods_summary["5-10 beni"] += 1
        else:
            goods_summary[">10 beni"] += 1

    print(f"✅ Creati/aggiornati {len(claims)} sinistri demo FE nel tenant demo")
    print(f"   Riferimenti: {claims[0]['external_ref']} → {claims[-1]['external_ref']}")
    print(f"   Complessità: {complexity_summary}")
    print(f"   Numero beni: {goods_summary}")
    print(f"   Fulminazione: {fulminazione_summary}")


async def main():
    import sys
    
    if len(sys.argv) < 2:
        print("Usage: python scripts/seed_data.py <postgres_url>")
        sys.exit(1)
    
    postgres_url = sys.argv[1]

    # asyncpg does not accept `ssl=require` as a libpq-style runtime param in the DSN.
    # Normalize it into a dedicated connect kwarg for Supabase-hosted Postgres.
    parsed = urlsplit(postgres_url)
    if parsed.scheme == "postgresql+asyncpg":
        parsed = parsed._replace(scheme="postgresql")
    elif parsed.scheme == "postgres+asyncpg":
        parsed = parsed._replace(scheme="postgres")
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
        tenant_id, admin_id, perito_id, cat_id = await seed_tenant_and_users(pool)
        await seed_sample_claims(pool, tenant_id, admin_id, perito_id, cat_id)
        print("\n✅ Seed completato!")
    finally:
        await pool.close()


if __name__ == "__main__":
    asyncio.run(main())
