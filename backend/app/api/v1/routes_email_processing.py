"""
Internal email processing queue routes for the local AI worker.
"""
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Header, HTTPException, Query, status
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db
from app.models.email import EmailProcessingJob, InboundEmailEvent
from app.schemas.comms import (
    EmailProcessingJobClaimResponse,
    EmailProcessingJobCompleteRequest,
    EmailProcessingJobFailRequest,
    EmailProcessingJobResponse,
)

router = APIRouter()


def _require_worker_secret(x_perx_worker_secret: str | None = Header(default=None)) -> None:
    expected_secret = settings.LOCAL_AI_WORKER_SHARED_SECRET
    if not expected_secret or x_perx_worker_secret != expected_secret:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid worker secret")


@router.get("/jobs/claim", response_model=EmailProcessingJobClaimResponse)
async def claim_email_processing_jobs(
    limit: int = Query(5, ge=1, le=25),
    worker_id: str = Query(..., min_length=1, max_length=120),
    lease_seconds: int = Query(300, ge=30, le=3600),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(_require_worker_secret),
):
    """Atomically claim pending email jobs for the local AI worker."""
    now = datetime.now(timezone.utc)
    lease_until = now + timedelta(seconds=lease_seconds)

    async with db.begin():
        result = await db.execute(
            select(EmailProcessingJob)
            .where(
                EmailProcessingJob.status.in_(["pending", "retry"]),
                EmailProcessingJob.available_at <= now,
                or_(
                    EmailProcessingJob.lease_expires_at.is_(None),
                    EmailProcessingJob.lease_expires_at <= now,
                ),
            )
            .order_by(EmailProcessingJob.priority.desc(), EmailProcessingJob.created_at.asc())
            .limit(limit)
            .with_for_update(skip_locked=True)
        )
        jobs = result.scalars().all()
        for job in jobs:
            job.status = "processing"
            job.lease_owner = worker_id
            job.lease_expires_at = lease_until
            job.started_at = now

            event = await db.get(InboundEmailEvent, job.inbound_event_id)
            if event:
                event.status = "processing"

    return EmailProcessingJobClaimResponse(
        items=[EmailProcessingJobResponse.model_validate(job) for job in jobs],
        total=len(jobs),
    )


@router.post("/jobs/{job_id}/complete")
async def complete_email_processing_job(
    job_id: str,
    payload: EmailProcessingJobCompleteRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(_require_worker_secret),
):
    job = await db.get(EmailProcessingJob, job_id)
    if not job:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Job not found")

    now = datetime.now(timezone.utc)
    job.status = "completed"
    job.email_id = payload.email_id
    job.result_json = payload.result_json
    job.completed_at = now
    job.lease_owner = None
    job.lease_expires_at = None
    job.last_error = None

    event = await db.get(InboundEmailEvent, job.inbound_event_id)
    if event:
        event.status = "processed"

    await db.commit()
    return {"status": "completed", "job_id": job.id}


@router.post("/jobs/{job_id}/fail")
async def fail_email_processing_job(
    job_id: str,
    payload: EmailProcessingJobFailRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(_require_worker_secret),
):
    job = await db.get(EmailProcessingJob, job_id)
    if not job:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Job not found")

    now = datetime.now(timezone.utc)
    next_retry_count = job.retry_count + 1
    should_retry = payload.retry and next_retry_count < job.max_retries

    job.retry_count = next_retry_count
    job.last_error = payload.error
    job.result_json = payload.result_json
    job.lease_owner = None
    job.lease_expires_at = None

    event = await db.get(InboundEmailEvent, job.inbound_event_id)
    if should_retry:
        backoff_seconds = min(3600, 60 * (2 ** next_retry_count))
        job.status = "retry"
        job.available_at = now + timedelta(seconds=backoff_seconds)
        if event:
            event.status = "queued"
    else:
        job.status = "failed"
        job.completed_at = now
        if event:
            event.status = "failed"

    await db.commit()
    return {"status": job.status, "job_id": job.id, "retry_count": job.retry_count}
