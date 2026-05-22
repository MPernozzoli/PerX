"""Add Resend inbound email pipeline tables

Revision ID: 007_resend_inbound_email
Revises: 006_document_versions
Create Date: 2026-05-21 00:00:00.000000
"""
from alembic import op
import sqlalchemy as sa


revision = "007_resend_inbound_email"
down_revision = "006_document_versions"
branch_labels = None
depends_on = None


def _indexes(table_name: str) -> set[str]:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if not inspector.has_table(table_name):
        return set()
    return {index["name"] for index in inspector.get_indexes(table_name)}


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)

    if not inspector.has_table("tenant_email_domains"):
        op.create_table(
            "tenant_email_domains",
            sa.Column("id", sa.String(), nullable=False),
            sa.Column("tenant_id", sa.String(), nullable=False),
            sa.Column("domain", sa.String(), nullable=False),
            sa.Column("provider", sa.String(), nullable=False, server_default="resend"),
            sa.Column("provider_domain_id", sa.String(), nullable=True),
            sa.Column("inbound_enabled", sa.String(), nullable=False, server_default="true"),
            sa.Column("outbound_enabled", sa.String(), nullable=False, server_default="true"),
            sa.Column("catch_all_enabled", sa.String(), nullable=False, server_default="true"),
            sa.Column("status", sa.String(), nullable=False, server_default="pending"),
            sa.Column("settings_json", sa.JSON(), nullable=True),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=True),
            sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint("domain", name="uq_tenant_email_domains_domain"),
        )

    existing_indexes = _indexes("tenant_email_domains")
    for name, columns, unique in (
        (op.f("ix_tenant_email_domains_id"), ["id"], False),
        (op.f("ix_tenant_email_domains_tenant_id"), ["tenant_id"], False),
        (op.f("ix_tenant_email_domains_domain"), ["domain"], True),
    ):
        if name not in existing_indexes:
            op.create_index(name, "tenant_email_domains", columns, unique=unique)

    if not inspector.has_table("inbound_email_events"):
        op.create_table(
            "inbound_email_events",
            sa.Column("id", sa.String(), nullable=False),
            sa.Column("tenant_id", sa.String(), nullable=False),
            sa.Column("domain_id", sa.String(), nullable=True),
            sa.Column("mailbox_id", sa.String(), nullable=True),
            sa.Column("provider", sa.String(), nullable=False, server_default="resend"),
            sa.Column("provider_event_id", sa.String(), nullable=False),
            sa.Column("provider_email_id", sa.String(), nullable=True),
            sa.Column("message_id", sa.String(), nullable=True),
            sa.Column("from_address", sa.String(), nullable=False),
            sa.Column("to_addresses", sa.JSON(), nullable=False),
            sa.Column("cc_addresses", sa.JSON(), nullable=False),
            sa.Column("subject", sa.String(), nullable=True),
            sa.Column("body_text", sa.Text(), nullable=True),
            sa.Column("body_html", sa.Text(), nullable=True),
            sa.Column("received_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("ingested_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
            sa.Column("status", sa.String(), nullable=False, server_default="queued"),
            sa.Column("raw_payload", sa.JSON(), nullable=False),
            sa.Column("attachments_json", sa.JSON(), nullable=True),
            sa.ForeignKeyConstraint(["domain_id"], ["tenant_email_domains.id"], ondelete="SET NULL"),
            sa.ForeignKeyConstraint(["mailbox_id"], ["mailboxes.id"], ondelete="SET NULL"),
            sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint("provider_event_id", name="uq_inbound_email_events_provider_event_id"),
        )

    existing_indexes = _indexes("inbound_email_events")
    for name, columns, unique in (
        (op.f("ix_inbound_email_events_id"), ["id"], False),
        (op.f("ix_inbound_email_events_tenant_id"), ["tenant_id"], False),
        (op.f("ix_inbound_email_events_domain_id"), ["domain_id"], False),
        (op.f("ix_inbound_email_events_mailbox_id"), ["mailbox_id"], False),
        (op.f("ix_inbound_email_events_provider_event_id"), ["provider_event_id"], True),
        (op.f("ix_inbound_email_events_provider_email_id"), ["provider_email_id"], False),
        (op.f("ix_inbound_email_events_message_id"), ["message_id"], False),
        (op.f("ix_inbound_email_events_from_address"), ["from_address"], False),
        (op.f("ix_inbound_email_events_received_at"), ["received_at"], False),
        ("idx_inbound_email_events_tenant_received", ["tenant_id", "received_at"], False),
    ):
        if name not in existing_indexes:
            op.create_index(name, "inbound_email_events", columns, unique=unique)

    if not inspector.has_table("email_processing_jobs"):
        op.create_table(
            "email_processing_jobs",
            sa.Column("id", sa.String(), nullable=False),
            sa.Column("tenant_id", sa.String(), nullable=False),
            sa.Column("inbound_event_id", sa.String(), nullable=False),
            sa.Column("email_id", sa.String(), nullable=True),
            sa.Column("status", sa.String(), nullable=False, server_default="pending"),
            sa.Column("priority", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("retry_count", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("max_retries", sa.Integer(), nullable=False, server_default="5"),
            sa.Column("available_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
            sa.Column("lease_owner", sa.String(), nullable=True),
            sa.Column("lease_expires_at", sa.DateTime(timezone=True), nullable=True),
            sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
            sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
            sa.Column("last_error", sa.Text(), nullable=True),
            sa.Column("input_json", sa.JSON(), nullable=False),
            sa.Column("result_json", sa.JSON(), nullable=True),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
            sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
            sa.ForeignKeyConstraint(["email_id"], ["emails.id"], ondelete="SET NULL"),
            sa.ForeignKeyConstraint(["inbound_event_id"], ["inbound_email_events.id"], ondelete="CASCADE"),
            sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint("inbound_event_id", name="uq_email_processing_jobs_inbound_event_id"),
        )

    existing_indexes = _indexes("email_processing_jobs")
    for name, columns, unique in (
        (op.f("ix_email_processing_jobs_id"), ["id"], False),
        (op.f("ix_email_processing_jobs_tenant_id"), ["tenant_id"], False),
        (op.f("ix_email_processing_jobs_inbound_event_id"), ["inbound_event_id"], True),
        (op.f("ix_email_processing_jobs_email_id"), ["email_id"], False),
        (op.f("ix_email_processing_jobs_status"), ["status"], False),
        (op.f("ix_email_processing_jobs_available_at"), ["available_at"], False),
        (op.f("ix_email_processing_jobs_lease_owner"), ["lease_owner"], False),
        (op.f("ix_email_processing_jobs_lease_expires_at"), ["lease_expires_at"], False),
        ("idx_email_processing_jobs_claim", ["status", "available_at", "priority"], False),
    ):
        if name not in existing_indexes:
            op.create_index(name, "email_processing_jobs", columns, unique=unique)


def downgrade() -> None:
    for name in (
        "idx_email_processing_jobs_claim",
        op.f("ix_email_processing_jobs_lease_expires_at"),
        op.f("ix_email_processing_jobs_lease_owner"),
        op.f("ix_email_processing_jobs_available_at"),
        op.f("ix_email_processing_jobs_status"),
        op.f("ix_email_processing_jobs_email_id"),
        op.f("ix_email_processing_jobs_inbound_event_id"),
        op.f("ix_email_processing_jobs_tenant_id"),
        op.f("ix_email_processing_jobs_id"),
    ):
        op.drop_index(name, table_name="email_processing_jobs")
    op.drop_table("email_processing_jobs")

    for name in (
        "idx_inbound_email_events_tenant_received",
        op.f("ix_inbound_email_events_received_at"),
        op.f("ix_inbound_email_events_from_address"),
        op.f("ix_inbound_email_events_message_id"),
        op.f("ix_inbound_email_events_provider_email_id"),
        op.f("ix_inbound_email_events_provider_event_id"),
        op.f("ix_inbound_email_events_mailbox_id"),
        op.f("ix_inbound_email_events_domain_id"),
        op.f("ix_inbound_email_events_tenant_id"),
        op.f("ix_inbound_email_events_id"),
    ):
        op.drop_index(name, table_name="inbound_email_events")
    op.drop_table("inbound_email_events")

    for name in (
        op.f("ix_tenant_email_domains_domain"),
        op.f("ix_tenant_email_domains_tenant_id"),
        op.f("ix_tenant_email_domains_id"),
    ):
        op.drop_index(name, table_name="tenant_email_domains")
    op.drop_table("tenant_email_domains")
