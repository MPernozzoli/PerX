"""
WhatsApp metadata models
"""
from sqlalchemy import Column, String, DateTime, ForeignKey, JSON, Index
from sqlalchemy.sql import func

from app.core.database import Base


class WhatsAppAccount(Base):
    __tablename__ = "whatsapp_accounts"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    label = Column(String, nullable=False)
    phone_number = Column(String, nullable=True)
    provider = Column(String, nullable=False, default="hub")
    provider_account_ref = Column(String, nullable=True)
    status = Column(String, nullable=False, default="active")
    metadata_json = Column(JSON, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class WhatsAppThread(Base):
    __tablename__ = "whatsapp_threads"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=True, index=True)
    account_id = Column(String, ForeignKey("whatsapp_accounts.id"), nullable=True, index=True)
    external_thread_ref = Column(String, nullable=True)
    contact_name = Column(String, nullable=True)
    contact_phone = Column(String, nullable=True)
    status = Column(String, nullable=False, default="open")
    last_message_at = Column(DateTime(timezone=True), nullable=True)
    metadata_json = Column(JSON, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class WhatsAppMessage(Base):
    __tablename__ = "whatsapp_messages"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    thread_id = Column(String, ForeignKey("whatsapp_threads.id"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=True, index=True)
    direction = Column(String, nullable=False)
    message_type = Column(String, nullable=False, default="text")
    provider_message_id = Column(String, nullable=True)
    sender_user_id = Column(String, ForeignKey("users.id"), nullable=True)
    sender_label = Column(String, nullable=True)
    body_text = Column(String, nullable=True)
    media_document_id = Column(String, ForeignKey("documents.id"), nullable=True)
    sent_at = Column(DateTime(timezone=True), server_default=func.now())
    delivered_at = Column(DateTime(timezone=True), nullable=True)
    read_at = Column(DateTime(timezone=True), nullable=True)
    status = Column(String, nullable=False, default="sent")
    metadata_json = Column(JSON, nullable=True)

    __table_args__ = (
        Index("ix_whatsapp_messages_thread_sent_at", "thread_id", "sent_at"),
    )
