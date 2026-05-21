"""Add general process jobs queue

Revision ID: 010_general_process_jobs
Revises: 009_user_personal_professional_email
Create Date: 2026-05-21 00:00:00.000000
"""
from alembic import op
import sqlalchemy as sa


revision = "010_general_process_jobs"
down_revision = "009_user_personal_professional_email"
branch_labels = None
depends_on = None


def _indexes(table_name: str) -> set[str]:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if not inspector.has_table(table_name):
        return set()
    return {index["name"] for index in inspector.get_indexes(table_name)}


def upgrade() -> None:
    inspector = sa.inspect(op.get_bind())
    if not inspector.has_table("process_jobs"):
        op.create_table(
            "process_jobs",
            sa.Column("id", sa.String(), nullable=False),
            sa.Column("tenant_id", sa.String(), nullable=False),
            sa.Column("claim_id", sa.String(), nullable=True),
            sa.Column("created_by_user_id", sa.String(), nullable=True),
            sa.Column("job_type", sa.String(), nullable=False),
            sa.Column("status", sa.String(), nullable=False, server_default="pending"),
            sa.Column("priority", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("retry_count", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("max_retries", sa.Integer(), nullable=False, server_default="5"),
            sa.Column("available_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
            sa.Column("lease_owner", sa.String(), nullable=True),
            sa.Column("lease_expires_at", sa.DateTime(timezone=True), nullable=True),
            sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
            sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
            sa.Column("last_heartbeat_at", sa.DateTime(timezone=True), nullable=True),
            sa.Column("last_error", sa.Text(), nullable=True),
            sa.Column("idempotency_key", sa.String(), nullable=True),
            sa.Column("input_json", sa.JSON(), nullable=False),
            sa.Column("result_json", sa.JSON(), nullable=True),
            sa.Column("tags_json", sa.JSON(), nullable=True),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
            sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
            sa.ForeignKeyConstraint(["claim_id"], ["claims.id"], ondelete="SET NULL"),
            sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="SET NULL"),
            sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
            sa.PrimaryKeyConstraint("id"),
        )

    existing_indexes = _indexes("process_jobs")
    for name, columns, unique in (
        (op.f("ix_process_jobs_id"), ["id"], False),
        (op.f("ix_process_jobs_tenant_id"), ["tenant_id"], False),
        (op.f("ix_process_jobs_claim_id"), ["claim_id"], False),
        (op.f("ix_process_jobs_created_by_user_id"), ["created_by_user_id"], False),
        (op.f("ix_process_jobs_job_type"), ["job_type"], False),
        (op.f("ix_process_jobs_status"), ["status"], False),
        (op.f("ix_process_jobs_available_at"), ["available_at"], False),
        (op.f("ix_process_jobs_lease_owner"), ["lease_owner"], False),
        (op.f("ix_process_jobs_lease_expires_at"), ["lease_expires_at"], False),
        (op.f("ix_process_jobs_idempotency_key"), ["idempotency_key"], True),
        ("idx_process_jobs_claim_status", ["claim_id", "status"], False),
        ("idx_process_jobs_claimable", ["status", "available_at", "priority", "created_at"], False),
        ("idx_process_jobs_type_status", ["job_type", "status"], False),
    ):
        if name not in existing_indexes:
            op.create_index(name, "process_jobs", columns, unique=unique)


def downgrade() -> None:
    if not sa.inspect(op.get_bind()).has_table("process_jobs"):
        return
    for name in (
        "idx_process_jobs_type_status",
        "idx_process_jobs_claimable",
        "idx_process_jobs_claim_status",
        op.f("ix_process_jobs_idempotency_key"),
        op.f("ix_process_jobs_lease_expires_at"),
        op.f("ix_process_jobs_lease_owner"),
        op.f("ix_process_jobs_available_at"),
        op.f("ix_process_jobs_status"),
        op.f("ix_process_jobs_job_type"),
        op.f("ix_process_jobs_created_by_user_id"),
        op.f("ix_process_jobs_claim_id"),
        op.f("ix_process_jobs_tenant_id"),
        op.f("ix_process_jobs_id"),
    ):
        op.drop_index(name, table_name="process_jobs")
    op.drop_table("process_jobs")
