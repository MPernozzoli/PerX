"""Add marketing and product apps to domain routing.

Revision ID: 014_domain_routing_apps
Revises: 013_domain_routing
"""

from alembic import op
import sqlalchemy as sa


revision = "014_domain_routing_apps"
down_revision = "013_domain_routing"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Some early production databases were stamped past 013 without the optional
    # domain_routes table. The merge migration 040 repairs that drift; this
    # branch must remain a no-op until then instead of aborting the deploy.
    if not sa.inspect(op.get_bind()).has_table("domain_routes"):
        return
    op.drop_constraint("ck_domain_routes_app", "domain_routes", type_="check")
    op.create_check_constraint(
        "ck_domain_routes_app",
        "domain_routes",
        "app in ('bignami', 'catdispatcher', 'insight_studio', 'perx_admin', 'randa', 'insured_portal')",
    )


def downgrade() -> None:
    if not sa.inspect(op.get_bind()).has_table("domain_routes"):
        return
    op.drop_constraint("ck_domain_routes_app", "domain_routes", type_="check")
    op.create_check_constraint(
        "ck_domain_routes_app",
        "domain_routes",
        "app in ('catdispatcher', 'perx_admin', 'insured_portal')",
    )
