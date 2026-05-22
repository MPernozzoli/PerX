"""
User settings and shared (tenant-level) settings models
"""
from sqlalchemy import Column, String, DateTime, ForeignKey, JSON
from sqlalchemy.sql import func

from app.core.database import Base


class UserSettings(Base):
    __tablename__ = "user_settings"

    id = Column(String, primary_key=True, index=True)
    user_id = Column(String, ForeignKey("users.id"), nullable=False, unique=True, index=True)
    tenant_id = Column(String, nullable=False, index=True)
    settings_json = Column(JSON, nullable=True)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)


class SharedSettings(Base):
    __tablename__ = "shared_settings"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, unique=True, index=True)
    settings_json = Column(JSON, nullable=True)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)
