"""
Attachment model - file attachments metadata
"""
from sqlalchemy import Column, String, DateTime, ForeignKey, Integer, BigInteger
from sqlalchemy.sql import func
from app.core.database import Base


class Attachment(Base):
    __tablename__ = "attachments"
    
    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    email_id = Column(String, ForeignKey("emails.id"), nullable=True, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=True, index=True)
    file_name = Column(String, nullable=False)
    mime_type = Column(String, nullable=True)
    size_bytes = Column(BigInteger, nullable=False)
    storage_bucket = Column(String, nullable=False)
    storage_path = Column(String, nullable=False)  # Full path in bucket
    checksum = Column(String, nullable=True)  # MD5 or SHA256
    uploaded_at = Column(DateTime(timezone=True), server_default=func.now())
    uploaded_by_user_id = Column(String, ForeignKey("users.id"), nullable=True)

