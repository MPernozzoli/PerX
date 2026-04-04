"""
Claim folder metadata model
"""
from sqlalchemy import Column, String, DateTime, ForeignKey, JSON, Index
from sqlalchemy.sql import func

from app.core.database import Base


class ClaimFolder(Base):
    __tablename__ = "claim_folders"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=True, index=True)
    parent_id = Column(String, ForeignKey("claim_folders.id"), nullable=True, index=True)
    name = Column(String, nullable=False)
    folder_type = Column(String, nullable=False, default="generic")
    path = Column(String, nullable=False)
    source = Column(String, nullable=False, default="hub")
    external_ref = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    metadata_json = Column(JSON, nullable=True)

    __table_args__ = (
        Index("ux_claim_folders_tenant_path", "tenant_id", "path", unique=True),
    )
