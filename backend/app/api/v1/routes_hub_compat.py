"""
Compatibility routes for legacy Hub clients now backed by FastAPI.
"""
from __future__ import annotations

import base64
import hashlib
import json
import mimetypes
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db
from app.core.security import get_current_active_user
from app.models.claim import Claim
from app.models.claim_event import ClaimEvent
from app.models.document import Document
from app.models.document_version import DocumentVersion
from app.models.email import Email, EmailClaimLink
from app.models.user import User
from app.models.whatsapp import WhatsAppAccount, WhatsAppMessage, WhatsAppThread
from app.services.vault_storage_service import VaultStorageService

router = APIRouter()


class HeartbeatRequest(BaseModel):
    user_id: str
    client_info: Optional[str] = None


class FileUploadRequest(BaseModel):
    filename: str
    folder: str = ""
    data: str
    mimeType: Optional[str] = None


class EmailSendRequest(BaseModel):
    accountId: str
    to: list[str]
    cc: list[str] | None = None
    bcc: list[str] | None = None
    subject: str
    body: str
    isHtml: bool = True
    replyToThreadId: Optional[str] = None
    inReplyTo: Optional[str] = None
    references: Optional[str] = None
    attachments: list[dict] | None = None


class EmailScheduleRequest(BaseModel):
    accountId: str
    to: list[str]
    cc: list[str] | None = None
    subject: str
    body: str
    scheduledFor: datetime
    sinistroRef: Optional[str] = None


class WhatsAppInitRequest(BaseModel):
    phoneNumber: Optional[str] = None


class WhatsAppCheckNumberRequest(BaseModel):
    phoneNumber: str


class WhatsAppSendRequest(BaseModel):
    to: str
    body: str
    media: Optional[dict] = None


class WhatsAppScheduleRequest(BaseModel):
    accountId: str
    phoneNumber: str
    body: str
    scheduledFor: datetime
    sinistroRef: Optional[str] = None
    mediaData: Optional[str] = None
    mediaType: Optional[str] = None
    mediaFilename: Optional[str] = None


class ChatAssociateRequest(BaseModel):
    sinistroRef: str


class VaultRestoreRequest(BaseModel):
    originalPath: Optional[str] = None


