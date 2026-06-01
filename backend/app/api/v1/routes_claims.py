"""
Claims routes
"""
from typing import Literal, Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, status, Query, UploadFile
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_active_user
from app.models.user import User
from app.services.claim_service import ClaimService
from app.services.portal_service import PortalService
from app.services.state_service import StateService
from app.schemas.claim import (
    ClaimActorInput, ClaimCreate, ClaimUpdate, ClaimResponse, ClaimListResponse,
    ClaimStateTransitionRequest, ClaimAssignmentRequest, ClaimEventResponse
)
from app.services.actor_service import ActorService


AttoChannel = Literal["push", "email", "whatsapp"]


class AttoSendRequest(BaseModel):
    document_id: str = Field(..., description="ID del Document che contiene il PDF dell'atto")
    channels: list[AttoChannel] = Field(default_factory=lambda: ["push", "email"])
    wa_account_id: Optional[str] = None


class AttoSendResponse(BaseModel):
    status: str
    claim_id: str
    document_id: str
    channels: list[str]
    delivery: dict
    act_flow: Optional[dict] = None

router = APIRouter()


@router.post("", response_model=ClaimResponse, status_code=status.HTTP_201_CREATED)
async def create_claim(
    claim_data: ClaimCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """Create a new claim"""
    claim = await ClaimService.create_claim(
        db, current_user.tenant_id, claim_data, current_user.id
    )
    return ClaimResponse.model_validate(claim)


@router.get("", response_model=ClaimListResponse)
async def list_claims(
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
    stato: str = Query(None),
    assignee_id: str = Query(None),
    search: str = Query(None),
    tenant_id: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """List claims with filters and pagination"""
    effective_tenant_id = current_user.tenant_id
    if current_user.is_platform_admin:
        effective_tenant_id = tenant_id
    elif tenant_id and tenant_id != current_user.tenant_id:
        raise HTTPException(status_code=403, detail="Tenant access denied")

    skip = (page - 1) * page_size
    claims, total = await ClaimService.list_claims(
        db, effective_tenant_id, skip, page_size, stato, assignee_id, search
    )
    return ClaimListResponse(
        items=[ClaimResponse.model_validate(c) for c in claims],
        total=total,
        page=page,
        page_size=page_size
    )


@router.get("/{claim_id}", response_model=ClaimResponse)
async def get_claim(
    claim_id: str,
    tenant_id: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """Get a claim by ID"""
    effective_tenant_id = current_user.tenant_id
    if current_user.is_platform_admin:
        effective_tenant_id = tenant_id
    elif tenant_id and tenant_id != current_user.tenant_id:
        raise HTTPException(status_code=403, detail="Tenant access denied")

    claim = await ClaimService.get_claim(db, effective_tenant_id, claim_id)
    if not claim:
        raise HTTPException(status_code=404, detail="Claim not found")
    return ClaimResponse.model_validate(claim)


@router.put("/{claim_id}", response_model=ClaimResponse)
async def update_claim(
    claim_id: str,
    claim_data: ClaimUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """Update a claim"""
    claim = await ClaimService.update_claim(
        db, current_user.tenant_id, claim_id, claim_data, current_user.id
    )
    if not claim:
        raise HTTPException(status_code=404, detail="Claim not found")
    response = ClaimResponse.model_validate(claim)
    try:
        from app.api.v1.routes_realtime import sse_manager
        await sse_manager.broadcast(
            current_user.tenant_id,
            "claim_updated",
            {"claim_id": claim.id, "updated_by": current_user.id},
        )
    except Exception:
        pass
    return response


class ClaimActorsPatchRequest(BaseModel):
    """Aggiornamento mirato dei soli riferimenti ad anagrafica del sinistro.
    Non richiede `version` perché non tocca i campi business; serve a
    collegare/scollegare attori e agenzia/compagnia in modo atomico."""
    contraente: Optional[ClaimActorInput] = None
    assicurato: Optional[ClaimActorInput] = None
    danneggiato: Optional[ClaimActorInput] = None
    agency_id: Optional[str] = None
    compagnia_id: Optional[str] = None


@router.patch("/{claim_id}/actors", response_model=ClaimResponse)
async def patch_claim_actors(
    claim_id: str,
    payload: ClaimActorsPatchRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    """Aggiorna soltanto i riferimenti agli Actor (e agency/compagnia) del
    sinistro. Ogni ruolo passato viene risolto via `_resolve_actor_input`:
    se l'input contiene `actor_id` si usa quello, se contiene `actor_data`
    viene fatto upsert per CF/PIVA. Gli indici cross-sinistro vengono
    aggiornati di conseguenza."""
    claim = await ClaimService.get_claim(db, current_user.tenant_id, claim_id)
    if claim is None:
        raise HTTPException(status_code=404, detail="Claim not found")

    agency_changed = False
    compagnia_changed = False
    if payload.agency_id is not None and claim.agency_id != payload.agency_id:
        claim.agency_id = payload.agency_id or None
        agency_changed = True
    if payload.compagnia_id is not None and claim.compagnia_id != payload.compagnia_id:
        claim.compagnia_id = payload.compagnia_id or None
        compagnia_changed = True

    for role, role_payload in (
        ("contraente", payload.contraente),
        ("assicurato", payload.assicurato),
        ("danneggiato", payload.danneggiato),
    ):
        if role_payload is None:
            continue
        aid, addr_snap, iban_snap = await ClaimService._resolve_actor_input(
            db, current_user.tenant_id, role_payload
        )
        setattr(claim, f"{role}_id", aid)
        setattr(
            claim,
            f"{role}_address_snapshot",
            addr_snap.model_dump() if addr_snap else None,
        )
        if role == "danneggiato" and iban_snap is not None:
            claim.iban_snapshot = iban_snap.model_dump()

    if agency_changed or compagnia_changed:
        actor_ids = {a for a in (claim.contraente_id, claim.assicurato_id, claim.danneggiato_id) if a}
        for aid in actor_ids:
            if claim.agency_id:
                await ActorService.touch_agency_link(
                    db, current_user.tenant_id, aid, claim.agency_id, claim.id
                )
            if claim.compagnia_id:
                await ActorService.touch_company_link(
                    db, current_user.tenant_id, aid, claim.compagnia_id, claim.id
                )

    claim.version += 1
    await db.commit()
    await db.refresh(claim)

    try:
        from app.api.v1.routes_realtime import sse_manager
        await sse_manager.broadcast(
            current_user.tenant_id,
            "claim_updated",
            {"claim_id": claim.id, "updated_by": current_user.id, "kind": "actors"},
        )
    except Exception:
        pass

    return ClaimResponse.model_validate(claim)


@router.delete("/{claim_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_claim(
    claim_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """Delete a claim within the current tenant."""
    deleted = await ClaimService.delete_claim(db, current_user.tenant_id, claim_id, current_user.id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Claim not found")
    try:
        from app.api.v1.routes_realtime import sse_manager
        await sse_manager.broadcast(
            current_user.tenant_id,
            "claim_deleted",
            {"claim_id": claim_id, "deleted_by": current_user.id},
        )
    except Exception:
        pass


@router.post("/{claim_id}/perizia/generate", status_code=status.HTTP_202_ACCEPTED)
async def request_perizia_generation(
    claim_id: str,
    payload: dict,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """Richiede al server la generazione della perizia per il sinistro.

    Il client invia i dati strutturati (beni, danni, foto refs) nel payload.
    Il server enqueua un `ProcessJob` di tipo `perizia.generate`; un worker
    (Mac Mini o futuro fallback in-process) eseguirà la pipeline AI e
    caricherà il PDF risultante sul bucket Supabase.

    Idempotente per (claim, clientRequestId): replay con lo stesso
    clientRequestId restituisce il job esistente invece di duplicare.
    """
    from app.services.process_job_service import ProcessJobService
    from app.models.claim import Claim
    from sqlalchemy import select as _select

    claim = (
        await db.execute(
            _select(Claim).where(
                Claim.id == claim_id, Claim.tenant_id == current_user.tenant_id
            )
        )
    ).scalar_one_or_none()
    if claim is None:
        raise HTTPException(status_code=404, detail="Claim not found")

    client_req_id = (payload or {}).get("clientRequestId")
    idempotency_key = (
        f"perizia.generate:{current_user.tenant_id}:{claim_id}:{client_req_id}"
        if client_req_id else None
    )

    job = await ProcessJobService.enqueue(
        db,
        tenant_id=current_user.tenant_id,
        claim_id=claim_id,
        created_by_user_id=current_user.id,
        job_type="perizia.generate",
        priority=70,
        idempotency_key=idempotency_key,
        input_json={
            "claimId": claim_id,
            "claimRef": claim.external_ref,
            "data": payload or {},
        },
        tags_json={"source": "client", "kind": "perizia"},
    )
    await db.commit()
    return {"jobId": job.id, "status": job.status}


@router.post("/{claim_id}/state-transitions")
async def transition_state(
    claim_id: str,
    transition: ClaimStateTransitionRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """Transition claim to new state"""
    success = await StateService.transition_state(
        db, current_user.tenant_id, claim_id,
        transition.from_state, transition.to_state,
        current_user.id, transition.reason, transition.payload,
        sopralluogo_substato=transition.sopralluogo_substato,
    )
    if not success:
        raise HTTPException(status_code=400, detail="Invalid state transition")
    return {"status": "success"}


@router.get("/{claim_id}/events", response_model=list[ClaimEventResponse])
async def get_claim_events(
    claim_id: str,
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
    tenant_id: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """Get timeline events for a claim"""
    from sqlalchemy import select
    from app.models.claim_event import ClaimEvent
    
    effective_tenant_id = current_user.tenant_id
    if current_user.is_platform_admin:
        effective_tenant_id = tenant_id
    elif tenant_id and tenant_id != current_user.tenant_id:
        raise HTTPException(status_code=403, detail="Tenant access denied")

    skip = (page - 1) * page_size
    query = select(ClaimEvent).where(ClaimEvent.claim_id == claim_id)
    if effective_tenant_id:
        query = query.where(ClaimEvent.tenant_id == effective_tenant_id)

    result = await db.execute(
        query.order_by(ClaimEvent.event_time.desc()).offset(skip).limit(page_size)
    )
    events = result.scalars().all()
    return [ClaimEventResponse.model_validate(e) for e in events]


@router.post("/{claim_id}/atto/send", response_model=AttoSendResponse)
async def send_atto_to_insured(
    claim_id: str,
    payload: AttoSendRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    try:
        result = await PortalService.send_act_to_insured(
            db,
            tenant_id=current_user.tenant_id,
            claim_id=claim_id,
            document_id=payload.document_id,
            channels=list(payload.channels),
            wa_account_id=payload.wa_account_id,
            actor_user_id=current_user.id,
        )
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return AttoSendResponse.model_validate(result)


@router.post("/{claim_id}/atto/upload-and-send", response_model=AttoSendResponse)
async def upload_and_send_atto(
    claim_id: str,
    file: UploadFile = File(...),
    channels: str = Form("push,email"),
    wa_account_id: Optional[str] = Form(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    """
    Upload PDF dell'atto in un colpo solo + invio multicanale.
    Pensato per il client iOS che genera il PDF localmente.
    """
    import uuid as _uuid
    from pathlib import Path as _Path
    from datetime import datetime as _dt, timezone as _tz
    from app.core.config import settings
    from app.models.document import Document
    from app.services.supabase_storage_service import SupabaseStorageService

    claim = await ClaimService.get_claim(db, current_user.tenant_id, claim_id)
    if not claim:
        raise HTTPException(status_code=404, detail="Claim not found")

    content = await file.read()
    if not content:
        raise HTTPException(status_code=400, detail="File vuoto")

    document_id = str(_uuid.uuid4())
    safe_name = (file.filename or f"atto_{claim.external_ref or claim.id}.pdf").strip()
    mime_type = file.content_type or "application/pdf"

    if SupabaseStorageService.is_configured():
        claim_ref = "".join(
            c if c.isalnum() or c in {"-", "_"} else "_"
            for c in (claim.external_ref or claim.numero_sinistro or claim.id)
        ).strip("_") or claim.id
        object_path = SupabaseStorageService.build_object_path(
            current_user.tenant_id, claim_ref, document_id, safe_name
        )
        blob = await SupabaseStorageService.upload(
            object_path=object_path, content=content, mime_type=mime_type
        )
        storage_provider = "supabase"
        storage_bucket = blob.bucket
        storage_path = blob.storage_path
    else:
        # Fallback locale
        target_dir = (
            _Path(__file__).resolve().parents[3]
            / "runtime"
            / "atti_uploads"
            / current_user.tenant_id
            / claim.id
        )
        target_dir.mkdir(parents=True, exist_ok=True)
        local_path = target_dir / f"{document_id}_{safe_name}"
        local_path.write_bytes(content)
        storage_provider = "local"
        storage_bucket = None
        storage_path = str(local_path)

    document = Document(
        id=document_id,
        tenant_id=current_user.tenant_id,
        claim_id=claim.id,
        source_type="manual",
        file_name=safe_name,
        original_file_name=safe_name,
        mime_type=mime_type,
        extension=_Path(safe_name).suffix.lstrip(".") or "pdf",
        size_bytes=len(content),
        storage_provider=storage_provider,
        storage_bucket=storage_bucket,
        storage_path=storage_path,
        status="uploaded",
        category="atto",
        tags_json=["atto", "perizia"],
        uploaded_by_user_id=current_user.id,
        uploaded_at=_dt.now(_tz.utc),
        metadata_json={"uploaded_via": "atto_send_flow"},
    )
    db.add(document)
    await db.commit()
    await db.refresh(document)

    channels_list = [c.strip() for c in channels.split(",") if c.strip()]
    try:
        result = await PortalService.send_act_to_insured(
            db,
            tenant_id=current_user.tenant_id,
            claim_id=claim_id,
            document_id=document.id,
            channels=channels_list,
            wa_account_id=wa_account_id,
            actor_user_id=current_user.id,
        )
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return AttoSendResponse.model_validate(result)
