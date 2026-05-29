"""
Runtime job that sends due scheduled emails through Resend.
"""
from __future__ import annotations

import asyncio
import json
import logging
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import select

from app.core.config import settings
from app.core.database import AsyncSessionLocal
from app.models.email import Email
from app.services.resend_email_service import ResendEmailMessage, ResendEmailService

logger = logging.getLogger(__name__)


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _json_list(value: str | None) -> list[str]:
    if not value:
        return []
    try:
        parsed = json.loads(value)
    except json.JSONDecodeError:
        return []
    if not isinstance(parsed, list):
        return []
    return [str(item) for item in parsed if item]


def _metadata(email: Email) -> dict:
    if not email.raw_headers:
        return {}
    try:
        parsed = json.loads(email.raw_headers)
    except json.JSONDecodeError:
        return {}
    return parsed if isinstance(parsed, dict) else {}


class ScheduledEmailService:
    @classmethod
    async def process_due(cls, limit: int | None = None) -> int:
        batch_size = max(1, limit or settings.RESEND_SCHEDULED_EMAIL_BATCH_SIZE)
        async with AsyncSessionLocal() as session:
            result = await session.execute(
                select(Email)
                .where(
                    Email.status == "scheduled",
                    Email.received_at <= _now(),
                )
                .order_by(Email.received_at.asc())
                .limit(batch_size)
            )
            emails = list(result.scalars().all())

            sent_count = 0
            for email in emails:
                email.status = "outbound_sending"
                await session.commit()

                metadata = _metadata(email)
                body = metadata.get("body") or email.body_html or email.body_text or ""
                is_html = bool(metadata.get("isHtml")) or bool(email.body_html)
                message = ResendEmailMessage(
                    from_address=email.from_address,
                    to=_json_list(email.to_addresses),
                    cc=_json_list(email.cc_addresses),
                    bcc=metadata.get("bcc") or [],
                    subject=email.subject or "",
                    body=body,
                    is_html=is_html,
                    in_reply_to=metadata.get("inReplyTo"),
                    references=metadata.get("references"),
                    attachments=metadata.get("attachments") or [],
                )

                result = await ResendEmailService.send(message)
                metadata["provider"] = "resend"
                metadata["resendMessageId"] = result.message_id
                metadata["error"] = result.error
                metadata["sentAt"] = _now().isoformat() if result.success else None
                email.raw_headers = json.dumps(metadata)
                email.status = "outbound_sent" if result.success else "outbound_failed"
                email.provider_id = result.message_id or "resend"
                await session.commit()

                if result.success:
                    sent_count += 1
                else:
                    logger.warning("Scheduled email %s failed through Resend: %s", email.id, result.error)

            return sent_count


class ScheduledEmailRuntime:
    _task: Optional[asyncio.Task] = None
    _stop_event: Optional[asyncio.Event] = None

    @classmethod
    async def start(cls) -> None:
        if not settings.RESEND_SCHEDULED_EMAILS_ENABLED or cls._task is not None:
            return
        cls._stop_event = asyncio.Event()
        cls._task = asyncio.create_task(cls._runner(), name="perx-scheduled-email-runtime")

    @classmethod
    async def stop(cls) -> None:
        if cls._stop_event is not None:
            cls._stop_event.set()
        if cls._task is not None:
            try:
                await cls._task
            finally:
                cls._task = None
                cls._stop_event = None

    @classmethod
    async def _runner(cls) -> None:
        assert cls._stop_event is not None
        while not cls._stop_event.is_set():
            try:
                await ScheduledEmailService.process_due()
            except asyncio.CancelledError:
                raise
            except Exception:
                logger.exception("Scheduled email runtime loop failed")

            try:
                await asyncio.wait_for(
                    cls._stop_event.wait(),
                    timeout=max(10, settings.RESEND_SCHEDULED_EMAIL_POLL_SECONDS),
                )
            except asyncio.TimeoutError:
                continue
