"""Add insured portal architecture

Revision ID: 003_portal_architecture
Revises: 002_platform_admin
Create Date: 2026-04-05 00:00:00.000000
"""
from alembic import op
import sqlalchemy as sa


revision = "003_portal_architecture"
down_revision = "002_platform_admin"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "portal_claim_accesses",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("tenant_id", sa.String(), nullable=False),
        sa.Column("claim_id", sa.String(), nullable=False),
        sa.Column("role", sa.String(), nullable=False, server_default="insured"),
        sa.Column("full_name", sa.String(), nullable=False),
        sa.Column("normalized_full_name", sa.String(), nullable=True),
        sa.Column("email", sa.String(), nullable=False),
        sa.Column("phone_number", sa.String(), nullable=True),
        sa.Column("normalized_phone_number", sa.String(), nullable=True),
        sa.Column("tax_code_hash", sa.String(), nullable=True),
        sa.Column("tax_code_last4", sa.String(), nullable=True),
        sa.Column("preferred_channel", sa.String(), nullable=False, server_default="email"),
        sa.Column("status", sa.String(), nullable=False, server_default="active"),
        sa.Column("is_primary", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("invited_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_access_requested_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_authenticated_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_delivery_status", sa.String(), nullable=True),
        sa.Column("metadata_json", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["claim_id"], ["claims.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_portal_claim_accesses_id"), "portal_claim_accesses", ["id"], unique=False)
    op.create_index(op.f("ix_portal_claim_accesses_tenant_id"), "portal_claim_accesses", ["tenant_id"], unique=False)
    op.create_index(op.f("ix_portal_claim_accesses_claim_id"), "portal_claim_accesses", ["claim_id"], unique=False)
    op.create_index(op.f("ix_portal_claim_accesses_email"), "portal_claim_accesses", ["email"], unique=False)
    op.create_index(op.f("ix_portal_claim_accesses_normalized_full_name"), "portal_claim_accesses", ["normalized_full_name"], unique=False)
    op.create_index(op.f("ix_portal_claim_accesses_normalized_phone_number"), "portal_claim_accesses", ["normalized_phone_number"], unique=False)
    op.create_index(op.f("ix_portal_claim_accesses_tax_code_hash"), "portal_claim_accesses", ["tax_code_hash"], unique=False)
    op.create_index("idx_portal_claim_accesses_claim_email", "portal_claim_accesses", ["claim_id", "email"], unique=False)
    op.create_index("idx_portal_claim_accesses_claim_status", "portal_claim_accesses", ["claim_id", "status"], unique=False)

    op.create_table(
        "portal_auth_challenges",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("tenant_id", sa.String(), nullable=False),
        sa.Column("claim_id", sa.String(), nullable=False),
        sa.Column("portal_access_id", sa.String(), nullable=False),
        sa.Column("challenge_type", sa.String(), nullable=False, server_default="magic_link"),
        sa.Column("delivery_channel", sa.String(), nullable=False, server_default="email"),
        sa.Column("destination", sa.String(), nullable=True),
        sa.Column("token_hash", sa.String(), nullable=True),
        sa.Column("otp_code_hash", sa.String(), nullable=True),
        sa.Column("status", sa.String(), nullable=False, server_default="pending"),
        sa.Column("requested_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("consumed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("metadata_json", sa.JSON(), nullable=True),
        sa.ForeignKeyConstraint(["claim_id"], ["claims.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["portal_access_id"], ["portal_claim_accesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_portal_auth_challenges_id"), "portal_auth_challenges", ["id"], unique=False)
    op.create_index(op.f("ix_portal_auth_challenges_tenant_id"), "portal_auth_challenges", ["tenant_id"], unique=False)
    op.create_index(op.f("ix_portal_auth_challenges_claim_id"), "portal_auth_challenges", ["claim_id"], unique=False)
    op.create_index(op.f("ix_portal_auth_challenges_portal_access_id"), "portal_auth_challenges", ["portal_access_id"], unique=False)
    op.create_index(op.f("ix_portal_auth_challenges_token_hash"), "portal_auth_challenges", ["token_hash"], unique=False)
    op.create_index(op.f("ix_portal_auth_challenges_status"), "portal_auth_challenges", ["status"], unique=False)
    op.create_index(op.f("ix_portal_auth_challenges_expires_at"), "portal_auth_challenges", ["expires_at"], unique=False)

    op.create_table(
        "portal_document_collection_submissions",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("tenant_id", sa.String(), nullable=False),
        sa.Column("claim_id", sa.String(), nullable=False),
        sa.Column("portal_access_id", sa.String(), nullable=False),
        sa.Column("status", sa.String(), nullable=False, server_default="submitted"),
        sa.Column("payload_json", sa.JSON(), nullable=True),
        sa.Column("metadata_json", sa.JSON(), nullable=True),
        sa.Column("submitted_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["claim_id"], ["claims.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["portal_access_id"], ["portal_claim_accesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_portal_document_collection_submissions_id"), "portal_document_collection_submissions", ["id"], unique=False)
    op.create_index(op.f("ix_portal_document_collection_submissions_tenant_id"), "portal_document_collection_submissions", ["tenant_id"], unique=False)
    op.create_index(op.f("ix_portal_document_collection_submissions_claim_id"), "portal_document_collection_submissions", ["claim_id"], unique=False)
    op.create_index(op.f("ix_portal_document_collection_submissions_portal_access_id"), "portal_document_collection_submissions", ["portal_access_id"], unique=False)

    op.create_table(
        "portal_bank_account_submissions",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("tenant_id", sa.String(), nullable=False),
        sa.Column("claim_id", sa.String(), nullable=False),
        sa.Column("portal_access_id", sa.String(), nullable=False),
        sa.Column("iban", sa.String(), nullable=False),
        sa.Column("account_holder", sa.String(), nullable=True),
        sa.Column("validation_status", sa.String(), nullable=False, server_default="pending"),
        sa.Column("bank_name", sa.String(), nullable=True),
        sa.Column("branch_name", sa.String(), nullable=True),
        sa.Column("is_selected", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("metadata_json", sa.JSON(), nullable=True),
        sa.Column("submitted_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("confirmed_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["claim_id"], ["claims.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["portal_access_id"], ["portal_claim_accesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_portal_bank_account_submissions_id"), "portal_bank_account_submissions", ["id"], unique=False)
    op.create_index(op.f("ix_portal_bank_account_submissions_tenant_id"), "portal_bank_account_submissions", ["tenant_id"], unique=False)
    op.create_index(op.f("ix_portal_bank_account_submissions_claim_id"), "portal_bank_account_submissions", ["claim_id"], unique=False)
    op.create_index(op.f("ix_portal_bank_account_submissions_portal_access_id"), "portal_bank_account_submissions", ["portal_access_id"], unique=False)

    op.create_table(
        "portal_signature_requests",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("tenant_id", sa.String(), nullable=False),
        sa.Column("claim_id", sa.String(), nullable=False),
        sa.Column("portal_access_id", sa.String(), nullable=False),
        sa.Column("document_id", sa.String(), nullable=False),
        sa.Column("challenge_id", sa.String(), nullable=True),
        sa.Column("signature_method", sa.String(), nullable=False, server_default="otp"),
        sa.Column("status", sa.String(), nullable=False, server_default="pending_confirmation"),
        sa.Column("otp_attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("requested_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("signed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("metadata_json", sa.JSON(), nullable=True),
        sa.ForeignKeyConstraint(["challenge_id"], ["portal_auth_challenges.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["claim_id"], ["claims.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["document_id"], ["documents.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["portal_access_id"], ["portal_claim_accesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_portal_signature_requests_id"), "portal_signature_requests", ["id"], unique=False)
    op.create_index(op.f("ix_portal_signature_requests_tenant_id"), "portal_signature_requests", ["tenant_id"], unique=False)
    op.create_index(op.f("ix_portal_signature_requests_claim_id"), "portal_signature_requests", ["claim_id"], unique=False)
    op.create_index(op.f("ix_portal_signature_requests_portal_access_id"), "portal_signature_requests", ["portal_access_id"], unique=False)
    op.create_index(op.f("ix_portal_signature_requests_document_id"), "portal_signature_requests", ["document_id"], unique=False)
    op.create_index(op.f("ix_portal_signature_requests_challenge_id"), "portal_signature_requests", ["challenge_id"], unique=False)
    op.create_index(op.f("ix_portal_signature_requests_status"), "portal_signature_requests", ["status"], unique=False)

    op.create_table(
        "portal_conversations",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("tenant_id", sa.String(), nullable=False),
        sa.Column("claim_id", sa.String(), nullable=False),
        sa.Column("portal_access_id", sa.String(), nullable=False),
        sa.Column("internal_thread_id", sa.String(), nullable=True),
        sa.Column("status", sa.String(), nullable=False, server_default="active"),
        sa.Column("metadata_json", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["claim_id"], ["claims.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["internal_thread_id"], ["internal_chat_threads.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["portal_access_id"], ["portal_claim_accesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_portal_conversations_id"), "portal_conversations", ["id"], unique=False)
    op.create_index(op.f("ix_portal_conversations_tenant_id"), "portal_conversations", ["tenant_id"], unique=False)
    op.create_index(op.f("ix_portal_conversations_claim_id"), "portal_conversations", ["claim_id"], unique=False)
    op.create_index(op.f("ix_portal_conversations_portal_access_id"), "portal_conversations", ["portal_access_id"], unique=False)
    op.create_index(op.f("ix_portal_conversations_internal_thread_id"), "portal_conversations", ["internal_thread_id"], unique=False)
    op.create_index(op.f("ix_portal_conversations_status"), "portal_conversations", ["status"], unique=False)

    op.create_table(
        "portal_conversation_messages",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("tenant_id", sa.String(), nullable=False),
        sa.Column("conversation_id", sa.String(), nullable=False),
        sa.Column("claim_id", sa.String(), nullable=False),
        sa.Column("author_type", sa.String(), nullable=False, server_default="portal"),
        sa.Column("body_text", sa.Text(), nullable=False),
        sa.Column("internal_chat_message_id", sa.String(), nullable=True),
        sa.Column("metadata_json", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["claim_id"], ["claims.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["conversation_id"], ["portal_conversations.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["internal_chat_message_id"], ["internal_chat_messages.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_portal_conversation_messages_id"), "portal_conversation_messages", ["id"], unique=False)
    op.create_index(op.f("ix_portal_conversation_messages_tenant_id"), "portal_conversation_messages", ["tenant_id"], unique=False)
    op.create_index(op.f("ix_portal_conversation_messages_conversation_id"), "portal_conversation_messages", ["conversation_id"], unique=False)
    op.create_index(op.f("ix_portal_conversation_messages_claim_id"), "portal_conversation_messages", ["claim_id"], unique=False)
    op.create_index(op.f("ix_portal_conversation_messages_internal_chat_message_id"), "portal_conversation_messages", ["internal_chat_message_id"], unique=False)


def downgrade() -> None:
    op.drop_index(op.f("ix_portal_conversation_messages_internal_chat_message_id"), table_name="portal_conversation_messages")
    op.drop_index(op.f("ix_portal_conversation_messages_claim_id"), table_name="portal_conversation_messages")
    op.drop_index(op.f("ix_portal_conversation_messages_conversation_id"), table_name="portal_conversation_messages")
    op.drop_index(op.f("ix_portal_conversation_messages_tenant_id"), table_name="portal_conversation_messages")
    op.drop_index(op.f("ix_portal_conversation_messages_id"), table_name="portal_conversation_messages")
    op.drop_table("portal_conversation_messages")

    op.drop_index(op.f("ix_portal_conversations_status"), table_name="portal_conversations")
    op.drop_index(op.f("ix_portal_conversations_internal_thread_id"), table_name="portal_conversations")
    op.drop_index(op.f("ix_portal_conversations_portal_access_id"), table_name="portal_conversations")
    op.drop_index(op.f("ix_portal_conversations_claim_id"), table_name="portal_conversations")
    op.drop_index(op.f("ix_portal_conversations_tenant_id"), table_name="portal_conversations")
    op.drop_index(op.f("ix_portal_conversations_id"), table_name="portal_conversations")
    op.drop_table("portal_conversations")

    op.drop_index(op.f("ix_portal_signature_requests_status"), table_name="portal_signature_requests")
    op.drop_index(op.f("ix_portal_signature_requests_challenge_id"), table_name="portal_signature_requests")
    op.drop_index(op.f("ix_portal_signature_requests_document_id"), table_name="portal_signature_requests")
    op.drop_index(op.f("ix_portal_signature_requests_portal_access_id"), table_name="portal_signature_requests")
    op.drop_index(op.f("ix_portal_signature_requests_claim_id"), table_name="portal_signature_requests")
    op.drop_index(op.f("ix_portal_signature_requests_tenant_id"), table_name="portal_signature_requests")
    op.drop_index(op.f("ix_portal_signature_requests_id"), table_name="portal_signature_requests")
    op.drop_table("portal_signature_requests")

    op.drop_index(op.f("ix_portal_bank_account_submissions_portal_access_id"), table_name="portal_bank_account_submissions")
    op.drop_index(op.f("ix_portal_bank_account_submissions_claim_id"), table_name="portal_bank_account_submissions")
    op.drop_index(op.f("ix_portal_bank_account_submissions_tenant_id"), table_name="portal_bank_account_submissions")
    op.drop_index(op.f("ix_portal_bank_account_submissions_id"), table_name="portal_bank_account_submissions")
    op.drop_table("portal_bank_account_submissions")

    op.drop_index(op.f("ix_portal_document_collection_submissions_portal_access_id"), table_name="portal_document_collection_submissions")
    op.drop_index(op.f("ix_portal_document_collection_submissions_claim_id"), table_name="portal_document_collection_submissions")
    op.drop_index(op.f("ix_portal_document_collection_submissions_tenant_id"), table_name="portal_document_collection_submissions")
    op.drop_index(op.f("ix_portal_document_collection_submissions_id"), table_name="portal_document_collection_submissions")
    op.drop_table("portal_document_collection_submissions")

    op.drop_index(op.f("ix_portal_auth_challenges_expires_at"), table_name="portal_auth_challenges")
    op.drop_index(op.f("ix_portal_auth_challenges_status"), table_name="portal_auth_challenges")
    op.drop_index(op.f("ix_portal_auth_challenges_token_hash"), table_name="portal_auth_challenges")
    op.drop_index(op.f("ix_portal_auth_challenges_portal_access_id"), table_name="portal_auth_challenges")
    op.drop_index(op.f("ix_portal_auth_challenges_claim_id"), table_name="portal_auth_challenges")
    op.drop_index(op.f("ix_portal_auth_challenges_tenant_id"), table_name="portal_auth_challenges")
    op.drop_index(op.f("ix_portal_auth_challenges_id"), table_name="portal_auth_challenges")
    op.drop_table("portal_auth_challenges")

    op.drop_index("idx_portal_claim_accesses_claim_status", table_name="portal_claim_accesses")
    op.drop_index("idx_portal_claim_accesses_claim_email", table_name="portal_claim_accesses")
    op.drop_index(op.f("ix_portal_claim_accesses_tax_code_hash"), table_name="portal_claim_accesses")
    op.drop_index(op.f("ix_portal_claim_accesses_normalized_phone_number"), table_name="portal_claim_accesses")
    op.drop_index(op.f("ix_portal_claim_accesses_normalized_full_name"), table_name="portal_claim_accesses")
    op.drop_index(op.f("ix_portal_claim_accesses_email"), table_name="portal_claim_accesses")
    op.drop_index(op.f("ix_portal_claim_accesses_claim_id"), table_name="portal_claim_accesses")
    op.drop_index(op.f("ix_portal_claim_accesses_tenant_id"), table_name="portal_claim_accesses")
    op.drop_index(op.f("ix_portal_claim_accesses_id"), table_name="portal_claim_accesses")
    op.drop_table("portal_claim_accesses")
