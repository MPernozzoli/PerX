"""
Endpoint "Impostazioni e privacy" del portale assicurato.

Tutti gli endpoint sono sotto /api/v1/portal/me/* e operano sull'identità
corrente della session (multi-claim aware via PortalService).

Audit log: ogni operazione passa per AuditService con entity_type='portal_me'.
"""
from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.portal_security import PortalSessionContext, get_current_portal_session
from app.schemas.portal_me import (
    PortalMeConsentAcceptRequest,
    PortalMeConsentResponse,
    PortalMeDeletionRequestCreate,
    PortalMeDeletionRequestResponse,
    PortalMeExportRequest,
    PortalMeNotificationPrefs,
    PortalMeNotificationPrefsResponse,
    PortalMePolicyResponse,
    PortalMeProfileResponse,
    PortalMeProfileUpdate,
    PortalMeSessionResponse,
)
from app.services.audit_service import AuditService
from app.services.portal_me_service import PortalMeService

router = APIRouter()


# ----------------------------------------------------------------------
# Audit helper (entity_type = portal_me)
# ----------------------------------------------------------------------

async def _audit(
    db: AsyncSession,
    session: PortalSessionContext,
    action: str,
    *,
    entity_id: Optional[str] = None,
    extra: Optional[dict] = None,
    request: Optional[Request] = None,
):
    await AuditService.log(
        db,
        tenant_id=session.tenant_id,
        user_id=None,  # l'utente non è un User backend; portal_access_id è in details
        action=action,
        entity_type="portal_me",
        entity_id=entity_id or session.portal_access_id,
        details={"portal_access_id": session.portal_access_id, **(extra or {})},
        request=request,
        commit=True,
    )


# ----------------------------------------------------------------------
# Profile
# ----------------------------------------------------------------------

