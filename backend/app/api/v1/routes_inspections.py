"""
CAT inspection workflow routes.
"""
from __future__ import annotations

from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_active_user
from app.models.claim import Claim
from app.models.role import Role, user_roles
from app.models.user import User
from app.schemas.inspection import (
    InspectionAvailabilityDayResponse,
    InspectionAvailabilityMonthResponse,
    InspectionAvailabilityOverrideUpsert,
    InspectionExpirationProcessResponse,
    InspectionManualAppointmentCreate,
    InspectionRoutePreferredWindowResponse,
    InspectionRouteDecisionRequest,
    InspectionRouteProposalListResponse,
    InspectionRouteProposalResponse,
    InspectionRouteRunRequest,
    InspectionRouteRunResponse,
    InspectionRouteStopResponse,
    InspectionSchedulingPreferencesResponse,
    InspectionSchedulingPreferencesUpsert,
)
from app.services.inspection_workflow_service import InspectionWorkflowService, LOCAL_TIMEZONE

router = APIRouter()


async def _fetch_user_role_names(db: AsyncSession, user_id: str) -> set[str]:
    result = await db.execute(
        select(Role.name)
        .select_from(user_roles.join(Role, user_roles.c.role_id == Role.id))
        .where(user_roles.c.user_id == user_id)
    )
    role_names: set[str] = set()
    for row in result.all():
        role_name = row[0]
        if role_name == "admin_tenant":
            role_name = "admin"
        elif role_name == "expert":
            role_name = "perito"
        role_names.add(role_name)
    return role_names


async def _is_tenant_admin(db: AsyncSession, user: User) -> bool:
    if user.is_platform_admin:
        return True
    role_names = await _fetch_user_role_names(db, user.id)
    return "admin" in role_names


async def _resolve_tenant_id(
    current_user: User,
    tenant_id: str | None,
) -> str:
    if tenant_id and tenant_id != current_user.tenant_id and not current_user.is_platform_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Tenant access denied",
        )
    return tenant_id or current_user.tenant_id


async def _get_claim_or_404(
    db: AsyncSession,
    tenant_id: str,
    claim_id: str,
) -> Claim:
    result = await db.execute(
        select(Claim).where(
            Claim.id == claim_id,
            Claim.tenant_id == tenant_id,
        )
    )
    claim = result.scalar_one_or_none()
    if claim is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Claim not found")
    return claim


def _preferences_response(claim: Claim) -> InspectionSchedulingPreferencesResponse:
    preferences = InspectionWorkflowService._preferences_metadata(claim)
    automation = InspectionWorkflowService._automation_metadata(claim)
    return InspectionSchedulingPreferencesResponse(
        claim_id=claim.id,
        state=claim.stato_corrente,
        workflow_stage=(claim.metadata_json or {}).get("inspection_workflow_stage"),
        eligible_route_generation_date=InspectionWorkflowService._parse_date(
            automation.get("eligible_route_generation_date")
        ),
        preferred_slots_count=len(preferences.get("preferred_slots") or []),
        address_confirmed=bool(
            preferences.get("address_line")
            or preferences.get("municipality")
            or preferences.get("latitude")
        ),
    )


