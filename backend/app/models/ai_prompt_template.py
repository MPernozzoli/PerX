"""
Template di prompt AI editabili dalle impostazioni.

Ogni template è identificato da una `key` (es. "perizia.beni", "perizia.relazione",
"diario.summary"). Le righe con `tenant_id IS NULL` sono i default globali;
quelle con `tenant_id` valorizzato sono override per tenant.

`AIPromptService.render` esegue il lookup tenant→global e sostituisce i
placeholder `{{var}}` con i valori passati.
"""
from sqlalchemy import Column, String, Text, Integer, DateTime, ForeignKey, JSON, UniqueConstraint
from sqlalchemy.sql import func

from app.core.database import Base


class AIPromptTemplate(Base):
    __tablename__ = "ai_prompt_templates"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=True, index=True)
    key = Column(String, nullable=False, index=True)

    title = Column(String, nullable=False)
    description = Column(Text, nullable=True)
    body = Column(Text, nullable=False)
    variables_json = Column(JSON, nullable=True)  # lista nomi variabili attese, per UI

    version = Column(Integer, nullable=False, default=1)

    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)
    updated_by_user_id = Column(String, ForeignKey("users.id"), nullable=True)

    __table_args__ = (
        UniqueConstraint("tenant_id", "key", name="uq_ai_prompt_tenant_key"),
    )
