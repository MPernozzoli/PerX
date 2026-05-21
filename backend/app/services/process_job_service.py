"""
Helpers for enqueueing and recording externally executed process jobs.
"""
from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.claim_event import ClaimEvent
from app.models.process_job import ProcessJob


class ProcessJobService:
    @staticmethod
    def _now() -> datetime:
        return datetime.now(timezone.utc)

    @staticmethod
    async def enqueue(
        db: AsyncSession,
        *,
        tenant_id: str,
        job_type: str,
        input_json: dict,
        claim_id: Optional[str] = None,
        created_by_user_id: Optional[str] = None,
        priority: int = 0,
        max_retries: int = 5,
        available_at: Optional[datetime] = None,
        idempotency_key: Optional[str] = None,
        tags_json: Optional[dict] = None,
    ) -> ProcessJob:
        if idempotency_key:
            existing = (
                await db.execute(select(ProcessJob).where(ProcessJob.idempotency_key == idempotency_key))
            ).scalar_one_or_none()
            if existing is not None:
                return existing

        job = ProcessJob(
            id=str(uuid.uuid4()),
            tenant_id=tenant_id,
            claim_id=claim_id,
            created_by_user_id=created_by_user_id,
            job_type=job_type,
            status="pending",
            priority=priority,
            retry_count=0,
            max_retries=max_retries,
            available_at=available_at or ProcessJobService._now(),
            idempotency_key=idempotency_key,
            input_json=input_json,
            tags_json=tags_json,
        )
        db.add(job)

        if claim_id:
            db.add(
                ClaimEvent(
                    id=str(uuid.uuid4()),
                    tenant_id=tenant_id,
                    claim_id=claim_id,
                    event_type="process_job_queued",
                    actor_user_id=created_by_user_id,
                    data_json={"jobId": job.id, "jobType": job_type},
                    source="automation",
                )
            )
        return job

    @staticmethod
    async def record_completion(db: AsyncSession, job: ProcessJob) -> None:
        if not job.claim_id:
            return
        db.add(
            ClaimEvent(
                id=str(uuid.uuid4()),
                tenant_id=job.tenant_id,
                claim_id=job.claim_id,
                event_type="process_job_completed",
                actor_user_id=None,
                data_json={"jobId": job.id, "jobType": job.job_type, "result": job.result_json or {}},
                source="local_worker",
            )
        )

    @staticmethod
    async def record_failure(db: AsyncSession, job: ProcessJob) -> None:
        if not job.claim_id:
            return
        db.add(
            ClaimEvent(
                id=str(uuid.uuid4()),
                tenant_id=job.tenant_id,
                claim_id=job.claim_id,
                event_type="process_job_failed",
                actor_user_id=None,
                data_json={"jobId": job.id, "jobType": job.job_type, "error": job.last_error},
                source="local_worker",
            )
        )
