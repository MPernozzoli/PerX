"""
Case task model - sinistro-centric tasks
"""
from sqlalchemy import Column, String, DateTime, ForeignKey, Integer, JSON, Index
from sqlalchemy.sql import func
from app.core.database import Base


class CaseTask(Base):
    __tablename__ = "case_tasks"
    
    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=False, index=True)
    title = Column(String, nullable=False)
    description = Column(String, nullable=True)
    status = Column(String, nullable=False, default="open")  # open, in_progress, done, cancelled
    assignee_user_id = Column(String, ForeignKey("users.id"), nullable=True, index=True)
    created_by_user_id = Column(String, ForeignKey("users.id"), nullable=False)
    due_date = Column(DateTime(timezone=True), nullable=True, index=True)
    completed_at = Column(DateTime(timezone=True), nullable=True)
    priority = Column(Integer, default=0, nullable=False)  # 0-100
    type = Column(String, nullable=True)  # "base", "followup", "monitoring", "ai_triage", etc.
    metadata_json = Column(JSON, nullable=True)
    
    __table_args__ = (
        Index("idx_case_tasks_claim_status", "claim_id", "status"),
        Index("idx_case_tasks_assignee_due", "assignee_user_id", "due_date"),
    )