def _route_response(event, owner: User | None) -> InspectionRouteProposalResponse:
    metadata = InspectionWorkflowService._route_metadata(event)
    plan_date = InspectionWorkflowService._parse_date(metadata.get("plan_date"))
    if plan_date is None:
        plan_date = event.starts_at.astimezone(LOCAL_TIMEZONE).date()
    stops = metadata.get("stops") if isinstance(metadata.get("stops"), list) else []
    return InspectionRouteProposalResponse(
        event_id=event.id,
        tenant_id=event.tenant_id,
        owner_user_id=event.owner_user_id,
        owner_email=(owner.email if owner else metadata.get("owner_email")),
        owner_name=(owner.full_name if owner else metadata.get("owner_name")),
        title=event.title,
        plan_date=plan_date,
        generated_at=InspectionWorkflowService._parse_datetime(metadata.get("generated_at")),
        starts_at=event.starts_at,
        ends_at=event.ends_at,
        review_deadline=InspectionWorkflowService._parse_datetime(metadata.get("review_deadline")),
        status=event.status,
        total_distance_km=float(metadata.get("total_distance_km") or 0),
        total_duration_minutes=int(metadata.get("total_duration_minutes") or 0),
        tenant_names=[
            item for item in (metadata.get("tenant_names") or []) if isinstance(item, str)
        ],
        stops=[
            InspectionRouteStopResponse(
                claim_id=raw_stop.get("claim_id"),
                claim_reference=raw_stop.get("claim_reference"),
                starts_at=InspectionWorkflowService._parse_datetime(raw_stop.get("starts_at")),
                ends_at=InspectionWorkflowService._parse_datetime(raw_stop.get("ends_at")),
                municipality=raw_stop.get("municipality"),
                province=raw_stop.get("province"),
                region=raw_stop.get("region"),
                latitude=raw_stop.get("latitude"),
                longitude=raw_stop.get("longitude"),
                masked_location=raw_stop.get("masked_location"),
                outside_zone=bool(raw_stop.get("outside_zone")),
                distance_from_previous_km=float(raw_stop.get("distance_from_previous_km") or 0),
                duration_minutes=int(raw_stop.get("duration_minutes") or 0),
                asset_count=int(raw_stop.get("asset_count") or 0),
                complexity=raw_stop.get("complexity"),
                manually_fixed=bool(raw_stop.get("manually_fixed")),
                note=raw_stop.get("note"),
                preferred_windows=[
                    InspectionRoutePreferredWindowResponse(
                        start_time=InspectionWorkflowService._parse_time(window.get("start_time")),
                        end_time=InspectionWorkflowService._parse_time(window.get("end_time")),
                        label=window.get("label"),
                    )
                    for window in raw_stop.get("preferred_windows", [])
                    if isinstance(window, dict)
                    and InspectionWorkflowService._parse_time(window.get("start_time")) is not None
                    and InspectionWorkflowService._parse_time(window.get("end_time")) is not None
                ],
            )
            for raw_stop in stops
            if isinstance(raw_stop, dict)
            and isinstance(raw_stop.get("claim_id"), str)
            and InspectionWorkflowService._parse_datetime(raw_stop.get("starts_at")) is not None
            and InspectionWorkflowService._parse_datetime(raw_stop.get("ends_at")) is not None
        ],
        rejection_reason_code=metadata.get("rejection_reason_code"),
        rejection_reason=metadata.get("rejection_reason"),
    )


