"""
Business logic for the insured portal.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
import uuid

from sqlalchemy import and_, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.portal_security import (
    PortalSessionContext,
    create_portal_session_token,
    generate_magic_token,
    hash_secret,
    normalize_email,
    normalize_person_name,
    normalize_phone_number,
    normalize_tax_code,
)
from app.models.claim import Claim
from app.models.claim_assignment import ClaimAssignment
from app.models.claim_event import ClaimEvent
from app.models.document import Document
from app.models.internal_chat import InternalChatMember, InternalChatMessage, InternalChatThread
from app.models.planning import CalendarEvent, UserWorkSchedule
from app.models.portal import (
    PortalAuthChallenge,
    PortalBankAccountSubmission,
    PortalClaimAccess,
    PortalConversation,
    PortalConversationMessage,
    PortalDocumentCollectionSubmission,
    PortalSignatureRequest,
)
from app.models.user import User
from app.schemas.portal import (
    PortalAccessInviteRequest,
    PortalAuthStartRequest,
    PortalBankAccountSubmissionCreate,
    PortalConversationMessageCreate,
    PortalDocumentCollectionSubmissionCreate,
    PortalSignatureRequestCreate,
    PortalUploadIntentCreate,
)
from app.services.iban_service import IbanService
from app.services.portal_status_service import PortalStatusService
from app.services.state_service import StateService


class PortalService:
    @staticmethod
    def mask_email(email: str | None) -> str | None:
        if not email or "@" not in email:
            return None
        local, domain = email.split("@", 1)
        if len(local) <= 2:
            visible = local[:1]
        else:
            visible = f"{local[:2]}***"
        return f"{visible}@{domain}"

    @staticmethod
    def mask_phone(phone_number: str | None) -> str | None:
        normalized = normalize_phone_number(phone_number)
        if not normalized:
            return None
        suffix = normalized[-4:]
        return f"***{suffix}"

    @staticmethod
    def build_magic_link_url(token: str) -> str:
        base_url = settings.PORTAL_APP_URL.rstrip("/")
        return f"{base_url}/access/{token}"

    @staticmethod
    async def _create_claim_event(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
        event_type: str,
        source: str,
        data: dict,
    ) -> None:
        db.add(
            ClaimEvent(
                id=str(uuid.uuid4()),
                tenant_id=tenant_id,
                claim_id=claim_id,
                event_type=event_type,
                actor_user_id=None,
                data_json=data,
                source=source,
            )
        )

    @staticmethod
    async def get_claim_for_tenant(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
    ) -> Claim | None:
        result = await db.execute(
            select(Claim).where(Claim.id == claim_id, Claim.tenant_id == tenant_id)
        )
        return result.scalar_one_or_none()

    @staticmethod
    async def create_or_update_access(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
        payload: PortalAccessInviteRequest,
    ) -> PortalClaimAccess:
        email = normalize_email(payload.email)
        existing = await db.execute(
            select(PortalClaimAccess).where(
                PortalClaimAccess.claim_id == claim_id,
                PortalClaimAccess.tenant_id == tenant_id,
                PortalClaimAccess.email == email,
                PortalClaimAccess.status == "active",
            )
        )
        access = existing.scalar_one_or_none()
        now = datetime.now(timezone.utc)
        if not access:
            access = PortalClaimAccess(
                id=str(uuid.uuid4()),
                tenant_id=tenant_id,
                claim_id=claim_id,
                invited_at=now,
            )
            db.add(access)

        tax_code = normalize_tax_code(payload.tax_code)
        access.role = payload.role
        access.full_name = payload.full_name
        access.normalized_full_name = normalize_person_name(payload.full_name)
        access.email = email or payload.email
        access.phone_number = payload.phone_number
        access.normalized_phone_number = normalize_phone_number(payload.phone_number)
        access.tax_code_hash = hash_secret(tax_code) if tax_code else None
        access.tax_code_last4 = tax_code[-4:] if tax_code else None
        access.preferred_channel = payload.preferred_channel
        access.status = "active"
        access.is_primary = payload.is_primary
        access.metadata_json = payload.metadata_json
        access.last_delivery_status = None

        await db.flush()
        return access

    @staticmethod
    async def create_magic_link_challenge(
        db: AsyncSession,
        access: PortalClaimAccess,
        *,
        challenge_type: str = "magic_link",
        delivery_channel: str = "email",
        metadata_json: dict | None = None,
    ) -> tuple[PortalAuthChallenge, str]:
        now = datetime.now(timezone.utc)
        raw_token = generate_magic_token()
        challenge = PortalAuthChallenge(
            id=str(uuid.uuid4()),
            tenant_id=access.tenant_id,
            claim_id=access.claim_id,
            portal_access_id=access.id,
            challenge_type=challenge_type,
            delivery_channel=delivery_channel,
            destination=access.email if delivery_channel == "email" else access.phone_number,
            token_hash=hash_secret(raw_token),
            status="pending",
            requested_at=now,
            expires_at=now + timedelta(minutes=settings.PORTAL_CHALLENGE_EXPIRE_MINUTES),
            metadata_json=metadata_json,
        )
        access.last_access_requested_at = now
        db.add(challenge)
        await db.flush()
        return challenge, raw_token

    @staticmethod
    async def issue_access_link(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
        payload: PortalAccessInviteRequest,
    ) -> tuple[PortalClaimAccess, PortalAuthChallenge, str]:
        access = await PortalService.create_or_update_access(db, tenant_id, claim_id, payload)
        challenge, raw_token = await PortalService.create_magic_link_challenge(
            db,
            access,
            metadata_json={"issued_via": "internal_api"},
        )
        await PortalService._create_claim_event(
            db,
            tenant_id,
            claim_id,
            "portal_access_issued",
            "portal",
            {"portal_access_id": access.id, "challenge_id": challenge.id},
        )
        await db.commit()
        await db.refresh(access)
        await db.refresh(challenge)
        return access, challenge, raw_token

    @staticmethod
    async def start_public_auth(
        db: AsyncSession,
        payload: PortalAuthStartRequest,
    ) -> tuple[PortalClaimAccess | None, PortalAuthChallenge | None, str | None]:
        conditions = [PortalClaimAccess.status == "active"]
        if payload.claim_reference:
            conditions.append(
                or_(
                    Claim.external_ref == payload.claim_reference,
                    Claim.numero_sinistro == payload.claim_reference,
                )
            )

        tax_code = normalize_tax_code(payload.tax_code)
        if tax_code:
            conditions.append(PortalClaimAccess.tax_code_hash == hash_secret(tax_code))

        normalized_name = normalize_person_name(payload.full_name)
        normalized_phone = normalize_phone_number(payload.phone_number)
        if normalized_name and normalized_phone:
            conditions.append(PortalClaimAccess.normalized_full_name == normalized_name)
            conditions.append(PortalClaimAccess.normalized_phone_number == normalized_phone)

        if len(conditions) == 1:
            return None, None, None

        result = await db.execute(
            select(PortalClaimAccess)
            .join(Claim, Claim.id == PortalClaimAccess.claim_id)
            .where(and_(*conditions))
            .order_by(PortalClaimAccess.is_primary.desc(), PortalClaimAccess.created_at.desc())
            .limit(1)
        )
        access = result.scalar_one_or_none()
        if not access:
            return None, None, None

        challenge, raw_token = await PortalService.create_magic_link_challenge(
            db,
            access,
            delivery_channel=payload.channel,
            metadata_json={"issued_via": "public_auth_start"},
        )
        access.last_delivery_status = "pending_integration"
        await db.commit()
        await db.refresh(challenge)
        return access, challenge, raw_token

    @staticmethod
    async def exchange_magic_token(
        db: AsyncSession,
        token: str,
    ) -> tuple[PortalClaimAccess, str, int]:
        hashed = hash_secret(token)
        now = datetime.now(timezone.utc)
        result = await db.execute(
            select(PortalAuthChallenge, PortalClaimAccess)
            .join(PortalClaimAccess, PortalClaimAccess.id == PortalAuthChallenge.portal_access_id)
            .where(
                PortalAuthChallenge.token_hash == hashed,
                PortalAuthChallenge.status == "pending",
                PortalAuthChallenge.expires_at >= now,
                PortalClaimAccess.status == "active",
            )
        )
        row = result.first()
        if not row:
            raise ValueError("Invalid or expired portal token")

        challenge, access = row
        challenge.status = "consumed"
        challenge.consumed_at = now
        access.last_authenticated_at = now
        session_token, expires_in = create_portal_session_token(
            access.tenant_id,
            access.claim_id,
            access.id,
            access.role,
        )
        await db.commit()
        return access, session_token, expires_in

    @staticmethod
    async def get_access(
        db: AsyncSession,
        session: PortalSessionContext,
    ) -> PortalClaimAccess:
        result = await db.execute(
            select(PortalClaimAccess).where(
                PortalClaimAccess.id == session.portal_access_id,
                PortalClaimAccess.tenant_id == session.tenant_id,
                PortalClaimAccess.claim_id == session.claim_id,
            )
        )
        return result.scalar_one()

    @staticmethod
    async def get_assigned_expert(
        db: AsyncSession,
        claim_id: str,
        tenant_id: str,
    ) -> tuple[User | None, bool, str | None]:
        assignment_result = await db.execute(
            select(User)
            .join(ClaimAssignment, ClaimAssignment.assignee_user_id == User.id)
            .where(
                ClaimAssignment.claim_id == claim_id,
                ClaimAssignment.tenant_id == tenant_id,
                ClaimAssignment.unassigned_at.is_(None),
            )
            .order_by(ClaimAssignment.assigned_at.desc())
            .limit(1)
        )
        expert = assignment_result.scalar_one_or_none()
        if not expert:
            return None, False, "Perito non ancora assegnato"

        now = datetime.now()
        weekday = now.weekday()
        schedule_result = await db.execute(
            select(UserWorkSchedule).where(
                UserWorkSchedule.tenant_id == tenant_id,
                UserWorkSchedule.user_id == expert.id,
                UserWorkSchedule.weekday == weekday,
            )
        )
        schedules = schedule_result.scalars().all()
        current_time = now.time()
        is_available_now = any(
            schedule.start_time <= current_time <= schedule.end_time for schedule in schedules
        )
        is_online = bool((expert.settings_json or {}).get("portal_presence", {}).get("online"))
        note = None
        if schedules:
            first_slot = sorted(schedules, key=lambda item: item.start_time)[0]
            note = f"Disponibilita oggi {first_slot.start_time.strftime('%H:%M')} - {first_slot.end_time.strftime('%H:%M')}"
        return expert, is_available_now, note

    @staticmethod
    async def get_upcoming_appointment(
        db: AsyncSession,
        claim_id: str,
        tenant_id: str,
    ) -> CalendarEvent | None:
        now = datetime.now(timezone.utc)
        result = await db.execute(
            select(CalendarEvent).where(
                CalendarEvent.claim_id == claim_id,
                CalendarEvent.tenant_id == tenant_id,
                CalendarEvent.starts_at >= now,
            )
            .order_by(CalendarEvent.starts_at.asc())
            .limit(1)
        )
        return result.scalar_one_or_none()

    @staticmethod
    def build_requirements(claim: Claim) -> list[dict]:
        requirements: list[dict] = []
        if claim.stato_corrente in {"SV002", "SV022", "SV023"}:
            requirements.append(
                {
                    "key": "documents",
                    "label": "Documentazione richiesta",
                    "status": "pending",
                    "description": "Carica la documentazione necessaria per continuare la gestione.",
                }
            )
        if not claim.foto:
            requirements.append(
                {
                    "key": "photos",
                    "label": "Foto del danno",
                    "status": "pending",
                    "description": "La documentale fotografica non risulta ancora completata.",
                }
            )
        if not claim.iban:
            requirements.append(
                {
                    "key": "iban",
                    "label": "Coordinate bancarie",
                    "status": "missing",
                    "description": "Inserisci l'IBAN per eventuale liquidazione.",
                }
            )
        if claim.stato_corrente in {"SV020", "SV030", "SV031"}:
            requirements.append(
                {
                    "key": "act_signature",
                    "label": "Firma atto",
                    "status": "required",
                    "description": "È presente un atto o un esito in attesa di conferma.",
                }
            )
        return requirements

    @staticmethod
    async def build_claim_summary(
        db: AsyncSession,
        session: PortalSessionContext,
    ) -> dict:
        claim = await PortalService.get_claim_for_tenant(db, session.tenant_id, session.claim_id)
        if not claim:
            raise ValueError("Claim not found")

        expert, is_available_now, availability_note = await PortalService.get_assigned_expert(
            db,
            claim.id,
            claim.tenant_id,
        )
        appointment = await PortalService.get_upcoming_appointment(db, claim.id, claim.tenant_id)
        macro_state = PortalStatusService.build_macro_state(claim.stato_corrente)
        expert_payload = {
            "user_id": expert.id if expert else None,
            "full_name": expert.full_name if expert else None,
            "email": expert.email if expert else None,
            "phone_number": expert.phone_number if expert else None,
            "job_title": expert.job_title if expert else None,
            "is_available_now": is_available_now,
            "is_online": bool((expert.settings_json or {}).get("portal_presence", {}).get("online")) if expert else False,
            "availability_note": availability_note,
        }
        appointment_payload = None
        if appointment:
            appointment_payload = {
                "id": appointment.id,
                "title": appointment.title,
                "starts_at": appointment.starts_at,
                "ends_at": appointment.ends_at,
                "location": appointment.location,
                "status": appointment.status,
            }

        return {
            "claim_id": claim.id,
            "tenant_id": claim.tenant_id,
            "external_ref": claim.external_ref,
            "numero_sinistro": claim.numero_sinistro,
            "compagnia": claim.compagnia,
            "nome_assicurato": claim.nome_assicurato,
            "data_sinistro": claim.data_sinistro,
            "macro_state": macro_state,
            "expert": expert_payload,
            "requirements": PortalService.build_requirements(claim),
            "upcoming_appointment": appointment_payload,
            "chat_enabled": True,
            "document_upload_enabled": True,
            "act_signature_enabled": True,
        }

    @staticmethod
    async def list_timeline(
        db: AsyncSession,
        session: PortalSessionContext,
        limit: int = 25,
    ) -> list[dict]:
        result = await db.execute(
            select(ClaimEvent)
            .where(
                ClaimEvent.tenant_id == session.tenant_id,
                ClaimEvent.claim_id == session.claim_id,
            )
            .order_by(ClaimEvent.event_time.desc())
            .limit(limit)
        )
        items = []
        for event in result.scalars().all():
            label = event.event_type.replace("_", " ").capitalize()
            description = None
            if event.event_type == "state_changed":
                data = event.data_json or {}
                description = f"{data.get('from', 'n/d')} -> {data.get('to', 'n/d')}"
            items.append(
                {
                    "id": event.id,
                    "event_type": event.event_type,
                    "event_time": event.event_time,
                    "label": label,
                    "description": description,
                    "source": event.source,
                }
            )
        return items

    @staticmethod
    async def list_documents(
        db: AsyncSession,
        session: PortalSessionContext,
        limit: int = 100,
    ) -> list[dict]:
        result = await db.execute(
            select(Document)
            .where(
                Document.tenant_id == session.tenant_id,
                Document.claim_id == session.claim_id,
            )
            .order_by(Document.uploaded_at.desc())
            .limit(limit)
        )
        return [
            {
                "id": document.id,
                "file_name": document.file_name,
                "category": document.category,
                "status": document.status,
                "uploaded_at": document.uploaded_at,
            }
            for document in result.scalars().all()
        ]

    @staticmethod
    async def create_upload_intent(
        db: AsyncSession,
        session: PortalSessionContext,
        payload: PortalUploadIntentCreate,
    ) -> dict:
        document_id = str(uuid.uuid4())
        storage_path = f"portal/{session.tenant_id}/{session.claim_id}/{document_id}/{payload.file_name}"
        document = Document(
            id=document_id,
            tenant_id=session.tenant_id,
            claim_id=session.claim_id,
            source_type="portal",
            file_name=payload.file_name,
            original_file_name=payload.file_name,
            mime_type=payload.mime_type,
            size_bytes=payload.size_bytes,
            storage_provider="supabase",
            storage_bucket=settings.STORAGE_BUCKET_NAME,
            storage_path=storage_path,
            status="pending_upload",
            category=payload.category,
            metadata_json={"portal_access_id": session.portal_access_id},
        )
        db.add(document)
        await PortalService._create_claim_event(
            db,
            session.tenant_id,
            session.claim_id,
            "portal_upload_intent_created",
            "portal",
            {"document_id": document.id, "file_name": document.file_name},
        )
        await db.commit()
        return {
            "document_id": document.id,
            "upload_mode": "signed-url-pending",
            "upload_url": None,
            "storage_path": storage_path,
            "expires_in": 3600,
        }

    @staticmethod
    async def submit_document_collection(
        db: AsyncSession,
        session: PortalSessionContext,
        payload: PortalDocumentCollectionSubmissionCreate,
    ) -> PortalDocumentCollectionSubmission:
        submission = PortalDocumentCollectionSubmission(
            id=str(uuid.uuid4()),
            tenant_id=session.tenant_id,
            claim_id=session.claim_id,
            portal_access_id=session.portal_access_id,
            status="submitted",
            payload_json=payload.model_dump(),
            metadata_json=payload.metadata_json,
        )
        db.add(submission)

        claim = await PortalService.get_claim_for_tenant(db, session.tenant_id, session.claim_id)
        if claim:
            claim.foto = payload.photos_count > 0 or claim.foto
            claim.updated_at = datetime.now(timezone.utc)

        await PortalService._create_claim_event(
            db,
            session.tenant_id,
            session.claim_id,
            "portal_document_collection_submitted",
            "portal",
            {"submission_id": submission.id, "photos_count": payload.photos_count},
        )
        await db.flush()

        if claim and claim.stato_corrente in {"SV002", "SV022", "SV023"}:
            await StateService.transition_state(
                db,
                session.tenant_id,
                session.claim_id,
                claim.stato_corrente,
                "SV010",
                None,
                "Portal document collection submitted",
                {"submission_id": submission.id},
            )
        else:
            await db.commit()

        await db.refresh(submission)
        return submission

    @staticmethod
    async def submit_bank_account(
        db: AsyncSession,
        session: PortalSessionContext,
        payload: PortalBankAccountSubmissionCreate,
    ) -> tuple[PortalBankAccountSubmission, dict]:
        validation = IbanService.validate(payload.iban)
        submission = PortalBankAccountSubmission(
            id=str(uuid.uuid4()),
            tenant_id=session.tenant_id,
            claim_id=session.claim_id,
            portal_access_id=session.portal_access_id,
            iban=validation["normalized_iban"],
            account_holder=payload.account_holder,
            validation_status="valid" if validation["is_valid"] else "invalid",
            bank_name=validation.get("abi"),
            branch_name=validation.get("cab"),
            is_selected=True,
            metadata_json=validation,
        )
        db.add(submission)

        claim = await PortalService.get_claim_for_tenant(db, session.tenant_id, session.claim_id)
        if claim and validation["is_valid"]:
            claim.iban = True
            claim.updated_at = datetime.now(timezone.utc)

        await PortalService._create_claim_event(
            db,
            session.tenant_id,
            session.claim_id,
            "portal_iban_submitted",
            "portal",
            {"submission_id": submission.id, "valid": validation["is_valid"]},
        )
        await db.commit()
        await db.refresh(submission)
        return submission, validation

    @staticmethod
    async def get_or_create_conversation(
        db: AsyncSession,
        session: PortalSessionContext,
        access: PortalClaimAccess,
    ) -> PortalConversation:
        result = await db.execute(
            select(PortalConversation).where(
                PortalConversation.tenant_id == session.tenant_id,
                PortalConversation.claim_id == session.claim_id,
                PortalConversation.portal_access_id == session.portal_access_id,
                PortalConversation.status == "active",
            )
        )
        conversation = result.scalar_one_or_none()
        if conversation:
            return conversation

        conversation = PortalConversation(
            id=str(uuid.uuid4()),
            tenant_id=session.tenant_id,
            claim_id=session.claim_id,
            portal_access_id=session.portal_access_id,
            status="active",
            metadata_json={"source": "portal"},
        )
        db.add(conversation)
        await db.flush()

        expert, _, _ = await PortalService.get_assigned_expert(db, session.claim_id, session.tenant_id)
        thread = InternalChatThread(
            id=str(uuid.uuid4()),
            tenant_id=session.tenant_id,
            claim_id=session.claim_id,
            title=f"Portale assicurato - {access.full_name}",
            thread_type="portal",
            created_by_user_id=None,
            metadata_json={
                "source": "portal",
                "portal_conversation_id": conversation.id,
                "portal_access_id": access.id,
            },
        )
        db.add(thread)
        await db.flush()
        conversation.internal_thread_id = thread.id

        if expert:
            db.add(InternalChatMember(thread_id=thread.id, user_id=expert.id))

        return conversation

    @staticmethod
    async def list_conversation_messages(
        db: AsyncSession,
        session: PortalSessionContext,
    ) -> list[dict]:
        result = await db.execute(
            select(PortalConversationMessage)
            .join(PortalConversation, PortalConversation.id == PortalConversationMessage.conversation_id)
            .where(
                PortalConversation.tenant_id == session.tenant_id,
                PortalConversation.claim_id == session.claim_id,
                PortalConversation.portal_access_id == session.portal_access_id,
            )
            .order_by(PortalConversationMessage.created_at.asc())
        )
        return [
            {
                "id": item.id,
                "author_type": item.author_type,
                "body_text": item.body_text,
                "created_at": item.created_at,
            }
            for item in result.scalars().all()
        ]

    @staticmethod
    async def create_conversation_message(
        db: AsyncSession,
        session: PortalSessionContext,
        payload: PortalConversationMessageCreate,
    ) -> PortalConversationMessage:
        access = await PortalService.get_access(db, session)
        conversation = await PortalService.get_or_create_conversation(db, session, access)

        internal_message_id = None
        if conversation.internal_thread_id:
            internal_message = InternalChatMessage(
                id=str(uuid.uuid4()),
                tenant_id=session.tenant_id,
                thread_id=conversation.internal_thread_id,
                claim_id=session.claim_id,
                sender_user_id=None,
                body_text=payload.body_text,
                message_type="portal",
                metadata_json={
                    "source": "portal",
                    "portal_access_id": access.id,
                    "insured_name": access.full_name,
                    "insured_email": access.email,
                    "insured_phone_number": access.phone_number,
                },
            )
            db.add(internal_message)
            await db.flush()
            internal_message_id = internal_message.id

        message = PortalConversationMessage(
            id=str(uuid.uuid4()),
            tenant_id=session.tenant_id,
            conversation_id=conversation.id,
            claim_id=session.claim_id,
            author_type="portal",
            body_text=payload.body_text,
            internal_chat_message_id=internal_message_id,
            metadata_json={"portal_access_id": access.id},
        )
        db.add(message)
        await PortalService._create_claim_event(
            db,
            session.tenant_id,
            session.claim_id,
            "portal_message_created",
            "portal",
            {"conversation_id": conversation.id, "message_id": message.id},
        )
        await db.commit()
        await db.refresh(message)
        return message

    @staticmethod
    async def create_signature_request(
        db: AsyncSession,
        session: PortalSessionContext,
        payload: PortalSignatureRequestCreate,
    ) -> tuple[PortalSignatureRequest, str]:
        document_result = await db.execute(
            select(Document).where(
                Document.id == payload.document_id,
                Document.tenant_id == session.tenant_id,
                Document.claim_id == session.claim_id,
            )
        )
        document = document_result.scalar_one_or_none()
        if not document:
            raise ValueError("Document not found for claim")

        access = await PortalService.get_access(db, session)
        challenge, raw_token = await PortalService.create_magic_link_challenge(
            db,
            access,
            challenge_type="signature_confirmation",
            delivery_channel="email",
            metadata_json={"document_id": document.id},
        )
        signature_request = PortalSignatureRequest(
            id=str(uuid.uuid4()),
            tenant_id=session.tenant_id,
            claim_id=session.claim_id,
            portal_access_id=session.portal_access_id,
            document_id=document.id,
            challenge_id=challenge.id,
            signature_method=payload.signature_method,
            status="pending_confirmation",
            expires_at=challenge.expires_at,
            metadata_json={"delivery_channel": challenge.delivery_channel},
        )
        db.add(signature_request)
        await PortalService._create_claim_event(
            db,
            session.tenant_id,
            session.claim_id,
            "portal_signature_requested",
            "portal",
            {"signature_request_id": signature_request.id, "document_id": document.id},
        )
        await db.commit()
        await db.refresh(signature_request)
        return signature_request, raw_token

    @staticmethod
    async def confirm_signature_request(
        db: AsyncSession,
        session: PortalSessionContext,
        request_id: str,
        token: str,
    ) -> PortalSignatureRequest:
        hashed = hash_secret(token)
        result = await db.execute(
            select(PortalSignatureRequest, PortalAuthChallenge)
            .join(PortalAuthChallenge, PortalAuthChallenge.id == PortalSignatureRequest.challenge_id)
            .where(
                PortalSignatureRequest.id == request_id,
                PortalSignatureRequest.tenant_id == session.tenant_id,
                PortalSignatureRequest.claim_id == session.claim_id,
                PortalSignatureRequest.portal_access_id == session.portal_access_id,
                PortalSignatureRequest.status == "pending_confirmation",
                PortalAuthChallenge.token_hash == hashed,
                PortalAuthChallenge.status == "pending",
            )
        )
        row = result.first()
        if not row:
            raise ValueError("Invalid signature confirmation token")

        signature_request, challenge = row
        now = datetime.now(timezone.utc)
        signature_request.status = "signed"
        signature_request.signed_at = now
        challenge.status = "consumed"
        challenge.consumed_at = now

        claim = await PortalService.get_claim_for_tenant(db, session.tenant_id, session.claim_id)
        if claim:
            claim.data_ritorno_atto = now

        await PortalService._create_claim_event(
            db,
            session.tenant_id,
            session.claim_id,
            "portal_signature_confirmed",
            "portal",
            {"signature_request_id": signature_request.id, "document_id": signature_request.document_id},
        )
        await db.flush()

        if claim and claim.stato_corrente in {"SV030", "SV031"}:
            await StateService.transition_state(
                db,
                session.tenant_id,
                session.claim_id,
                claim.stato_corrente,
                "SV032",
                None,
                "Portal act signature confirmed",
                {"signature_request_id": signature_request.id},
            )
        else:
            await db.commit()

        await db.refresh(signature_request)
        return signature_request
