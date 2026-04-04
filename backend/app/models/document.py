"""
Document metadata model
"""
from sqlalchemy import Column, String, DateTime, ForeignKey, Integer, BigInteger, JSON, Index
from sqlalchemy.sql import func

from app.core.database import Base


class Document(Base):
    __tablename__ = "documents"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=True, index=True)
    folder_id = Column(String, ForeignKey("claim_folders.id"), nullable=True, index=True)
    attachment_id = Column(String, ForeignKey("attachments.id"), nullable=True, index=True)
    source_type = Column(String, nullable=False, default="hub")
    source_id = Column(String, nullable=True)
    file_name = Column(String, nullable=False)
    original_file_name = Column(String, nullable=True)
    mime_type = Column(String, nullable=True)
    extension = Column(String, nullable=True)
    size_bytes = Column(BigInteger, nullable=False, default=0)
    storage_provider = Column(String, nullable=False, default="hub")
    storage_bucket = Column(String, nullable=True)
    storage_path = Column(String, nullable=False)
    logical_path = Column(String, nullable=True)
    checksum_sha256 = Column(String, nullable=True)
    checksum_md5 = Column(String, nullable=True)
    version_no = Column(Integer, nullable=False, default=1)
    status = Column(String, nullable=False, default="active")
    category = Column(String, nullable=True)
    tags_json = Column(JSON, nullable=True)
    uploaded_at = Column(DateTime(timezone=True), server_default=func.now())
    uploaded_by_user_id = Column(String, ForeignKey("users.id"), nullable=True)
    metadata_json = Column(JSON, nullable=True)

    __table_args__ = (
        Index("ix_documents_storage_path", "storage_path"),
    )
