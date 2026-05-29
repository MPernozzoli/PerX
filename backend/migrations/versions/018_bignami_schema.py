"""Add Bignami Online schema.

Revision ID: 018
Revises: 017
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa

revision = "018"
down_revision = "017"
branch_labels = None
depends_on = None


CONTENT_TABLES = [
    "companies",
    "policies",
    "policy_editions",
    "coverages",
    "sections",
    "common_limits",
    "coverage_items",
    "guarantee_maximums",
    "guarantee_deductibles",
    "guarantee_exclusion_groups",
    "guarantee_damage_definitions",
    "guarantee_groups",
    "norm_refs",
]

AUTH_TABLES = [
    "profiles",
    "comments",
    "edit_history",
    "user_policy_interactions",
    "user_roles",
    "bulk_imports",
]


def _scalar(sql: str):
    return op.get_bind().execute(sa.text(sql)).scalar()


def _has_schema(schema_name: str) -> bool:
    return bool(_scalar(f"SELECT to_regnamespace('{schema_name}') IS NOT NULL"))


def _has_role(role_name: str) -> bool:
    return bool(_scalar(f"SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '{role_name}')"))


def _policy_exists(table_name: str, policy_name: str) -> bool:
    return bool(
        op.get_bind()
        .execute(
            sa.text(
                """
                SELECT EXISTS (
                    SELECT 1
                    FROM pg_policies
                    WHERE schemaname = 'bignami'
                      AND tablename = :table_name
                      AND policyname = :policy_name
                )
                """
            ),
            {"table_name": table_name, "policy_name": policy_name},
        )
        .scalar()
    )


def _create_policy_if_missing(table_name: str, policy_name: str, ddl: str) -> None:
    if not _policy_exists(table_name, policy_name):
        op.execute(ddl)


def _storage_policy_exists(policy_name: str) -> bool:
    return bool(
        op.get_bind()
        .execute(
            sa.text(
                """
                SELECT EXISTS (
                    SELECT 1
                    FROM pg_policies
                    WHERE schemaname = 'storage'
                      AND tablename = 'objects'
                      AND policyname = :policy_name
                )
                """
            ),
            {"policy_name": policy_name},
        )
        .scalar()
    )


def _create_core_schema() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS pgcrypto")
    op.execute("CREATE SCHEMA IF NOT EXISTS bignami")
    op.execute("CREATE SCHEMA IF NOT EXISTS bignami_private")

    op.execute(
        """
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM pg_type t
                JOIN pg_namespace n ON n.oid = t.typnamespace
                WHERE n.nspname = 'bignami' AND t.typname = 'studio_role'
            ) THEN
                CREATE TYPE bignami.studio_role AS ENUM ('admin', 'moderator', 'member');
            END IF;
            IF NOT EXISTS (
                SELECT 1 FROM pg_type t
                JOIN pg_namespace n ON n.oid = t.typnamespace
                WHERE n.nspname = 'bignami' AND t.typname = 'app_role'
            ) THEN
                CREATE TYPE bignami.app_role AS ENUM ('admin', 'moderator', 'user');
            END IF;
        END $$;
        """
    )

    op.execute(
        """
        CREATE TABLE IF NOT EXISTS bignami.profiles (
            id uuid PRIMARY KEY,
            name text NOT NULL,
            email text NOT NULL,
            auth_provider text DEFAULT 'email',
            default_company text,
            default_guarantee text,
            created_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS bignami.companies (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            name text NOT NULL,
            code text NOT NULL DEFAULT upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
            aliases text[] DEFAULT '{}',
            created_at timestamptz NOT NULL DEFAULT now(),
            UNIQUE (code)
        )
        """
    )
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS bignami.policies (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id uuid NOT NULL REFERENCES bignami.companies(id) ON DELETE CASCADE,
            name text NOT NULL,
            code text NOT NULL DEFAULT upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
            type text NOT NULL CHECK (type IN ('domestica', 'azienda', 'agricola')),
            description text NOT NULL,
            tags text[] DEFAULT '{}',
            default_guarantee text NOT NULL DEFAULT 'Fenomeno Elettrico',
            created_at timestamptz NOT NULL DEFAULT now(),
            UNIQUE (code)
        )
        """
    )
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS bignami.policy_editions (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            policy_id uuid NOT NULL REFERENCES bignami.policies(id) ON DELETE CASCADE,
            year integer NOT NULL,
            edition_label text,
            code text NOT NULL DEFAULT upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
            pdf_url text,
            pdf_sha256 text,
            status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published')),
            canonical_group_id uuid,
            created_at timestamptz NOT NULL DEFAULT now(),
            UNIQUE (policy_id, code)
        )
        """
    )
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS bignami.coverages (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            policy_edition_id uuid NOT NULL REFERENCES bignami.policy_editions(id) ON DELETE CASCADE,
            guarantee text NOT NULL DEFAULT 'Fenomeno Elettrico',
            overview_text text NOT NULL,
            definitions text[] DEFAULT '{}',
            common_exclusions text[] DEFAULT '{}',
            common_interpretations text[] DEFAULT '{}',
            common_notes text[] DEFAULT '{}',
            value_type text,
            primo_rischio_value text,
            page_reference text,
            article_number text,
            created_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS bignami.sections (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            coverage_id uuid NOT NULL REFERENCES bignami.coverages(id) ON DELETE CASCADE,
            party text NOT NULL,
            exact_name text,
            definition text NOT NULL,
            exclusions text[] DEFAULT '{}',
            notes text[] DEFAULT '{}',
            links_to_common_limits text[] DEFAULT '{}',
            value_type text,
            primo_rischio_value text,
            page_reference text,
            article_number text,
            definition_page_reference text,
            definition_article_number text,
            deroga_percentage numeric,
            determinazione text[] DEFAULT '{}',
            emoji text,
            created_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS bignami.common_limits (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            coverage_id uuid NOT NULL REFERENCES bignami.coverages(id) ON DELETE CASCADE,
            label text NOT NULL,
            scope text NOT NULL,
            value text NOT NULL,
            on_frontespizio boolean DEFAULT false,
            page_reference text,
            article_number text,
            created_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS bignami.coverage_items (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            coverage_id uuid NOT NULL REFERENCES bignami.coverages(id) ON DELETE CASCADE,
            guarantee_group text NOT NULL DEFAULT 'generale',
            guarantee_name text NOT NULL,
            exact_name text,
            description text,
            value_type text,
            primo_rischio_value text,
            available_parties text[] DEFAULT '{}',
            maximum_type text,
            maximum_value text,
            maximum_applies_to text[] DEFAULT '{}',
            maximum_page_reference text,
            maximum_article_number text,
            deductible_type text,
            deductible_value text,
            deductible_percentage text,
            deductible_minimum text,
            deductible_maximum text,
            deductible_applies_to text[] DEFAULT '{}',
            deductible_page_reference text,
            deductible_article_number text,
            guarantee_exclusions text[] DEFAULT '{}',
            common_exclusions text[] DEFAULT '{}',
            exclusions_apply_to text[] DEFAULT '{}',
            exclusions_page_reference text,
            exclusions_article_number text,
            order_index integer NOT NULL DEFAULT 0,
            created_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS bignami.guarantee_maximums (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            coverage_item_id uuid NOT NULL REFERENCES bignami.coverage_items(id) ON DELETE CASCADE,
            exact_value text,
            minimum_value text,
            maximum_value text,
            percentage_of_party text,
            applies_to text[] DEFAULT '{}',
            on_frontespizio boolean DEFAULT false,
            notes text,
            page_reference text,
            article_number text,
            order_index integer DEFAULT 0,
            created_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS bignami.guarantee_deductibles (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            coverage_item_id uuid NOT NULL REFERENCES bignami.coverage_items(id) ON DELETE CASCADE,
            exact_value text,
            percentage text,
            minimum_value text,
            maximum_value text,
            applies_to text[] DEFAULT '{}',
            on_frontespizio boolean DEFAULT false,
            notes text,
            page_reference text,
            article_number text,
            order_index integer DEFAULT 0,
            created_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS bignami.guarantee_exclusion_groups (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            coverage_item_id uuid NOT NULL REFERENCES bignami.coverage_items(id) ON DELETE CASCADE,
            exclusions text[] NOT NULL DEFAULT '{}',
            applies_to text[] DEFAULT '{}',
            page_reference text,
            article_number text,
            order_index integer DEFAULT 0,
            created_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS bignami.guarantee_damage_definitions (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            coverage_item_id uuid NOT NULL REFERENCES bignami.coverage_items(id) ON DELETE CASCADE,
            definition_type text NOT NULL,
            applies_to text[] DEFAULT '{}',
            notes text,
            page_reference text,
            article_number text,
            order_index integer DEFAULT 0,
            created_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS bignami.guarantee_groups (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            code text NOT NULL UNIQUE,
            name text NOT NULL,
            is_active boolean NOT NULL DEFAULT true,
            created_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS bignami.norm_refs (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            code text NOT NULL,
            article text NOT NULL,
            comma text,
            text text NOT NULL,
            summary text NOT NULL,
            tags text[] DEFAULT '{}',
            links text[] DEFAULT '{}',
            last_update timestamptz NOT NULL DEFAULT now()
        )
        """
    )
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS bignami.edit_history (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            target_type text NOT NULL,
            target_id uuid NOT NULL,
            user_id uuid NOT NULL,
            change_summary text NOT NULL,
            diff jsonb,
            status text NOT NULL DEFAULT 'pending',
            visibility text NOT NULL DEFAULT 'global',
            approved_by uuid,
            approved_at timestamptz,
            rejection_reason text,
            created_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS bignami.comments (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            target_type text NOT NULL,
            target_id uuid NOT NULL,
            user_id uuid NOT NULL,
            visibility text NOT NULL DEFAULT 'public',
            body text NOT NULL,
            parent_comment_id uuid REFERENCES bignami.comments(id) ON DELETE CASCADE,
            resolved boolean DEFAULT false,
            created_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS bignami.user_policy_interactions (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id uuid NOT NULL,
            policy_id uuid NOT NULL REFERENCES bignami.policies(id) ON DELETE CASCADE,
            policy_edition_id uuid NOT NULL REFERENCES bignami.policy_editions(id) ON DELETE CASCADE,
            last_viewed timestamptz NOT NULL DEFAULT now(),
            view_count integer DEFAULT 1,
            bookmarked boolean DEFAULT false,
            selected_guarantee_group text,
            active_guarantees jsonb,
            preferences_updated_at timestamptz,
            UNIQUE(user_id, policy_id, policy_edition_id)
        )
        """
    )
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS bignami.user_roles (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id uuid NOT NULL,
            role bignami.app_role NOT NULL DEFAULT 'user',
            created_at timestamptz NOT NULL DEFAULT now(),
            UNIQUE(user_id, role)
        )
        """
    )
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS bignami.bulk_imports (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id uuid NOT NULL,
            filename text NOT NULL,
            file_url text NOT NULL,
            status text NOT NULL DEFAULT 'pending',
            imported_policies_count integer,
            ai_analysis jsonb,
            error_message text,
            processed_at timestamptz,
            created_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )


def _create_indexes() -> None:
    for statement in [
        "CREATE INDEX IF NOT EXISTS idx_bignami_policies_company ON bignami.policies(company_id)",
        "CREATE INDEX IF NOT EXISTS idx_bignami_policy_editions_policy ON bignami.policy_editions(policy_id)",
        "CREATE INDEX IF NOT EXISTS idx_bignami_coverages_edition ON bignami.coverages(policy_edition_id)",
        "CREATE INDEX IF NOT EXISTS idx_bignami_sections_coverage ON bignami.sections(coverage_id)",
        "CREATE INDEX IF NOT EXISTS idx_bignami_coverage_items_coverage_order ON bignami.coverage_items(coverage_id, order_index)",
        "CREATE INDEX IF NOT EXISTS idx_bignami_common_limits_coverage ON bignami.common_limits(coverage_id)",
        "CREATE INDEX IF NOT EXISTS idx_bignami_user_interactions_user ON bignami.user_policy_interactions(user_id)",
        "CREATE INDEX IF NOT EXISTS idx_bignami_user_roles_user ON bignami.user_roles(user_id)",
    ]:
        op.execute(statement)


def _configure_supabase_access() -> None:
    for table_name in CONTENT_TABLES + AUTH_TABLES:
        op.execute(f"ALTER TABLE bignami.{table_name} ENABLE ROW LEVEL SECURITY")

    if _has_role("anon"):
        op.execute("GRANT USAGE ON SCHEMA bignami TO anon")
        for table_name in CONTENT_TABLES:
            op.execute(f"GRANT SELECT ON bignami.{table_name} TO anon")

    if _has_role("authenticated"):
        op.execute("GRANT USAGE ON SCHEMA bignami TO authenticated")
        op.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA bignami TO authenticated")

    for table_name in CONTENT_TABLES:
        _create_policy_if_missing(
            table_name,
            f"{table_name}_public_read",
            f"CREATE POLICY {table_name}_public_read ON bignami.{table_name} FOR SELECT USING (true)",
        )
        if _has_role("authenticated"):
            _create_policy_if_missing(
                table_name,
                f"{table_name}_authenticated_manage",
                f"""
                CREATE POLICY {table_name}_authenticated_manage
                ON bignami.{table_name}
                FOR ALL TO authenticated
                USING (true)
                WITH CHECK (true)
                """,
            )

    if _has_schema("auth"):
        _create_policy_if_missing(
            "profiles",
            "profiles_own_read",
            "CREATE POLICY profiles_own_read ON bignami.profiles FOR SELECT USING (auth.uid() = id)",
        )
        _create_policy_if_missing(
            "profiles",
            "profiles_own_update",
            "CREATE POLICY profiles_own_update ON bignami.profiles FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id)",
        )
        _create_policy_if_missing(
            "user_roles",
            "user_roles_own_read",
            "CREATE POLICY user_roles_own_read ON bignami.user_roles FOR SELECT USING (auth.uid() = user_id)",
        )
        _create_policy_if_missing(
            "user_policy_interactions",
            "user_policy_interactions_own_manage",
            """
            CREATE POLICY user_policy_interactions_own_manage
            ON bignami.user_policy_interactions
            FOR ALL
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id)
            """,
        )
        for table_name in ["comments", "edit_history", "bulk_imports"]:
            _create_policy_if_missing(
                table_name,
                f"{table_name}_own_manage",
                f"""
                CREATE POLICY {table_name}_own_manage
                ON bignami.{table_name}
                FOR ALL
                USING (auth.uid() = user_id)
                WITH CHECK (auth.uid() = user_id)
                """,
            )

        op.execute(
            """
            CREATE OR REPLACE FUNCTION bignami_private.handle_new_bignami_user()
            RETURNS trigger
            LANGUAGE plpgsql
            SECURITY DEFINER
            SET search_path = bignami, public
            AS $$
            BEGIN
                INSERT INTO bignami.profiles (id, name, email, auth_provider)
                VALUES (
                    NEW.id,
                    COALESCE(NEW.raw_user_meta_data ->> 'full_name', NEW.raw_user_meta_data ->> 'name', NEW.email),
                    NEW.email,
                    COALESCE(NEW.raw_user_meta_data ->> 'provider', 'email')
                )
                ON CONFLICT (id) DO NOTHING;

                INSERT INTO bignami.user_roles (user_id, role)
                VALUES (NEW.id, 'user')
                ON CONFLICT (user_id, role) DO NOTHING;

                RETURN NEW;
            END;
            $$;
            """
        )
        op.execute(
            """
            DO $$
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM pg_trigger WHERE tgname = 'on_auth_user_created_bignami'
                ) THEN
                    CREATE TRIGGER on_auth_user_created_bignami
                    AFTER INSERT ON auth.users
                    FOR EACH ROW EXECUTE FUNCTION bignami_private.handle_new_bignami_user();
                END IF;
            END $$;
            """
        )


def _seed_defaults() -> None:
    op.execute(
        """
        INSERT INTO bignami.guarantee_groups (code, name)
        VALUES
            ('FE', 'Fenomeno Elettrico'),
            ('ACQUA', 'Acqua Condotta'),
            ('INCENDIO', 'Incendio'),
            ('FURTO', 'Furto')
        ON CONFLICT (code) DO NOTHING
        """
    )


def _configure_storage() -> None:
    if not bool(_scalar("SELECT to_regclass('storage.buckets') IS NOT NULL")):
        return

    op.execute(
        """
        INSERT INTO storage.buckets (id, name, public)
        VALUES ('policy-pdfs', 'policy-pdfs', true)
        ON CONFLICT (id) DO UPDATE SET public = true
        """
    )
    if not _storage_policy_exists("policy_pdfs_public_read"):
        op.execute(
            """
            CREATE POLICY policy_pdfs_public_read
            ON storage.objects
            FOR SELECT
            USING (bucket_id = 'policy-pdfs')
            """
        )
    if _has_role("authenticated") and not _storage_policy_exists("policy_pdfs_authenticated_upload"):
        op.execute(
            """
            CREATE POLICY policy_pdfs_authenticated_upload
            ON storage.objects
            FOR INSERT TO authenticated
            WITH CHECK (bucket_id = 'policy-pdfs')
            """
        )
    if _has_role("authenticated") and not _storage_policy_exists("policy_pdfs_authenticated_update"):
        op.execute(
            """
            CREATE POLICY policy_pdfs_authenticated_update
            ON storage.objects
            FOR UPDATE TO authenticated
            USING (bucket_id = 'policy-pdfs')
            WITH CHECK (bucket_id = 'policy-pdfs')
            """
        )
    if _has_role("authenticated") and not _storage_policy_exists("policy_pdfs_authenticated_delete"):
        op.execute(
            """
            CREATE POLICY policy_pdfs_authenticated_delete
            ON storage.objects
            FOR DELETE TO authenticated
            USING (bucket_id = 'policy-pdfs')
            """
        )


def upgrade() -> None:
    _create_core_schema()
    _create_indexes()
    _configure_supabase_access()
    _configure_storage()
    _seed_defaults()


def downgrade() -> None:
    op.execute("DROP SCHEMA IF EXISTS bignami_private CASCADE")
    op.execute("DROP SCHEMA IF EXISTS bignami CASCADE")
