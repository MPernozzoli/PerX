"""
User profile asset metadata model
"""
from sqlalchemy import BigInteger, Column, DateTime, ForeignKey, Index, String
from sqlalchemy.sql import func

from app.core.database import Base


class UserProfileAsset(Base):
    __tablename__ = "user_profile_assets"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    user_id = Column(String, ForeignKey("users.id"), nullable=False, index=True)
    asset_type = Column(String, nullable=False)
    file_name = Column(String, nullable=False)
    mime_type = Column(String, nullable=True)
    size_bytes = Column(BigInteger, nullable=False, default=0)
    storage_provider = Column(String, nullable=False, default="backend-local")
    storage_path = Column(String, nullable=False)
    checksum_sha256 = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        Index("uq_user_profile_assets_user_type", "user_id", "asset_type", unique=True),
    )
