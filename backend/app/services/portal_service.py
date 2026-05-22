"""
Business logic for the insured portal.
"""
from __future__ import annotations

from datetime import date, datetime, time, timedelta, timezone
import hashlib
from pathlib import Path
import re
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
from app.models.claim_folder import ClaimFolder
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
from app.models.tenant import TenantPortalDomain
from app.models.user import User
from app.schemas.portal import (
    PortalAccessInviteRequest,
    PortalAuthStartRequest,
    PortalBankAccountSubmissionCreate,
    PortalConversationMessageCreate,
    PortalDocumentCollectionSubmissionCreate,
    PortalInspectionLocationUpdateRequest,
    PortalInspectionPreferencesUpdateRequest,
    PortalSignatureRequestCreate,
    PortalUploadIntentCreate,
)
from app.services.iban_service import IbanService
from app.services.inspection_workflow_service import InspectionWorkflowService
from app.services.portal_status_service import PortalStatusService
from app.services.process_job_service import ProcessJobService
from app.services.state_service import StateService
from app.services.supabase_storage_service import SupabaseStorageService
from app.schemas.inspection import InspectionPreferredSlotInput


class PortalService:
    PORTAL_UPLOAD_ROOT = Path(__file__).resolve().parents[2] / "runtime" / "portal_uploads"
    PORTAL_SUBDOMAIN = "assicurati"
    REQUIRED_DOCUMENT_COLLECTION_CONFIRMATIONS = {
        "authentic_photos",
        "photos_match_insured_property",
        "photos_clear_for_damage_assessment",
        "preserve_damaged_goods_until_claim_closed",
        "no_additional_damaged_goods",
    }

    @staticmethod
    def _amount_to_float(value: object | None) -> float | None:
        if value is None:
            return None

    @staticmethod
    def _mask_iban_value(value: str | None) -> str | None:
        compact = (value or "").replace(" ", "").upper()
        if len(compact) < 8:
            return None
        return f"{compact[:4]} •••• •••• •••• {compact[-4:]}"
        try:
            return float(value)
        except (TypeError, ValueError):
            return None

    @staticmethod
    def _merge_metadata(base: dict | None, **updates) -> dict:
        metadata = dict(base or {})
        for key, value in updates.items():
            if value is None:
                metadata.pop(key, None)
            else:
                metadata[key] = value
        return metadata

    @staticmethod
    def _document_collection_draft_payload(claim: Claim) -> dict:
        metadata = claim.metadata_json or {}
        draft = metadata.get("portal_document_collection_draft")
        return draft if isinstance(draft, dict) else {}

    @staticmethod
    def _document_collection_draft_info(claim: Claim) -> dict:
        draft = PortalService._document_collection_draft_payload(claim)
        submitted = (claim.metadata_json or {}).get("portal_document_collection") or {}
        submitted_at = submitted.get("submitted_at")
        updated_at = draft.get("updated_at")
        return {
            "available": bool(draft),
            "status": str(draft.get("status") or ("submitted" if submitted_at else "not_started")),
            "current_step": draft.get("step_kind"),
            "updated_at": PortalService._parse_iso_datetime(updated_at) if isinstance(updated_at, str) else None,
            "submitted_at": PortalService._parse_iso_datetime(submitted_at) if isinstance(submitted_at, str) else None,
        }

    @staticmethod
    def _merge_uploaded_refs(existing: list[dict] | None, incoming: list[dict] | None) -> list[dict]:
        merged: list[dict] = []
        seen: set[str] = set()
        for source in (existing or [], incoming or []):
            for item in source:
                if not isinstance(item, dict):
                    continue
                document_id = str(item.get("document_id") or "").strip()
                key = document_id or str(item)
                if key in seen:
                    continue
                merged.append(item)
                seen.add(key)
        return merged

    @staticmethod
    def _merge_document_collection_item_draft(existing: dict | None, incoming: dict | None) -> dict:
        existing = existing or {}
        incoming = incoming or {}
        merged = dict(existing)
        for key in [
            "itemType",
            "brand",
            "model",
            "purchaseYear",
            "purchaseYearApproximate",
            "damageType",
            "damageDynamics",
            "hasDamagedComponents",
            "damagedComponents",
        ]:
            if key in incoming:
                merged[key] = incoming.get(key)
        merged["wholeItemUploads"] = PortalService._merge_uploaded_refs(
            existing.get("wholeItemUploads"),
            incoming.get("wholeItemUploads"),
        )
        merged["optionalVideosUploads"] = PortalService._merge_uploaded_refs(
            existing.get("optionalVideosUploads"),
            incoming.get("optionalVideosUploads"),
        )
        merged["optionalSupportingDocsUploads"] = PortalService._merge_uploaded_refs(
            existing.get("optionalSupportingDocsUploads"),
            incoming.get("optionalSupportingDocsUploads"),
        )
        existing_components = existing.get("componentUploads") if isinstance(existing.get("componentUploads"), dict) else {}
        incoming_components = incoming.get("componentUploads") if isinstance(incoming.get("componentUploads"), dict) else {}
        component_keys = set(existing_components.keys()) | set(incoming_components.keys())
        merged["componentUploads"] = {
            component: PortalService._merge_uploaded_refs(
                existing_components.get(component),
                incoming_components.get(component),
            )
            for component in component_keys
        }
        return merged

    @staticmethod
    def _merge_document_collection_draft(existing: dict | None, incoming: dict | None) -> dict:
        existing = existing or {}
        incoming = incoming or {}
        merged = dict(existing)
        for key in ["step_kind", "step_item_index", "inventory_count", "notes", "confirmations"]:
            if key in incoming:
                merged[key] = incoming.get(key)
        merged["buildingUploads"] = PortalService._merge_uploaded_refs(
            existing.get("buildingUploads"),
            incoming.get("buildingUploads"),
        )
        merged["repairReceiptUploads"] = PortalService._merge_uploaded_refs(
            existing.get("repairReceiptUploads"),
            incoming.get("repairReceiptUploads"),
        )
        existing_items = existing.get("items") if isinstance(existing.get("items"), list) else []
        incoming_items = incoming.get("items") if isinstance(incoming.get("items"), list) else []
        item_count = max(len(existing_items), len(incoming_items), int(incoming.get("inventory_count") or 0))
        merged["items"] = [
            PortalService._merge_document_collection_item_draft(
                existing_items[index] if index < len(existing_items) and isinstance(existing_items[index], dict) else None,
                incoming_items[index] if index < len(incoming_items) and isinstance(incoming_items[index], dict) else None,
            )
            for index in range(item_count)
        ]
        return merged

    @staticmethod
    def _portal_additional_document_requests(claim: Claim) -> list[str]:
        metadata = claim.metadata_json or {}
        raw = metadata.get("portal_additional_document_requests")
        if not isinstance(raw, list):
            return []
        return [str(item).strip() for item in raw if str(item).strip()]

    @staticmethod
    def _build_act_flow(claim: Claim) -> dict | None:
        metadata = claim.metadata_json or {}
        raw = metadata.get("portal_act_flow")
        if not isinstance(raw, dict):
            if claim.data_invio_atto:
                return {
                    "status": "awaiting_publication",
                    "label": "Atto in preparazione",
                    "provider": None,
                    "signing_url": None,
                    "provider_reference": None,
                    "request_id": None,
                    "act_document_id": None,
                    "signed_document_id": None,
                    "countersigned_document_id": None,
                    "signed_at": claim.data_ritorno_atto,
                    "countersigned_at": None,
                }
            return None
        status = str(raw.get("status") or "pending_external_signature")
        label_map = {
            "pending_external_signature": "Atto pronto da firmare",
            "signed_by_insured": "Atto firmato dall'assicurato",
            "countersigned": "Atto controfirmato disponibile",
            "completed": "Atto completato",
        }
        return {
            "status": status,
            "label": label_map.get(status, "Firma atto"),
            "provider": raw.get("provider"),
            "signing_url": raw.get("signing_url"),
            "provider_reference": raw.get("provider_reference"),
            "request_id": raw.get("request_id"),
            "act_document_id": raw.get("act_document_id"),
            "signed_document_id": raw.get("signed_document_id"),
            "countersigned_document_id": raw.get("countersigned_document_id"),
            "signed_at": PortalService._parse_iso_datetime(raw.get("signed_at")) if isinstance(raw.get("signed_at"), str) else raw.get("signed_at"),
            "countersigned_at": PortalService._parse_iso_datetime(raw.get("countersigned_at")) if isinstance(raw.get("countersigned_at"), str) else raw.get("countersigned_at"),
        }

    @staticmethod
    def _claim_reference_for_paths(claim: Claim) -> str:
        candidate = claim.external_ref or claim.numero_sinistro or claim.id
        return "".join(char if char.isalnum() or char in {"-", "_"} else "_" for char in candidate).strip("_") or claim.id

    @staticmethod
    def _safe_filename(filename: str | None, fallback: str) -> str:
        candidate = Path(filename or "").name.strip()
        return candidate or fallback

    @staticmethod
    async def _ensure_claim_folder(
        db: AsyncSession,
        tenant_id: str,
        claim: Claim,
        *,
        name: str,
        folder_type: str,
        parent_id: str | None = None,
        path: str,
        metadata_json: dict | None = None,
    ) -> ClaimFolder:
        result = await db.execute(
            select(ClaimFolder).where(
                ClaimFolder.tenant_id == tenant_id,
                ClaimFolder.path == path,
            )
        )
        existing = result.scalar_one_or_none()
        if existing:
            return existing

        folder = ClaimFolder(
            id=str(uuid.uuid4()),
            tenant_id=tenant_id,
            claim_id=claim.id,
            parent_id=parent_id,
            name=name,
            folder_type=folder_type,
            path=path,
            source="portal",
            external_ref=claim.external_ref or claim.numero_sinistro,
            metadata_json=metadata_json,
        )
        db.add(folder)
        await db.flush()
        return folder

    @staticmethod
    async def _ensure_insured_claim_folder(
        db: AsyncSession,
        tenant_id: str,
        claim: Claim,
    ) -> ClaimFolder:
        root_path = f"/claims/{claim.external_ref or claim.id}"
        root_folder = await PortalService._ensure_claim_folder(
            db,
            tenant_id,
            claim,
            name=claim.external_ref or claim.numero_sinistro or "Sinistro",
            folder_type="claim_root",
            path=root_path,
            metadata_json={"created_via": "portal"},
        )
        insured_path = f"{root_path}/da assicurato"
        return await PortalService._ensure_claim_folder(
            db,
            tenant_id,
            claim,
            name="da assicurato",
            folder_type="insured_uploads",
            parent_id=root_folder.id,
            path=insured_path,
            metadata_json={"created_via": "portal", "audience": "insured"},
        )

    @staticmethod
    def _build_insured_storage_path(
        claim: Claim,
        tenant_id: str,
        document_id: str,
        filename: str,
    ) -> Path:
        safe_reference = PortalService._claim_reference_for_paths(claim)
        safe_name = PortalService._safe_filename(filename, f"{document_id}.bin")
        target_dir = PortalService.PORTAL_UPLOAD_ROOT / tenant_id / safe_reference / "da_assicurato"
        target_dir.mkdir(parents=True, exist_ok=True)
        return target_dir / f"{document_id}_{safe_name}"

    @staticmethod
    def _build_document_collection_tags(registration: dict) -> list[str]:
        tags = ["da assicurato"]
        kind = (registration.get("kind") or "").strip()
        item_label = (registration.get("item_label") or registration.get("item_type") or "").strip()
        component_name = (registration.get("component_name") or "").strip()

        if kind == "building_photo":
            tags.append("foto ubicazione")
        elif kind == "whole_item_photo" and item_label:
            tags.append(f"foto bene {item_label}")
        elif kind == "component_photo":
            if item_label:
                tags.append(f"foto componente {item_label}")
            if component_name:
                tags.append(component_name)
        elif kind == "video" and item_label:
            tags.append(f"video bene {item_label}")
        elif kind == "supporting_document":
            tags.append("documentazione utile")
            if item_label:
                tags.append(f"bene {item_label}")
        elif kind == "repair_receipt":
            tags.append("giustificativi riparazione o sostituzione")

        return list(dict.fromkeys(tags))

    @staticmethod
    def _validate_document_collection_confirmations(metadata_json: dict | None) -> dict:
        metadata = metadata_json or {}
        confirmations = metadata.get("confirmations")
        if not isinstance(confirmations, dict):
            raise ValueError("Conferma tutte le dichiarazioni richieste prima di inviare.")
        missing = [
            key
            for key in PortalService.REQUIRED_DOCUMENT_COLLECTION_CONFIRMATIONS
            if confirmations.get(key) is not True
        ]
        if missing:
            raise ValueError("Conferma tutte le dichiarazioni richieste prima di inviare.")
        return confirmations

    @staticmethod
    async def upload_document_file(
        db: AsyncSession,
        session: PortalSessionContext,
        *,
        document_id: str,
        file_name: str,
        mime_type: str | None,
        content: bytes,
        claim_id: str | None = None,
    ) -> dict:
        if not content:
            raise ValueError("File vuoto.")

        claim, access = await PortalService.resolve_claim_for_session(db, session, claim_id)
        result = await db.execute(
            select(Document).where(
                Document.id == document_id,
                Document.tenant_id == session.tenant_id,
                Document.claim_id == claim.id,
            )
        )
        document = result.scalar_one_or_none()
        if not document:
            raise ValueError("Documento non trovato.")

        insured_folder = await PortalService._ensure_insured_claim_folder(db, session.tenant_id, claim)
        safe_name = PortalService._safe_filename(file_name or document.file_name, document.id)
        checksum_sha256 = hashlib.sha256(content).hexdigest()

        if SupabaseStorageService.is_configured():
            claim_ref = PortalService._claim_reference_for_paths(claim)
            object_path = SupabaseStorageService.build_object_path(
                session.tenant_id, claim_ref, document.id, safe_name
            )
            blob = await SupabaseStorageService.upload(
                object_path=object_path,
                content=content,
                mime_type=mime_type,
            )
            document.storage_provider = "supabase"
            document.storage_bucket = blob.bucket
            document.storage_path = blob.storage_path
        else:
            storage_path = PortalService._build_insured_storage_path(
                claim, session.tenant_id, document.id, safe_name
            )
            previous_path = Path(document.storage_path) if document.storage_path else None
            storage_path.write_bytes(content)
            if previous_path and previous_path != storage_path and previous_path.exists():
                previous_path.unlink(missing_ok=True)
            document.storage_provider = "local"
            document.storage_bucket = None
            document.storage_path = str(storage_path)

        document.file_name = safe_name
        document.original_file_name = safe_name
        document.mime_type = mime_type or document.mime_type
        document.extension = Path(safe_name).suffix.lstrip(".") or None
        document.size_bytes = len(content)
        document.folder_id = insured_folder.id
        document.logical_path = f"{insured_folder.path}/{safe_name}"
        document.status = "uploaded"
        document.checksum_sha256 = checksum_sha256
        document.uploaded_at = datetime.now(timezone.utc)
        document.metadata_json = PortalService._merge_metadata(
            document.metadata_json,
            portal_access_id=access.id,
            uploaded_via="portal",
            audience="insured",
        )

        await PortalService._create_claim_event(
            db,
            session.tenant_id,
            claim.id,
            "portal_document_uploaded",
            "portal",
            {"document_id": document.id, "file_name": document.file_name},
        )
        await db.commit()
        await db.refresh(document)
        return {
            "document_id": document.id,
            "file_name": document.file_name,
            "status": document.status,
            "storage_path": document.storage_path,
            "uploaded_at": document.uploaded_at,
        }

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
    def normalize_portal_host(value: str | None) -> str | None:
        if not value:
            return None
        candidate = value.split(",", 1)[0].strip().lower()
        candidate = re.sub(r"^https?://", "", candidate)
        candidate = candidate.split("/", 1)[0].split("?", 1)[0].strip().rstrip(".")
        if not candidate:
            return None
        if candidate.startswith("["):
            return candidate
        return candidate.rsplit(":", 1)[0]

    @staticmethod
    def portal_domain_from_host(host: str | None) -> str | None:
        normalized = PortalService.normalize_portal_host(host)
        if not normalized:
            return None
        prefix = f"{PortalService.PORTAL_SUBDOMAIN}."
        if normalized.startswith(prefix):
            tenant_domain = normalized[len(prefix):]
            return tenant_domain or None
        return normalized

    @staticmethod
    def _is_local_portal_host(host: str | None) -> bool:
        normalized = PortalService.normalize_portal_host(host)
        return normalized in {"localhost", "127.0.0.1", "::1", "[::1]"}

    @staticmethod
    def _requires_configured_tenant(host: str | None) -> bool:
        normalized = PortalService.normalize_portal_host(host)
        if not normalized or PortalService._is_local_portal_host(normalized):
            return False
        return normalized.startswith(f"{PortalService.PORTAL_SUBDOMAIN}.")

    @staticmethod
    async def resolve_tenant_id_for_portal_host(
        db: AsyncSession,
        host: str | None,
    ) -> str | None:
        normalized_host = PortalService.normalize_portal_host(host)
        tenant_domain = PortalService.portal_domain_from_host(normalized_host)
        if not normalized_host or not tenant_domain or PortalService._is_local_portal_host(normalized_host):
            return None

        candidates = {normalized_host, tenant_domain}
        result = await db.execute(
            select(TenantPortalDomain)
            .where(TenantPortalDomain.domain.in_(candidates))
            .order_by(TenantPortalDomain.is_primary.desc(), TenantPortalDomain.created_at.desc())
            .limit(1)
        )
        domain = result.scalar_one_or_none()
        return domain.tenant_id if domain else None

    @staticmethod
    async def build_magic_link_url_for_tenant(
        db: AsyncSession,
        tenant_id: str,
        token: str,
        portal_host: str | None = None,
    ) -> str:
        normalized_host = PortalService.normalize_portal_host(portal_host)
        if normalized_host and not PortalService._is_local_portal_host(normalized_host):
            scheme = "https"
            if settings.PORTAL_APP_URL.startswith("http://"):
                scheme = "http"
            return f"{scheme}://{normalized_host}/access/{token}"

        result = await db.execute(
            select(TenantPortalDomain)
            .where(TenantPortalDomain.tenant_id == tenant_id)
            .order_by(TenantPortalDomain.is_primary.desc(), TenantPortalDomain.created_at.desc())
            .limit(1)
        )
        domain = result.scalar_one_or_none()
        if not domain:
            return PortalService.build_magic_link_url(token)

        configured_domain = PortalService.normalize_portal_host(domain.domain)
        if not configured_domain:
            return PortalService.build_magic_link_url(token)

        host = (
            configured_domain
            if configured_domain.startswith(f"{PortalService.PORTAL_SUBDOMAIN}.")
            else f"{PortalService.PORTAL_SUBDOMAIN}.{configured_domain}"
        )
        return f"https://{host}/access/{token}"

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
    async def _find_claim_by_reference(
        db: AsyncSession,
        claim_reference: str,
        tenant_id: str | None = None,
    ) -> Claim | None:
        normalized_reference = claim_reference.strip()
        if not normalized_reference:
            return None
        conditions = [
            or_(
                Claim.external_ref == normalized_reference,
                Claim.numero_sinistro == normalized_reference,
            )
        ]
        if tenant_id:
            conditions.append(Claim.tenant_id == tenant_id)
        result = await db.execute(
            select(Claim)
            .where(and_(*conditions))
            .order_by(Claim.updated_at.desc(), Claim.created_at.desc())
            .limit(1)
        )
        return result.scalar_one_or_none()

    @staticmethod
    async def _ensure_dev_access_for_claim(
        db: AsyncSession,
        claim: Claim,
    ) -> PortalClaimAccess:
        email = normalize_email(claim.email_assicurato) or normalize_email(claim.email_contraente)
        if not email:
            email = f"dev-portal+{claim.id}@local.invalid"

        full_name = (
            claim.nome_assicurato
            or claim.nome_contraente
            or claim.nome_danneggiato
            or "Assicurato"
        )
        phone_number = (
            claim.telefono_assicurato
            or claim.telefono_contraente
            or claim.telefono_danneggiato
        )

        payload = PortalAccessInviteRequest(
            full_name=full_name,
            email=email,
            phone_number=phone_number,
            tax_code=None,
            role="insured",
            is_primary=True,
            preferred_channel="email",
            metadata_json={
                "provisioned_via": "dev_claim_reference_only_auth",
                "claim_reference": claim.external_ref or claim.numero_sinistro,
            },
        )
        return await PortalService.create_or_update_access(
            db,
            claim.tenant_id,
            claim.id,
            payload,
        )

    @staticmethod
    async def start_public_auth(
        db: AsyncSession,
        payload: PortalAuthStartRequest,
    ) -> tuple[PortalClaimAccess | None, PortalAuthChallenge | None, str | None]:
        tenant_id = await PortalService.resolve_tenant_id_for_portal_host(db, payload.portal_host)
        if not tenant_id and PortalService._requires_configured_tenant(payload.portal_host):
            return None, None, None
        if (
            settings.PORTAL_DEV_CLAIM_REFERENCE_ONLY_AUTH
            and payload.claim_reference
            and not payload.tax_code
            and not payload.full_name
            and not payload.phone_number
        ):
            claim = await PortalService._find_claim_by_reference(db, payload.claim_reference, tenant_id)
            if not claim:
                return None, None, None

            access = await PortalService._ensure_dev_access_for_claim(db, claim)
            challenge, raw_token = await PortalService.create_magic_link_challenge(
                db,
                access,
                delivery_channel="email",
                metadata_json={
                    "issued_via": "dev_claim_reference_only_auth",
                    "portal_host": PortalService.normalize_portal_host(payload.portal_host),
                },
            )
            access.last_delivery_status = "development_preview_only"
            await db.commit()
            await db.refresh(challenge)
            return access, challenge, raw_token

        conditions = [PortalClaimAccess.status == "active"]
        if tenant_id:
            conditions.append(PortalClaimAccess.tenant_id == tenant_id)
            conditions.append(Claim.tenant_id == tenant_id)
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
            metadata_json={
                "issued_via": "public_auth_start",
                "portal_host": PortalService.normalize_portal_host(payload.portal_host),
            },
        )
        access.last_delivery_status = "pending_integration"
        await db.commit()
        await db.refresh(challenge)
        return access, challenge, raw_token

    @staticmethod
    async def exchange_magic_token(
        db: AsyncSession,
        token: str,
        portal_host: str | None = None,
    ) -> tuple[PortalClaimAccess, str, int]:
        hashed = hash_secret(token)
        now = datetime.now(timezone.utc)
        tenant_id = await PortalService.resolve_tenant_id_for_portal_host(db, portal_host)
        if not tenant_id and PortalService._requires_configured_tenant(portal_host):
            raise ValueError("Invalid portal tenant")
        conditions = [
            PortalAuthChallenge.token_hash == hashed,
            PortalAuthChallenge.status == "pending",
            PortalAuthChallenge.expires_at >= now,
            PortalClaimAccess.status == "active",
        ]
        if tenant_id:
            conditions.append(PortalAuthChallenge.tenant_id == tenant_id)
            conditions.append(PortalClaimAccess.tenant_id == tenant_id)
        result = await db.execute(
            select(PortalAuthChallenge, PortalClaimAccess)
            .join(PortalClaimAccess, PortalClaimAccess.id == PortalAuthChallenge.portal_access_id)
            .where(and_(*conditions))
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
        claim_id: str | None = None,
    ) -> PortalClaimAccess:
        target_claim_id = claim_id or session.claim_id
        if target_claim_id == session.claim_id:
            result = await db.execute(
                select(PortalClaimAccess).where(
                    PortalClaimAccess.id == session.portal_access_id,
                    PortalClaimAccess.tenant_id == session.tenant_id,
                    PortalClaimAccess.claim_id == session.claim_id,
                )
            )
            anchor_access = result.scalar_one_or_none()
            if anchor_access:
                return anchor_access

        accessible_accesses = await PortalService.list_accessible_claim_accesses(db, session)
        for access in accessible_accesses:
            if access.claim_id == target_claim_id:
                return access

        raise ValueError("Claim not accessible from portal session")

    @staticmethod
    async def list_accessible_claim_accesses(
        db: AsyncSession,
        session: PortalSessionContext,
    ) -> list[PortalClaimAccess]:
        result = await db.execute(
            select(PortalClaimAccess).where(
                PortalClaimAccess.id == session.portal_access_id,
                PortalClaimAccess.tenant_id == session.tenant_id,
                PortalClaimAccess.claim_id == session.claim_id,
            )
        )
        anchor_access = result.scalar_one()

        identity_clauses = []
        if anchor_access.tax_code_hash:
            identity_clauses.append(PortalClaimAccess.tax_code_hash == anchor_access.tax_code_hash)
        if anchor_access.email:
            identity_clauses.append(PortalClaimAccess.email == anchor_access.email)
        if anchor_access.normalized_full_name and anchor_access.normalized_phone_number:
            identity_clauses.append(
                and_(
                    PortalClaimAccess.normalized_full_name == anchor_access.normalized_full_name,
                    PortalClaimAccess.normalized_phone_number == anchor_access.normalized_phone_number,
                )
            )

        if not identity_clauses:
            return [anchor_access]

        result = await db.execute(
            select(PortalClaimAccess)
            .where(
                PortalClaimAccess.tenant_id == session.tenant_id,
                PortalClaimAccess.status == "active",
                PortalClaimAccess.role == anchor_access.role,
                or_(*identity_clauses),
            )
            .order_by(
                PortalClaimAccess.is_primary.desc(),
                PortalClaimAccess.last_authenticated_at.desc().nullslast(),
                PortalClaimAccess.created_at.desc(),
            )
        )
        unique_by_claim: dict[str, PortalClaimAccess] = {}
        for access in result.scalars().all():
            unique_by_claim.setdefault(access.claim_id, access)
        return list(unique_by_claim.values())

    @staticmethod
    async def resolve_claim_for_session(
        db: AsyncSession,
        session: PortalSessionContext,
        claim_id: str | None = None,
    ) -> tuple[Claim, PortalClaimAccess]:
        access = await PortalService.get_access(db, session, claim_id)
        claim = await PortalService.get_claim_for_tenant(db, access.tenant_id, access.claim_id)
        if not claim:
            raise ValueError("Claim not found")
        return claim, access

    @staticmethod
    async def list_accessible_claims(
        db: AsyncSession,
        session: PortalSessionContext,
    ) -> list[dict]:
        accesses = await PortalService.list_accessible_claim_accesses(db, session)
        claim_ids = [access.claim_id for access in accesses]
        if not claim_ids:
            return []

        claims_result = await db.execute(
            select(Claim)
            .where(Claim.tenant_id == session.tenant_id, Claim.id.in_(claim_ids))
            .order_by(Claim.updated_at.desc(), Claim.created_at.desc())
        )
        claims_by_id = {claim.id: claim for claim in claims_result.scalars().all()}

        items: list[dict] = []
        for access in accesses:
            claim = claims_by_id.get(access.claim_id)
            if not claim:
                continue
            macro_state = PortalStatusService.build_macro_state(claim.stato_corrente)
            items.append(
                {
                    "claim_id": claim.id,
                    "tenant_id": claim.tenant_id,
                    "external_ref": claim.external_ref,
                    "numero_sinistro": claim.numero_sinistro,
                    "compagnia": claim.compagnia,
                    "nome_assicurato": claim.nome_assicurato,
                    "data_sinistro": claim.data_sinistro,
                    "updated_at": claim.updated_at,
                    "macro_state": macro_state,
                    "has_pending_actions": bool(macro_state.get("needs_action")),
                    "requested_amount": PortalService._amount_to_float(claim.richiesta),
                    "liquidated_amount": PortalService._amount_to_float(claim.liquidato),
                    "estimated_damage_amount": PortalService._amount_to_float(claim.stima_danno),
                }
            )

        items.sort(
            key=lambda item: (
                not item["has_pending_actions"],
                item["updated_at"] or datetime.min.replace(tzinfo=timezone.utc),
            ),
            reverse=False,
        )
        return items

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
        inspection_preferences = InspectionWorkflowService._preferences_metadata(claim)
        inspection_selected_slots = InspectionWorkflowService._selected_slot_payload(inspection_preferences)
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
                    "description": "Per proseguire con la perizia e arrivare alla liquidazione servirà l'IBAN intestato al contraente di polizza.",
                }
            )
        if claim.stato_corrente in {"SV052", "SV053"}:
            requirements.append(
                {
                    "key": "inspection_scheduling",
                    "label": "Sopralluogo da organizzare",
                    "status": "pending_confirmation" if inspection_selected_slots else "required",
                    "description": (
                        "Abbiamo registrato le tue preferenze: il sopralluogo resta in attesa di conferma."
                        if inspection_selected_slots
                        else "Conferma posizione e scegli una o piu fasce orarie per il sopralluogo."
                    ),
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
        claim_id: str | None = None,
    ) -> dict:
        claim, _ = await PortalService.resolve_claim_for_session(db, session, claim_id)

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
            "inspection_scheduling_enabled": claim.stato_corrente in {"SV052", "SV053", "SV050"},
            "requested_amount": PortalService._amount_to_float(claim.richiesta),
            "liquidated_amount": PortalService._amount_to_float(claim.liquidato),
            "estimated_damage_amount": PortalService._amount_to_float(claim.stima_danno),
            "act_sent_at": claim.data_invio_atto,
            "act_signed_at": claim.data_ritorno_atto,
            "contraente_name": claim.nome_contraente,
            "iban_value_masked": PortalService._mask_iban_value(claim.iban_value),
            "iban_required_for_progress": True,
            "document_collection_draft": PortalService._document_collection_draft_info(claim),
            "additional_document_requests": PortalService._portal_additional_document_requests(claim),
            "act_flow": PortalService._build_act_flow(claim),
        }

    @staticmethod
    async def list_timeline(
        db: AsyncSession,
        session: PortalSessionContext,
        claim_id: str | None = None,
        limit: int = 25,
    ) -> list[dict]:
        claim, _ = await PortalService.resolve_claim_for_session(db, session, claim_id)
        event_labels = {
            "inspection_scheduling_requested": "Richiesta fissazione sopralluogo",
            "inspection_location_confirmed": "Posizione sopralluogo confermata",
            "inspection_preferences_confirmed": "Preferenze sopralluogo inviate",
            "inspection_route_proposed": "Proposta CAT in revisione",
            "inspection_appointment_confirmed": "Sopralluogo confermato",
        }
        result = await db.execute(
            select(ClaimEvent)
            .where(
                ClaimEvent.tenant_id == session.tenant_id,
                ClaimEvent.claim_id == claim.id,
            )
            .order_by(ClaimEvent.event_time.desc())
            .limit(limit)
        )
        items = []
        for event in result.scalars().all():
            label = event_labels.get(event.event_type, event.event_type.replace("_", " ").capitalize())
            description = None
            if event.event_type == "state_changed":
                data = event.data_json or {}
                description = f"{data.get('from', 'n/d')} -> {data.get('to', 'n/d')}"
            elif event.event_type == "inspection_scheduling_requested":
                description = "Conferma il punto di incontro e scegli una o piu fasce da due ore."
            elif event.event_type == "inspection_preferences_confirmed":
                description = "Le tue finestre preferite sono state inoltrate al sistema appuntamenti."
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
        claim_id: str | None = None,
        limit: int = 100,
    ) -> list[dict]:
        claim, _ = await PortalService.resolve_claim_for_session(db, session, claim_id)
        result = await db.execute(
            select(Document)
            .where(
                Document.tenant_id == session.tenant_id,
                Document.claim_id == claim.id,
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
    async def get_claim_document_file(
        db: AsyncSession,
        session: PortalSessionContext,
        document_id: str,
        claim_id: str | None = None,
    ) -> Document:
        claim, _ = await PortalService.resolve_claim_for_session(db, session, claim_id)
        result = await db.execute(
            select(Document).where(
                Document.id == document_id,
                Document.tenant_id == session.tenant_id,
                Document.claim_id == claim.id,
            )
        )
        document = result.scalar_one_or_none()
        if not document:
            raise ValueError("Documento non trovato.")
        return document

    @staticmethod
    def _parse_iso_date(raw_value: str) -> date:
        return date.fromisoformat(raw_value)

    @staticmethod
    def _parse_iso_time(raw_value: str) -> time:
        return time.fromisoformat(raw_value)

    @staticmethod
    async def get_inspection_scheduling_overview(
        db: AsyncSession,
        session: PortalSessionContext,
        claim_id: str | None = None,
    ) -> dict:
        claim, _ = await PortalService.resolve_claim_for_session(db, session, claim_id)
        return await InspectionWorkflowService.get_portal_scheduling_overview(
            db,
            session.tenant_id,
            claim.id,
        )

    @staticmethod
    async def update_inspection_location(
        db: AsyncSession,
        session: PortalSessionContext,
        payload: PortalInspectionLocationUpdateRequest,
        claim_id: str | None = None,
    ) -> dict:
        claim, _ = await PortalService.resolve_claim_for_session(db, session, claim_id)
        await InspectionWorkflowService.upsert_portal_location(
            db,
            session.tenant_id,
            claim.id,
            address_line=payload.address_line,
            municipality=payload.municipality,
            province=payload.province,
            region=payload.region,
            latitude=payload.latitude,
            longitude=payload.longitude,
        )
        return await PortalService.get_inspection_scheduling_overview(db, session, claim.id)

    @staticmethod
    async def submit_inspection_preferences(
        db: AsyncSession,
        session: PortalSessionContext,
        payload: PortalInspectionPreferencesUpdateRequest,
        claim_id: str | None = None,
    ) -> dict:
        claim, _ = await PortalService.resolve_claim_for_session(db, session, claim_id)
        selected_slots: list[InspectionPreferredSlotInput] = []
        for raw_slot in payload.selected_slots:
            selected_slots.append(
                InspectionPreferredSlotInput(
                    date=PortalService._parse_iso_date(raw_slot.date),
                    start_time=PortalService._parse_iso_time(raw_slot.start_time),
                    end_time=PortalService._parse_iso_time(raw_slot.end_time),
                    label=raw_slot.label,
                )
            )

        await InspectionWorkflowService.submit_portal_preferences(
            db,
            session.tenant_id,
            claim.id,
            selected_slots=selected_slots,
            notes=payload.notes,
            requested_duration_minutes=payload.requested_duration_minutes,
        )
        return await PortalService.get_inspection_scheduling_overview(db, session, claim.id)

    @staticmethod
    async def create_upload_intent(
        db: AsyncSession,
        session: PortalSessionContext,
        payload: PortalUploadIntentCreate,
        claim_id: str | None = None,
    ) -> dict:
        claim, access = await PortalService.resolve_claim_for_session(db, session, claim_id)
        document_id = str(uuid.uuid4())
        storage_path = f"portal/{session.tenant_id}/{claim.id}/{document_id}/{payload.file_name}"
        document = Document(
            id=document_id,
            tenant_id=session.tenant_id,
            claim_id=claim.id,
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
            metadata_json={"portal_access_id": access.id},
        )
        db.add(document)
        await PortalService._create_claim_event(
            db,
            session.tenant_id,
            claim.id,
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
    async def get_document_collection_draft(
        db: AsyncSession,
        session: PortalSessionContext,
        claim_id: str | None = None,
    ) -> dict:
        claim, _ = await PortalService.resolve_claim_for_session(db, session, claim_id)
        draft = PortalService._document_collection_draft_payload(claim)
        return {
            "status": str(draft.get("status") or "not_started"),
            "draft_json": draft,
            "updated_at": PortalService._parse_iso_datetime(draft.get("updated_at"))
            if isinstance(draft.get("updated_at"), str)
            else None,
        }

    @staticmethod
    async def save_document_collection_draft(
        db: AsyncSession,
        session: PortalSessionContext,
        draft_json: dict,
        claim_id: str | None = None,
    ) -> dict:
        claim, access = await PortalService.resolve_claim_for_session(db, session, claim_id)
        existing_draft = PortalService._document_collection_draft_payload(claim)
        merged = PortalService._merge_document_collection_draft(existing_draft, draft_json or {})
        merged["status"] = "draft"
        merged["updated_at"] = datetime.now(timezone.utc).isoformat()
        merged["portal_access_id"] = access.id
        claim.metadata_json = PortalService._merge_metadata(
            claim.metadata_json,
            portal_document_collection_draft=merged,
        )
        claim.updated_at = datetime.now(timezone.utc)
        await PortalService._create_claim_event(
            db,
            session.tenant_id,
            claim.id,
            "portal_document_collection_draft_saved",
            "portal",
            {
                "step_kind": merged.get("step_kind"),
                "inventory_count": merged.get("inventory_count"),
            },
        )
        await db.commit()
        return {
            "status": "draft",
            "draft_json": merged,
            "updated_at": PortalService._parse_iso_datetime(merged.get("updated_at")),
        }

    @staticmethod
    async def submit_document_collection(
        db: AsyncSession,
        session: PortalSessionContext,
        payload: PortalDocumentCollectionSubmissionCreate,
        claim_id: str | None = None,
    ) -> PortalDocumentCollectionSubmission:
        claim, access = await PortalService.resolve_claim_for_session(db, session, claim_id)
        confirmations = PortalService._validate_document_collection_confirmations(payload.metadata_json)
        insured_folder = await PortalService._ensure_insured_claim_folder(db, session.tenant_id, claim)
        submission = PortalDocumentCollectionSubmission(
            id=str(uuid.uuid4()),
            tenant_id=session.tenant_id,
            claim_id=claim.id,
            portal_access_id=access.id,
            status="submitted",
            payload_json=payload.model_dump(),
            metadata_json=payload.metadata_json,
        )
        db.add(submission)

        metadata = dict(payload.metadata_json or {})
        raw_upload_registrations = metadata.get("upload_intents")
        upload_registrations = raw_upload_registrations if isinstance(raw_upload_registrations, list) else []
        uploaded_documents: list[dict] = []
        if upload_registrations:
            document_ids = [
                str(item.get("document_id"))
                for item in upload_registrations
                if isinstance(item, dict) and item.get("document_id")
            ]
            if document_ids:
                result = await db.execute(
                    select(Document).where(
                        Document.tenant_id == session.tenant_id,
                        Document.claim_id == claim.id,
                        Document.id.in_(document_ids),
                    )
                )
                documents_by_id = {document.id: document for document in result.scalars().all()}
                for registration in upload_registrations:
                    if not isinstance(registration, dict):
                        continue
                    document = documents_by_id.get(str(registration.get("document_id")))
                    if not document:
                        continue
                    tags = PortalService._build_document_collection_tags(registration)
                    document.folder_id = insured_folder.id
                    document.logical_path = f"{insured_folder.path}/{document.file_name}"
                    document.tags_json = tags
                    document.metadata_json = PortalService._merge_metadata(
                        document.metadata_json,
                        portal_access_id=access.id,
                        audience="insured",
                        workflow="documentale_guidata",
                        insured_document_kind=registration.get("kind"),
                        insured_item_label=registration.get("item_label"),
                        insured_component_name=registration.get("component_name"),
                    )
                    uploaded_documents.append(
                        {
                            "document_id": document.id,
                            "file_name": document.file_name,
                            "category": document.category,
                            "status": document.status,
                            "tags": tags,
                            "kind": registration.get("kind"),
                        }
                    )

        claim.foto = payload.photos_count > 0 or claim.foto
        claim.giustificativi = any(
            item.get("kind") == "repair_receipt"
            for item in upload_registrations
            if isinstance(item, dict)
        ) or claim.giustificativi
        claim.oltre_dieci_beni = len(payload.items) > 10
        claim.updated_at = datetime.now(timezone.utc)
        claim.metadata_json = PortalService._merge_metadata(
            claim.metadata_json,
            portal_document_collection={
                "submitted_at": datetime.now(timezone.utc).isoformat(),
                "status": "documentazione_ricevuta",
                "folder_id": insured_folder.id,
                "folder_path": insured_folder.path,
                "confirmations": confirmations,
                "items": [item.model_dump() for item in payload.items],
                "notes": payload.notes,
                "photos_count": payload.photos_count,
                "uploaded_documents": uploaded_documents,
                "wizard_metadata": {
                    key: value
                    for key, value in metadata.items()
                    if key not in {"upload_intents"}
                },
            },
            document_collection_status="documentazione_ricevuta",
            numero_beni=len(payload.items),
            portal_document_collection_draft={
                **PortalService._merge_document_collection_draft(
                    PortalService._document_collection_draft_payload(claim),
                    metadata.get("draft_snapshot") if isinstance(metadata.get("draft_snapshot"), dict) else {},
                ),
                "status": "submitted",
                "submitted_at": datetime.now(timezone.utc).isoformat(),
                "updated_at": datetime.now(timezone.utc).isoformat(),
            },
        )

        await PortalService._create_claim_event(
            db,
            session.tenant_id,
            claim.id,
            "portal_document_collection_submitted",
            "portal",
            {
                "submission_id": submission.id,
                "photos_count": payload.photos_count,
                "document_count": len(uploaded_documents),
                "folder_path": insured_folder.path,
            },
        )
        await db.flush()

        if claim and claim.stato_corrente in {"SV002", "SV022", "SV023"}:
            await StateService.transition_state(
                db,
                session.tenant_id,
                claim.id,
                claim.stato_corrente,
                "SV010",
                None,
                "Portal document collection submitted",
                {
                    "submission_id": submission.id,
                    "document_collection_status": "documentazione_ricevuta",
                    "workflow_label": "perizia da eseguire (documentale)",
                },
            )
        else:
            await db.commit()

        if settings.FF_PORTAL_PHOTO_AI_ANALYSIS_ENABLED and payload.photos_count > 0:
            await PortalService._enqueue_photo_analysis_job(
                db,
                tenant_id=session.tenant_id,
                claim=claim,
                upload_registrations=upload_registrations,
                submission_id=submission.id,
            )
            await db.commit()

        await db.refresh(submission)
        return submission

    @staticmethod
    async def _enqueue_photo_analysis_job(
        db: AsyncSession,
        *,
        tenant_id: str,
        claim: Claim,
        upload_registrations: list[dict],
        submission_id: str,
    ) -> None:
        """
        Build the input payload for ai_asset_photo_analysis and enqueue it.

        For each uploaded photo we include a signed Supabase URL (or a flag that
        the worker should fetch via the vault API if Supabase is not configured).
        """
        photo_kinds = {
            "building_photo", "whole_item_photo", "component_photo", "video",
        }
        photo_entries: list[dict] = []

        if upload_registrations:
            from sqlalchemy import select as sa_select
            from app.models.document import Document as DocumentModel

            doc_ids = [
                str(r.get("document_id"))
                for r in upload_registrations
                if isinstance(r, dict) and r.get("document_id") and r.get("kind") in photo_kinds
            ]
            if not doc_ids:
                return

            result = await db.execute(
                sa_select(DocumentModel).where(
                    DocumentModel.tenant_id == tenant_id,
                    DocumentModel.claim_id == claim.id,
                    DocumentModel.id.in_(doc_ids),
                    DocumentModel.status == "uploaded",
                )
            )
            docs_by_id = {d.id: d for d in result.scalars().all()}

            for reg in upload_registrations:
                if not isinstance(reg, dict) or reg.get("kind") not in photo_kinds:
                    continue
                doc = docs_by_id.get(str(reg.get("document_id")))
                if not doc:
                    continue

                entry: dict = {
                    "document_id": doc.id,
                    "file_name": doc.file_name,
                    "mime_type": doc.mime_type,
                    "kind": reg.get("kind"),
                    "item_label": reg.get("item_label"),
                    "component_name": reg.get("component_name"),
                    "storage_provider": doc.storage_provider,
                    "storage_bucket": doc.storage_bucket,
                    "storage_path": doc.storage_path,
                    "download_url": None,
                }

                if doc.storage_provider == "supabase" and SupabaseStorageService.is_configured():
                    try:
                        entry["download_url"] = await SupabaseStorageService.create_signed_url(
                            doc.storage_path,
                            expires_in_seconds=settings.PORTAL_PHOTO_SIGNED_URL_EXPIRE_SECONDS,
                        )
                    except Exception:
                        pass  # worker falls back to vault API

                photo_entries.append(entry)

        if not photo_entries:
            return

        await ProcessJobService.enqueue(
            db,
            tenant_id=tenant_id,
            claim_id=claim.id,
            job_type="ai_asset_photo_analysis",
            priority=5,
            max_retries=3,
            idempotency_key=f"photo_analysis_{submission_id}",
            input_json={
                "submission_id": submission_id,
                "claim_id": claim.id,
                "tenant_id": tenant_id,
                "claim_ref": claim.external_ref or claim.numero_sinistro or claim.id,
                "garanzia": claim.garanzia,
                "photos": photo_entries,
            },
            tags_json={"source": "portal_document_collection"},
        )

    @staticmethod
    async def submit_bank_account(
        db: AsyncSession,
        session: PortalSessionContext,
        payload: PortalBankAccountSubmissionCreate,
        claim_id: str | None = None,
    ) -> tuple[PortalBankAccountSubmission, dict]:
        claim, access = await PortalService.resolve_claim_for_session(db, session, claim_id)
        validation = IbanService.validate(payload.iban)
        submission = PortalBankAccountSubmission(
            id=str(uuid.uuid4()),
            tenant_id=session.tenant_id,
            claim_id=claim.id,
            portal_access_id=access.id,
            iban=validation["normalized_iban"],
            account_holder=claim.nome_contraente or payload.account_holder,
            validation_status="valid" if validation["is_valid"] else "invalid",
            bank_name=validation.get("abi"),
            branch_name=validation.get("cab"),
            is_selected=True,
            metadata_json=validation,
        )
        db.add(submission)

        if validation["is_valid"]:
            claim.iban = True
            claim.iban_value = validation["normalized_iban"]
            claim.updated_at = datetime.now(timezone.utc)
            claim.metadata_json = PortalService._merge_metadata(
                claim.metadata_json,
                portal_iban_workflow={
                    "status": "provided",
                    "provided_at": datetime.now(timezone.utc).isoformat(),
                    "contraente_required": True,
                    "contraente_name": claim.nome_contraente,
                    "validation": validation,
                },
            )

        await PortalService._create_claim_event(
            db,
            session.tenant_id,
            claim.id,
            "portal_iban_submitted",
            "portal",
            {"submission_id": submission.id, "valid": validation["is_valid"]},
        )
        await db.commit()
        await db.refresh(submission)
        return submission, validation

    @staticmethod
    async def submit_additional_documents(
        db: AsyncSession,
        session: PortalSessionContext,
        *,
        note: str | None,
        document_ids: list[str],
        requested_items: list[str],
        claim_id: str | None = None,
    ) -> dict:
        claim, access = await PortalService.resolve_claim_for_session(db, session, claim_id)
        insured_folder = await PortalService._ensure_insured_claim_folder(db, session.tenant_id, claim)
        result = await db.execute(
            select(Document).where(
                Document.tenant_id == session.tenant_id,
                Document.claim_id == claim.id,
                Document.id.in_(document_ids or []),
            )
        )
        documents = result.scalars().all()
        normalized_requested = [item.strip() for item in requested_items if item and item.strip()]
        for document in documents:
            tags = list(dict.fromkeys([*(document.tags_json or []), "da assicurato", "documentazione aggiuntiva"]))
            document.folder_id = insured_folder.id
            document.logical_path = f"{insured_folder.path}/{document.file_name}"
            document.tags_json = tags
            document.metadata_json = PortalService._merge_metadata(
                document.metadata_json,
                portal_access_id=access.id,
                audience="insured",
                workflow="documentazione_aggiuntiva",
                requested_items=normalized_requested,
                note=note,
            )

        existing_submissions = (claim.metadata_json or {}).get("portal_additional_documents") or []
        if not isinstance(existing_submissions, list):
            existing_submissions = []
        existing_submissions.append(
            {
                "submitted_at": datetime.now(timezone.utc).isoformat(),
                "portal_access_id": access.id,
                "document_ids": [document.id for document in documents],
                "requested_items": normalized_requested,
                "note": note,
            }
        )
        claim.metadata_json = PortalService._merge_metadata(
            claim.metadata_json,
            portal_additional_documents=existing_submissions,
        )
        claim.updated_at = datetime.now(timezone.utc)
        await PortalService._create_claim_event(
            db,
            session.tenant_id,
            claim.id,
            "portal_additional_documents_submitted",
            "portal",
            {"document_count": len(documents), "requested_items": normalized_requested},
        )
        await db.commit()
        return {
            "status": "submitted",
            "submitted_at": datetime.now(timezone.utc),
            "document_count": len(documents),
        }

    @staticmethod
    async def update_additional_document_requests(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
        items: list[str],
    ) -> dict:
        claim = await PortalService.get_claim_for_tenant(db, tenant_id, claim_id)
        if not claim:
            raise ValueError("Claim not found")
        normalized = [item.strip() for item in items if item and item.strip()]
        claim.metadata_json = PortalService._merge_metadata(
            claim.metadata_json,
            portal_additional_document_requests=normalized,
        )
        claim.updated_at = datetime.now(timezone.utc)
        await db.commit()
        return {"items": normalized}

    @staticmethod
    async def update_act_flow(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
        payload: dict,
    ) -> dict:
        claim = await PortalService.get_claim_for_tenant(db, tenant_id, claim_id)
        if not claim:
            raise ValueError("Claim not found")
        existing = dict((claim.metadata_json or {}).get("portal_act_flow") or {})
        next_payload = {
            **existing,
            **payload,
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }
        claim.metadata_json = PortalService._merge_metadata(
            claim.metadata_json,
            portal_act_flow=next_payload,
        )
        claim.updated_at = datetime.now(timezone.utc)
        await db.commit()
        return PortalService._build_act_flow(claim) or {
            "status": next_payload.get("status") or "pending_external_signature",
            "label": "Firma atto",
        }

    @staticmethod
    async def process_signature_provider_webhook(
        db: AsyncSession,
        payload: dict,
    ) -> dict:
        claim: Claim | None = None
        request_id = payload.get("request_id")
        provider_reference = payload.get("provider_reference")
        if payload.get("claim_id"):
            result = await db.execute(select(Claim).where(Claim.id == payload["claim_id"]))
            claim = result.scalar_one_or_none()

        if claim is None and request_id:
            result = await db.execute(
                select(Claim).where(
                    func.json_extract_path_text(Claim.metadata_json, "portal_act_flow", "request_id") == str(request_id)
                )
            )
            claim = result.scalar_one_or_none()

        if claim is None and provider_reference:
            result = await db.execute(
                select(Claim).where(
                    func.json_extract_path_text(Claim.metadata_json, "portal_act_flow", "provider_reference")
                    == str(provider_reference)
                )
            )
            claim = result.scalar_one_or_none()

        if claim is None:
            raise ValueError("Claim not found")

        next_payload = {
            **dict((claim.metadata_json or {}).get("portal_act_flow") or {}),
            **payload,
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }
        claim.metadata_json = PortalService._merge_metadata(
            claim.metadata_json,
            portal_act_flow=next_payload,
        )
        claim.updated_at = datetime.now(timezone.utc)

        status = str(payload.get("status") or "")
        if status in {"signed", "signed_by_insured"} and claim.stato_corrente in {"SV030", "SV031"}:
            await StateService.transition_state(
                db,
                claim.tenant_id,
                claim.id,
                claim.stato_corrente,
                "SV032",
                None,
                "External act signature confirmed",
                {"provider_reference": provider_reference, "request_id": request_id},
                event_source="portal_webhook",
            )
        else:
            await db.commit()

        refreshed = await PortalService.get_claim_for_tenant(db, claim.tenant_id, claim.id)
        return PortalService._build_act_flow(refreshed or claim) or {
            "status": status or "pending_external_signature",
            "label": "Firma atto",
        }

    @staticmethod
    async def get_or_create_conversation(
        db: AsyncSession,
        session: PortalSessionContext,
        access: PortalClaimAccess,
        claim_id: str,
    ) -> PortalConversation:
        result = await db.execute(
            select(PortalConversation).where(
                PortalConversation.tenant_id == session.tenant_id,
                PortalConversation.claim_id == claim_id,
                PortalConversation.portal_access_id == access.id,
                PortalConversation.status == "active",
            )
        )
        conversation = result.scalar_one_or_none()
        if conversation:
            return conversation

        conversation = PortalConversation(
            id=str(uuid.uuid4()),
            tenant_id=session.tenant_id,
            claim_id=claim_id,
            portal_access_id=access.id,
            status="active",
            metadata_json={"source": "portal"},
        )
        db.add(conversation)
        await db.flush()

        expert, _, _ = await PortalService.get_assigned_expert(db, claim_id, session.tenant_id)
        thread = InternalChatThread(
            id=str(uuid.uuid4()),
            tenant_id=session.tenant_id,
            claim_id=claim_id,
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
        claim_id: str | None = None,
    ) -> list[dict]:
        claim, access = await PortalService.resolve_claim_for_session(db, session, claim_id)
        result = await db.execute(
            select(PortalConversationMessage)
            .join(PortalConversation, PortalConversation.id == PortalConversationMessage.conversation_id)
            .where(
                PortalConversation.tenant_id == session.tenant_id,
                PortalConversation.claim_id == claim.id,
                PortalConversation.portal_access_id == access.id,
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
        claim_id: str | None = None,
    ) -> PortalConversationMessage:
        claim, access = await PortalService.resolve_claim_for_session(db, session, claim_id)
        conversation = await PortalService.get_or_create_conversation(db, session, access, claim.id)

        internal_message_id = None
        if conversation.internal_thread_id:
            internal_message = InternalChatMessage(
                id=str(uuid.uuid4()),
                tenant_id=session.tenant_id,
                thread_id=conversation.internal_thread_id,
                claim_id=claim.id,
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
            claim_id=claim.id,
            author_type="portal",
            body_text=payload.body_text,
            internal_chat_message_id=internal_message_id,
            metadata_json={"portal_access_id": access.id},
        )
        db.add(message)
        await PortalService._create_claim_event(
            db,
            session.tenant_id,
            claim.id,
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
        claim_id: str | None = None,
    ) -> tuple[PortalSignatureRequest, str]:
        claim, access = await PortalService.resolve_claim_for_session(db, session, claim_id)
        document_result = await db.execute(
            select(Document).where(
                Document.id == payload.document_id,
                Document.tenant_id == session.tenant_id,
                Document.claim_id == claim.id,
            )
        )
        document = document_result.scalar_one_or_none()
        if not document:
            raise ValueError("Document not found for claim")

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
            claim_id=claim.id,
            portal_access_id=access.id,
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
            claim.id,
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
        claim_id: str | None = None,
    ) -> PortalSignatureRequest:
        claim, access = await PortalService.resolve_claim_for_session(db, session, claim_id)
        hashed = hash_secret(token)
        result = await db.execute(
            select(PortalSignatureRequest, PortalAuthChallenge)
            .join(PortalAuthChallenge, PortalAuthChallenge.id == PortalSignatureRequest.challenge_id)
            .where(
                PortalSignatureRequest.id == request_id,
                PortalSignatureRequest.tenant_id == session.tenant_id,
                PortalSignatureRequest.claim_id == claim.id,
                PortalSignatureRequest.portal_access_id == access.id,
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

        claim.data_ritorno_atto = now

        await PortalService._create_claim_event(
            db,
            session.tenant_id,
            claim.id,
            "portal_signature_confirmed",
            "portal",
            {"signature_request_id": signature_request.id, "document_id": signature_request.document_id},
        )
        await db.flush()

        if claim and claim.stato_corrente in {"SV030", "SV031"}:
            await StateService.transition_state(
                db,
                session.tenant_id,
                claim.id,
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
