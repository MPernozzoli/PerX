"""
Push notification dispatcher — bridges domain events to APNs / VoIP push.

Looks up registered iOS device tokens for the target user(s) and fires the
correct APNs payload. Tokens that come back as invalid (HTTP 410) are
cleaned up.
"""
from __future__ import annotations

import logging
from typing import Iterable

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.communication import Call, CallParticipant, CommunicationSession
from app.models.device_token import DeviceToken
from app.services.apns_service import apns_service


logger = logging.getLogger(__name__)


async def _tokens_for_users(db: AsyncSession, user_ids: Iterable[str], token_type: str) -> list[DeviceToken]:
    ids = [u for u in user_ids if u]
    if not ids:
        return []
    result = await db.execute(
        select(DeviceToken).where(
            DeviceToken.user_id.in_(ids),
            DeviceToken.token_type == token_type,
        )
    )
    return list(result.scalars().all())


async def notify_incoming_call(db: AsyncSession, session_id: str) -> int:
    """
    Send a VoIP push to every callee participant's iOS device for the given
    communication session. Returns the number of pushes successfully sent.
    """
    result = await db.execute(
        select(CommunicationSession).where(CommunicationSession.id == session_id)
    )
    session = result.scalar_one_or_none()
    if not session:
        return 0

    result = await db.execute(
        select(Call).where(Call.session_id == session_id).limit(1)
    )
    call = result.scalar_one_or_none()

    result = await db.execute(
        select(CallParticipant).where(
            CallParticipant.session_id == session_id,
            CallParticipant.role == "callee",
            CallParticipant.user_id.is_not(None),
        )
    )
    callees = list(result.scalars().all())
    if not callees:
        return 0

    user_ids = [p.user_id for p in callees if p.user_id]
    tokens = await _tokens_for_users(db, user_ids, token_type="voip")
    if not tokens:
        return 0

    display_name = session.display_name or "Chiamata in arrivo"
    caller_handle = call.from_value if call else ""
    sent = 0
    for tok in tokens:
        payload = {
            "session_id": session_id,
            "caller_name": display_name,
            "caller_handle": caller_handle or "",
            "has_video": session.transport == "livekit",
        }
        ok = await apns_service.send(
            tok.token,
            payload,
            push_type="voip",
            priority=10,
            bundle_id=tok.bundle_id,
        )
        if ok:
            sent += 1
        else:
            logger.info("VoIP push failed for token=%s…", tok.token[:8])
    return sent


async def notify_alert(
    db: AsyncSession,
    user_ids: Iterable[str],
    *,
    title: str,
    body: str,
    data: dict | None = None,
    thread_id: str | None = None,
) -> int:
    tokens = await _tokens_for_users(db, user_ids, token_type="apns")
    sent = 0
    for tok in tokens:
        aps: dict = {"alert": {"title": title, "body": body}, "sound": "default"}
        if thread_id:
            aps["thread-id"] = thread_id
        payload: dict = {"aps": aps}
        if data:
            payload.update(data)
        ok = await apns_service.send(
            tok.token,
            payload,
            push_type="alert",
            priority=10,
            bundle_id=tok.bundle_id,
        )
        if ok:
            sent += 1
    return sent
