"""
Tenant model for multi-tenancy
"""
from sqlalchemy import Boolean, Column, DateTime, ForeignKey, JSON, String
from sqlalchemy.sql import func
from app.core.database import Base


class Tenant(Base):
    __tablename__ = "tenants"
    
    id = Column(String, primary_key=True, index=True)
    name = Column(String, nullable=False)
    slug = Column(String, unique=True, nullable=False, index=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    settings_json = Column(JSON, nullable=True)


class TenantPortalDomain(Base):
    __tablename__ = "tenant_portal_domains"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id", ondelete="CASCADE"), nullable=False, index=True)
    domain = Column(String, unique=True, nullable=False, index=True)
    is_primary = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
