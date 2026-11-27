"""
Email routes
"""
import json
import logging
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_active_user
from app.core.config import settings
from app.models.claim import Claim
from app.models.claim_event import ClaimEvent
from app.models.email import Email, EmailClaimLink
from app.models.user import User
from app.schemas.comms import (
    EmailClaimLinkRequest,
    EmailCreate,
    EmailListResponse,
    EmailResponse,
)
from app.services.claim_service import ClaimService
from app.services.email_routing_service import EmailRoutingService
from app.services.gmail_sync_service import (
    GmailSyncService,
    decode_pubsub_push,
    fetch_google_certs,
    verify_pubsub_token,
)

router = APIRouter()
logger = logging.getLogger(__name__)


@router.post("/gmail/push")
async def gmail_push(
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    """Notifica Pub/Sub di Gmail. Il token è quello della subscription, non dell'utente."""
    if not settings.GMAIL_PUBSUB_TOPIC.strip():
        raise HTTPException(status_code=404, detail="Watch Gmail non configurato")
    authorization = request.headers.get("authorization") or ""
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        raise HTTPException(status_code=401, detail="Token mancante")
    try:
        keys = await fetch_google_certs()
        verify_pubsub_token(
            token.strip(),
            keys,
            settings.GMAIL_PUSH_AUDIENCE,
            settings.GMAIL_PUSH_SERVICE_ACCOUNT.strip(),
        )
    except Exception:
        logger.exception("Token push Gmail rifiutato")
        raise HTTPException(status_code=401, detail="Token non valido") from None
    try:
        note = decode_pubsub_push(await request.json())
    except Exception:
        return {"status": "ignored"}
    if not note["email"]:
        return {"status": "ignored"}
    try:
        outcome = await GmailSyncService.accept_push(db, note)
    except Exception:
        await db.rollback()
        # A non-2xx response makes Pub/Sub redeliver immediately and can turn a
        # transient Gmail/DB failure into a retry storm. The normal mailbox poll
        # remains the recovery path, so acknowledge the authenticated push.
        logger.exception("Push Gmail rinviato al polling")
        return {"status": "deferred"}
    return {"status": outcome}


@router.post("/gmail/sync")
async def sync_gmail_mailbox(
    current_user: User = Depends(get_current_active_user),
):
    """Scarica una pagina di posta Gmail della casella collegata all'utente."""
    if not current_user.tenant_id:
        return {"imported": 0}
    return await GmailSyncService.sync_mailbox_for(current_user.tenant_id, current_user.email)


@router.get("", response_model=EmailListResponse)
async def list_emails(
    claim_id: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """List emails with optional claim filter"""
    query = select(Email).where(Email.tenant_id == current_user.tenant_id)

    if claim_id:
        claim = await ClaimService.get_claim(db, current_user.tenant_id, claim_id)
        if not claim:
            raise HTTPException(status_code=404, detail="Claim not found")
        query = query.join(EmailClaimLink, EmailClaimLink.email_id == Email.id).where(
            EmailClaimLink.claim_id == claim.id,
            EmailClaimLink.tenant_id == current_user.tenant_id,
        )

    total = (await db.execute(select(func.count()).select_from(query.subquery()))).scalar() or 0
    result = await db.execute(query.order_by(Email.received_at.desc()))
    items = result.scalars().all()
    return EmailListResponse(
        items=[EmailResponse.model_validate(item) for item in items],
        total=total,
    )


@router.post("", response_model=EmailResponse, status_code=status.HTTP_201_CREATED)
async def create_email(
    payload: EmailCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    existing = await db.execute(
        select(Email).where(
            Email.tenant_id == current_user.tenant_id,
            Email.message_id == payload.message_id,
        )
    )
    email = existing.scalar_one_or_none()
    if email:
        return EmailResponse.model_validate(email)

    email = Email(
        id=str(uuid.uuid4()),
        tenant_id=current_user.tenant_id,
        message_id=payload.message_id,
        thread_id=payload.thread_id,
        from_address=payload.from_address,
        to_addresses=json.dumps(payload.to_addresses),
        cc_addresses=json.dumps(payload.cc_addresses),
        subject=payload.subject,
        body_text=payload.body_text,
        body_html=payload.body_html,
        received_at=payload.received_at,
        status=payload.status,
        raw_headers=payload.raw_headers,
        mailbox_id=payload.mailbox_id,
        provider_id=payload.provider_id,
    )
    db.add(email)
    await EmailRoutingService.reroute_disabled_user_email(db, email)
    await db.commit()
    await db.refresh(email)
    return EmailResponse.model_validate(email)


@router.post("/{email_id}/link-claim", status_code=status.HTTP_201_CREATED)
async def link_email_to_claim(
    email_id: str,
    payload: EmailClaimLinkRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    email_result = await db.execute(
        select(Email).where(
            Email.id == email_id,
            Email.tenant_id == current_user.tenant_id,
        )
    )
    email = email_result.scalar_one_or_none()
    if not email:
        raise HTTPException(status_code=404, detail="Email not found")

    claim = await ClaimService.get_claim(db, current_user.tenant_id, payload.claim_id)
    if not claim:
        raise HTTPException(status_code=404, detail="Claim not found")

    existing = await db.execute(
        select(EmailClaimLink).where(
            EmailClaimLink.tenant_id == current_user.tenant_id,
            EmailClaimLink.email_id == email.id,
            EmailClaimLink.claim_id == claim.id,
        )
    )
    if existing.scalar_one_or_none():
        return {"status": "already_linked", "claim_id": claim.id, "email_id": email.id}

    link = EmailClaimLink(
        id=str(uuid.uuid4()),
        tenant_id=current_user.tenant_id,
        email_id=email.id,
        claim_id=claim.id,
        link_type=payload.link_type,
        created_by=payload.created_by,
    )
    db.add(link)
    await EmailRoutingService.reroute_disabled_user_email(db, email, claim_ids=[claim.id])
    db.add(
        ClaimEvent(
            id=str(uuid.uuid4()),
            tenant_id=current_user.tenant_id,
            claim_id=claim.id,
            event_type="email_linked",
            actor_user_id=current_user.id,
            data_json={"email_id": email.id, "subject": email.subject, "link_type": payload.link_type},
            source="email",
        )
    )
    await db.commit()
    return {"status": "linked", "claim_id": claim.id, "email_id": email.id}
