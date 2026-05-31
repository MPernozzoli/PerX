"""
Real-time SSE (Server-Sent Events) routes
Provides a persistent streaming endpoint for push notifications to connected clients.

Auth: supports both standard Authorization: Bearer header and ?token= query param,
because SSE connections (especially from native iOS clients) may pass the JWT as a
query parameter rather than an HTTP header.
"""
import asyncio
import json
import logging
from collections import defaultdict
from datetime import datetime, timezone
from typing import AsyncGenerator, Optional

from fastapi import APIRouter, Query, Request
from fastapi.responses import StreamingResponse
from jose import JWTError, jwt
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db_context
from app.models.user import User

logger = logging.getLogger(__name__)

router = APIRouter()

# All valid topic names
ALL_TOPICS = {"chat", "claims", "tasks", "folders", "presence"}

# Topic → event_type mapping for filtering
TOPIC_EVENT_TYPES: dict[str, set[str]] = {
    "chat": {"chat_message"},
    "claims": {"claim_updated"},
    "tasks": {"task_updated"},
    "folders": {"folder_ready"},
    "presence": {"presence_update"},
}


class SSEConnectionManager:
    """
    In-process singleton SSE connection manager.
    Manages per-tenant asyncio queues for connected clients.

    Usage from other route modules (import at call site to avoid circular imports):
        from app.api.v1.routes_realtime import sse_manager
        await sse_manager.broadcast(tenant_id, "claim_updated", {...})
    """

    def __init__(self) -> None:
        # tenant_id → list of asyncio.Queue instances (one per connected client)
        self._connections: dict[str, list[asyncio.Queue]] = defaultdict(list)

    async def connect(self, tenant_id: str, queue: asyncio.Queue) -> None:
        self._connections[tenant_id].append(queue)
        logger.debug(
            "SSE client connected: tenant=%s total=%d",
            tenant_id,
            len(self._connections[tenant_id]),
        )

    async def disconnect(self, tenant_id: str, queue: asyncio.Queue) -> None:
        try:
            self._connections[tenant_id].remove(queue)
        except ValueError:
            pass
        logger.debug(
            "SSE client disconnected: tenant=%s total=%d",
            tenant_id,
            len(self._connections[tenant_id]),
        )

    async def broadcast(self, tenant_id: str, event_type: str, payload: dict) -> None:
        """
        Broadcast an SSE event to all clients connected under a tenant.
        Dead queues (full) are silently removed.
        """
        msg = f"data: {json.dumps({'type': event_type, 'payload': payload})}\n\n"
        dead: list[asyncio.Queue] = []

        for q in list(self._connections.get(tenant_id, [])):
            try:
                q.put_nowait(msg)
            except asyncio.QueueFull:
                dead.append(q)

        for q in dead:
            try:
                self._connections[tenant_id].remove(q)
            except ValueError:
                pass


# Module-level singleton exported for use in other route modules
sse_manager = SSEConnectionManager()


async def _resolve_user_from_token(token: str) -> Optional[User]:
    """
    Resolve a User from a raw JWT string.
    Opens its own DB session so it can be used outside a normal request context.
    Returns None if resolution fails.
    """
    from app.core.security import is_supabase_auth_enabled

    try:
        async with get_db_context() as db:
            if is_supabase_auth_enabled():
                from app.core.security import get_supabase_user

                supabase_user = await get_supabase_user(token)
                user_email = (supabase_user.get("email") or "").lower()
                idp_subject = supabase_user.get("id")
                if not user_email:
                    return None
                result = await db.execute(
                    select(User).where(User.is_active == True).where(
                        (User.idp_subject == idp_subject) | (User.email == user_email)
                    )
                )
            else:
                jwt_payload = jwt.decode(
                    token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM]
                )
                user_id = jwt_payload.get("sub")
                if not user_id:
                    return None
                result = await db.execute(
                    select(User).where(User.id == user_id, User.is_active == True)
                )
            return result.scalar_one_or_none()
    except (JWTError, Exception):
        return None


async def _event_generator(
    tenant_id: str,
    queue: asyncio.Queue,
    allowed_event_types: Optional[set[str]],
    heartbeat_interval: int = 30,
) -> AsyncGenerator[str, None]:
    """
    Async generator that yields SSE-formatted strings.
    Sends a heartbeat every `heartbeat_interval` seconds of inactivity.
    """
    try:
        while True:
            try:
                msg: str = await asyncio.wait_for(queue.get(), timeout=heartbeat_interval)
                # Apply topic filter if requested
                if allowed_event_types is not None:
                    try:
                        parsed = json.loads(msg.removeprefix("data: ").strip())
                        if parsed.get("type") not in allowed_event_types:
                            continue
                    except Exception:
                        pass  # If we can't parse, let it through unchanged
                yield msg
            except asyncio.TimeoutError:
                heartbeat = json.dumps(
                    {
                        "type": "heartbeat",
                        "payload": {"ts": datetime.now(timezone.utc).isoformat()},
                    }
                )
                yield f"data: {heartbeat}\n\n"
    except asyncio.CancelledError:
        pass


@router.get("/stream")
async def sse_stream(
    request: Request,
    token: Optional[str] = Query(None, description="JWT token (alt to Authorization header)"),
    topics: Optional[str] = Query(
        None,
        description="Comma-separated topic filter: chat,claims,tasks,whatsapp,folders,presence",
    ),
):
    """
    SSE stream endpoint.

    Authenticate via:
    - Authorization: Bearer <token> header, OR
    - ?token=<jwt> query parameter

    Optionally filter events by topic with ?topics=chat,claims
    """
    # Resolve token: header takes priority over query param
    auth_header = request.headers.get("Authorization", "")
    resolved_token: Optional[str] = None
    if auth_header.startswith("Bearer "):
        resolved_token = auth_header.removeprefix("Bearer ").strip()
    elif token:
        resolved_token = token

    async def _stream() -> AsyncGenerator[str, None]:
        if not resolved_token:
            yield f"data: {json.dumps({'type': 'error', 'payload': {'detail': 'Unauthorized'}})}\n\n"
            return

        user = await _resolve_user_from_token(resolved_token)
        if not user:
            yield f"data: {json.dumps({'type': 'error', 'payload': {'detail': 'Unauthorized'}})}\n\n"
            return

        # Parse topic filter
        topic_set: set[str] = set()
        if topics:
            for t in topics.split(","):
                t = t.strip().lower()
                if t in ALL_TOPICS:
                    topic_set.add(t)

        allowed_event_types: Optional[set[str]] = None
        if topic_set:
            allowed_event_types = set()
            for topic in topic_set:
                allowed_event_types.update(TOPIC_EVENT_TYPES.get(topic, set()))

        queue: asyncio.Queue = asyncio.Queue(maxsize=200)
        await sse_manager.connect(user.tenant_id, queue)

        try:
            async for event in _event_generator(user.tenant_id, queue, allowed_event_types):
                # Stop if client disconnected
                if await request.is_disconnected():
                    break
                yield event
        finally:
            await sse_manager.disconnect(user.tenant_id, queue)

    return StreamingResponse(
        _stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
            "Connection": "keep-alive",
        },
    )
