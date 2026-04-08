"""
Insured portal routes.
"""
from pathlib import Path

from fastapi import APIRouter, Depends, File, Header, HTTPException, Query, UploadFile, status
from fastapi.responses import FileResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db
from app.core.portal_security import PortalSessionContext, get_current_portal_session
from app.core.security import get_current_active_user
from app.models.user import User
from app.schemas.portal import (
    PortalAccessInviteRequest,
    PortalAccessInviteResponse,
    PortalAccessibleClaimResponse,
    PortalActFlowResponse,
    PortalActFlowUpdateRequest,
    PortalAdditionalDocumentRequestsUpdate,
    PortalAdditionalDocumentSubmissionCreate,
    PortalAdditionalDocumentSubmissionResponse,
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
    PortalDocumentCollectionDraftResponse,
    PortalDocumentCollectionDraftUpdateRequest,
    PortalDocumentCollectionSubmissionCreate,
    PortalDocumentCollectionSubmissionResponse,
    PortalDocumentResponse,
    PortalInspectionLocationUpdateRequest,
    PortalInspectionPreferencesUpdateRequest,
    PortalInspectionSchedulingOverviewResponse,
    PortalSignatureConfirmRequest,
    PortalSignatureConfirmResponse,
    PortalSignatureProviderWebhookRequest,
    PortalSignatureRequestCreate,
    PortalSignatureRequestResponse,
    PortalTimelineEventResponse,
    PortalUploadedDocumentResponse,
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


@router.get("/claims", response_model=list[PortalAccessibleClaimResponse])
async def list_accessible_claims(
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    items = await PortalService.list_accessible_claims(db, session)
    return [PortalAccessibleClaimResponse.model_validate(item) for item in items]


@router.get("/claim", response_model=PortalClaimSummaryResponse)
async def get_current_claim_summary(
    claim_id: str | None = Query(default=None),
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    try:
        summary = await PortalService.build_claim_summary(db, session, claim_id)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return PortalClaimSummaryResponse.model_validate(summary)


@router.get("/claim/inspection-scheduling", response_model=PortalInspectionSchedulingOverviewResponse)
async def get_current_claim_inspection_scheduling(
    claim_id: str | None = Query(default=None),
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    overview = await PortalService.get_inspection_scheduling_overview(db, session, claim_id)
    return PortalInspectionSchedulingOverviewResponse.model_validate(overview)


@router.put("/claim/inspection-scheduling/location", response_model=PortalInspectionSchedulingOverviewResponse)
async def update_claim_inspection_location(
    payload: PortalInspectionLocationUpdateRequest,
    claim_id: str | None = Query(default=None),
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    overview = await PortalService.update_inspection_location(db, session, payload, claim_id)
    return PortalInspectionSchedulingOverviewResponse.model_validate(overview)


@router.put("/claim/inspection-scheduling/preferences", response_model=PortalInspectionSchedulingOverviewResponse)
async def update_claim_inspection_preferences(
    payload: PortalInspectionPreferencesUpdateRequest,
    claim_id: str | None = Query(default=None),
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    try:
        overview = await PortalService.submit_inspection_preferences(db, session, payload, claim_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return PortalInspectionSchedulingOverviewResponse.model_validate(overview)


@router.get("/claim/timeline", response_model=list[PortalTimelineEventResponse])
async def get_current_claim_timeline(
    claim_id: str | None = Query(default=None),
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    items = await PortalService.list_timeline(db, session, claim_id)
    return [PortalTimelineEventResponse.model_validate(item) for item in items]


@router.get("/claim/documents", response_model=list[PortalDocumentResponse])
async def get_current_claim_documents(
    claim_id: str | None = Query(default=None),
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    items = await PortalService.list_documents(db, session, claim_id)
    return [PortalDocumentResponse.model_validate(item) for item in items]


@router.get("/claim/documents/{document_id}/download")
async def download_claim_document(
    document_id: str,
    claim_id: str | None = Query(default=None),
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    try:
        document = await PortalService.get_claim_document_file(db, session, document_id, claim_id)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    file_path = Path(document.storage_path)
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="Documento non disponibile per il download")
    return FileResponse(
        path=file_path,
        media_type=document.mime_type or "application/octet-stream",
        filename=document.file_name,
    )


@router.post("/claim/upload-intents", response_model=PortalUploadIntentResponse)
async def create_upload_intent(
    payload: PortalUploadIntentCreate,
    claim_id: str | None = Query(default=None),
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    intent = await PortalService.create_upload_intent(db, session, payload, claim_id)
    return PortalUploadIntentResponse.model_validate(intent)


@router.post("/claim/documents/{document_id}/upload", response_model=PortalUploadedDocumentResponse)
async def upload_document_file(
    document_id: str,
    file: UploadFile = File(...),
    claim_id: str | None = Query(default=None),
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    content = await file.read()
    try:
        uploaded = await PortalService.upload_document_file(
            db,
            session,
            document_id=document_id,
            file_name=file.filename or document_id,
            mime_type=file.content_type,
            content=content,
            claim_id=claim_id,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return PortalUploadedDocumentResponse.model_validate(uploaded)


@router.post(
    "/claim/document-collection-submissions",
    response_model=PortalDocumentCollectionSubmissionResponse,
    status_code=status.HTTP_201_CREATED,
)
async def submit_document_collection(
    payload: PortalDocumentCollectionSubmissionCreate,
    claim_id: str | None = Query(default=None),
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    try:
        submission = await PortalService.submit_document_collection(db, session, payload, claim_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return PortalDocumentCollectionSubmissionResponse(
        id=submission.id,
        status=submission.status,
        submitted_at=submission.submitted_at,
    )


@router.get("/claim/document-collection-draft", response_model=PortalDocumentCollectionDraftResponse)
async def get_document_collection_draft(
    claim_id: str | None = Query(default=None),
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    draft = await PortalService.get_document_collection_draft(db, session, claim_id)
    return PortalDocumentCollectionDraftResponse.model_validate(draft)


@router.put("/claim/document-collection-draft", response_model=PortalDocumentCollectionDraftResponse)
async def save_document_collection_draft(
    payload: PortalDocumentCollectionDraftUpdateRequest,
    claim_id: str | None = Query(default=None),
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    draft = await PortalService.save_document_collection_draft(db, session, payload.draft_json, claim_id)
    return PortalDocumentCollectionDraftResponse.model_validate(draft)


@router.post(
    "/claim/bank-accounts",
    response_model=PortalBankAccountSubmissionResponse,
    status_code=status.HTTP_201_CREATED,
)
async def submit_bank_account(
    payload: PortalBankAccountSubmissionCreate,
    claim_id: str | None = Query(default=None),
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    submission, validation = await PortalService.submit_bank_account(db, session, payload, claim_id)
    return PortalBankAccountSubmissionResponse(
        id=submission.id,
        status=submission.validation_status,
        submitted_at=submission.submitted_at,
        validation=validation,
    )


@router.post(
    "/claim/additional-document-submissions",
    response_model=PortalAdditionalDocumentSubmissionResponse,
    status_code=status.HTTP_201_CREATED,
)
async def submit_additional_documents(
    payload: PortalAdditionalDocumentSubmissionCreate,
    claim_id: str | None = Query(default=None),
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    response = await PortalService.submit_additional_documents(
        db,
        session,
        note=payload.note,
        document_ids=payload.document_ids,
        requested_items=payload.requested_items,
        claim_id=claim_id,
    )
    return PortalAdditionalDocumentSubmissionResponse.model_validate(response)


@router.get("/claim/chat/messages", response_model=PortalConversationMessageListResponse)
async def list_chat_messages(
    claim_id: str | None = Query(default=None),
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    items = await PortalService.list_conversation_messages(db, session, claim_id)
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
    claim_id: str | None = Query(default=None),
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    message = await PortalService.create_conversation_message(db, session, payload, claim_id)
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
    claim_id: str | None = Query(default=None),
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    try:
        signature_request, raw_token = await PortalService.create_signature_request(
            db, session, payload, claim_id
        )
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
    claim_id: str | None = Query(default=None),
    session: PortalSessionContext = Depends(get_current_portal_session),
    db: AsyncSession = Depends(get_db),
):
    try:
        signature_request = await PortalService.confirm_signature_request(
            db,
            session,
            request_id,
            payload.token,
            claim_id,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return PortalSignatureConfirmResponse(
        id=signature_request.id,
        status=signature_request.status,
        signed_at=signature_request.signed_at,
    )


@router.put("/claims/{claim_id}/act-flow", response_model=PortalActFlowResponse)
async def update_claim_act_flow(
    claim_id: str,
    payload: PortalActFlowUpdateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    try:
        act_flow = await PortalService.update_act_flow(
            db,
            current_user.tenant_id,
            claim_id,
            payload.model_dump(exclude_none=True),
        )
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return PortalActFlowResponse.model_validate(act_flow)


@router.put("/claims/{claim_id}/additional-document-requests")
async def update_claim_additional_document_requests(
    claim_id: str,
    payload: PortalAdditionalDocumentRequestsUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    try:
        response = await PortalService.update_additional_document_requests(
            db,
            current_user.tenant_id,
            claim_id,
            payload.items,
        )
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return response


@router.post("/webhooks/signature-provider", response_model=PortalActFlowResponse)
async def signature_provider_webhook(
    payload: PortalSignatureProviderWebhookRequest,
    db: AsyncSession = Depends(get_db),
    x_portal_webhook_secret: str | None = Header(default=None),
):
    expected_secret = settings.PORTAL_SIGNATURE_WEBHOOK_SECRET
    if expected_secret and x_portal_webhook_secret != expected_secret:
        raise HTTPException(status_code=401, detail="Invalid webhook secret")
    try:
        act_flow = await PortalService.process_signature_provider_webhook(
            db,
            payload.model_dump(exclude_none=True),
        )
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return PortalActFlowResponse.model_validate(act_flow)
