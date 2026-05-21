"""Add portal domains per tenant

Revision ID: 011_portal_tenant_domains
Revises: 010_general_process_jobs
Create Date: 2026-05-21 00:00:00.000000
"""
from alembic import op
import sqlalchemy as sa


revision = "011_portal_tenant_domains"
down_revision = "010_general_process_jobs"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "tenant_portal_domains",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("tenant_id", sa.String(), nullable=False),
        sa.Column("domain", sa.String(), nullable=False),
        sa.Column("is_primary", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_tenant_portal_domains_id"), "tenant_portal_domains", ["id"], unique=False)
    op.create_index(op.f("ix_tenant_portal_domains_tenant_id"), "tenant_portal_domains", ["tenant_id"], unique=False)
    op.create_index(op.f("ix_tenant_portal_domains_domain"), "tenant_portal_domains", ["domain"], unique=True)
    op.create_index("idx_tenant_portal_domains_tenant_primary", "tenant_portal_domains", ["tenant_id", "is_primary"], unique=False)


def downgrade() -> None:
    op.drop_index("idx_tenant_portal_domains_tenant_primary", table_name="tenant_portal_domains")
    op.drop_index(op.f("ix_tenant_portal_domains_domain"), table_name="tenant_portal_domains")
    op.drop_index(op.f("ix_tenant_portal_domains_tenant_id"), table_name="tenant_portal_domains")
    op.drop_index(op.f("ix_tenant_portal_domains_id"), table_name="tenant_portal_domains")
    op.drop_table("tenant_portal_domains")
