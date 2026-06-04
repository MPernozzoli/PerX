"""
Lifecycle service for VideoperiziaSession.

The state machine:
    scheduled    → lobby_open (insured joins from portal)
    lobby_open   → live (expert presses "Avvia" from the app)
    live         → ended (expert presses "Termina")
    *            → aborted (admin/system rescue path)

At /end the parent claim transitions from VIDEOPERIZIA → DA_GESTIRE_VIDEO,
mirroring how the on-site sopralluogo handoff works.
"""
from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.claim_status import ClaimStatus
from app.models.claim import Claim
from app.models.claim_event import ClaimEvent
from app.models.process_job import ProcessJob
from app.models.videoperizia import (
    VideoperiziaLocationPing,
    VideoperiziaMedia,
    VideoperiziaSession,
)
from app.services.state_service import StateService
from app.services.supabase_storage_service import SupabaseStorageService

# Minimum number of frame captures required to auto-complete the inspection.
# Below this threshold the expert is asked to confirm the outcome explicitly.
MIN_FRAMES_FOR_AUTO_COMPLETE = 3


SESSION_STATES = {"scheduled", "lobby_open", "live", "ended", "aborted"}


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _room_name(claim: Claim) -> str:
    """
    Stable, human-debuggable LiveKit room name. Claim-scoped so we can
    recover the session if both clients reload. Uniqueness is enforced
    at column level — a second open session for the same claim is rejected.
    """
    ref = claim.external_ref or claim.numero_sinistro or claim.id
    return f"vp-{ref}-{uuid.uuid4().hex[:8]}"


