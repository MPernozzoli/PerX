"""
Storico immutabile dei prompt template.

Ogni update di `ai_prompt_templates.body` genera una nuova riga qui con un
`version_id` short-hash stabile (8 char) che client e log di esecuzione usano
per identificare con quale versione del prompt è stata prodotta un'analisi.

La riga corrente del template (`ai_prompt_templates`) tiene `current_version_id`
che punta qui. Le versioni passate non vengono mai modificate o cancellate,
così possiamo riprocessare un sinistro con il prompt esatto di allora.
"""
from sqlalchemy import Column, String, Text, DateTime, ForeignKey, JSON, UniqueConstraint, Index
from sqlalchemy.sql import func

from app.core.database import Base


class AIPromptTemplateVersion(Base):
    __tablename__ = "ai_prompt_template_versions"

    id = Column(String, primary_key=True, index=True)
    template_id = Column(String, ForeignKey("ai_prompt_templates.id", ondelete="CASCADE"), nullable=False, index=True)

    version_id = Column(String, nullable=False)  # short hash 8 char, unique per template_id
    body = Column(Text, nullable=False)
    variables_json = Column(JSON, nullable=True)
    changelog = Column(Text, nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    created_by_user_id = Column(String, ForeignKey("users.id"), nullable=True)

    __table_args__ = (
        UniqueConstraint("template_id", "version_id", name="uq_ai_prompt_version"),
        Index("ix_ai_prompt_versions_template_created", "template_id", "created_at"),
    )
