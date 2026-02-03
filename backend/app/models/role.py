"""
Role and user-role mapping models
"""
from sqlalchemy import Column, String, ForeignKey, Table
from app.core.database import Base

# Association table for many-to-many relationship
user_roles = Table(
    "user_roles",
    Base.metadata,
    Column("user_id", String, ForeignKey("users.id"), primary_key=True),
    Column("role_id", String, ForeignKey("roles.id"), primary_key=True)
)


class Role(Base):
    __tablename__ = "roles"
    
    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    name = Column(String, nullable=False)
    description = Column(String, nullable=True)

