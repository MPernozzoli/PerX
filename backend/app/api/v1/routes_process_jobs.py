"""
Process job queue routes for API-created jobs and local Mac mini workers.
"""
import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Header, HTTPException, Query, status
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db
from app.core.security import get_current_active_user
from app.models.claim import Claim
from app.models.claim_event import ClaimEvent
from app.models.claim_photo_analysis import ClaimPhotoAnalysis
from app.models.process_job import ProcessJob
from app.models.user import User
from app.models.videoperizia import VideoperiziaMedia
from app.schemas.process_jobs import (
    ProcessJobClaimResponse,
    ProcessJobCompleteRequest,
    ProcessJobCreateRequest,
    ProcessJobFailRequest,
    ProcessJobHeartbeatRequest,
    ProcessJobResponse,
)
from app.services.process_job_service import ProcessJobService

router = APIRouter()


def _require_worker_secret(x_perx_worker_secret: str | None = Header(default=None)) -> None:
    expected_secret = settings.LOCAL_AI_WORKER_SHARED_SECRET
    if not expected_secret or x_perx_worker_secret != expected_secret:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid worker secret")


@router.post("/jobs", response_model=ProcessJobResponse, status_code=status.HTTP_201_CREATED)
async def create_process_job(
    payload: ProcessJobCreateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    claim_id = payload.claim_id
    if claim_id:
        claim = await db.get(Claim, claim_id)
        if not claim or claim.tenant_id != current_user.tenant_id:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Claim not found")

    job = await ProcessJobService.enqueue(
        db,
        tenant_id=current_user.tenant_id,
        claim_id=claim_id,
        created_by_user_id=current_user.id,
        job_type=payload.job_type,
        priority=payload.priority,
        max_retries=payload.max_retries,
        available_at=payload.available_at,
        idempotency_key=payload.idempotency_key,
        input_json=payload.input_json,
        tags_json=payload.tags_json,
    )
    await db.commit()
    await db.refresh(job)
    return job


@router.get("/jobs/claim", response_model=ProcessJobClaimResponse)
async def claim_process_jobs(
    limit: int = Query(3, ge=1, le=25),
    worker_id: str = Query(..., min_length=1, max_length=120),
    lease_seconds: int = Query(300, ge=30, le=3600),
    job_type: list[str] | None = Query(None),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(_require_worker_secret),
):
    now = datetime.now(timezone.utc)
    lease_until = now + timedelta(seconds=lease_seconds)

    async with db.begin():
        query = (
            select(ProcessJob)
            .where(
                ProcessJob.status.in_(["pending", "retry"]),
                ProcessJob.available_at <= now,
                or_(
                    ProcessJob.lease_expires_at.is_(None),
                    ProcessJob.lease_expires_at <= now,
                ),
            )
            .order_by(ProcessJob.priority.desc(), ProcessJob.created_at.asc())
            .limit(limit)
            .with_for_update(skip_locked=True)
        )
        if job_type:
            query = query.where(ProcessJob.job_type.in_(job_type))

        result = await db.execute(query)
        jobs = result.scalars().all()
        for job in jobs:
            job.status = "processing"
            job.lease_owner = worker_id
            job.lease_expires_at = lease_until
            job.started_at = job.started_at or now
            job.last_heartbeat_at = now

    return ProcessJobClaimResponse(items=[ProcessJobResponse.model_validate(job) for job in jobs], total=len(jobs))


@router.post("/jobs/{job_id}/heartbeat")
async def heartbeat_process_job(
    job_id: str,
    payload: ProcessJobHeartbeatRequest,
    worker_id: str = Query(..., min_length=1, max_length=120),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(_require_worker_secret),
):
    job = await db.get(ProcessJob, job_id)
    if not job:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Job not found")
    if job.lease_owner != worker_id or job.status != "processing":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Job is not leased by this worker")

    now = datetime.now(timezone.utc)
    job.last_heartbeat_at = now
    job.lease_expires_at = now + timedelta(seconds=payload.lease_seconds)
    await db.commit()
    return {"status": "processing", "job_id": job.id, "lease_expires_at": job.lease_expires_at}


@router.post("/jobs/{job_id}/complete")
async def complete_process_job(
    job_id: str,
    payload: ProcessJobCompleteRequest,
    worker_id: str = Query(..., min_length=1, max_length=120),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(_require_worker_secret),
):
    job = await db.get(ProcessJob, job_id)
    if not job:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Job not found")
    if job.lease_owner != worker_id or job.status != "processing":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Job is not leased by this worker")

    now = datetime.now(timezone.utc)
    job.status = "completed"
    job.result_json = payload.result_json
    job.completed_at = now
    job.last_heartbeat_at = now
    job.lease_owner = None
    job.lease_expires_at = None
    job.last_error = None
    await ProcessJobService.record_completion(db, job)

    if job.job_type == "ai_asset_photo_analysis" and job.claim_id and payload.result_json:
        await _apply_photo_analysis_result(db, job, now)

    if job.job_type == "videoperizia_media_ai" and job.claim_id:
        await _apply_videoperizia_media_result(db, job, payload.result_json, status="done")

    await db.commit()
    return {"status": "completed", "job_id": job.id}


@router.post("/jobs/{job_id}/fail")
async def fail_process_job(
    job_id: str,
    payload: ProcessJobFailRequest,
    worker_id: str = Query(..., min_length=1, max_length=120),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(_require_worker_secret),
):
    job = await db.get(ProcessJob, job_id)
    if not job:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Job not found")
    if job.lease_owner != worker_id or job.status != "processing":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Job is not leased by this worker")

    now = datetime.now(timezone.utc)
    next_retry_count = job.retry_count + 1
    should_retry = payload.retry and next_retry_count < job.max_retries

    job.retry_count = next_retry_count
    job.last_error = payload.error
    job.result_json = payload.result_json
    job.last_heartbeat_at = now
    job.lease_owner = None
    job.lease_expires_at = None

    if should_retry:
        backoff_seconds = min(3600, 60 * (2 ** next_retry_count))
        job.status = "retry"
        job.available_at = now + timedelta(seconds=backoff_seconds)
    else:
        job.status = "failed"
        job.completed_at = now
        await ProcessJobService.record_failure(db, job)
        if job.job_type == "videoperizia_media_ai" and job.claim_id:
            await _apply_videoperizia_media_result(
                db, job, payload.result_json, status="failed"
            )

    await db.commit()
    return {"status": job.status, "job_id": job.id, "retry_count": job.retry_count}


# ---------------------------------------------------------------------------
# Post-completion handlers
# ---------------------------------------------------------------------------

async def _apply_photo_analysis_result(
    db: AsyncSession,
    job: ProcessJob,
    now: datetime,
) -> None:
    """
    Apply AI photo-analysis results to the claim.

    The worker sends numeric contribution values; this function owns the final
    score computation and label derivation so the logic stays server-side.

    Expected result_json keys (all optional):
      complexity_ai_contribution  float  additive score from photo analysis (0.0–0.5)
      priority_ai_contribution    float  additive priority from photo analysis (0.0–0.5)
      relazione_complessiva       str    overall analysis narrative (PerxiaAnalisi.relazioneComplessiva)
      analysis_provider           str    local_multimodal | cloud_openai | cloud_claude
      model                       str    model identifier
      analysis_confidence         float  0.0–1.0
      beni                        list   PerxiaBene-shaped objects:
        ordine, tipo_bene, foto_associate,
        tipologia, componenti, modello, anno,
        osservazioni_visive, valutazione_test, compatibilita_garanzia,
        compatibilita_danno, stima_economica, note_aggiuntive,
        certezza_tipologia, certezza_modello, certezza_anno,
        certezza_osservazioni, certezza_test, certezza_compatibilita, certezza_stima,
        componenti_dettaglio (recursive list)
    """
    import uuid as _uuid
    from app.services.claim_complexity_service import (
        compute_complexity_score,
        compute_priority_score,
    )

    result = job.result_json or {}
    claim = await db.get(Claim, job.claim_id)
    if not claim or claim.tenant_id != job.tenant_id:
        return

    # --- Parse AI contributions (numeric floats from worker) ---
    def _safe_float(val, default: float = 0.0) -> float:
        try:
            return float(val) if val is not None else default
        except (TypeError, ValueError):
            return default

    complexity_ai = _safe_float(result.get("complexity_ai_contribution"))
    priority_ai = _safe_float(result.get("priority_ai_contribution"))
    confidence_raw = result.get("analysis_confidence")
    confidence = round(_safe_float(confidence_raw), 3) if confidence_raw is not None else None

    # --- Server-side scoring (replicates AssignmentPlannerService.swift) ---
    complexity_base, _ = compute_complexity_score(claim, ai_contribution=0.0)
    complexity_total, complessita_label = compute_complexity_score(claim, ai_contribution=complexity_ai)

    priority_base, _ = compute_priority_score(claim, ai_contribution=0.0)
    priority_total, normalized_priority = compute_priority_score(claim, ai_contribution=priority_ai)

    # --- Apply to claim ---
    changed: list[str] = []
    previous_complessita = claim.complessita
    previous_priority = claim.priority

    if claim.complessita != complessita_label:
        claim.complessita = complessita_label
        changed.append("complessita")

    if claim.complexity_score != complexity_total:
        claim.complexity_score = complexity_total
        changed.append("complexity_score")

    if claim.priority != normalized_priority:
        claim.priority = normalized_priority
        changed.append("priority")

    # --- Persist analysis record ---
    beni = result.get("beni") or []
    db.add(
        ClaimPhotoAnalysis(
            id=str(_uuid.uuid4()),
            tenant_id=job.tenant_id,
            claim_id=job.claim_id,
            process_job_id=job.id,
            submission_id=(job.input_json or {}).get("submission_id"),
            status="completed",
            analysis_provider=result.get("analysis_provider"),
            model=result.get("model"),
            complexity_base_score=round(complexity_base, 4),
            complexity_ai_contribution=round(complexity_ai, 4),
            complexity_score=round(complexity_total, 4),
            complessita=complessita_label,
            priority_base_score=round(priority_base, 4),
            priority_ai_contribution=round(priority_ai, 4),
            priority_score=round(priority_total, 4),
            ai_priority=normalized_priority,
            analysis_confidence=confidence,
            relazione_complessiva=result.get("relazione_complessiva"),
            beni_json=beni,
            raw_result_json=result,
            completed_at=now,
        )
    )

    if changed:
        claim.updated_at = now

        existing_meta = dict(claim.metadata_json or {})
        existing_meta["ai_photo_analysis"] = {
            "job_id": job.id,
            "completed_at": now.isoformat(),
            "provider": result.get("analysis_provider", "unknown"),
            "model": result.get("model"),
            "complexity_score": complexity_total,
            "complessita": complessita_label,
            "priority_score": priority_total,
            "ai_priority": normalized_priority,
            "beni_count": len(beni),
        }
        claim.metadata_json = existing_meta

        db.add(
            ClaimEvent(
                id=str(_uuid.uuid4()),
                tenant_id=job.tenant_id,
                claim_id=job.claim_id,
                event_type="ai_photo_analysis_applied",
                actor_user_id=None,
                data_json={
                    "job_id": job.id,
                    "changed_fields": changed,
                    "complexity_score": complexity_total,
                    "complessita": complessita_label,
                    "priority_score": priority_total,
                    "ai_priority": normalized_priority,
                    "provider": result.get("analysis_provider"),
                },
                source="local_worker",
            )
        )

        # Hook re-routing: se la banda di complessità è cambiata o la priorità
        # si è spostata di almeno 2 punti, emetti un evento di review per il
        # planner (lato iOS / Hub) che valuta la riassegnazione del perito.
        complessita_band_changed = (
            "complessita" in changed and previous_complessita != complessita_label
        )
        priority_delta = abs((normalized_priority or 0) - (previous_priority or 0))
        priority_changed_significantly = (
            "priority" in changed and priority_delta >= 2
        )
        if complessita_band_changed or priority_changed_significantly:
            db.add(
                ClaimEvent(
                    id=str(_uuid.uuid4()),
                    tenant_id=job.tenant_id,
                    claim_id=job.claim_id,
                    event_type="claim_routing_review_requested",
                    actor_user_id=None,
                    data_json={
                        "trigger": "ai_photo_analysis",
                        "previous_complessita": previous_complessita,
                        "new_complessita": complessita_label,
                        "previous_priority": previous_priority,
                        "new_priority": normalized_priority,
                        "priority_delta": round(priority_delta, 3),
                        "complexity_score": complexity_total,
                        "reason": (
                            "complexity_band_changed"
                            if complessita_band_changed
                            else "priority_delta_threshold"
                        ),
                    },
                    source="local_worker",
                )
            )
            existing_meta = dict(claim.metadata_json or {})
            existing_meta["routing_review"] = {
                "requested_at": now.isoformat(),
                "trigger": "ai_photo_analysis",
                "previous_complessita": previous_complessita,
                "new_complessita": complessita_label,
                "previous_priority": previous_priority,
                "new_priority": normalized_priority,
                "status": "pending_review",
            }
            claim.metadata_json = existing_meta


async def _apply_videoperizia_media_result(
    db: AsyncSession,
    job: ProcessJob,
    result_json: dict | None,
    *,
    status: str,
) -> None:
    """
    Apply the AI pipeline result coming back from perxHUB to the
    `videoperizia_media` row referenced by the job. Status is either
    "done" (completion) or "failed" (after retries exhausted).

    The result_json shape is opaque server-side: perxHUB owns the schema and
    the expert app renders whatever fields are present (detected items,
    serials, confidence). We only persist + flip status.
    """
    media_id = (job.input_json or {}).get("media_id")
    if not media_id:
        return
    media = await db.get(VideoperiziaMedia, media_id)
    if media is None or media.tenant_id != job.tenant_id:
        return
    media.processing_status = status
    if result_json is not None:
        media.hub_result_json = result_json
    db.add(
        ClaimEvent(
            id=str(uuid.uuid4()),
            tenant_id=job.tenant_id,
            claim_id=job.claim_id,
            event_type=(
                "videoperizia_media_result_ready"
                if status == "done"
                else "videoperizia_media_processing_failed"
            ),
            data_json={"media_id": media_id, "job_id": job.id},
            source="local_worker",
        )
    )
