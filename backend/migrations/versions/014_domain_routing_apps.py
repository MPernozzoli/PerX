"""Add marketing and product apps to domain routing.

Revision ID: 014_domain_routing_apps
Revises: 013_domain_routing
"""

from alembic import op


revision = "014_domain_routing_apps"
down_revision = "013_domain_routing"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.drop_constraint("ck_domain_routes_app", "domain_routes", type_="check")
    op.create_check_constraint(
        "ck_domain_routes_app",
        "domain_routes",
        "app in ('bignami', 'catdispatcher', 'insight_studio', 'perx_admin', 'randa', 'insured_portal')",
    )


def downgrade() -> None:
    op.drop_constraint("ck_domain_routes_app", "domain_routes", type_="check")
    op.create_check_constraint(
        "ck_domain_routes_app",
        "domain_routes",
        "app in ('catdispatcher', 'perx_admin', 'insured_portal')",
    )
