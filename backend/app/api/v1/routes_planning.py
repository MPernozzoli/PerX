"""
Planning and dashboard routes
"""
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_active_user
from app.models.planning import CalendarEvent, DashboardWidget, UserWorkSchedule
from app.models.user import User
from app.schemas.collab import (
    CalendarEventCreate,
    CalendarEventListResponse,
    CalendarEventResponse,
    DashboardWidgetListResponse,
    DashboardWidgetResponse,
    DashboardWidgetUpsert,
    UserWorkScheduleCreate,
    UserWorkScheduleListResponse,
    UserWorkScheduleResponse,
)
from app.services.claim_service import ClaimService

router = APIRouter()


@router.get("/work-schedules", response_model=UserWorkScheduleListResponse)
async def list_work_schedules(
    user_id: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    target_user_id = user_id or current_user.id
    query = select(UserWorkSchedule).where(
        UserWorkSchedule.tenant_id == current_user.tenant_id,
        UserWorkSchedule.user_id == target_user_id,
    )
    result = await db.execute(query.order_by(UserWorkSchedule.weekday.asc(), UserWorkSchedule.start_time.asc()))
    items = result.scalars().all()
    return UserWorkScheduleListResponse(items=[UserWorkScheduleResponse.model_validate(i) for i in items], total=len(items))


@router.post("/work-schedules", response_model=UserWorkScheduleResponse, status_code=status.HTTP_201_CREATED)
async def create_work_schedule(
    payload: UserWorkScheduleCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    target_user_id = payload.user_id or current_user.id
    if target_user_id != current_user.id and not current_user.is_platform_admin:
        raise HTTPException(status_code=403, detail="Cannot create schedule for another user")

    schedule = UserWorkSchedule(
        id=str(uuid.uuid4()),
        tenant_id=current_user.tenant_id,
        user_id=target_user_id,
        weekday=payload.weekday,
        start_time=payload.start_time,
        end_time=payload.end_time,
        location=payload.location,
        slot_type=payload.slot_type,
        effective_from=payload.effective_from,
        effective_to=payload.effective_to,
        metadata_json=payload.metadata_json,
    )
    db.add(schedule)
    await db.commit()
    await db.refresh(schedule)
    return UserWorkScheduleResponse.model_validate(schedule)


@router.get("/calendar-events", response_model=CalendarEventListResponse)
async def list_calendar_events(
    owner_user_id: str | None = Query(None),
    claim_id: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    query = select(CalendarEvent).where(CalendarEvent.tenant_id == current_user.tenant_id)
    query = query.where(CalendarEvent.owner_user_id == (owner_user_id or current_user.id))
    if claim_id:
        claim = await ClaimService.get_claim(db, current_user.tenant_id, claim_id)
        if not claim:
            raise HTTPException(status_code=404, detail="Claim not found")
        query = query.where(CalendarEvent.claim_id == claim.id)
    result = await db.execute(query.order_by(CalendarEvent.starts_at.asc()))
    items = result.scalars().all()
    return CalendarEventListResponse(items=[CalendarEventResponse.model_validate(i) for i in items], total=len(items))


@router.post("/calendar-events", response_model=CalendarEventResponse, status_code=status.HTTP_201_CREATED)
async def create_calendar_event(
    payload: CalendarEventCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    owner_user_id = payload.owner_user_id or current_user.id
    if owner_user_id != current_user.id and not current_user.is_platform_admin:
        raise HTTPException(status_code=403, detail="Cannot create calendar events for another user")

    claim_pk = None
    if payload.claim_id:
        claim = await ClaimService.get_claim(db, current_user.tenant_id, payload.claim_id)
        if not claim:
            raise HTTPException(status_code=404, detail="Claim not found")
        claim_pk = claim.id

    event = CalendarEvent(
        id=str(uuid.uuid4()),
        tenant_id=current_user.tenant_id,
        claim_id=claim_pk,
        task_id=payload.task_id,
        owner_user_id=owner_user_id,
        title=payload.title,
        description=payload.description,
        event_type=payload.event_type,
        starts_at=payload.starts_at,
        ends_at=payload.ends_at,
        all_day=payload.all_day,
        location=payload.location,
        status=payload.status,
        visibility=payload.visibility,
        source=payload.source,
        metadata_json=payload.metadata_json,
    )
    db.add(event)
    await db.commit()
    await db.refresh(event)
    return CalendarEventResponse.model_validate(event)


@router.get("/dashboard/widgets", response_model=DashboardWidgetListResponse)
async def list_dashboard_widgets(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    result = await db.execute(
        select(DashboardWidget)
        .where(
            DashboardWidget.tenant_id == current_user.tenant_id,
            DashboardWidget.user_id == current_user.id,
        )
        .order_by(DashboardWidget.position.asc(), DashboardWidget.created_at.asc())
    )
    items = result.scalars().all()
    return DashboardWidgetListResponse(items=[DashboardWidgetResponse.model_validate(i) for i in items], total=len(items))


@router.put("/dashboard/widgets/{widget_key}", response_model=DashboardWidgetResponse)
async def upsert_dashboard_widget(
    widget_key: str,
    payload: DashboardWidgetUpsert,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    result = await db.execute(
        select(DashboardWidget).where(
            DashboardWidget.tenant_id == current_user.tenant_id,
            DashboardWidget.user_id == current_user.id,
            DashboardWidget.widget_key == widget_key,
        )
    )
    widget = result.scalar_one_or_none()
    if not widget:
        widget = DashboardWidget(
            id=str(uuid.uuid4()),
            tenant_id=current_user.tenant_id,
            user_id=current_user.id,
            widget_key=widget_key,
        )
        db.add(widget)

    widget.position = payload.position
    widget.enabled = payload.enabled
    widget.settings_json = payload.settings_json
    await db.commit()
    await db.refresh(widget)
    return DashboardWidgetResponse.model_validate(widget)