@router.get("/profile", response_model=PortalMeProfileResponse)
async def get_profile(
    request: Request,
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    data = await PortalMeService.get_profile(db, session)
    await _audit(db, session, "portal_me_profile_view", request=request)
    return PortalMeProfileResponse(**data)


@router.patch("/profile", response_model=PortalMeProfileResponse)
async def update_profile(
    payload: PortalMeProfileUpdate,
    request: Request,
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    """Aggiorna SOLO email e telefono. Indirizzo non modificabile: vale
    sempre quello di polizza."""
    try:
        profile, changes = await PortalMeService.update_profile(
            db,
            session,
            email=payload.email,
            phone=payload.phone,
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    if changes:
        await _audit(
            db, session, "portal_me_profile_update",
            extra={"changed_fields": list(changes.keys()), "changes": changes},
            request=request,
        )
        # TODO: inviare notifica al vecchio email/phone come security alert
        # ("la tua email/telefono di portale è stato cambiato in ...")
    return PortalMeProfileResponse(**profile)


# ----------------------------------------------------------------------
# Privacy policy + consents
# ----------------------------------------------------------------------

@router.get("/privacy/policy", response_model=PortalMePolicyResponse)
async def get_current_policy(
    request: Request,
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    policy = await PortalMeService.current_policy(db, session.tenant_id)
    if policy is None:
        raise HTTPException(status_code=404, detail="privacy_policy_not_configured")
    await _audit(db, session, "portal_me_policy_view",
                 extra={"policy_id": policy.id, "version": policy.version},
                 request=request)
    return PortalMePolicyResponse(
        id=policy.id,
        version=policy.version,
        title=policy.title,
        summary=policy.summary,
        content_md=policy.content_md,
        effective_from=policy.effective_from,
    )


@router.get("/privacy/consents", response_model=list[PortalMeConsentResponse])
async def list_consents(
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    items = await PortalMeService.list_consents(db, session)
    return [PortalMeConsentResponse.model_validate(c) for c in items]


@router.post(
    "/privacy/consents",
    response_model=PortalMeConsentResponse,
    status_code=status.HTTP_201_CREATED,
)
async def accept_consent(
    payload: PortalMeConsentAcceptRequest,
    request: Request,
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    try:
        consent = await PortalMeService.accept_consent(
            db, session,
            policy_id=payload.policy_id,
            consent_type=payload.consent_type,
            request=request,
        )
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    await _audit(
        db, session, "portal_me_consent_accepted",
        entity_id=consent.id,
        extra={
            "policy_id": consent.policy_id,
            "policy_version": consent.policy_version,
            "consent_type": consent.consent_type,
        },
        request=request,
    )
    return PortalMeConsentResponse.model_validate(consent)


# ----------------------------------------------------------------------
# Notifications
# ----------------------------------------------------------------------

@router.get("/notifications", response_model=PortalMeNotificationPrefsResponse)
async def get_notifications(
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    prefs = await PortalMeService.get_notification_prefs(db, session)
    return PortalMeNotificationPrefsResponse(
        channel_push=prefs.channel_push,
        channel_email=prefs.channel_email,
        channel_whatsapp=prefs.channel_whatsapp,
        channel_sms=prefs.channel_sms,
        preferred_channel=prefs.preferred_channel,
        allow_phone_calls=prefs.allow_phone_calls,
        call_window_start=prefs.call_window_start,
        call_window_end=prefs.call_window_end,
        quiet_hours_start=prefs.quiet_hours_start,
        quiet_hours_end=prefs.quiet_hours_end,
        documents_via_email=prefs.documents_via_email,
        updated_at=prefs.updated_at,
    )


@router.put("/notifications", response_model=PortalMeNotificationPrefsResponse)
async def update_notifications(
    payload: PortalMeNotificationPrefs,
    request: Request,
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    try:
        prefs = await PortalMeService.update_notification_prefs(
            db, session, payload.model_dump(exclude_unset=True)
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    await _audit(
        db, session, "portal_me_notifications_update",
        extra={"fields": list(payload.model_dump(exclude_unset=True).keys())},
        request=request,
    )
    return PortalMeNotificationPrefsResponse(
        channel_push=prefs.channel_push,
        channel_email=prefs.channel_email,
        channel_whatsapp=prefs.channel_whatsapp,
        channel_sms=prefs.channel_sms,
        preferred_channel=prefs.preferred_channel,
        allow_phone_calls=prefs.allow_phone_calls,
        call_window_start=prefs.call_window_start,
        call_window_end=prefs.call_window_end,
        quiet_hours_start=prefs.quiet_hours_start,
        quiet_hours_end=prefs.quiet_hours_end,
        documents_via_email=prefs.documents_via_email,
        updated_at=prefs.updated_at,
    )


# ----------------------------------------------------------------------
# Deletion request (GDPR art. 17 — diritto all'oblio)
# ----------------------------------------------------------------------

@router.get("/deletion-request", response_model=Optional[PortalMeDeletionRequestResponse])
async def get_active_deletion_request(
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    req = await PortalMeService.get_active_deletion_request(db, session)
    if req is None:
        return None
    return PortalMeDeletionRequestResponse.model_validate(req)


@router.post(
    "/deletion-request",
    response_model=PortalMeDeletionRequestResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_deletion_request(
    payload: PortalMeDeletionRequestCreate,
    request: Request,
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    req = await PortalMeService.create_deletion_request(
        db, session, reason=payload.reason, request=request,
    )
    await _audit(
        db, session, "portal_me_deletion_requested",
        entity_id=req.id,
        extra={
            "eligible_from": req.eligible_from.isoformat(),
            "has_reason": bool(payload.reason),
        },
        request=request,
    )
    # TODO: alert all'admin (email/notifica interna) della nuova richiesta
    return PortalMeDeletionRequestResponse.model_validate(req)


@router.delete("/deletion-request/{request_id}", status_code=status.HTTP_204_NO_CONTENT)
async def cancel_deletion_request(
    request_id: str,
    request: Request,
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    ok = await PortalMeService.cancel_deletion_request(db, session, request_id)
    if not ok:
        raise HTTPException(status_code=404, detail="request_not_cancellable")
    await _audit(
        db, session, "portal_me_deletion_cancelled",
        entity_id=request_id, request=request,
    )


# ----------------------------------------------------------------------
# Sessions
# ----------------------------------------------------------------------

@router.get("/sessions", response_model=list[PortalMeSessionResponse])
async def list_sessions(
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    items = await PortalMeService.list_sessions(db, session)
    return [PortalMeSessionResponse.model_validate(s) for s in items]


@router.delete("/sessions/{session_id}", status_code=status.HTTP_204_NO_CONTENT)
async def revoke_session(
    session_id: str,
    request: Request,
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    ok = await PortalMeService.revoke_session(db, session, session_id)
    if not ok:
        raise HTTPException(status_code=404, detail="session_not_found")
    await _audit(
        db, session, "portal_me_session_revoked",
        entity_id=session_id, request=request,
    )


# ----------------------------------------------------------------------
# Export (GDPR art. 15/20) — TODO 2FA step-up
# ----------------------------------------------------------------------

@router.post("/export/request-otp", status_code=status.HTTP_202_ACCEPTED)
async def request_export_otp(
    request: Request,
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    """Step 1 dell'export self-service: invia OTP step-up sul canale
    verificato dell'assicurato. TODO: implementare invio OTP riusando
    `PortalAuthChallenge` o un nuovo `PortalStepUpChallenge`."""
    await _audit(db, session, "portal_me_export_otp_requested", request=request)
    # TODO: generare OTP, hashare, salvare in PortalAuthChallenge con
    # challenge_type='export_step_up', inviare via email/SMS.
    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="export_step_up_not_yet_implemented",
    )


@router.post("/export")
async def perform_export(
    payload: PortalMeExportRequest,
    request: Request,
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    """Step 2: verifica OTP e ritorna l'export JSON. TODO step-up."""
    await _audit(db, session, "portal_me_export_attempt",
                 extra={"two_factor_verified": False}, request=request)
    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="export_step_up_not_yet_implemented",
    )
