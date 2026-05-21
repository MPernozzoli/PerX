"""
General process job queue for work executed outside the API process.
"""
from sqlalchemy import Column, DateTime, ForeignKey, Index, Integer, JSON, String, Text
from sqlalchemy.sql import func

from app.core.database import Base


class ProcessJob(Base):
    __tablename__ = "process_jobs"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=True, index=True)
    created_by_user_id = Column(String, ForeignKey("users.id"), nullable=True, index=True)
    job_type = Column(String, nullable=False, index=True)
    status = Column(String, nullable=False, default="pending", index=True)
    priority = Column(Integer, nullable=False, default=0)
    retry_count = Column(Integer, nullable=False, default=0)
    max_retries = Column(Integer, nullable=False, default=5)
    available_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False, index=True)
    lease_owner = Column(String, nullable=True, index=True)
    lease_expires_at = Column(DateTime(timezone=True), nullable=True, index=True)
    started_at = Column(DateTime(timezone=True), nullable=True)
    completed_at = Column(DateTime(timezone=True), nullable=True)
    last_heartbeat_at = Column(DateTime(timezone=True), nullable=True)
    last_error = Column(Text, nullable=True)
    idempotency_key = Column(String, nullable=True, unique=True, index=True)
    input_json = Column(JSON, nullable=False)
    result_json = Column(JSON, nullable=True)
    tags_json = Column(JSON, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)

    __table_args__ = (
        Index("idx_process_jobs_claim_status", "claim_id", "status"),
        Index("idx_process_jobs_claimable", "status", "available_at", "priority", "created_at"),
        Index("idx_process_jobs_type_status", "job_type", "status"),
    )
