"""
Platform error log - cross-tenant error/exception tracking for platform admins.

First iteration covers only the FastAPI backend (unhandled exceptions caught in
main.py's global exception handler). `source` is deliberately a free string,
not an enum, so future ingestion points (web apps, native apps, PerXHub) can
write here without a migration.
"""
from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Index, Integer, JSON, String, Text
from sqlalchemy.sql import func
from app.core.database import Base


class PlatformErrorLog(Base):
    __tablename__ = "platform_error_log"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=True, index=True)
    source = Column(String, nullable=False, default="backend", index=True)
    severity = Column(String, nullable=False, default="error", index=True)  # error, warning, critical
    message = Column(Text, nullable=False)
    stack_trace = Column(Text, nullable=True)
    path = Column(String, nullable=True)
    method = Column(String, nullable=True)
    status_code = Column(Integer, nullable=True)
    context_json = Column(JSON, nullable=True)
    resolved = Column(Boolean, nullable=False, default=False)
    resolved_at = Column(DateTime(timezone=True), nullable=True)
    resolved_by_user_id = Column(String, ForeignKey("users.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), index=True)

    __table_args__ = (
        Index("idx_platform_error_log_tenant_created", "tenant_id", "created_at"),
        Index("idx_platform_error_log_resolved_created", "resolved", "created_at"),
    )
