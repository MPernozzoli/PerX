"""
Document version metadata model.
"""
from sqlalchemy import Column, String, DateTime, ForeignKey, BigInteger, Integer, JSON, Index
from sqlalchemy.sql import func

from app.core.database import Base


class DocumentVersion(Base):
    __tablename__ = "document_versions"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    document_id = Column(String, ForeignKey("documents.id"), nullable=False, index=True)
    version_no = Column(Integer, nullable=False)
    storage_path = Column(String, nullable=False)
    size_bytes = Column(BigInteger, nullable=False, default=0)
    checksum_sha256 = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    created_by_user_id = Column(String, ForeignKey("users.id"), nullable=True)
    metadata_json = Column(JSON, nullable=True)

    __table_args__ = (
        Index("ux_document_versions_doc_version", "document_id", "version_no", unique=True),
    )
