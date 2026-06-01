"""
032 - Versioning prompt AI + routing policy locale/cloud + log esecuzioni.

Aggiunte:
  * ai_prompt_template_versions  - storico immutabile delle versioni di ogni
    prompt. Ogni update da UI crea una riga qui e aggiorna
    ai_prompt_templates.current_version_id.
  * ai_prompt_templates.current_version_id - puntatore alla versione corrente.
    Backfill: per ogni riga esistente creiamo una versione iniziale dal body
    attuale, con version_id derivato dall'hash.
  * ai_routing_policy - per (tenant_id, phase) decide locale vs cloud.
  * ai_analysis_runs - log per audit/osservabilita delle esecuzioni AI.

Idempotente per quanto possibile: il backfill usa ON CONFLICT DO NOTHING.
"""
from __future__ import annotations

import hashlib
import json
import uuid

from alembic import op
import sqlalchemy as sa


revision = "032_ai_prompt_versioning"
# NOTA: down_revision punta a "029" perche al momento di scrivere questa
# migration ci sono altre 030_* / 031_* in flight (portal_gdpr, videoperizia,
# ...) di cui non si conosce l'ordering finale. Da rebasare in catena lineare
# al merge.
down_revision = "029"
branch_labels = None
depends_on = None


def _short_version_id(template_id: str, body: str) -> str:
    """Hash stabile 8 char derivato da template_id+body. Stesso body -> stessa version_id."""
    h = hashlib.sha1(f"{template_id}\x00{body}".encode("utf-8")).hexdigest()
    return h[:8]


def upgrade() -> None:
    # --- ai_prompt_template_versions ---
    op.create_table(
        "ai_prompt_template_versions",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("template_id", sa.String(), sa.ForeignKey("ai_prompt_templates.id", ondelete="CASCADE"), nullable=False),
        sa.Column("version_id", sa.String(), nullable=False),
        sa.Column("body", sa.Text(), nullable=False),
        sa.Column("variables_json", sa.JSON(), nullable=True),
        sa.Column("changelog", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("created_by_user_id", sa.String(), sa.ForeignKey("users.id"), nullable=True),
        sa.UniqueConstraint("template_id", "version_id", name="uq_ai_prompt_version"),
    )
    op.create_index("ix_ai_prompt_versions_template_id", "ai_prompt_template_versions", ["template_id"])
    op.create_index(
        "ix_ai_prompt_versions_template_created",
        "ai_prompt_template_versions",
        ["template_id", "created_at"],
    )

    # --- ai_prompt_templates.current_version_id ---
    op.add_column(
        "ai_prompt_templates",
        sa.Column("current_version_id", sa.String(), nullable=True),
    )

    # --- ai_routing_policy ---
    # Chiave logica (tenant_id, phase, trigger) per supportare le regole:
    #   user_initiated su immagini -> cloud (velocita per UX)
    #   background                 -> locale (no spreco budget cloud)
    #   regenerate                 -> cloud_only (l'utente non si fida del locale)
    op.create_table(
        "ai_routing_policy",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=True),
        sa.Column("phase", sa.String(), nullable=False),
        sa.Column("trigger", sa.String(), nullable=False),
        sa.Column("mode", sa.String(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_by_user_id", sa.String(), sa.ForeignKey("users.id"), nullable=True),
        sa.UniqueConstraint("tenant_id", "phase", "trigger", name="uq_ai_routing_tenant_phase_trigger"),
    )
    op.create_index("ix_ai_routing_tenant_id", "ai_routing_policy", ["tenant_id"])
    op.create_index("ix_ai_routing_phase", "ai_routing_policy", ["phase"])
    op.create_index("ix_ai_routing_trigger", "ai_routing_policy", ["trigger"])

    # --- ai_analysis_runs ---
    op.create_table(
        "ai_analysis_runs",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=True),
        sa.Column("sinistro_ref", sa.String(), nullable=True),
        sa.Column("phase", sa.String(), nullable=False),
        sa.Column("prompt_key", sa.String(), nullable=False),
        sa.Column("prompt_version_id", sa.String(), nullable=False),
        sa.Column("provider_used", sa.String(), nullable=False),
        sa.Column("model_name", sa.String(), nullable=True),
        sa.Column("mode_applied", sa.String(), nullable=False),
        sa.Column("trigger", sa.String(), nullable=False),
        sa.Column("latency_ms", sa.Integer(), nullable=True),
        sa.Column("input_token_count", sa.Integer(), nullable=True),
        sa.Column("output_token_count", sa.Integer(), nullable=True),
        sa.Column("status", sa.String(), nullable=False),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column("client_id", sa.String(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_ai_runs_tenant_id", "ai_analysis_runs", ["tenant_id"])
    op.create_index("ix_ai_runs_sinistro_ref", "ai_analysis_runs", ["sinistro_ref"])
    op.create_index("ix_ai_runs_phase", "ai_analysis_runs", ["phase"])
    op.create_index("ix_ai_runs_created_at", "ai_analysis_runs", ["created_at"])
    op.create_index(
        "ix_ai_runs_tenant_phase_created",
        "ai_analysis_runs",
        ["tenant_id", "phase", "created_at"],
    )

    # --- backfill: per ogni template esistente crea versione 1 con hash del body ---
    bind = op.get_bind()
    rows = bind.execute(
        sa.text("SELECT id, body, variables_json FROM ai_prompt_templates")
    ).fetchall()
    for row in rows:
        template_id, body, variables_json = row[0], row[1], row[2]
        version_id = _short_version_id(template_id, body or "")
        bind.execute(
            sa.text(
                """
                INSERT INTO ai_prompt_template_versions
                  (id, template_id, version_id, body, variables_json, changelog)
                VALUES
                  (:id, :template_id, :version_id, :body, CAST(:variables AS JSON), :changelog)
                ON CONFLICT (template_id, version_id) DO NOTHING
                """
            ),
            {
                "id": str(uuid.uuid4()),
                "template_id": template_id,
                "version_id": version_id,
                "body": body or "",
                "variables": None if variables_json is None else json.dumps(variables_json),
                "changelog": "initial backfill (migration 030)",
            },
        )
        bind.execute(
            sa.text(
                "UPDATE ai_prompt_templates SET current_version_id = :v WHERE id = :id"
            ),
            {"v": version_id, "id": template_id},
        )


def downgrade() -> None:
    op.drop_index("ix_ai_runs_tenant_phase_created", table_name="ai_analysis_runs")
    op.drop_index("ix_ai_runs_created_at", table_name="ai_analysis_runs")
    op.drop_index("ix_ai_runs_phase", table_name="ai_analysis_runs")
    op.drop_index("ix_ai_runs_sinistro_ref", table_name="ai_analysis_runs")
    op.drop_index("ix_ai_runs_tenant_id", table_name="ai_analysis_runs")
    op.drop_table("ai_analysis_runs")

    op.drop_index("ix_ai_routing_trigger", table_name="ai_routing_policy")
    op.drop_index("ix_ai_routing_phase", table_name="ai_routing_policy")
    op.drop_index("ix_ai_routing_tenant_id", table_name="ai_routing_policy")
    op.drop_table("ai_routing_policy")

    op.drop_column("ai_prompt_templates", "current_version_id")

    op.drop_index("ix_ai_prompt_versions_template_created", table_name="ai_prompt_template_versions")
    op.drop_index("ix_ai_prompt_versions_template_id", table_name="ai_prompt_template_versions")
    op.drop_table("ai_prompt_template_versions")
