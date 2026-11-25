"""Add PynkStudio product-domain aliases and merge migration heads.

Revision ID: 040_pynkstudio_domains
Revises: 014_domain_routing_apps, 039_bignami_condominio
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "040_pynkstudio_domains"
down_revision = ("014_domain_routing_apps", "039_bignami_condominio")
branch_labels = None
depends_on = None


PRODUCT_DOMAIN_ROUTES = (
    ("perx.pynkstudio.eu", "insight_studio", "PerX public product portal"),
    ("catdispatcher.pynkstudio.eu", "catdispatcher", "CAT Dispatcher product portal"),
    ("bignamionline.pynkstudio.eu", "bignami", "Bignami Online product portal"),
)


def upgrade() -> None:
    inspector = sa.inspect(op.get_bind())
    if not inspector.has_table("domain_routes"):
        op.create_table(
            "domain_routes",
            sa.Column(
                "id",
                sa.String(),
                primary_key=True,
                server_default=sa.text("gen_random_uuid()::text"),
            ),
            sa.Column("hostname", sa.String(), nullable=False),
            sa.Column("app", sa.String(), nullable=False),
            sa.Column("tenant_id", sa.String(), nullable=True),
            sa.Column("destination_url", sa.String(), nullable=True),
            sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
            sa.Column("notes", sa.Text(), nullable=True),
            sa.Column(
                "metadata_json",
                sa.JSON(),
                nullable=False,
                server_default=sa.text("'{}'::jsonb"),
            ),
            sa.Column(
                "created_at",
                sa.DateTime(timezone=True),
                nullable=False,
                server_default=sa.text("now()"),
            ),
            sa.Column(
                "updated_at",
                sa.DateTime(timezone=True),
                nullable=False,
                server_default=sa.text("now()"),
            ),
            sa.CheckConstraint(
                "app in ('bignami', 'catdispatcher', 'insight_studio', "
                "'perx_admin', 'randa', 'insured_portal')",
                name="ck_domain_routes_app",
            ),
            sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="SET NULL"),
            sa.UniqueConstraint("hostname", name="uq_domain_routes_hostname"),
        )
        op.create_index("idx_domain_routes_app_active", "domain_routes", ["app", "is_active"])
        op.create_index("idx_domain_routes_tenant", "domain_routes", ["tenant_id"])

    for hostname, app, notes in PRODUCT_DOMAIN_ROUTES:
        op.execute(
            f"""
            INSERT INTO domain_routes (hostname, app, destination_url, notes)
            VALUES ('{hostname}', '{app}', NULL, '{notes}')
            ON CONFLICT (hostname) DO UPDATE
            SET app = EXCLUDED.app,
                notes = EXCLUDED.notes,
                is_active = true,
                updated_at = now()
            """
        )


def downgrade() -> None:
    if not sa.inspect(op.get_bind()).has_table("domain_routes"):
        return
    hostnames = ", ".join(f"'{hostname}'" for hostname, _, _ in PRODUCT_DOMAIN_ROUTES)
    op.execute(f"DELETE FROM domain_routes WHERE hostname IN ({hostnames})")
