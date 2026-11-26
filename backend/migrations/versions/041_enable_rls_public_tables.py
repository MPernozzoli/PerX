"""Enable Row Level Security on PerX tables exposed through the Supabase Data API.

Revision ID: 041_enable_rls_public
Revises: 040_pynkstudio_domains

Contesto: lo schema ``public`` e' esposto dalla Data API di Supabase (PostgREST). Le migrazioni
Alembic precedenti creano le tabelle senza abilitare RLS, quindi chiunque conosca la chiave
anon/publishable puo' leggere (e scrivere) tabelle come ``users`` (password_hash), i token del
portale, gli IBAN, i device token, ecc. L'Advisor di Supabase lo segnala come
``sensitive_columns_exposed``.

Il backend FastAPI si collega direttamente a Postgres con ``DATABASE_URL`` (ruolo proprietario
delle tabelle) e il Hub/le edge function usano la service-role key: entrambi bypassano RLS.
Abilitare RLS *senza policy* chiude quindi l'accesso ad ``anon``/``authenticated`` senza
toccare nessun flusso PerX.

Cosa fa:
- abilita RLS (senza ``FORCE``, cosi' il proprietario/backend continua a funzionare) su ogni
  tabella di ``public`` che ancora non ce l'ha;
- salta le tabelle estensione (es. ``spatial_ref_sys``) e quelle non possedute dal ruolo che
  esegue la migrazione (``ALTER TABLE`` fallirebbe e bloccherebbe il deploy);
- salta ``LEGACY_DIRECT_ACCESS_TABLES``: tabelle che il frontend CAT Dispatcher interroga ancora
  direttamente via PostgREST (``apps/catdispatcher/src``). Per queste servono policy esplicite
  prima di poter abilitare RLS; vedi Documentation/06-Decisioni-e-Intenzioni-Future.md.

Idempotente: le tabelle con RLS gia' attiva (es. quelle di Insight Studio) non vengono toccate.
"""

from __future__ import annotations

from alembic import op


revision = "041_enable_rls_public"
down_revision = "040_pynkstudio_domains"
branch_labels = None
depends_on = None


# Tabelle lette/scritte direttamente dal frontend CAT Dispatcher con la chiave publishable
# (supabase.from(...) / supabase.rpc(...)). NON abilitare RLS qui senza averne prima
# definito le policy, altrimenti le schermate /, /admin e /api smettono di funzionare.
LEGACY_DIRECT_ACCESS_TABLES = (
    "allowed_domains",
    "cat_commune",
    "cat_suspensions",
    "cats",
    "communes",
    "geojson_backup_log",
    "provinces",
    "regions",
    "tenants",
    "user_roles",
    "user_tenants",
)


def upgrade() -> None:
    skipped = ", ".join(f"'{name}'" for name in LEGACY_DIRECT_ACCESS_TABLES)
    # Niente format()/%I e niente RAISE con '%': evita problemi di escaping con il driver.
    op.execute(
        f"""
        DO $$
        DECLARE
            tbl record;
        BEGIN
            FOR tbl IN
                SELECT c.relname
                FROM pg_class c
                JOIN pg_namespace n ON n.oid = c.relnamespace
                WHERE n.nspname = 'public'
                  AND c.relkind IN ('r', 'p')
                  AND NOT c.relispartition
                  AND NOT c.relrowsecurity
                  AND pg_get_userbyid(c.relowner) = current_user
                  AND c.relname <> ALL (ARRAY[{skipped}])
                  AND NOT EXISTS (
                      SELECT 1
                      FROM pg_depend d
                      WHERE d.classid = 'pg_class'::regclass
                        AND d.objid = c.oid
                        AND d.deptype = 'e'
                  )
            LOOP
                EXECUTE 'ALTER TABLE public.' || quote_ident(tbl.relname)
                        || ' ENABLE ROW LEVEL SECURITY';
            END LOOP;
        END
        $$;
        """
    )


def downgrade() -> None:
    # Volutamente vuoto: disabilitare RLS riesporrebbe i dati sensibili alla Data API.
    pass
