"""Add unified login user invitations

Revision ID: 014_user_invitations
Revises: 013_domain_routing
Create Date: 2026-05-22 00:00:00.000000
"""
from alembic import op
import sqlalchemy as sa


revision = "014_user_invitations"
down_revision = "013_domain_routing"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "user_invitations",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("tenant_id", sa.String(), nullable=False),
        sa.Column("user_id", sa.String(), nullable=False),
        sa.Column("personal_email", sa.String(), nullable=False),
        sa.Column("token_hash", sa.String(), nullable=False),
        sa.Column("status", sa.String(), nullable=False, server_default="pending"),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("accepted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_by_user_id", sa.String(), nullable=True),
        sa.Column("metadata_json", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=True),
        sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("token_hash", name="uq_user_invitations_token_hash"),
    )
    op.create_index(op.f("ix_user_invitations_id"), "user_invitations", ["id"], unique=False)
    op.create_index(op.f("ix_user_invitations_tenant_id"), "user_invitations", ["tenant_id"], unique=False)
    op.create_index(op.f("ix_user_invitations_user_id"), "user_invitations", ["user_id"], unique=False)
    op.create_index(op.f("ix_user_invitations_personal_email"), "user_invitations", ["personal_email"], unique=False)
    op.create_index(op.f("ix_user_invitations_token_hash"), "user_invitations", ["token_hash"], unique=True)
    op.create_index(op.f("ix_user_invitations_status"), "user_invitations", ["status"], unique=False)
    op.create_index(op.f("ix_user_invitations_expires_at"), "user_invitations", ["expires_at"], unique=False)
    op.create_index(op.f("ix_user_invitations_created_by_user_id"), "user_invitations", ["created_by_user_id"], unique=False)


def downgrade() -> None:
    op.drop_index(op.f("ix_user_invitations_created_by_user_id"), table_name="user_invitations")
    op.drop_index(op.f("ix_user_invitations_expires_at"), table_name="user_invitations")
    op.drop_index(op.f("ix_user_invitations_status"), table_name="user_invitations")
    op.drop_index(op.f("ix_user_invitations_token_hash"), table_name="user_invitations")
    op.drop_index(op.f("ix_user_invitations_personal_email"), table_name="user_invitations")
    op.drop_index(op.f("ix_user_invitations_user_id"), table_name="user_invitations")
    op.drop_index(op.f("ix_user_invitations_tenant_id"), table_name="user_invitations")
    op.drop_index(op.f("ix_user_invitations_id"), table_name="user_invitations")
    op.drop_table("user_invitations")
