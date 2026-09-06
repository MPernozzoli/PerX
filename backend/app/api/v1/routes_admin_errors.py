"""
Platform-admin routes: error log (backend-only, see platform_error_log model).
"""
import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import require_platform_admin_or_api_key
from app.models.platform_error_log import PlatformErrorLog
from app.models.tenant import Tenant
from app.models.user import User
from app.schemas.admin import ErrorSeverity, PlatformErrorResolvePayload, PlatformErrorResponse

router = APIRouter()


def _error_response(error: PlatformErrorLog, tenant_name: str | None) -> PlatformErrorResponse:
    return PlatformErrorResponse(
        id=error.id,
        tenant_id=error.tenant_id,
        tenant_name=tenant_name,
        source=error.source,
        severity=error.severity,
        message=error.message,
        stack_trace=error.stack_trace,
        path=error.path,
        method=error.method,
        status_code=error.status_code,
        context_json=error.context_json,
        resolved=error.resolved,
        resolved_at=error.resolved_at,
        resolved_by_user_id=error.resolved_by_user_id,
        created_at=error.created_at,
    )


@router.get("/errors", response_model=list[PlatformErrorResponse])
async def list_errors(
    tenant_id: str | None = Query(None),
    severity: ErrorSeverity | None = Query(None),
    resolved: bool | None = Query(None),
    since: datetime | None = Query(None),
    limit: int = Query(100, ge=1, le=500),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_platform_admin_or_api_key),
):
    query = (
        select(PlatformErrorLog, Tenant.name)
        .outerjoin(Tenant, Tenant.id == PlatformErrorLog.tenant_id)
        .order_by(PlatformErrorLog.created_at.desc())
        .limit(limit)
    )
    if tenant_id:
        query = query.where(PlatformErrorLog.tenant_id == tenant_id)
    if severity:
        query = query.where(PlatformErrorLog.severity == severity)
    if resolved is not None:
        query = query.where(PlatformErrorLog.resolved == resolved)
    if since:
        query = query.where(PlatformErrorLog.created_at >= since)

    result = await db.execute(query)
    return [_error_response(error, tenant_name) for error, tenant_name in result.all()]


@router.get("/errors/{error_id}", response_model=PlatformErrorResponse)
async def get_error(
    error_id: str,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_platform_admin_or_api_key),
):
    result = await db.execute(
        select(PlatformErrorLog, Tenant.name)
        .outerjoin(Tenant, Tenant.id == PlatformErrorLog.tenant_id)
        .where(PlatformErrorLog.id == error_id)
    )
    row = result.first()
    if row is None:
        raise HTTPException(status_code=404, detail="Error log not found")
    error, tenant_name = row
    return _error_response(error, tenant_name)


@router.patch("/errors/{error_id}", response_model=PlatformErrorResponse)
async def resolve_error(
    error_id: str,
    payload: PlatformErrorResolvePayload,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_platform_admin_or_api_key),
):
    result = await db.execute(select(PlatformErrorLog).where(PlatformErrorLog.id == error_id))
    error = result.scalar_one_or_none()
    if error is None:
        raise HTTPException(status_code=404, detail="Error log not found")

    error.resolved = payload.resolved
    error.resolved_at = datetime.utcnow() if payload.resolved else None
    error.resolved_by_user_id = current_user.id if payload.resolved else None
    await db.commit()
    await db.refresh(error)

    tenant_name = None
    if error.tenant_id:
        tenant_result = await db.execute(select(Tenant.name).where(Tenant.id == error.tenant_id))
        tenant_name = tenant_result.scalar_one_or_none()
    return _error_response(error, tenant_name)


async def log_platform_error(
    db: AsyncSession,
    *,
    message: str,
    severity: str = "error",
    source: str = "backend",
    tenant_id: str | None = None,
    stack_trace: str | None = None,
    path: str | None = None,
    method: str | None = None,
    status_code: int | None = None,
    context_json: dict | None = None,
) -> None:
    """Best-effort write used by main.py's global exception handler.

    Caller is responsible for catching any exception this raises (e.g. a DB
    outage shouldn't turn a 500 into an unhandled crash while logging it).
    """
    db.add(
        PlatformErrorLog(
            id=str(uuid.uuid4()),
            tenant_id=tenant_id,
            source=source,
            severity=severity,
            message=message[:8000],
            stack_trace=stack_trace,
            path=path,
            method=method,
            status_code=status_code,
            context_json=context_json,
        )
    )
    await db.commit()
