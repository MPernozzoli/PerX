"""
Device tokens for APNs / VoIP push notifications.
"""
from sqlalchemy import Column, String, DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.sql import func

from app.core.database import Base


class DeviceToken(Base):
    __tablename__ = "device_tokens"
    __table_args__ = (
        UniqueConstraint("token", "token_type", name="uq_device_tokens_token_type"),
    )

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    user_id = Column(String, ForeignKey("users.id"), nullable=False, index=True)
    token = Column(String, nullable=False)
    token_type = Column(String, nullable=False)  # "apns" | "voip"
    platform = Column(String, nullable=False, default="ios")
    bundle_id = Column(String, nullable=True)
    environment = Column(String, nullable=False, default="production")  # "sandbox" | "production"
    app = Column(String, nullable=True)  # e.g. "perx_lite"
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)
    last_used_at = Column(DateTime(timezone=True), nullable=True)
