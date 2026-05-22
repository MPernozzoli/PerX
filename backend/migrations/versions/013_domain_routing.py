"""Add deploy domain routing table

Revision ID: 013_domain_routing
Revises: 012_cat_dispatcher_core
Create Date: 2026-05-22 00:00:00.000000
"""
from alembic import op
import sqlalchemy as sa


revision = "013_domain_routing"
down_revision = "012_cat_dispatcher_core"
branch_labels = None
depends_on = None


def _has_table(name: str) -> bool:
    return sa.inspect(op.get_bind()).has_table(name)


def upgrade() -> None:
    if not _has_table("domain_routes"):
        op.create_table(
            "domain_routes",
            sa.Column("id", sa.String(), primary_key=True, server_default=sa.text("gen_random_uuid()::text")),
            sa.Column("hostname", sa.String(), nullable=False),
            sa.Column("app", sa.String(), nullable=False),
            sa.Column("tenant_id", sa.String(), nullable=True),
            sa.Column("destination_url", sa.String(), nullable=True),
            sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
            sa.Column("notes", sa.Text(), nullable=True),
            sa.Column("metadata_json", sa.JSON(), nullable=False, server_default=sa.text("'{}'::jsonb")),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
            sa.CheckConstraint("app in ('catdispatcher', 'perx_admin', 'insured_portal')", name="ck_domain_routes_app"),
            sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="SET NULL"),
            sa.UniqueConstraint("hostname", name="uq_domain_routes_hostname"),
        )
    existing_indexes = {idx["name"] for idx in sa.inspect(op.get_bind()).get_indexes("domain_routes")}
    if "idx_domain_routes_app_active" not in existing_indexes:
        op.create_index("idx_domain_routes_app_active", "domain_routes", ["app", "is_active"])
    if "idx_domain_routes_tenant" not in existing_indexes:
        op.create_index("idx_domain_routes_tenant", "domain_routes", ["tenant_id"])

    # Seed the platform domains; they can be edited from the admin API after migration.
    op.execute(
        """
        INSERT INTO domain_routes (hostname, app, destination_url, notes)
        VALUES
          ('catdispatcher.it', 'catdispatcher', NULL, 'CAT Dispatcher public app'),
          ('www.catdispatcher.it', 'catdispatcher', NULL, 'CAT Dispatcher public app'),
          ('admin.perx.it', 'perx_admin', NULL, 'PerX platform admin')
        ON CONFLICT (hostname) DO NOTHING
        """
    )


def downgrade() -> None:
    if not _has_table("domain_routes"):
        return
    op.drop_index("idx_domain_routes_tenant", table_name="domain_routes")
    op.drop_index("idx_domain_routes_app_active", table_name="domain_routes")
    op.drop_table("domain_routes")
