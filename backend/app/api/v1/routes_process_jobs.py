"""
Process job queue routes for API-created jobs and local Mac mini workers.
"""
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Header, HTTPException, Query, status
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db
from app.core.security import get_current_active_user
from app.models.claim import Claim
from app.models.process_job import ProcessJob
from app.models.user import User
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

    await db.commit()
    return {"status": job.status, "job_id": job.id, "retry_count": job.retry_count}