def _sha256(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


async def _resolve_claim_or_404(db: AsyncSession, current_user: User, claim_ref: str) -> Claim:
    result = await db.execute(
        select(Claim).where(
            Claim.tenant_id == current_user.tenant_id,
            (Claim.id == claim_ref) | (Claim.external_ref == claim_ref),
        ).order_by(Claim.updated_at.desc(), Claim.created_at.desc())
    )
    claim = result.scalars().first()
    if not claim:
        raise HTTPException(status_code=404, detail="Claim not found")
    return claim


def _claim_ref(claim: Claim) -> str:
    return claim.external_ref or claim.id


def _document_to_vault_dto(document: Document, claim_ref: str) -> dict:
    metadata = document.metadata_json or {}
    return {
        "id": document.id,
        "sinistroRef": claim_ref,
        "filename": document.file_name,
        "folder": metadata.get("hub_folder") or "",
        "size": int(document.size_bytes or 0),
        "mimeType": document.mime_type,
        "checksum": document.checksum_sha256 or document.checksum_md5,
        "createdAt": document.uploaded_at,
        "modifiedAt": document.uploaded_at,
        "status": document.status,
        "logicalPath": document.logical_path,
        "storageProvider": document.storage_provider,
        "versionNo": document.version_no,
    }


def _folder_status_from_documents(claim_ref: str, documents: list[Document]) -> dict:
    total_size = sum(int(item.size_bytes or 0) for item in documents)
    last_sync_at = max((item.uploaded_at for item in documents if item.uploaded_at), default=None)
    return {
        "sinistroRef": claim_ref,
        "status": "available",
        "fileCount": len(documents),
        "totalSize": total_size,
        "lastSyncAt": last_sync_at,
    }


async def _vault_documents(db: AsyncSession, current_user: User, claim: Claim) -> list[Document]:
    result = await db.execute(
        select(Document).where(
            Document.tenant_id == current_user.tenant_id,
            Document.claim_id == claim.id,
            Document.source_type == "hub_vault",
            Document.status == "active",
        ).order_by(Document.uploaded_at.desc())
    )
    return list(result.scalars().all())


async def _trashed_vault_documents(db: AsyncSession, current_user: User, claim: Claim) -> list[Document]:
    result = await db.execute(
        select(Document).where(
            Document.tenant_id == current_user.tenant_id,
            Document.claim_id == claim.id,
            Document.source_type == "hub_vault",
            Document.status == "trashed",
        ).order_by(Document.uploaded_at.desc())
    )
    return list(result.scalars().all())


async def _resolve_document_or_404(db: AsyncSession, current_user: User, file_id: str) -> Document:
    result = await db.execute(
        select(Document).where(
            Document.id == file_id,
            Document.tenant_id == current_user.tenant_id,
        )
    )
    document = result.scalar_one_or_none()
    if not document:
        raise HTTPException(status_code=404, detail="File not found")
    return document


async def _next_document_version_no(db: AsyncSession, document_id: str) -> int:
    result = await db.execute(
        select(func.max(DocumentVersion.version_no)).where(DocumentVersion.document_id == document_id)
    )
    max_value = result.scalar_one_or_none()
    return int(max_value or 0) + 1


async def _snapshot_document_version(
    db: AsyncSession,
    *,
    current_user: User,
    claim_ref: str,
    document: Document,
    reason: str,
) -> DocumentVersion:
    version_no = await _next_document_version_no(db, document.id)
    version_path = VaultStorageService.build_version_relative_path(
        current_user.tenant_id,
        claim_ref,
        document.id,
        version_no,
        document.file_name,
    )
    await VaultStorageService.copy_file(document.storage_path, version_path, overwrite=True)
    version = DocumentVersion(
        id=str(uuid.uuid4()),
        tenant_id=current_user.tenant_id,
        document_id=document.id,
        version_no=version_no,
        storage_path=version_path,
        size_bytes=document.size_bytes,
        checksum_sha256=document.checksum_sha256,
        created_by_user_id=current_user.id,
        metadata_json={
            "reason": reason,
            "document_status": document.status,
            "logical_path": document.logical_path,
            "file_name": document.file_name,
        },
    )
    db.add(version)
    return version


async def _unique_active_file_name(
    db: AsyncSession,
    *,
    tenant_id: str,
    claim_id: str,
    folder: str,
    file_name: str,
) -> str:
    folder = folder.strip().strip("/")
    name = file_name
    counter = 1
    while True:
        logical_path = f"{folder}/{name}" if folder else name
        result = await db.execute(
            select(Document.id).where(
                Document.tenant_id == tenant_id,
                Document.claim_id == claim_id,
                Document.source_type == "hub_vault",
                Document.logical_path == logical_path,
                Document.status == "active",
            )
        )
        if result.scalar_one_or_none() is None:
            return name
        stem, ext = (name.rsplit(".", 1) + [""])[:2] if "." in name else [name, ""]
        name = f"{stem}_{counter}.{ext}" if ext else f"{stem}_{counter}"
        counter += 1


def _trash_item_dto(document: Document, claim_ref: str) -> dict:
    metadata = document.metadata_json or {}
    deleted_at = metadata.get("trashed_at")
    return {
        "id": document.id,
        "sinistroRef": claim_ref,
        "fileName": document.file_name,
        "originalPath": metadata.get("original_logical_path") or document.logical_path,
        "deletedAt": deleted_at,
        "size": int(document.size_bytes or 0),
        "mimeType": document.mime_type,
        "checksum": document.checksum_sha256 or document.checksum_md5,
    }


def _document_version_dto(version: DocumentVersion) -> dict:
    metadata = version.metadata_json or {}
    return {
        "id": version.id,
        "documentId": version.document_id,
        "versionNo": version.version_no,
        "size": int(version.size_bytes or 0),
        "checksum": version.checksum_sha256,
        "createdAt": version.created_at,
        "description": metadata.get("reason"),
        "metadata": metadata,
    }


def _email_metadata(email: Email) -> dict:
    if not email.raw_headers:
        return {}
    try:
        return json.loads(email.raw_headers)
    except json.JSONDecodeError:
        return {}


def _canonical_whatsapp_account_id(current_user: User) -> str:
    email = (current_user.personal_email or current_user.email or "").strip().lower()
    if not email:
        return current_user.id
    return email.split("@", 1)[0]


def _assert_whatsapp_account_owner(current_user: User, account_id: str) -> str:
    normalized = account_id.strip().lower()
    expected = _canonical_whatsapp_account_id(current_user)
    if normalized != expected:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="WhatsApp account does not belong to the authenticated user",
        )
    return normalized


async def _ensure_whatsapp_account(db: AsyncSession, current_user: User, account_id: str) -> WhatsAppAccount:
    account_id = _assert_whatsapp_account_owner(current_user, account_id)
    result = await db.execute(
        select(WhatsAppAccount).where(
            WhatsAppAccount.id == account_id,
            WhatsAppAccount.tenant_id == current_user.tenant_id,
        )
    )
    account = result.scalar_one_or_none()
    if account:
        return account

    account = WhatsAppAccount(
        id=account_id,
        tenant_id=current_user.tenant_id,
        label=account_id,
        provider="fastapi-compat",
        provider_account_ref=account_id,
        status="active",
        metadata_json={},
    )
    db.add(account)
    await db.commit()
    await db.refresh(account)
    return account


async def _find_or_create_thread(
    db: AsyncSession,
    current_user: User,
    account_id: str,
    chat_id: str,
    claim: Claim | None = None,
) -> WhatsAppThread:
    result = await db.execute(
        select(WhatsAppThread).where(
            WhatsAppThread.tenant_id == current_user.tenant_id,
            WhatsAppThread.account_id == account_id,
            WhatsAppThread.external_thread_ref == chat_id,
        )
    )
    thread = result.scalar_one_or_none()
    if thread:
        if claim and thread.claim_id != claim.id:
            thread.claim_id = claim.id
            await db.commit()
        return thread

    thread = WhatsAppThread(
        id=str(uuid.uuid4()),
        tenant_id=current_user.tenant_id,
        claim_id=claim.id if claim else None,
        account_id=account_id,
        external_thread_ref=chat_id,
        contact_name=None,
        contact_phone=chat_id.replace("@c.us", ""),
        status="open",
        metadata_json={},
    )
    db.add(thread)
    await db.commit()
    await db.refresh(thread)
    return thread


