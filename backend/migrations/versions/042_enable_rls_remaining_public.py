"""Enable RLS on the public tables that 041 left out (tenants, user_roles, ...).

Revision ID: 042_enable_rls_remaining
Revises: 041_enable_rls_public

Contesto: la 041 abilita RLS su ``public`` ma salta ``LEGACY_DIRECT_ACCESS_TABLES``, cioe' le
11 tabelle che il frontend CAT Dispatcher interroga via PostgREST. L'audit del database reale
(2026-11-26) ha mostrato che 9 di quelle tabelle (``cats``, ``communes``, ``regions``,
``provinces``, ``cat_commune``, ``cat_suspensions``, ``allowed_domains``,
``geojson_backup_log``, ``user_tenants``) non esistono in ``public``, mentre le due che esistono,
``tenants`` e ``user_roles``, sono tabelle core di PerX usate solo dal backend: lasciarle senza
RLS manteneva la Data API aperta a ``anon``.

La 041 era gia' stata applicata in produzione, quindi non si puo' modificare (Alembic non la
rieseguirebbe): questa revisione completa il lavoro. Stessa logica della 041, senza esclusioni:

- abilita RLS (senza ``FORCE``) su ogni tabella di ``public`` che ancora non ce l'ha;
- salta le tabelle estensione e quelle non possedute dal ruolo che esegue la migrazione
  (``ALTER TABLE`` fallirebbe e bloccherebbe il deploy).

Idempotente: le tabelle con RLS gia' attiva non vengono toccate. Backend (``DATABASE_URL``),
PerXHub ed edge function (service-role) bypassano RLS, quindi nessun flusso PerX cambia.
"""

from __future__ import annotations

from alembic import op


revision = "042_enable_rls_remaining"
down_revision = "041_enable_rls_public"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Niente format()/%I e niente RAISE con '%': evita problemi di escaping con il driver.
    op.execute(
        """
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
