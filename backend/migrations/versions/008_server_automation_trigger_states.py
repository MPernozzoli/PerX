"""Server automation trigger states

Revision ID: 008_automation_trigger_states
Revises: 007_resend_inbound_email
Create Date: 2026-05-21 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


revision = "008_automation_trigger_states"
down_revision = "007_resend_inbound_email"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "automation_trigger_states",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("tenant_id", sa.String(), nullable=False),
        sa.Column("claim_id", sa.String(), nullable=False),
        sa.Column("trigger_type", sa.String(), nullable=False),
        sa.Column("start_date", sa.DateTime(timezone=True), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        sa.Column("last_check_date", sa.DateTime(timezone=True), nullable=True),
        sa.Column("timeout_days", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["claim_id"], ["claims.id"]),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_automation_trigger_states_id"), "automation_trigger_states", ["id"], unique=False)
    op.create_index(op.f("ix_automation_trigger_states_tenant_id"), "automation_trigger_states", ["tenant_id"], unique=False)
    op.create_index(op.f("ix_automation_trigger_states_claim_id"), "automation_trigger_states", ["claim_id"], unique=False)
    op.create_index(op.f("ix_automation_trigger_states_trigger_type"), "automation_trigger_states", ["trigger_type"], unique=False)
    op.create_index("uq_automation_trigger_state_claim_type", "automation_trigger_states", ["claim_id", "trigger_type"], unique=True)
    op.create_index("idx_automation_trigger_state_tenant_active", "automation_trigger_states", ["tenant_id", "is_active"], unique=False)


def downgrade() -> None:
    op.drop_index("idx_automation_trigger_state_tenant_active", table_name="automation_trigger_states")
    op.drop_index("uq_automation_trigger_state_claim_type", table_name="automation_trigger_states")
    op.drop_index(op.f("ix_automation_trigger_states_trigger_type"), table_name="automation_trigger_states")
    op.drop_index(op.f("ix_automation_trigger_states_claim_id"), table_name="automation_trigger_states")
    op.drop_index(op.f("ix_automation_trigger_states_tenant_id"), table_name="automation_trigger_states")
    op.drop_index(op.f("ix_automation_trigger_states_id"), table_name="automation_trigger_states")
    op.drop_table("automation_trigger_states")