async def _whatsapp_message_response(
    db: AsyncSession,
    current_user: User,
    message: WhatsAppMessage,
    thread: WhatsAppThread,
) -> dict:
    claim_ref = None
    if message.claim_id:
        claim_result = await db.execute(
            select(Claim).where(
                Claim.id == message.claim_id,
                Claim.tenant_id == current_user.tenant_id,
            )
        )
        claim = claim_result.scalar_one_or_none()
        claim_ref = _claim_ref(claim) if claim else None
    metadata = message.metadata_json or {}
    body = message.body_text or ""
    return {
        "id": message.id,
        "accountId": thread.account_id or "",
        "chatId": thread.external_thread_ref or thread.id,
        "waMessageId": message.provider_message_id or message.id,
        "fromNumber": thread.contact_phone or "",
        "toNumber": thread.contact_phone,
        "body": body,
        "timestamp": message.sent_at,
        "direction": "out" if message.direction == "outbound" else "in",
        "type": "media" if message.media_document_id else "text",
        "mediaType": metadata.get("media_type"),
        "mediaFilename": metadata.get("media_filename"),
        "hasMedia": bool(message.media_document_id),
        "isRead": bool(message.read_at or message.direction == "outbound"),
        "sinistroRef": claim_ref,
        "ackStatus": 1 if message.status in {"scheduled", "queued"} else 3,
        "ackTimestamp": message.read_at or message.delivered_at,
    }


@router.get("/health")
async def compat_health():
    return {
        "status": "healthy",
        "version": "fastapi-compat",
        "uptime": 0,
        "timestamp": datetime.now(timezone.utc),
    }


@router.post("/heartbeat")
async def heartbeat(
    payload: HeartbeatRequest,
    current_user: User = Depends(get_current_active_user),
):
    return {
        "status": "ok",
        "userId": payload.user_id,
        "tenantId": current_user.tenant_id,
        "timestamp": datetime.now(timezone.utc),
        "clientInfo": payload.client_info,
    }


