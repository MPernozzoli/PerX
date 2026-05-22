"""
Sinistro folder request model (iPad → Mac ZIP package requests)
"""
from sqlalchemy import Column, String, DateTime
from sqlalchemy.sql import func

from app.core.database import Base


class SinistroFolderRequest(Base):
    __tablename__ = "sinistro_folder_requests"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, nullable=False, index=True)
    claim_id = Column(String, nullable=True, index=True)
    riferimento = Column(String, nullable=False)
    requested_by_user_id = Column(String, nullable=True)
    status = Column(String, nullable=False, default="pending")
    download_url = Column(String, nullable=True)
    error_message = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    completed_at = Column(DateTime(timezone=True), nullable=True)
