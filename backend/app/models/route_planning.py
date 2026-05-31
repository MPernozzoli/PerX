"""
Modelli a supporto del planner percorsi (cache Google Routes + storico CAT).
"""
from sqlalchemy import (
    Column,
    DateTime,
    ForeignKey,
    Integer,
    PrimaryKeyConstraint,
    SmallInteger,
    String,
)
from sqlalchemy.sql import func

from app.core.database import Base


class RouteTravelEstimate(Base):
    __tablename__ = "route_travel_estimates"

    origin_grid = Column(String(32), nullable=False)
    dest_grid = Column(String(32), nullable=False)
    dow = Column(SmallInteger, nullable=False)
    hour_bucket = Column(SmallInteger, nullable=False)
    minutes = Column(Integer, nullable=False)
    source = Column(String(32), nullable=False, default="google")
    fetched_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    __table_args__ = (
        PrimaryKeyConstraint("origin_grid", "dest_grid", "dow", "hour_bucket"),
    )


class CatInspectionDurationStat(Base):
    __tablename__ = "cat_inspection_duration_stats"

    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False)
    cat_user_id = Column(String, ForeignKey("users.id"), nullable=False)
    asset_count_bucket = Column(SmallInteger, nullable=False)
    median_minutes = Column(Integer, nullable=False)
    sample_size = Column(Integer, nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    __table_args__ = (
        PrimaryKeyConstraint("tenant_id", "cat_user_id", "asset_count_bucket"),
    )