@router.get("/vault/sinistri/{sinistro_ref}/files")
async def list_vault_files(
    sinistro_ref: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    claim = await _resolve_claim_or_404(db, current_user, sinistro_ref)
    claim_ref = _claim_ref(claim)
    documents = await _vault_documents(db, current_user, claim)
    return [_document_to_vault_dto(document, claim_ref) for document in documents]


@router.get("/vault/sinistri/{sinistro_ref}/status")
async def vault_status(
    sinistro_ref: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    claim = await _resolve_claim_or_404(db, current_user, sinistro_ref)
    documents = await _vault_documents(db, current_user, claim)
    return _folder_status_from_documents(_claim_ref(claim), documents)


@router.post("/vault/sinistri/{sinistro_ref}")
async def create_vault_folder(
    sinistro_ref: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    claim = await _resolve_claim_or_404(db, current_user, sinistro_ref)
    await VaultStorageService.ensure_claim_folder(current_user.tenant_id, _claim_ref(claim))
    documents = await _vault_documents(db, current_user, claim)
    return _folder_status_from_documents(_claim_ref(claim), documents)


@router.post("/vault/sinistri/{sinistro_ref}/upload")
async def upload_vault_file(
    sinistro_ref: str,
    payload: FileUploadRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    claim = await _resolve_claim_or_404(db, current_user, sinistro_ref)
    claim_ref = _claim_ref(claim)
    folder = payload.folder.strip().strip("/")
    content = base64.b64decode(payload.data.encode("utf-8"))
    await VaultStorageService.ensure_claim_folder(current_user.tenant_id, claim_ref)
    document_id = str(uuid.uuid4())
    requested_name = payload.filename or f"{document_id}.bin"
    file_name = await _unique_active_file_name(
        db,
        tenant_id=current_user.tenant_id,
        claim_id=claim.id,
        folder=folder,
        file_name=requested_name,
    )
    relative_path = VaultStorageService.build_relative_path(
        current_user.tenant_id,
        claim_ref,
        folder,
        file_name,
    )

    mime_type = payload.mimeType or mimetypes.guess_type(file_name)[0] or "application/octet-stream"
    stored = await VaultStorageService.upload_bytes(
        tenant_id=current_user.tenant_id,
        claim_ref=claim_ref,
        relative_path=relative_path,
        content=content,
        mime_type=mime_type,
    )
    document = Document(
        id=document_id,
        tenant_id=current_user.tenant_id,
        claim_id=claim.id,
        folder_id=None,
        attachment_id=None,
        source_type="hub_vault",
        source_id=None,
        file_name=file_name,
        original_file_name=requested_name,
        mime_type=stored.mime_type,
        extension=Path(file_name).suffix.lstrip(".") or None,
        size_bytes=stored.size_bytes,
        storage_provider=VaultStorageService.provider_name(),
        storage_bucket=None,
        storage_path=stored.relative_path,
        logical_path=f"{folder}/{file_name}" if folder else file_name,
        checksum_sha256=stored.checksum_sha256,
        checksum_md5=None,
        version_no=1,
        status="active",
        category="vault",
        tags_json=["hub-compat", "vault", "nas" if settings.VAULT_STORAGE_PROVIDER == "mac_mini" else "local-storage"],
        uploaded_by_user_id=current_user.id,
        metadata_json={
            "hub_folder": folder,
            "sinistro_ref": claim_ref,
            "original_logical_path": f"{folder}/{requested_name}" if folder else requested_name,
        },
    )
    db.add(document)
    await db.commit()
    await db.refresh(document)
    return _document_to_vault_dto(document, claim_ref)


@router.get("/vault/files/{file_id}/download")
async def download_vault_file(
    file_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    document = await _resolve_document_or_404(db, current_user, file_id)
    if not document.storage_path:
        raise HTTPException(status_code=404, detail="File content not found")
    try:
        content = await VaultStorageService.download_bytes(document.storage_path)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail="File content not found") from exc

    headers = {
        "Content-Disposition": f'attachment; filename="{document.file_name}"',
        "Content-Length": str(len(content)),
    }
    return Response(content=content, media_type=document.mime_type or "application/octet-stream", headers=headers)


@router.delete("/vault/files/{file_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_vault_file(
    file_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    document = await _resolve_document_or_404(db, current_user, file_id)
    if document.status == "deleted":
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    claim_ref = (document.metadata_json or {}).get("sinistro_ref")
    if not claim_ref and document.claim_id:
        claim_result = await db.execute(select(Claim).where(Claim.id == document.claim_id))
        claim = claim_result.scalar_one_or_none()
        claim_ref = _claim_ref(claim) if claim else document.claim_id
    if not claim_ref:
        claim_ref = document.claim_id or "unknown"

    if document.status != "trashed":
        await _snapshot_document_version(
            db,
            current_user=current_user,
            claim_ref=str(claim_ref),
            document=document,
            reason="trash_before_delete",
        )
        trash_name = f"{int(datetime.now(timezone.utc).timestamp())}_{document.file_name}"
        trash_path = VaultStorageService.build_trash_relative_path(
            current_user.tenant_id,
            str(claim_ref),
            trash_name,
        )
        await VaultStorageService.move_file(document.storage_path, trash_path, overwrite=True)
        metadata = document.metadata_json or {}
        metadata["trashed_at"] = datetime.now(timezone.utc).isoformat()
        metadata["trash_path"] = trash_path
        metadata["original_logical_path"] = metadata.get("original_logical_path") or document.logical_path
        metadata["trash_file_name"] = trash_name
        document.storage_path = trash_path
        document.status = "trashed"
        document.metadata_json = metadata
    else:
        await VaultStorageService.delete_file(document.storage_path, missing_ok=True)
        document.status = "deleted"

    await db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/vault/files/{file_id}/export")
async def export_vault_file(
    file_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    document = await _resolve_document_or_404(db, current_user, file_id)
    metadata = document.metadata_json or {}
    claim_ref = metadata.get("sinistro_ref")
    if not claim_ref and document.claim_id:
        claim_result = await db.execute(select(Claim).where(Claim.id == document.claim_id))
        claim = claim_result.scalar_one_or_none()
        claim_ref = _claim_ref(claim) if claim else document.claim_id
    claim_ref = str(claim_ref or document.claim_id or "unknown")
    export_path = VaultStorageService.build_relative_path(
        current_user.tenant_id,
        claim_ref,
        "_export",
        document.file_name,
    )
    await VaultStorageService.move_file(document.storage_path, export_path, overwrite=True)

    metadata["hub_folder"] = "_export"
    document.storage_path = export_path
    document.logical_path = f"_export/{document.file_name}"
    document.metadata_json = metadata
    await db.commit()
    await db.refresh(document)

    return _document_to_vault_dto(document, str(claim_ref))


@router.get("/vault/sinistri/{sinistro_ref}/trash")
async def list_vault_trash(
    sinistro_ref: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    claim = await _resolve_claim_or_404(db, current_user, sinistro_ref)
    documents = await _trashed_vault_documents(db, current_user, claim)
    return [_trash_item_dto(document, _claim_ref(claim)) for document in documents]


@router.post("/vault/files/{file_id}/restore")
async def restore_vault_file(
    file_id: str,
    payload: VaultRestoreRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    document = await _resolve_document_or_404(db, current_user, file_id)
    if document.status != "trashed":
        raise HTTPException(status_code=409, detail="File is not in trash")

    metadata = document.metadata_json or {}
    claim_ref = metadata.get("sinistro_ref") or document.claim_id or "unknown"
    original_logical_path = payload.originalPath or metadata.get("original_logical_path") or document.logical_path or document.file_name
    folder, _, requested_name = original_logical_path.rpartition("/")
    file_name = await _unique_active_file_name(
        db,
        tenant_id=current_user.tenant_id,
        claim_id=document.claim_id,
        folder=folder,
        file_name=requested_name or document.file_name,
    )
    restored_path = VaultStorageService.build_relative_path(
        current_user.tenant_id,
        str(claim_ref),
        folder,
        file_name,
    )
    await VaultStorageService.move_file(document.storage_path, restored_path, overwrite=True)

    metadata.pop("trashed_at", None)
    metadata.pop("trash_path", None)
    metadata["hub_folder"] = folder
    metadata["original_logical_path"] = original_logical_path
    document.storage_path = restored_path
    document.logical_path = f"{folder}/{file_name}" if folder else file_name
    document.file_name = file_name
    document.status = "active"
    document.metadata_json = metadata
    await db.commit()
    await db.refresh(document)
    return _document_to_vault_dto(document, str(claim_ref))


@router.get("/vault/files/{file_id}/versions")
async def list_vault_file_versions(
    file_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    document = await _resolve_document_or_404(db, current_user, file_id)
    result = await db.execute(
        select(DocumentVersion).where(
            DocumentVersion.tenant_id == current_user.tenant_id,
            DocumentVersion.document_id == document.id,
        ).order_by(DocumentVersion.version_no.desc())
    )
    return [_document_version_dto(version) for version in result.scalars().all()]


@router.post("/vault/files/{file_id}/versions/{version_id}/restore")
async def restore_vault_file_version(
    file_id: str,
    version_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    document = await _resolve_document_or_404(db, current_user, file_id)
    if document.status != "active":
        raise HTTPException(status_code=409, detail="Only active files can restore versions")

    result = await db.execute(
        select(DocumentVersion).where(
            DocumentVersion.id == version_id,
            DocumentVersion.document_id == document.id,
            DocumentVersion.tenant_id == current_user.tenant_id,
        )
    )
    version = result.scalar_one_or_none()
    if not version:
        raise HTTPException(status_code=404, detail="Version not found")

    claim_ref = (document.metadata_json or {}).get("sinistro_ref") or document.claim_id or "unknown"
    await _snapshot_document_version(
        db,
        current_user=current_user,
        claim_ref=str(claim_ref),
        document=document,
        reason=f"restore_version_{version.version_no}",
    )
    await VaultStorageService.copy_file(version.storage_path, document.storage_path, overwrite=True)
    content = await VaultStorageService.download_bytes(document.storage_path)
    document.checksum_sha256 = _sha256(content)
    document.size_bytes = len(content)
    document.version_no = version.version_no
    metadata = document.metadata_json or {}
    metadata["restored_from_version_id"] = version.id
    metadata["restored_from_version_no"] = version.version_no
    document.metadata_json = metadata
    await db.commit()
    await db.refresh(document)
    return _document_to_vault_dto(document, str(claim_ref))


@router.get("/jobs/pending")
async def pending_jobs(limit: int = Query(10, ge=1, le=100)):
    return []


@router.post("/jobs/import/folder")
async def import_folder_job():
    now = datetime.now(timezone.utc)
    return {
        "id": str(uuid.uuid4()),
        "type": "import_folder",
        "status": "queued",
        "priority": 0,
        "createdAt": now,
        "startedAt": None,
        "completedAt": None,
        "errorMessage": None,
    }


@router.get("/emails")
async def compat_list_emails(
    user: Optional[str] = Query(None),
    mailbox: Optional[str] = Query(None),
    limit: int = Query(100, ge=1, le=500),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    query = select(Email).where(Email.tenant_id == current_user.tenant_id)
    if mailbox:
        query = query.where(Email.mailbox_id == mailbox)
    result = await db.execute(query.order_by(Email.received_at.desc()).limit(limit))
    items = []
    for email in result.scalars().all():
        if user:
            recipients = json.loads(email.to_addresses or "[]")
            if user.lower() not in email.from_address.lower() and user.lower() not in ",".join(recipients).lower():
                continue
        metadata = _email_metadata(email)
        items.append({
            "id": email.id,
            "subject": email.subject or "(Senza oggetto)",
            "senderEmail": email.from_address,
            "senderName": None,
            "date": email.received_at,
            "category": email.status,
            "sinistroRef": metadata.get("sinistroRef"),
            "direction": metadata.get("direction") or ("out" if email.status.startswith("outbound") or email.status == "scheduled" else "in"),
            "mailbox": email.mailbox_id,
            "isRead": True,
        })
    return items


@router.get("/emails/mailboxes")
async def compat_list_mailboxes(
    user: Optional[str] = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    result = await db.execute(
        select(Email).where(Email.tenant_id == current_user.tenant_id).order_by(Email.mailbox_id.asc())
    )
    grouped: dict[str, int] = {}
    for email in result.scalars().all():
        if user:
            recipients = json.loads(email.to_addresses or "[]")
            if user.lower() not in email.from_address.lower() and user.lower() not in ",".join(recipients).lower():
                continue
        mailbox_id = email.mailbox_id or "default"
        grouped[mailbox_id] = grouped.get(mailbox_id, 0) + 1
    return [
        {"id": mailbox_id, "name": mailbox_id, "unreadCount": 0, "totalCount": total}
        for mailbox_id, total in grouped.items()
    ]


@router.get("/emails/detail/{message_id}")
async def compat_email_detail(
    message_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    result = await db.execute(
        select(Email).where(
            Email.tenant_id == current_user.tenant_id,
            (Email.id == message_id) | (Email.message_id == message_id),
        )
    )
    email = result.scalar_one_or_none()
    if not email:
        raise HTTPException(status_code=404, detail="Email not found")
    metadata = _email_metadata(email)
    return {
        "id": email.id,
        "subject": email.subject or "(Senza oggetto)",
        "senderEmail": email.from_address,
        "senderName": None,
        "recipients": json.loads(email.to_addresses or "[]"),
        "date": email.received_at,
        "bodyText": email.body_text,
        "bodyHtml": email.body_html,
        "category": email.status,
        "sinistroRef": metadata.get("sinistroRef"),
        "direction": metadata.get("direction") or ("out" if email.status.startswith("outbound") or email.status == "scheduled" else "in"),
    }


@router.post("/emails/{message_id}/associate", status_code=status.HTTP_204_NO_CONTENT)
async def compat_associate_email(
    message_id: str,
    payload: ChatAssociateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    email_result = await db.execute(
        select(Email).where(
            Email.tenant_id == current_user.tenant_id,
            (Email.id == message_id) | (Email.message_id == message_id),
        )
    )
    email = email_result.scalar_one_or_none()
    if not email:
        raise HTTPException(status_code=404, detail="Email not found")
    claim = await _resolve_claim_or_404(db, current_user, payload.sinistroRef)

    existing = await db.execute(
        select(EmailClaimLink).where(
            EmailClaimLink.tenant_id == current_user.tenant_id,
            EmailClaimLink.email_id == email.id,
            EmailClaimLink.claim_id == claim.id,
        )
    )
    if not existing.scalar_one_or_none():
        db.add(EmailClaimLink(
            id=str(uuid.uuid4()),
            tenant_id=current_user.tenant_id,
            email_id=email.id,
            claim_id=claim.id,
            link_type="primary",
            created_by="hub_compat",
        ))
        await db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/emails/{message_id}/read", status_code=status.HTTP_204_NO_CONTENT)
async def compat_mark_email_read(
    message_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    result = await db.execute(
        select(Email).where(
            Email.tenant_id == current_user.tenant_id,
            (Email.id == message_id) | (Email.message_id == message_id),
        )
    )
    email = result.scalar_one_or_none()
    if not email:
        raise HTTPException(status_code=404, detail="Email not found")
    email.status = "read"
    await db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/emails/{message_id}/tag", status_code=status.HTTP_204_NO_CONTENT)
async def compat_tag_email(
    message_id: str,
    payload: dict,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    result = await db.execute(
        select(Email).where(
            Email.tenant_id == current_user.tenant_id,
            (Email.id == message_id) | (Email.message_id == message_id),
        )
    )
    email = result.scalar_one_or_none()
    if not email:
        raise HTTPException(status_code=404, detail="Email not found")
    email.status = str(payload.get("category") or email.status)
    metadata = _email_metadata(email)
    if payload.get("sinistroRef"):
        metadata["sinistroRef"] = payload.get("sinistroRef")
    email.raw_headers = json.dumps(metadata)
    await db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/emails/send")
async def compat_send_email(
    payload: EmailSendRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    now = datetime.now(timezone.utc)
    metadata = {
        "accountId": payload.accountId,
        "to": payload.to,
        "cc": payload.cc or [],
        "bcc": payload.bcc or [],
        "direction": "out",
        "compat": True,
    }
    email = Email(
        id=str(uuid.uuid4()),
        tenant_id=current_user.tenant_id,
        message_id=f"compat-{uuid.uuid4()}",
        thread_id=payload.replyToThreadId,
        from_address=current_user.email,
        to_addresses=json.dumps(payload.to),
        cc_addresses=json.dumps(payload.cc or []),
        subject=payload.subject,
        body_text=None if payload.isHtml else payload.body,
        body_html=payload.body if payload.isHtml else None,
        received_at=now,
        status="outbound_sent",
        raw_headers=json.dumps(metadata),
        mailbox_id=payload.accountId,
        provider_id="fastapi_compat",
    )
    db.add(email)
    await db.commit()
    return {"success": True, "message_id": email.message_id, "error": None}


@router.post("/emails/schedule")
async def compat_schedule_email(
    payload: EmailScheduleRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    metadata = {
        "accountId": payload.accountId,
        "to": payload.to,
        "cc": payload.cc or [],
        "sinistroRef": payload.sinistroRef,
        "direction": "out",
        "compat": True,
        "scheduledFor": payload.scheduledFor.isoformat(),
        "body": payload.body,
    }
    email = Email(
        id=str(uuid.uuid4()),
        tenant_id=current_user.tenant_id,
        message_id=f"scheduled-{uuid.uuid4()}",
        thread_id=None,
        from_address=current_user.email,
        to_addresses=json.dumps(payload.to),
        cc_addresses=json.dumps(payload.cc or []),
        subject=payload.subject,
        body_text=payload.body,
        body_html=None,
        received_at=payload.scheduledFor,
        status="scheduled",
        raw_headers=json.dumps(metadata),
        mailbox_id=payload.accountId,
        provider_id="fastapi_compat",
    )
    db.add(email)
    await db.commit()
    return {
        "id": email.id,
        "accountId": payload.accountId,
        "to": payload.to,
        "cc": payload.cc or [],
        "subject": payload.subject,
        "body": payload.body,
        "scheduledFor": payload.scheduledFor,
        "scheduledAt": payload.scheduledFor,
        "status": "pending",
        "sinistroRef": payload.sinistroRef,
        "sentAt": None,
        "errorMessage": None,
    }


@router.get("/emails/scheduled")
async def compat_scheduled_emails(
    accountId: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    result = await db.execute(
        select(Email).where(
            Email.tenant_id == current_user.tenant_id,
            Email.mailbox_id == accountId,
            Email.status == "scheduled",
        ).order_by(Email.received_at.asc())
    )
    items = []
    for email in result.scalars().all():
        metadata = _email_metadata(email)
        items.append({
            "id": email.id,
            "accountId": accountId,
            "to": json.loads(email.to_addresses or "[]"),
            "cc": json.loads(email.cc_addresses or "[]"),
            "subject": email.subject,
            "body": metadata.get("body") or email.body_text or email.body_html,
            "scheduledFor": email.received_at,
            "scheduledAt": email.received_at,
            "status": "pending",
            "sinistroRef": metadata.get("sinistroRef"),
            "sentAt": None,
            "errorMessage": None,
        })
    return items


@router.delete("/emails/scheduled/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def compat_cancel_scheduled_email(
    item_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    result = await db.execute(
        select(Email).where(
            Email.id == item_id,
            Email.tenant_id == current_user.tenant_id,
            Email.status == "scheduled",
        )
    )
    email = result.scalar_one_or_none()
    if not email:
        raise HTTPException(status_code=404, detail="Scheduled email not found")
    await db.delete(email)
    await db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/whatsapp/clients/{account_id}/init")
async def compat_whatsapp_init(
    account_id: str,
    payload: WhatsAppInitRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    account = await _ensure_whatsapp_account(db, current_user, account_id)
    account.phone_number = payload.phoneNumber or account.phone_number
    account.status = "ready"
    await db.commit()
    return {"status": "ready"}


@router.post("/whatsapp/clients/{account_id}/disconnect")
async def compat_whatsapp_disconnect(
    account_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    account = await _ensure_whatsapp_account(db, current_user, account_id)
    account.status = "disconnected"
    await db.commit()
    return {"status": "disconnected"}


@router.get("/whatsapp/clients/{account_id}/qr")
async def compat_whatsapp_qr(
    account_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    account = await _ensure_whatsapp_account(db, current_user, account_id)
    status_value = "ready" if account.status != "disconnected" else "disconnected"
    return {"qr": None, "status": status_value}


@router.post("/whatsapp/clients/{account_id}/check-number")
async def compat_whatsapp_check_number(
    account_id: str,
    payload: WhatsAppCheckNumberRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    await _ensure_whatsapp_account(db, current_user, account_id)
    normalized = payload.phoneNumber.replace("@c.us", "")
    return {"isRegistered": True, "numberId": normalized}


@router.get("/whatsapp/clients/{account_id}/profile-pic/{contact_id}")
async def compat_whatsapp_profile_pic(
    account_id: str,
    contact_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    await _ensure_whatsapp_account(db, current_user, account_id)
    return {"contactId": contact_id, "profilePicUrl": None, "error": None}


@router.get("/whatsapp/chats")
async def compat_whatsapp_chats(
    accountId: Optional[str] = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    query = select(WhatsAppThread).where(WhatsAppThread.tenant_id == current_user.tenant_id)
    effective_account_id = (
        _assert_whatsapp_account_owner(current_user, accountId)
        if accountId
        else _canonical_whatsapp_account_id(current_user)
    )
    query = query.where(WhatsAppThread.account_id == effective_account_id)
    result = await db.execute(query.order_by(WhatsAppThread.last_message_at.desc().nullslast()))
    threads = result.scalars().all()
    items = []
    for thread in threads:
        message_result = await db.execute(
            select(WhatsAppMessage).where(
                WhatsAppMessage.tenant_id == current_user.tenant_id,
                WhatsAppMessage.thread_id == thread.id,
            ).order_by(WhatsAppMessage.sent_at.desc()).limit(1)
        )
        last_message = message_result.scalar_one_or_none()
        claim_ref = None
        if thread.claim_id:
            claim_result = await db.execute(select(Claim).where(Claim.id == thread.claim_id))
            claim = claim_result.scalar_one_or_none()
            claim_ref = _claim_ref(claim) if claim else None
        items.append({
            "id": thread.id,
            "accountId": thread.account_id or "",
            "chatId": thread.external_thread_ref or thread.id,
            "name": thread.contact_name or thread.contact_phone or thread.external_thread_ref,
            "phoneNumber": thread.contact_phone,
            "isGroup": False,
            "lastMessageBody": last_message.body_text if last_message else None,
            "lastMessageAt": thread.last_message_at,
            "unreadCount": 0,
            "sinistroRef": claim_ref,
        })
    return items


@router.get("/whatsapp/messages")
async def compat_whatsapp_messages(
    accountId: Optional[str] = Query(None),
    chatId: Optional[str] = Query(None),
    sinistroRef: Optional[str] = Query(None),
    limit: int = Query(100, ge=1, le=500),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    query = select(WhatsAppMessage, WhatsAppThread).join(
        WhatsAppThread, WhatsAppThread.id == WhatsAppMessage.thread_id
    ).where(
        WhatsAppMessage.tenant_id == current_user.tenant_id,
        WhatsAppThread.tenant_id == current_user.tenant_id,
    )
    effective_account_id = (
        _assert_whatsapp_account_owner(current_user, accountId)
        if accountId
        else _canonical_whatsapp_account_id(current_user)
    )
    query = query.where(WhatsAppThread.account_id == effective_account_id)
    if chatId:
        query = query.where(WhatsAppThread.external_thread_ref == chatId)
    if sinistroRef:
        claim = await _resolve_claim_or_404(db, current_user, sinistroRef)
        query = query.where(WhatsAppMessage.claim_id == claim.id)
    query = query.order_by(WhatsAppMessage.sent_at.asc()).limit(limit)
    result = await db.execute(query)
    items = []
    for message, thread in result.all():
        items.append(await _whatsapp_message_response(db, current_user, message, thread))
    return items


@router.post("/whatsapp/clients/{account_id}/send")
async def compat_whatsapp_send(
    account_id: str,
    payload: WhatsAppSendRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    await _ensure_whatsapp_account(db, current_user, account_id)
    thread = await _find_or_create_thread(db, current_user, account_id, payload.to)
    message_id = str(uuid.uuid4())
    message = WhatsAppMessage(
        id=message_id,
        tenant_id=current_user.tenant_id,
        thread_id=thread.id,
        claim_id=thread.claim_id,
        direction="outbound",
        message_type="media" if payload.media else "text",
        provider_message_id=message_id,
        sender_user_id=current_user.id,
        sender_label=current_user.full_name,
        body_text=payload.body,
        media_document_id=None,
        sent_at=datetime.now(timezone.utc),
        status="sent",
        metadata_json={
            "media_type": payload.media.get("mimetype") if payload.media else None,
            "media_filename": payload.media.get("filename") if payload.media else None,
        },
    )
    db.add(message)
    thread.last_message_at = message.sent_at
    await db.commit()
    return {"messageId": message_id}


@router.post("/whatsapp/schedule")
async def compat_whatsapp_schedule(
    payload: WhatsAppScheduleRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    await _ensure_whatsapp_account(db, current_user, payload.accountId)
    claim = await _resolve_claim_or_404(db, current_user, payload.sinistroRef) if payload.sinistroRef else None
    chat_id = f"{payload.phoneNumber}@c.us" if "@c.us" not in payload.phoneNumber else payload.phoneNumber
    thread = await _find_or_create_thread(db, current_user, payload.accountId, chat_id, claim)
    message = WhatsAppMessage(
        id=str(uuid.uuid4()),
        tenant_id=current_user.tenant_id,
        thread_id=thread.id,
        claim_id=thread.claim_id,
        direction="outbound",
        message_type="media" if payload.mediaData else "text",
        provider_message_id=None,
        sender_user_id=current_user.id,
        sender_label=current_user.full_name,
        body_text=payload.body,
        media_document_id=None,
        sent_at=payload.scheduledFor,
        status="scheduled",
        metadata_json={
            "media_type": payload.mediaType,
            "media_filename": payload.mediaFilename,
            "phone_number": payload.phoneNumber,
        },
    )
    db.add(message)
    await db.commit()
    return {"id": message.id}


@router.get("/whatsapp/scheduled")
async def compat_whatsapp_scheduled(
    accountId: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    accountId = _assert_whatsapp_account_owner(current_user, accountId)
    query = select(WhatsAppMessage, WhatsAppThread).join(
        WhatsAppThread, WhatsAppThread.id == WhatsAppMessage.thread_id
    ).where(
        WhatsAppMessage.tenant_id == current_user.tenant_id,
        WhatsAppThread.tenant_id == current_user.tenant_id,
        WhatsAppThread.account_id == accountId,
        WhatsAppMessage.status == "scheduled",
    ).order_by(WhatsAppMessage.sent_at.asc())
    result = await db.execute(query)
    items = []
    for message, thread in result.all():
        metadata = message.metadata_json or {}
        claim_ref = None
        if thread.claim_id:
            claim_result = await db.execute(select(Claim).where(Claim.id == thread.claim_id))
            claim = claim_result.scalar_one_or_none()
            claim_ref = _claim_ref(claim) if claim else None
        items.append({
            "id": message.id,
            "accountId": accountId,
            "phoneNumber": metadata.get("phone_number") or (thread.contact_phone or "").replace("@c.us", ""),
            "body": message.body_text or "",
            "mediaData": None,
            "mediaType": metadata.get("media_type"),
            "mediaFilename": metadata.get("media_filename"),
            "scheduledAt": message.sent_at,
            "status": "pending",
            "sinistroRef": claim_ref,
        })
    return items


@router.delete("/whatsapp/scheduled/{message_id}", status_code=status.HTTP_204_NO_CONTENT)
async def compat_whatsapp_cancel_scheduled(
    message_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    canonical_account_id = _canonical_whatsapp_account_id(current_user)
    result = await db.execute(
        select(WhatsAppMessage).join(
            WhatsAppThread, WhatsAppThread.id == WhatsAppMessage.thread_id
        ).where(
            WhatsAppMessage.id == message_id,
            WhatsAppMessage.tenant_id == current_user.tenant_id,
            WhatsAppThread.tenant_id == current_user.tenant_id,
            WhatsAppThread.account_id == canonical_account_id,
            WhatsAppMessage.status == "scheduled",
        )
    )
    message = result.scalar_one_or_none()
    if not message:
        raise HTTPException(status_code=404, detail="Scheduled message not found")
    await db.delete(message)
    await db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/internal/events")
async def compat_internal_events(
    since: float = Query(0.0),
):
    return []


@router.post("/whatsapp/chats/{chat_id}/read", status_code=status.HTTP_204_NO_CONTENT)
async def compat_whatsapp_mark_read(chat_id: str):
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/whatsapp/chats/{chat_id}/associate", status_code=status.HTTP_204_NO_CONTENT)
async def compat_whatsapp_associate(
    chat_id: str,
    payload: ChatAssociateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    claim = await _resolve_claim_or_404(db, current_user, payload.sinistroRef)
    result = await db.execute(
        select(WhatsAppThread).where(
            WhatsAppThread.tenant_id == current_user.tenant_id,
            WhatsAppThread.account_id == _canonical_whatsapp_account_id(current_user),
            WhatsAppThread.external_thread_ref == chat_id,
        )
    )
    thread = result.scalar_one_or_none()
    if not thread:
        raise HTTPException(status_code=404, detail="Chat not found")
    thread.claim_id = claim.id
    await db.commit()
    db.add(ClaimEvent(
        id=str(uuid.uuid4()),
        tenant_id=current_user.tenant_id,
        claim_id=claim.id,
        event_type="whatsapp_chat_linked",
        actor_user_id=current_user.id,
        data_json={"chat_id": chat_id, "thread_id": thread.id},
        source="whatsapp",
    ))
    await db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