@router.get("/inspections/context")
async def get_inspection_context(
    tenant_id: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    target_tenant_id = await _resolve_tenant_id(current_user, tenant_id)
    tenant, cat_settings = await InspectionWorkflowService._load_tenant_cat_settings(db, target_tenant_id)
    return {
        "tenant_id": tenant.id,
        "tenant_name": tenant.name,
        "tenant_slug": tenant.slug,
        "cat_settings": cat_settings.model_dump(),
    }


async def _route_owner_map(
    db: AsyncSession,
    owner_user_ids: list[str],
) -> dict[str, User]:
    if not owner_user_ids:
        return {}
    result = await db.execute(select(User).where(User.id.in_(owner_user_ids)))
    return {user.id: user for user in result.scalars().all()}


@router.put(
    "/inspections/claims/{claim_id}/preferences",
    response_model=InspectionSchedulingPreferencesResponse,
)
async def upsert_inspection_preferences(
    claim_id: str,
    payload: InspectionSchedulingPreferencesUpsert,
    tenant_id: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    target_tenant_id = await _resolve_tenant_id(current_user, tenant_id)
    await _get_claim_or_404(db, target_tenant_id, claim_id)
    try:
        claim = await InspectionWorkflowService.upsert_scheduling_preferences(
            db,
            target_tenant_id,
            claim_id,
            payload,
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    return _preferences_response(claim)


@router.post(
    "/inspections/claims/{claim_id}/manual-appointment",
    response_model=InspectionSchedulingPreferencesResponse,
)
async def create_manual_inspection_appointment(
    claim_id: str,
    payload: InspectionManualAppointmentCreate,
    tenant_id: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    target_tenant_id = await _resolve_tenant_id(current_user, tenant_id)
    if not await _is_tenant_admin(db, current_user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Tenant admin access required",
        )
    await _get_claim_or_404(db, target_tenant_id, claim_id)
    try:
        claim = await InspectionWorkflowService.create_manual_appointment(
            db,
            target_tenant_id,
            claim_id,
            payload,
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    return _preferences_response(claim)


@router.post(
    "/inspections/routes/run",
    response_model=InspectionRouteRunResponse,
)
async def run_inspection_route_generation(
    payload: InspectionRouteRunRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    target_tenant_id = await _resolve_tenant_id(current_user, payload.tenant_id)
    if not await _is_tenant_admin(db, current_user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Tenant admin access required",
        )
    try:
        summary = await InspectionWorkflowService.run_route_generation(
            db,
            target_tenant_id,
            plan_date=payload.plan_date,
            force=payload.force,
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    return InspectionRouteRunResponse(**summary)


@router.post(
    "/inspections/routes/process-expirations",
    response_model=InspectionExpirationProcessResponse,
)
async def process_expired_inspection_routes(
    tenant_id: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    target_tenant_id = await _resolve_tenant_id(current_user, tenant_id)
    if not await _is_tenant_admin(db, current_user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Tenant admin access required",
        )
    summary = await InspectionWorkflowService.process_expired_route_proposals(
        db,
        target_tenant_id,
    )
    await db.commit()
    return InspectionExpirationProcessResponse(
        processed_at=summary["processed_at"],
        expired_routes_count=summary["expired_routes_count"],
        replanned_routes_count=summary["replanned_routes_count"],
        manual_fallback_claims=summary["manual_fallback_claims"],
    )


@router.get(
    "/inspections/routes",
    response_model=InspectionRouteProposalListResponse,
)
async def list_inspection_routes(
    owner_user_id: str | None = Query(None),
    status_filter: str | None = Query(None),
    plan_date: str | None = Query(None),
    tenant_id: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    target_tenant_id = await _resolve_tenant_id(current_user, tenant_id)
    is_admin = await _is_tenant_admin(db, current_user)
    target_owner_user_id = owner_user_id
    if not is_admin:
        target_owner_user_id = current_user.id
    parsed_plan_date = InspectionWorkflowService._parse_date(plan_date) if plan_date else None
    items = await InspectionWorkflowService.list_route_proposals(
        db,
        target_tenant_id,
        owner_user_id=target_owner_user_id,
        status_filter=status_filter,
        plan_date=parsed_plan_date,
    )
    owners = await _route_owner_map(db, [item.owner_user_id for item in items])
    response_items = [_route_response(item, owners.get(item.owner_user_id)) for item in items]
    return InspectionRouteProposalListResponse(items=response_items, total=len(response_items))


@router.get(
    "/inspections/availability",
    response_model=InspectionAvailabilityMonthResponse,
)
async def list_inspection_availability(
    month: str = Query(..., description="Mese nel formato YYYY-MM oppure data YYYY-MM-DD"),
    owner_user_id: str | None = Query(None),
    tenant_id: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    target_tenant_id = await _resolve_tenant_id(current_user, tenant_id)
    target_owner_user_id = owner_user_id or current_user.id
    if target_owner_user_id != current_user.id and not await _is_tenant_admin(db, current_user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Tenant admin access required",
        )
    parsed_month = InspectionWorkflowService._parse_date(month)
    if parsed_month is None:
        month_parts = month.split("-")
        if len(month_parts) == 2:
            try:
                parsed_month = date(int(month_parts[0]), int(month_parts[1]), 1)
            except ValueError:
                parsed_month = None
    if parsed_month is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid month")
    try:
        return await InspectionWorkflowService.list_monthly_availability(
            db,
            target_tenant_id,
            target_owner_user_id,
            parsed_month,
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.put(
    "/inspections/availability/{target_date}",
    response_model=InspectionAvailabilityDayResponse,
)
async def upsert_inspection_availability(
    target_date: str,
    payload: InspectionAvailabilityOverrideUpsert,
    owner_user_id: str | None = Query(None),
    tenant_id: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    target_tenant_id = await _resolve_tenant_id(current_user, tenant_id)
    target_owner_user_id = owner_user_id or current_user.id
    if target_owner_user_id != current_user.id and not await _is_tenant_admin(db, current_user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Tenant admin access required",
        )
    parsed_date = InspectionWorkflowService._parse_date(target_date)
    if parsed_date is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid date")
    try:
        return await InspectionWorkflowService.upsert_daily_availability_override(
            db,
            target_tenant_id,
            target_owner_user_id,
            parsed_date,
            payload,
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


async def _get_route_for_decision(
    db: AsyncSession,
    event_id: str,
    current_user: User,
):
    event = await InspectionWorkflowService._fetch_route_event(db, event_id)
    if event is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Route proposal not found")
    if event.tenant_id != current_user.tenant_id and not current_user.is_platform_admin:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Tenant access denied")
    if current_user.is_platform_admin or await _is_tenant_admin(db, current_user):
        return event
    if event.owner_user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the assigned CAT can review this route",
        )
    return event


@router.post(
    "/inspections/routes/{event_id}/accept",
    response_model=InspectionRouteProposalResponse,
)
async def accept_inspection_route(
    event_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    await _get_route_for_decision(db, event_id, current_user)
    try:
        event = await InspectionWorkflowService.accept_route_proposal(
            db,
            event_id,
            actor_user_id=current_user.id,
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    owner_map = await _route_owner_map(db, [event.owner_user_id])
    return _route_response(event, owner_map.get(event.owner_user_id))


@router.post(
    "/inspections/routes/{event_id}/reject",
    response_model=InspectionRouteProposalResponse,
)
async def reject_inspection_route(
    event_id: str,
    payload: InspectionRouteDecisionRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    await _get_route_for_decision(db, event_id, current_user)
    try:
        event, _ = await InspectionWorkflowService.reject_route_proposal(
            db,
            event_id,
            reason_code=payload.reason_code,
            reason=payload.reason,
            actor_user_id=current_user.id,
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    owner_map = await _route_owner_map(db, [event.owner_user_id])
    return _route_response(event, owner_map.get(event.owner_user_id))
