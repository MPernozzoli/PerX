"""
Videoperizia (video-inspection) session and captured-media tracking.

A `VideoperiziaSession` represents one live video-inspection between the
insured (on the portal) and the assigned expert (on the iOS app). The session
goes through: scheduled → lobby_open → live → ended (or aborted).

A `VideoperiziaMedia` row tracks a single artifact captured during the call
(frame-grab or short clip) stored on Supabase and processed downstream by
perxHUB via the ProcessJob queue.
"""
from __future__ import annotations

from sqlalchemy import Column, DateTime, Float, ForeignKey, Index, JSON, String
from sqlalchemy.sql import func

from app.core.database import Base


class VideoperiziaSession(Base):
    __tablename__ = "videoperizia_sessions"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=False, index=True)

    # Stable room identifier used by the videocall provider (LiveKit room name).
    livekit_room_name = Column(String, nullable=False, unique=True, index=True)

    # Lifecycle: scheduled → lobby_open → live → ended | aborted.
    state = Column(String, nullable=False, default="scheduled", index=True)

    lobby_joined_at = Column(DateTime(timezone=True), nullable=True)
    started_at = Column(DateTime(timezone=True), nullable=True)
    ended_at = Column(DateTime(timezone=True), nullable=True)

    # Expert that actually conducted the call. Null until /start.
    perito_user_id = Column(String, ForeignKey("users.id"), nullable=True, index=True)

    # Free-form info captured at lobby (browser, device, low-light hint, …).
    client_meta_json = Column(JSON, nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    __table_args__ = (
        Index("idx_videoperizia_sessions_claim_state", "claim_id", "state"),
    )


class VideoperiziaMedia(Base):
    __tablename__ = "videoperizia_media"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=False, index=True)
    session_id = Column(
        String,
        ForeignKey("videoperizia_sessions.id"),
        nullable=False,
        index=True,
    )

    # "frame" (still capture from remote video) | "clip" (short recording).
    kind = Column(String, nullable=False)
    # Supabase storage path: {tenant}/{claim}/videoperizia/{id}.{ext}
    storage_path = Column(String, nullable=False)
    mime_type = Column(String, nullable=True)

    captured_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    captured_by_user_id = Column(String, ForeignKey("users.id"), nullable=True, index=True)

    # pending_hub → processing → done | failed. Tracks the perxHUB AI pipeline.
    processing_status = Column(String, nullable=False, default="pending_hub", index=True)
    hub_result_json = Column(JSON, nullable=True)
    hub_job_id = Column(String, ForeignKey("process_jobs.id"), nullable=True, index=True)


class VideoperiziaLocationPing(Base):
    """
    GPS ping streamed by the insured's device during the call. We persist the
    full timeline (per user choice 2026-06) so the perito can reconstruct where
    the insured stood at each capture and the audit trail survives the session.
    """
    __tablename__ = "videoperizia_location_pings"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=False, index=True)
    session_id = Column(
        String,
        ForeignKey("videoperizia_sessions.id"),
        nullable=False,
        index=True,
    )

    recorded_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False, index=True)
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    accuracy_m = Column(Float, nullable=True)
    altitude_m = Column(Float, nullable=True)
    speed_mps = Column(Float, nullable=True)
    heading_deg = Column(Float, nullable=True)

    # "portal" (insured browser) | "app" (expert iOS) — usually portal.
    source = Column(String, nullable=False, default="portal")
