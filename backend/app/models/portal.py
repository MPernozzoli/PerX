"""
Portal models for insured self-service access.
"""
from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Index, Integer, JSON, String, Text
from sqlalchemy.sql import func

from app.core.database import Base


class PortalClaimAccess(Base):
    __tablename__ = "portal_claim_accesses"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=False, index=True)
    role = Column(String, nullable=False, default="insured")
    full_name = Column(String, nullable=False)
    normalized_full_name = Column(String, nullable=True, index=True)
    email = Column(String, nullable=False, index=True)
    phone_number = Column(String, nullable=True)
    normalized_phone_number = Column(String, nullable=True, index=True)
    tax_code_hash = Column(String, nullable=True, index=True)
    tax_code_last4 = Column(String, nullable=True)
    preferred_channel = Column(String, nullable=False, default="email")
    status = Column(String, nullable=False, default="active", index=True)
    is_primary = Column(Boolean, nullable=False, default=True)
    invited_at = Column(DateTime(timezone=True), nullable=True)
    last_access_requested_at = Column(DateTime(timezone=True), nullable=True)
    last_authenticated_at = Column(DateTime(timezone=True), nullable=True)
    last_delivery_status = Column(String, nullable=True)
    metadata_json = Column(JSON, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        Index("idx_portal_claim_accesses_claim_email", "claim_id", "email"),
        Index("idx_portal_claim_accesses_claim_status", "claim_id", "status"),
    )


class PortalAuthChallenge(Base):
    __tablename__ = "portal_auth_challenges"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=False, index=True)
    portal_access_id = Column(String, ForeignKey("portal_claim_accesses.id"), nullable=False, index=True)
    challenge_type = Column(String, nullable=False, default="magic_link")
    delivery_channel = Column(String, nullable=False, default="email")
    destination = Column(String, nullable=True)
    token_hash = Column(String, nullable=True, index=True)
    otp_code_hash = Column(String, nullable=True)
    status = Column(String, nullable=False, default="pending", index=True)
    requested_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    expires_at = Column(DateTime(timezone=True), nullable=False, index=True)
    consumed_at = Column(DateTime(timezone=True), nullable=True)
    metadata_json = Column(JSON, nullable=True)


class PortalDocumentCollectionSubmission(Base):
    __tablename__ = "portal_document_collection_submissions"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=False, index=True)
    portal_access_id = Column(String, ForeignKey("portal_claim_accesses.id"), nullable=False, index=True)
    status = Column(String, nullable=False, default="submitted")
    payload_json = Column(JSON, nullable=True)
    metadata_json = Column(JSON, nullable=True)
    submitted_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class PortalBankAccountSubmission(Base):
    __tablename__ = "portal_bank_account_submissions"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=False, index=True)
    portal_access_id = Column(String, ForeignKey("portal_claim_accesses.id"), nullable=False, index=True)
    iban = Column(String, nullable=False)
    account_holder = Column(String, nullable=True)
    validation_status = Column(String, nullable=False, default="pending")
    bank_name = Column(String, nullable=True)
    branch_name = Column(String, nullable=True)
    is_selected = Column(Boolean, nullable=False, default=True)
    metadata_json = Column(JSON, nullable=True)
    submitted_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    confirmed_at = Column(DateTime(timezone=True), nullable=True)


class PortalSignatureRequest(Base):
    __tablename__ = "portal_signature_requests"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=False, index=True)
    portal_access_id = Column(String, ForeignKey("portal_claim_accesses.id"), nullable=False, index=True)
    document_id = Column(String, ForeignKey("documents.id"), nullable=False, index=True)
    challenge_id = Column(String, ForeignKey("portal_auth_challenges.id"), nullable=True, index=True)
    signature_method = Column(String, nullable=False, default="otp")
    status = Column(String, nullable=False, default="pending_confirmation", index=True)
    otp_attempts = Column(Integer, nullable=False, default=0)
    requested_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    expires_at = Column(DateTime(timezone=True), nullable=True)
    signed_at = Column(DateTime(timezone=True), nullable=True)
    metadata_json = Column(JSON, nullable=True)


class PortalPushSubscription(Base):
    __tablename__ = "portal_push_subscriptions"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=False, index=True)
    portal_access_id = Column(
        String, ForeignKey("portal_claim_accesses.id"), nullable=False, index=True
    )
    endpoint = Column(Text, nullable=False)
    p256dh = Column(String, nullable=False)
    auth = Column(String, nullable=False)
    user_agent = Column(String, nullable=True)
    status = Column(String, nullable=False, default="active")
    last_used_at = Column(DateTime(timezone=True), nullable=True)
    revoked_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    __table_args__ = (
        Index("idx_portal_push_subscriptions_access", "portal_access_id", "status"),
    )


class PortalConversation(Base):
    __tablename__ = "portal_conversations"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=False, index=True)
    portal_access_id = Column(String, ForeignKey("portal_claim_accesses.id"), nullable=False, index=True)
    internal_thread_id = Column(String, ForeignKey("internal_chat_threads.id"), nullable=True, index=True)
    status = Column(String, nullable=False, default="active", index=True)
    metadata_json = Column(JSON, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


class PortalConversationMessage(Base):
    __tablename__ = "portal_conversation_messages"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    conversation_id = Column(String, ForeignKey("portal_conversations.id"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=False, index=True)
    author_type = Column(String, nullable=False, default="portal")
    body_text = Column(Text, nullable=False)
    internal_chat_message_id = Column(String, ForeignKey("internal_chat_messages.id"), nullable=True, index=True)
    metadata_json = Column(JSON, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
