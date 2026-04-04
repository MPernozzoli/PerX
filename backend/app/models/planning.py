"""
Planning and dashboard models
"""
from sqlalchemy import Column, String, DateTime, Date, Time, ForeignKey, JSON, Boolean, Integer
from sqlalchemy.sql import func

from app.core.database import Base


class UserWorkSchedule(Base):
    __tablename__ = "user_work_schedules"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    user_id = Column(String, ForeignKey("users.id"), nullable=False, index=True)
    weekday = Column(Integer, nullable=False)
    start_time = Column(Time, nullable=False)
    end_time = Column(Time, nullable=False)
    location = Column(String, nullable=True)
    slot_type = Column(String, nullable=False, default="work")
    effective_from = Column(Date, nullable=True)
    effective_to = Column(Date, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    metadata_json = Column(JSON, nullable=True)


class CalendarEvent(Base):
    __tablename__ = "calendar_events"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=True, index=True)
    task_id = Column(String, ForeignKey("case_tasks.id"), nullable=True)
    owner_user_id = Column(String, ForeignKey("users.id"), nullable=False, index=True)
    title = Column(String, nullable=False)
    description = Column(String, nullable=True)
    event_type = Column(String, nullable=False, default="appointment")
    starts_at = Column(DateTime(timezone=True), nullable=False, index=True)
    ends_at = Column(DateTime(timezone=True), nullable=False)
    all_day = Column(Boolean, nullable=False, default=False)
    location = Column(String, nullable=True)
    status = Column(String, nullable=False, default="confirmed")
    visibility = Column(String, nullable=False, default="tenant")
    source = Column(String, nullable=False, default="manual")
    metadata_json = Column(JSON, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


class DashboardWidget(Base):
    __tablename__ = "dashboard_widgets"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    user_id = Column(String, ForeignKey("users.id"), nullable=False, index=True)
    widget_key = Column(String, nullable=False)
    position = Column(Integer, nullable=False, default=0)
    enabled = Column(Boolean, nullable=False, default=True)
    settings_json = Column(JSON, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
