"""
Insured portal routes.
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db
from app.core.portal_security import PortalSessionContext, get_current_portal_session
from app.core.security import get_current_active_user
from app.models.user import User
from app.schemas.portal import (
    PortalAccessInviteRequest,
    PortalAccessInviteResponse,
    PortalAuthExchangeRequest,
    PortalAuthExchangeResponse,
    PortalAuthStartRequest,
    PortalAuthStartResponse,
    PortalBankAccountSubmissionCreate,
    PortalBankAccountSubmissionResponse,
    PortalClaimSummaryResponse,
    PortalConversationMessageCreate,
    PortalConversationMessageListResponse,
    PortalConversationMessageResponse,
    PortalDocumentCollectionSubmissionCreate,
    PortalDocumentCollectionSubmissionResponse,
    PortalDocumentResponse,
    PortalSignatureConfirmRequest,
    PortalSignatureConfirmResponse,
    PortalSignatureRequestCreate,
    PortalSignatureRequestResponse,
    PortalTimelineEventResponse,
    PortalUploadIntentCreate,
    PortalUploadIntentResponse,
)
from app.services.portal_service import PortalService

router = APIRouter()


@router.post(
    "/claims/{claim_id}/access-links",
    response_model=PortalAccessInviteResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_claim_access_link(
    claim_id: str,
    payload: PortalAccessInviteRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    claim = await PortalService.get_claim_for_tenant(db, current_user.tenant_id, claim_id)
    if not claim:
        raise HTTPException(status_code=404, detail="Claim not found")

    access, challenge, raw_token = await PortalService.issue_access_link(
        db,
        current_user.tenant_id,
        claim.id,
        payload,
    )
    return PortalAccessInviteResponse(
        portal_access_id=access.id,
        challenge_id=challenge.id,
        masked_destination=PortalService.mask_email(access.email),
        magic_link_url=PortalService.build_magic_link_url(raw_token),
        expires_at=challenge.expires_at,
    )


@router.post("/auth/start", response_model=PortalAuthStartResponse)
async def start_auth(
    payload: PortalAuthStartRequest,
    db: AsyncSession = Depends(get_db),
):
    access, challenge, raw_token = await PortalService.start_public_auth(db, payload)
    if not access or not challenge:
        return PortalAuthStartResponse(status="accepted")

    preview_magic_link_url = None
    if settings.PORTAL_DEBUG_PREVIEW_LINKS and raw_token:
        preview_magic_link_url = PortalService.build_magic_link_url(raw_token)

    masked_destination = (
        PortalService.mask_email(access.email)
        if payload.channel == "email"
        else PortalService.mask_phone(access.phone_number)
    )
    return PortalAuthStartResponse(
        status="challenge_created",
        challenge_id=challenge.id,
        delivery_channel=challenge.delivery_channel,
        masked_destination=masked_destination,
        expires_at=challenge.expires_at,
        preview_magic_link_url=preview_magic_link_url,
    )


@router.post("/auth/exchange", response_model=PortalAuthExchangeResponse)
async def exchange_auth_token(
    payload: PortalAuthExchangeRequest,
    db: AsyncSession = Depends(get_db),
):
    try:
        access, session_token, expires_in = await PortalService.exchange_magic_token(db, payload.token)
    except ValueError as exc:
        raise HTTPException(status_code=401, detail=str(exc)) from exc

    return PortalAuthExchangeResponse(
        access_token=session_token,
        expires_in=expires_in,
        claim_id=access.claim_id,
        portal_access_id=access.id,
    )


@router.get("/claim", response_model=PortalClaimSummaryResponse)
async def get_current_claim_summary(
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    try:
        summary = await PortalService.build_claim_summary(db, session)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return PortalClaimSummaryResponse.model_validate(summary)


@router.get("/claim/timeline", response_model=list[PortalTimelineEventResponse])
async def get_current_claim_timeline(
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    items = await PortalService.list_timeline(db, session)
    return [PortalTimelineEventResponse.model_validate(item) for item in items]


@router.get("/claim/documents", response_model=list[PortalDocumentResponse])
async def get_current_claim_documents(
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    items = await PortalService.list_documents(db, session)
    return [PortalDocumentResponse.model_validate(item) for item in items]


@router.post("/claim/upload-intents", response_model=PortalUploadIntentResponse)
async def create_upload_intent(
    payload: PortalUploadIntentCreate,
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    intent = await PortalService.create_upload_intent(db, session, payload)
    return PortalUploadIntentResponse.model_validate(intent)


@router.post(
    "/claim/document-collection-submissions",
    response_model=PortalDocumentCollectionSubmissionResponse,
    status_code=status.HTTP_201_CREATED,
)
async def submit_document_collection(
    payload: PortalDocumentCollectionSubmissionCreate,
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    submission = await PortalService.submit_document_collection(db, session, payload)
    return PortalDocumentCollectionSubmissionResponse(
        id=submission.id,
        status=submission.status,
        submitted_at=submission.submitted_at,
    )


@router.post(
    "/claim/bank-accounts",
    response_model=PortalBankAccountSubmissionResponse,
    status_code=status.HTTP_201_CREATED,
)
async def submit_bank_account(
    payload: PortalBankAccountSubmissionCreate,
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    submission, validation = await PortalService.submit_bank_account(db, session, payload)
    return PortalBankAccountSubmissionResponse(
        id=submission.id,
        status=submission.validation_status,
        submitted_at=submission.submitted_at,
        validation=validation,
    )


@router.get("/claim/chat/messages", response_model=PortalConversationMessageListResponse)
async def list_chat_messages(
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    items = await PortalService.list_conversation_messages(db, session)
    return PortalConversationMessageListResponse(
        items=[PortalConversationMessageResponse.model_validate(item) for item in items],
        total=len(items),
    )


@router.post(
    "/claim/chat/messages",
    response_model=PortalConversationMessageResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_chat_message(
    payload: PortalConversationMessageCreate,
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    message = await PortalService.create_conversation_message(db, session, payload)
    return PortalConversationMessageResponse(
        id=message.id,
        author_type=message.author_type,
        body_text=message.body_text,
        created_at=message.created_at,
    )


@router.post(
    "/claim/signature-requests",
    response_model=PortalSignatureRequestResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_signature_request(
    payload: PortalSignatureRequestCreate,
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    try:
        signature_request, raw_token = await PortalService.create_signature_request(db, session, payload)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc

    return PortalSignatureRequestResponse(
        id=signature_request.id,
        status=signature_request.status,
        challenge_id=signature_request.challenge_id,
        expires_at=signature_request.expires_at,
        preview_token=raw_token if settings.PORTAL_DEBUG_PREVIEW_LINKS else None,
    )


@router.post(
    "/claim/signature-requests/{request_id}/confirm",
    response_model=PortalSignatureConfirmResponse,
)
async def confirm_signature_request(
    request_id: str,
    payload: PortalSignatureConfirmRequest,
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    try:
        signature_request = await PortalService.confirm_signature_request(
            db,
            session,
            request_id,
            payload.token,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return PortalSignatureConfirmResponse(
        id=signature_request.id,
        status=signature_request.status,
        signed_at=signature_request.signed_at,
    )
