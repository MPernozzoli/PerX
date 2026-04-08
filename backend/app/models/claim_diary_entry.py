"""
Claim diary / timeline notes model
"""
from sqlalchemy import Column, String, DateTime, ForeignKey, JSON, Index
from sqlalchemy.sql import func

from app.core.database import Base


class ClaimDiaryEntry(Base):
    __tablename__ = "claim_diary_entries"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=False, index=True)
    entry_type = Column(String, nullable=False, default="note")
    title = Column(String, nullable=True)
    body_text = Column(String, nullable=True)
    visibility = Column(String, nullable=False, default="internal")
    happened_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    created_by_user_id = Column(String, ForeignKey("users.id"), nullable=True)
    metadata_json = Column(JSON, nullable=True)

    __table_args__ = (
        Index("ix_claim_diary_entries_happened_at", "happened_at"),
    )