class VideoperiziaSessionService:
    @staticmethod
    async def _load_claim(db: AsyncSession, tenant_id: str, claim_id: str) -> Claim:
        """
        Resolve a claim by primary key OR by external_ref / numero_sinistro.
        The macOS app stores only the human-facing reference locally and uses
        that as `claim_id` in the URL; lookup by-PK fails there, so we fall
        back to the alternate keys (tenant-scoped to avoid cross-tenant leaks).
        """
        claim = await db.get(Claim, claim_id)
        if claim is not None and claim.tenant_id == tenant_id:
            return claim
        result = await db.execute(
            select(Claim).where(
                Claim.tenant_id == tenant_id,
                (Claim.external_ref == claim_id) | (Claim.numero_sinistro == claim_id),
            ).limit(1)
        )
        claim = result.scalar_one_or_none()
        if claim is None:
            raise ValueError("Claim not found")
        return claim

    @staticmethod
    async def _active_for_claim(
        db: AsyncSession, tenant_id: str, claim_id: str
    ) -> Optional[VideoperiziaSession]:
        # Resolve claim first (handles reference-based ids from the macOS app).
        try:
            claim = await VideoperiziaSessionService._load_claim(db, tenant_id, claim_id)
        except ValueError:
            return None
        result = await db.execute(
            select(VideoperiziaSession)
            .where(
                VideoperiziaSession.tenant_id == tenant_id,
                VideoperiziaSession.claim_id == claim.id,
                VideoperiziaSession.state.in_(("scheduled", "lobby_open", "live")),
            )
            .order_by(VideoperiziaSession.created_at.desc())
            .limit(1)
        )
        return result.scalar_one_or_none()

    @staticmethod
    async def create_or_get(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
    ) -> VideoperiziaSession:
        """
        Idempotent create: if there's already an open session (scheduled/lobby/live)
        for the claim, return it. Otherwise create a fresh one.
        """
        claim = await VideoperiziaSessionService._load_claim(db, tenant_id, claim_id)
        if claim.stato_corrente != ClaimStatus.VIDEOPERIZIA.value:
            raise ValueError("Claim is not in videoperizia state")

        existing = await VideoperiziaSessionService._active_for_claim(db, tenant_id, claim_id)
        if existing is not None:
            return existing

        session = VideoperiziaSession(
            id=str(uuid.uuid4()),
            tenant_id=tenant_id,
            claim_id=claim.id,
            livekit_room_name=_room_name(claim),
            state="scheduled",
        )
        db.add(session)
        db.add(
            ClaimEvent(
                id=str(uuid.uuid4()),
                tenant_id=tenant_id,
                claim_id=claim.id,
                event_type="videoperizia_session_created",
                event_time=_utcnow(),
                source="api",
                data_json={"session_id": session.id, "room": session.livekit_room_name},
            )
        )
        await db.commit()
        await db.refresh(session)
        return session

    @staticmethod
    async def mark_lobby_joined(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
        *,
        client_meta: Optional[dict] = None,
    ) -> VideoperiziaSession:
        """Insured opened the lobby from the portal."""
        claim = await VideoperiziaSessionService._load_claim(db, tenant_id, claim_id)
        session = await VideoperiziaSessionService._active_for_claim(db, tenant_id, claim.id)
        if session is None:
            session = await VideoperiziaSessionService.create_or_get(db, tenant_id, claim.id)
        if session.state in ("ended", "aborted"):
            raise ValueError("Session is closed")
        if session.lobby_joined_at is None:
            session.lobby_joined_at = _utcnow()
        if session.state == "scheduled":
            session.state = "lobby_open"
        if client_meta:
            session.client_meta_json = client_meta
        db.add(
            ClaimEvent(
                id=str(uuid.uuid4()),
                tenant_id=tenant_id,
                claim_id=claim.id,
                event_type="videoperizia_lobby_joined",
                event_time=_utcnow(),
                source="portal",
                data_json={"session_id": session.id},
            )
        )
        await db.commit()
        await db.refresh(session)
        return session

    @staticmethod
    async def start(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
        session_id: str,
        *,
        perito_user_id: str,
    ) -> VideoperiziaSession:
        """Expert presses 'Avvia' from the iOS app."""
        claim = await VideoperiziaSessionService._load_claim(db, tenant_id, claim_id)
        session = await db.get(VideoperiziaSession, session_id)
        if session is None or session.tenant_id != tenant_id or session.claim_id != claim.id:
            raise ValueError("Session not found")
        if session.state == "live":
            return session
        if session.state not in ("scheduled", "lobby_open"):
            raise ValueError(f"Cannot start a session in state {session.state}")
        session.state = "live"
        session.started_at = _utcnow()
        session.perito_user_id = perito_user_id
        db.add(
            ClaimEvent(
                id=str(uuid.uuid4()),
                tenant_id=tenant_id,
                claim_id=claim.id,
                event_type="videoperizia_session_started",
                event_time=_utcnow(),
                actor_user_id=perito_user_id,
                source="api",
                data_json={"session_id": session.id},
            )
        )
        await db.commit()
        await db.refresh(session)
        return session

    @staticmethod
    async def end(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
        session_id: str,
        *,
        ended_by_user_id: Optional[str],
        reason: Optional[str] = None,
    ) -> tuple[VideoperiziaSession, bool, int]:
        """
        Expert presses 'Termina'. Always closes the session.

        Returns ``(session, needs_outcome_confirmation, frame_count)``.

        Outcome logic:
        - frame_count >= MIN_FRAMES_FOR_AUTO_COMPLETE → claim transitions
          VIDEOPERIZIA → DA_GESTIRE_VIDEO immediately; confirmation = False.
        - frame_count < MIN_FRAMES_FOR_AUTO_COMPLETE → claim is NOT transitioned
          yet; the caller must invoke ``submit_outcome()`` after the expert
          chooses one of the three options in the UI.
        """
        claim = await VideoperiziaSessionService._load_claim(db, tenant_id, claim_id)
        session = await db.get(VideoperiziaSession, session_id)
        if session is None or session.tenant_id != tenant_id or session.claim_id != claim.id:
            raise ValueError("Session not found")

        # Count frame captures for this session.
        frame_result = await db.execute(
            select(VideoperiziaMedia).where(
                VideoperiziaMedia.tenant_id == tenant_id,
                VideoperiziaMedia.session_id == session_id,
                VideoperiziaMedia.kind == "frame",
            )
        )
        frame_count = len(frame_result.scalars().all())

        if session.state == "ended":
            needs_confirmation = frame_count < MIN_FRAMES_FOR_AUTO_COMPLETE
            return session, needs_confirmation, frame_count

        session.state = "ended"
        session.ended_at = _utcnow()
        db.add(
            ClaimEvent(
                id=str(uuid.uuid4()),
                tenant_id=tenant_id,
                claim_id=claim.id,
                event_type="videoperizia_session_ended",
                event_time=_utcnow(),
                actor_user_id=ended_by_user_id,
                source="api",
                data_json={"session_id": session.id, "reason": reason, "frame_count": frame_count},
            )
        )
        # Commit the session close before any claim transition so downstream
        # reads see a coherent snapshot.
        await db.commit()
        await db.refresh(session)

        needs_confirmation = frame_count < MIN_FRAMES_FOR_AUTO_COMPLETE
        if not needs_confirmation:
            # Sufficient evidence → auto-complete.
            await db.refresh(claim)
            if claim.stato_corrente == ClaimStatus.VIDEOPERIZIA.value:
                await StateService.transition_state(
                    db,
                    tenant_id,
                    claim.id,
                    from_state=ClaimStatus.VIDEOPERIZIA.value,
                    to_state=ClaimStatus.DA_GESTIRE_VIDEO.value,
                    user_id=ended_by_user_id,
                    reason=reason or "videoperizia_completed",
                    event_source="automation",
                )
        return session, needs_confirmation, frame_count

    @staticmethod
    async def submit_outcome(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
        session_id: str,
        *,
        outcome: str,
        user_id: Optional[str],
    ) -> VideoperiziaSession:
        """
        Expert submits a manual outcome after a low-evidence session end.

        ``outcome`` must be one of:
          - ``"confirmed"``             → claim → DA_GESTIRE_VIDEO (inspection accepted)
          - ``"reschedule_video"``      → claim stays VIDEOPERIZIA, resets substato to
                                          da_fissare so the insured gets a new scheduling
                                          notification
          - ``"escalate_sopralluogo"`` → claim → SOPRALLUOGO da_fissare (CAT physical
                                          inspection flow)
        """
        allowed_outcomes = ("confirmed", "reschedule_video", "escalate_sopralluogo")
        if outcome not in allowed_outcomes:
            raise ValueError(f"Invalid outcome '{outcome}'. Must be one of {allowed_outcomes}")

        claim = await VideoperiziaSessionService._load_claim(db, tenant_id, claim_id)
        session = await db.get(VideoperiziaSession, session_id)
        if session is None or session.tenant_id != tenant_id or session.claim_id != claim.id:
            raise ValueError("Session not found")

        await db.refresh(claim)
        current_state = claim.stato_corrente

        if outcome == "confirmed":
            if current_state == ClaimStatus.VIDEOPERIZIA.value:
                await StateService.transition_state(
                    db, tenant_id, claim.id,
                    from_state=ClaimStatus.VIDEOPERIZIA.value,
                    to_state=ClaimStatus.DA_GESTIRE_VIDEO.value,
                    user_id=user_id,
                    reason="videoperizia_outcome_confirmed",
                    event_source="api",
                )
        elif outcome == "reschedule_video":
            # Reset the VIDEOPERIZIA flow — new da_fissare substato triggers
            # an insured notification to pick a new slot.
            await StateService.transition_state(
                db, tenant_id, claim.id,
                from_state=current_state,
                to_state=ClaimStatus.VIDEOPERIZIA.value,
                user_id=user_id,
                reason="videoperizia_rescheduled",
                event_source="api",
                videoperizia_substato="da_fissare",
            )
        elif outcome == "escalate_sopralluogo":
            await StateService.transition_state(
                db, tenant_id, claim.id,
                from_state=current_state,
                to_state=ClaimStatus.SOPRALLUOGO.value,
                user_id=user_id,
                reason="videoperizia_escalated_to_sopralluogo",
                event_source="api",
                sopralluogo_substato="da_fissare",
            )

        db.add(
            ClaimEvent(
                id=str(uuid.uuid4()),
                tenant_id=tenant_id,
                claim_id=claim.id,
                event_type="videoperizia_outcome_submitted",
                event_time=_utcnow(),
                actor_user_id=user_id,
                source="api",
                data_json={"session_id": session_id, "outcome": outcome},
            )
        )
        await db.commit()
        await db.refresh(session)
        return session

    @staticmethod
    async def record_insured_leave(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
    ) -> Optional[VideoperiziaSession]:
        """
        Called when the insured navigates away from the portal page (explicit
        /leave call or LiveKit participant_left webhook). Stamps the timestamp
        so the expert app poll can surface the "assicurato ha lasciato" badge.

        Does nothing if the session is already ended / no active session.
        """
        session = await VideoperiziaSessionService._active_for_claim(db, tenant_id, claim_id)
        if session is None or session.state in ("ended", "aborted"):
            return session
        if session.insured_disconnected_at is None:
            session.insured_disconnected_at = _utcnow()
            db.add(
                ClaimEvent(
                    id=str(uuid.uuid4()),
                    tenant_id=tenant_id,
                    claim_id=session.claim_id,
                    event_type="videoperizia_insured_left",
                    event_time=_utcnow(),
                    source="portal",
                    data_json={"session_id": session.id},
                )
            )
            await db.commit()
            await db.refresh(session)
        return session

    @staticmethod
    async def get(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
        session_id: str,
    ) -> VideoperiziaSession:
        claim = await VideoperiziaSessionService._load_claim(db, tenant_id, claim_id)
        session = await db.get(VideoperiziaSession, session_id)
        if session is None or session.tenant_id != tenant_id or session.claim_id != claim.id:
            raise ValueError("Session not found")
        return session

    # ------------------------------------------------------------------
    # Media: frame-grab + clip
    # ------------------------------------------------------------------

    @staticmethod
    async def record_media(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
        session_id: str,
        *,
        kind: str,
        content: bytes,
        mime_type: Optional[str],
        original_filename: Optional[str],
        captured_by_user_id: Optional[str],
    ) -> VideoperiziaMedia:
        """
        Upload a captured artifact to Supabase, persist a VideoperiziaMedia row,
        and enqueue a ProcessJob so perxHUB runs the AI pipeline (object
        detection, OCR, etc.) before syncing the result back to the expert app.
        """
        if kind not in ("frame", "clip"):
            raise ValueError("Invalid media kind")
        session = await VideoperiziaSessionService.get(db, tenant_id, claim_id, session_id)
        claim = await VideoperiziaSessionService._load_claim(db, tenant_id, claim_id)

        media_id = str(uuid.uuid4())
        ext = _guess_extension(mime_type, original_filename, kind)
        claim_ref = claim.external_ref or claim.numero_sinistro or claim.id
        object_path = f"portal/{tenant_id}/{claim_ref}/videoperizia/{media_id}{ext}"

        if SupabaseStorageService.is_configured():
            await SupabaseStorageService.upload(
                object_path=object_path,
                content=content,
                mime_type=mime_type,
            )

        media = VideoperiziaMedia(
            id=media_id,
            tenant_id=tenant_id,
            claim_id=claim.id,
            session_id=session_id,
            kind=kind,
            storage_path=object_path,
            mime_type=mime_type,
            captured_by_user_id=captured_by_user_id,
            processing_status="pending_hub",
        )
        db.add(media)

        job = ProcessJob(
            id=str(uuid.uuid4()),
            tenant_id=tenant_id,
            claim_id=claim.id,
            created_by_user_id=captured_by_user_id,
            job_type="videoperizia_media_ai",
            status="pending",
            input_json={
                "media_id": media_id,
                "session_id": session_id,
                "storage_path": object_path,
                "kind": kind,
            },
        )
        db.add(job)
        media.hub_job_id = job.id

        db.add(
            ClaimEvent(
                id=str(uuid.uuid4()),
                tenant_id=tenant_id,
                claim_id=claim.id,
                event_type="videoperizia_media_captured",
                event_time=_utcnow(),
                actor_user_id=captured_by_user_id,
                source="api",
                data_json={"media_id": media_id, "kind": kind},
            )
        )
        await db.commit()
        await db.refresh(media)
        # Touch the session timestamp so polling clients see fresh activity.
        session.updated_at = _utcnow()
        await db.commit()
        return media

    @staticmethod
    async def list_media(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
        session_id: Optional[str] = None,
    ) -> list[VideoperiziaMedia]:
        claim = await VideoperiziaSessionService._load_claim(db, tenant_id, claim_id)
        query = select(VideoperiziaMedia).where(
            VideoperiziaMedia.tenant_id == tenant_id,
            VideoperiziaMedia.claim_id == claim.id,
        )
        if session_id is not None:
            query = query.where(VideoperiziaMedia.session_id == session_id)
        query = query.order_by(VideoperiziaMedia.captured_at.desc())
        result = await db.execute(query)
        return list(result.scalars().all())

    # ------------------------------------------------------------------
    # GPS pings (timeline)
    # ------------------------------------------------------------------

    @staticmethod
    async def record_location_ping(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
        *,
        latitude: float,
        longitude: float,
        accuracy_m: Optional[float] = None,
        altitude_m: Optional[float] = None,
        speed_mps: Optional[float] = None,
        heading_deg: Optional[float] = None,
        recorded_at: Optional[datetime] = None,
        source: str = "portal",
    ) -> VideoperiziaLocationPing:
        """
        Persist a GPS reading for the active session. If there's no active
        session this raises — the portal should stop publishing pings once the
        session ends.
        """
        claim = await VideoperiziaSessionService._load_claim(db, tenant_id, claim_id)
        session = await VideoperiziaSessionService._active_for_claim(db, tenant_id, claim.id)
        if session is None:
            raise ValueError("No active videoperizia session")
        ping = VideoperiziaLocationPing(
            id=str(uuid.uuid4()),
            tenant_id=tenant_id,
            claim_id=claim.id,
            session_id=session.id,
            recorded_at=recorded_at or _utcnow(),
            latitude=latitude,
            longitude=longitude,
            accuracy_m=accuracy_m,
            altitude_m=altitude_m,
            speed_mps=speed_mps,
            heading_deg=heading_deg,
            source=source,
        )
        db.add(ping)
        await db.commit()
        await db.refresh(ping)
        return ping

    @staticmethod
    async def list_location_pings(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
        session_id: Optional[str] = None,
        limit: int = 500,
    ) -> list[VideoperiziaLocationPing]:
        claim = await VideoperiziaSessionService._load_claim(db, tenant_id, claim_id)
        query = select(VideoperiziaLocationPing).where(
            VideoperiziaLocationPing.tenant_id == tenant_id,
            VideoperiziaLocationPing.claim_id == claim.id,
        )
        if session_id is not None:
            query = query.where(VideoperiziaLocationPing.session_id == session_id)
        query = query.order_by(VideoperiziaLocationPing.recorded_at.asc()).limit(limit)
        result = await db.execute(query)
        return list(result.scalars().all())


def _guess_extension(mime_type: Optional[str], filename: Optional[str], kind: str) -> str:
    if filename and "." in filename:
        return "." + filename.rsplit(".", 1)[-1].lower()
    if mime_type:
        if "jpeg" in mime_type or "jpg" in mime_type:
            return ".jpg"
        if "png" in mime_type:
            return ".png"
        if "webp" in mime_type:
            return ".webp"
        if "mp4" in mime_type:
            return ".mp4"
        if "webm" in mime_type:
            return ".webm"
        if "quicktime" in mime_type or "mov" in mime_type:
            return ".mov"
    return ".jpg" if kind == "frame" else ".mp4"
