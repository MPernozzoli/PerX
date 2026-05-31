"""
021 - ai_prompt_templates

Tabella per i template di prompt AI editabili dalle impostazioni.

- Una riga per (tenant_id, key); tenant_id NULL = default globale.
- AIPromptService fa lookup con fallback: tenant → globale.
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "021"
down_revision = "020"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "ai_prompt_templates",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=True),
        sa.Column("key", sa.String(), nullable=False),
        sa.Column("title", sa.String(), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("body", sa.Text(), nullable=False),
        sa.Column("variables_json", sa.JSON(), nullable=True),
        sa.Column("version", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_by_user_id", sa.String(), sa.ForeignKey("users.id"), nullable=True),
        sa.UniqueConstraint("tenant_id", "key", name="uq_ai_prompt_tenant_key"),
    )
    op.create_index("ix_ai_prompt_templates_tenant_id", "ai_prompt_templates", ["tenant_id"])
    op.create_index("ix_ai_prompt_templates_key", "ai_prompt_templates", ["key"])


def downgrade() -> None:
    op.drop_index("ix_ai_prompt_templates_key", table_name="ai_prompt_templates")
    op.drop_index("ix_ai_prompt_templates_tenant_id", table_name="ai_prompt_templates")
    op.drop_table("ai_prompt_templates")
