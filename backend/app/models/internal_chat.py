"""
Internal chat models
"""
from sqlalchemy import Column, String, DateTime, ForeignKey, JSON
from sqlalchemy.sql import func

from app.core.database import Base


class InternalChatThread(Base):
    __tablename__ = "internal_chat_threads"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=True, index=True)
    title = Column(String, nullable=False)
    thread_type = Column(String, nullable=False, default="claim")
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    created_by_user_id = Column(String, ForeignKey("users.id"), nullable=True)
    metadata_json = Column(JSON, nullable=True)


class InternalChatMember(Base):
    __tablename__ = "internal_chat_members"

    thread_id = Column(String, ForeignKey("internal_chat_threads.id"), primary_key=True)
    user_id = Column(String, ForeignKey("users.id"), primary_key=True)
    joined_at = Column(DateTime(timezone=True), server_default=func.now())


class InternalChatMessage(Base):
    __tablename__ = "internal_chat_messages"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    thread_id = Column(String, ForeignKey("internal_chat_threads.id"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=True, index=True)
    sender_user_id = Column(String, ForeignKey("users.id"), nullable=True)
    body_text = Column(String, nullable=True)
    message_type = Column(String, nullable=False, default="text")
    attachment_document_id = Column(String, ForeignKey("documents.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    edited_at = Column(DateTime(timezone=True), nullable=True)
    metadata_json = Column(JSON, nullable=True)
