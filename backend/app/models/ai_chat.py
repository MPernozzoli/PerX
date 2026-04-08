"""
AI chat models
"""
from sqlalchemy import Column, String, DateTime, ForeignKey, JSON
from sqlalchemy.sql import func

from app.core.database import Base


class AIChatSession(Base):
    __tablename__ = "ai_chat_sessions"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=True, index=True)
    user_id = Column(String, ForeignKey("users.id"), nullable=False, index=True)
    title = Column(String, nullable=False)
    model = Column(String, nullable=True)
    status = Column(String, nullable=False, default="active")
    context_json = Column(JSON, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


class AIChatMessage(Base):
    __tablename__ = "ai_chat_messages"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    session_id = Column(String, ForeignKey("ai_chat_sessions.id"), nullable=False, index=True)
    role = Column(String, nullable=False)
    body_text = Column(String, nullable=True)
    payload_json = Column(JSON, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
