"""
Folder and document routes
"""
from datetime import datetime
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_active_user
from app.models.claim_folder import ClaimFolder
from app.models.document import Document
from app.models.user import User
from app.schemas.content import (
    ClaimFolderCreate,
    ClaimFolderListResponse,
    ClaimFolderResponse,
    DocumentCreate,
    DocumentListResponse,
    DocumentResponse,
    DocumentUpdate,
)
from app.services.claim_service import ClaimService

router = APIRouter()


async def _resolve_claim_or_404(
    db: AsyncSession,
    current_user: User,
    claim_identifier: str,
):
    claim = await ClaimService.get_claim(db, current_user.tenant_id, claim_identifier)
    if not claim:
        raise HTTPException(status_code=404, detail="Claim not found")
    return claim


@router.get("/claims/{claim_id}/folders", response_model=ClaimFolderListResponse)
async def list_claim_folders(
    claim_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    claim = await _resolve_claim_or_404(db, current_user, claim_id)

    query = (
        select(ClaimFolder)
        .where(
            ClaimFolder.tenant_id == current_user.tenant_id,
            ClaimFolder.claim_id == claim.id,
        )
        .order_by(ClaimFolder.path.asc(), ClaimFolder.created_at.asc())
    )
    result = await db.execute(query)
    items = result.scalars().all()
    return ClaimFolderListResponse(
        items=[ClaimFolderResponse.model_validate(item) for item in items],
        total=len(items),
    )


@router.post(
    "/claims/{claim_id}/folders",
    response_model=ClaimFolderResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_claim_folder(
    claim_id: str,
    folder_data: ClaimFolderCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    claim = await _resolve_claim_or_404(db, current_user, claim_id)

    parent_path = None
    if folder_data.parent_id:
        parent_result = await db.execute(
            select(ClaimFolder).where(
                ClaimFolder.id == folder_data.parent_id,
                ClaimFolder.tenant_id == current_user.tenant_id,
            )
        )
        parent_folder = parent_result.scalar_one_or_none()
        if not parent_folder:
            raise HTTPException(status_code=404, detail="Parent folder not found")
        parent_path = parent_folder.path.rstrip("/")

    folder_path = folder_data.path
    if not folder_path:
        base_path = parent_path or f"/claims/{claim.external_ref or claim.id}"
        folder_path = f"{base_path}/{folder_data.name}".replace("//", "/")

    existing = await db.execute(
        select(ClaimFolder).where(
            ClaimFolder.tenant_id == current_user.tenant_id,
            ClaimFolder.path == folder_path,
        )
    )
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="Folder path already exists")

    folder = ClaimFolder(
        id=str(uuid.uuid4()),
        tenant_id=current_user.tenant_id,
        claim_id=claim.id,
        parent_id=folder_data.parent_id,
        name=folder_data.name,
        folder_type=folder_data.folder_type,
        path=folder_path,
        source=folder_data.source,
        external_ref=folder_data.external_ref,
        metadata_json=folder_data.metadata_json,
    )
    db.add(folder)
    await db.commit()
    await db.refresh(folder)

    await ClaimService._create_event(
        db,
        current_user.tenant_id,
        claim.id,
        "folder_created",
        current_user.id,
        {"folder_id": folder.id, "path": folder.path},
    )

    return ClaimFolderResponse.model_validate(folder)


@router.get("/documents", response_model=DocumentListResponse)
async def list_documents(
    claim_id: str | None = Query(None),
    folder_id: str | None = Query(None),
    category: str | None = Query(None),
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    query = select(Document).where(Document.tenant_id == current_user.tenant_id)

    if claim_id:
        claim = await _resolve_claim_or_404(db, current_user, claim_id)
        query = query.where(Document.claim_id == claim.id)
    if folder_id:
        query = query.where(Document.folder_id == folder_id)
    if category:
        query = query.where(Document.category == category)

    count_query = select(func.count()).select_from(query.subquery())
    total = (await db.execute(count_query)).scalar() or 0

    result = await db.execute(
        query.order_by(Document.uploaded_at.desc()).offset((page - 1) * page_size).limit(page_size)
    )
    items = result.scalars().all()
    return DocumentListResponse(
        items=[DocumentResponse.model_validate(item) for item in items],
        total=total,
    )


@router.get("/documents/{document_id}", response_model=DocumentResponse)
async def get_document(
    document_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    result = await db.execute(
        select(Document).where(
            Document.id == document_id,
            Document.tenant_id == current_user.tenant_id,
        )
    )
    document = result.scalar_one_or_none()
    if not document:
        raise HTTPException(status_code=404, detail="Document not found")
    return DocumentResponse.model_validate(document)


@router.post("/documents", response_model=DocumentResponse, status_code=status.HTTP_201_CREATED)
async def create_document(
    payload: DocumentCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    claim_pk = None
    if payload.claim_id:
        claim = await _resolve_claim_or_404(db, current_user, payload.claim_id)
        claim_pk = claim.id

    if payload.folder_id:
        folder_result = await db.execute(
            select(ClaimFolder).where(
                ClaimFolder.id == payload.folder_id,
                ClaimFolder.tenant_id == current_user.tenant_id,
            )
        )
        folder = folder_result.scalar_one_or_none()
        if not folder:
            raise HTTPException(status_code=404, detail="Folder not found")
        if claim_pk is None:
            claim_pk = folder.claim_id

    document = Document(
        id=str(uuid.uuid4()),
        tenant_id=current_user.tenant_id,
        claim_id=claim_pk,
        folder_id=payload.folder_id,
        attachment_id=payload.attachment_id,
        source_type=payload.source_type,
        source_id=payload.source_id,
        file_name=payload.file_name,
        original_file_name=payload.original_file_name,
        mime_type=payload.mime_type,
        extension=payload.extension,
        size_bytes=payload.size_bytes,
        storage_provider=payload.storage_provider,
        storage_bucket=payload.storage_bucket,
        storage_path=payload.storage_path,
        logical_path=payload.logical_path,
        checksum_sha256=payload.checksum_sha256,
        checksum_md5=payload.checksum_md5,
        version_no=payload.version_no,
        status=payload.status,
        category=payload.category,
        tags_json=payload.tags_json,
        uploaded_by_user_id=current_user.id,
        metadata_json=payload.metadata_json,
    )
    db.add(document)
    await db.commit()
    await db.refresh(document)

    if document.claim_id:
        await ClaimService._create_event(
            db,
            current_user.tenant_id,
            document.claim_id,
            "document_registered",
            current_user.id,
            {
                "document_id": document.id,
                "file_name": document.file_name,
                "storage_path": document.storage_path,
            },
        )

    return DocumentResponse.model_validate(document)


@router.put("/documents/{document_id}", response_model=DocumentResponse)
async def update_document(
    document_id: str,
    payload: DocumentUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    result = await db.execute(
        select(Document).where(
            Document.id == document_id,
            Document.tenant_id == current_user.tenant_id,
        )
    )
    document = result.scalar_one_or_none()
    if not document:
        raise HTTPException(status_code=404, detail="Document not found")

    if payload.folder_id is not None:
        folder_result = await db.execute(
            select(ClaimFolder).where(
                ClaimFolder.id == payload.folder_id,
                ClaimFolder.tenant_id == current_user.tenant_id,
            )
        )
        folder = folder_result.scalar_one_or_none()
        if not folder:
            raise HTTPException(status_code=404, detail="Folder not found")
        document.folder_id = folder.id
        if folder.claim_id:
            document.claim_id = folder.claim_id

    if payload.status is not None:
        document.status = payload.status
    if payload.category is not None:
        document.category = payload.category
    if payload.logical_path is not None:
        document.logical_path = payload.logical_path
    if payload.tags_json is not None:
        document.tags_json = payload.tags_json
    if payload.metadata_json is not None:
        document.metadata_json = payload.metadata_json

    await db.commit()
    await db.refresh(document)

    if document.claim_id:
        await ClaimService._create_event(
            db,
            current_user.tenant_id,
            document.claim_id,
            "document_updated",
            current_user.id,
            {"document_id": document.id, "status": document.status},
        )

    return DocumentResponse.model_validate(document)
