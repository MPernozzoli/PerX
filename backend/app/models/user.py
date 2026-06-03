"""
User model
"""
from sqlalchemy import Column, String, Boolean, DateTime, ForeignKey, JSON, Text, UniqueConstraint
from sqlalchemy.sql import func
from app.core.database import Base


class User(Base):
    __tablename__ = "users"
    __table_args__ = (
        UniqueConstraint("tenant_id", "extension_number", name="uq_users_tenant_extension_number"),
    )
    
    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    email = Column(String, unique=True, nullable=False, index=True)
    personal_email = Column(String, unique=True, nullable=True, index=True)
    professional_email = Column(String, unique=True, nullable=True, index=True)
    full_name = Column(String, nullable=False)
    first_name = Column(String, nullable=True)
    last_name = Column(String, nullable=True)
    job_title = Column(String, nullable=True)
    phone_number = Column(String, nullable=True)
    birth_date = Column(DateTime(timezone=True), nullable=True)
    birthday_visibility = Column(String, nullable=False, default="everyone")
    notify_birthday = Column(Boolean, default=True, nullable=False)
    password_hash = Column(String, nullable=True)  # Nullable for OAuth users
    idp_subject = Column(String, nullable=True)  # For external IdP
    contract_type = Column(String, nullable=True)
    extension_number = Column(String(3), nullable=True, index=True)
    extension_enabled = Column(Boolean, default=False, nullable=False)
    extension_assigned_at = Column(DateTime(timezone=True), nullable=True)
    extension_display_name = Column(String, nullable=True)
    availability_status = Column(String, nullable=False, default="available")
    communication_status = Column(String, nullable=False, default="idle")
    avatar_type = Column(String, nullable=False, default="generated")
    avatar_photo_base64 = Column(Text, nullable=True)
    generated_avatar_color = Column(String, nullable=True)
    generated_avatar_icon = Column(String, nullable=True)
    avatar_gif_url = Column(String, nullable=True)
    enable_badges = Column(Boolean, default=False, nullable=False)
    send_read_receipts = Column(Boolean, default=True, nullable=False)
    email_signature_html = Column(Text, nullable=True)
    email_signature_text = Column(Text, nullable=True)
    settings_json = Column(JSON, nullable=True)
    is_active = Column(Boolean, default=True, nullable=False)
    is_platform_admin = Column(Boolean, default=False, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    last_login_at = Column(DateTime(timezone=True), nullable=True)
