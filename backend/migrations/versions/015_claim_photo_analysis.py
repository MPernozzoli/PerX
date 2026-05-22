"""
015 – claim photo analysis

Adds:
  • claim_photo_analyses  – per-submission AI analysis results (PerxiaAnalisi/PerxiaBene equivalent)
  • claims.complexity_score  – server-computed numeric score (replaces client-only calculation)
  • documents.uploaded_by_portal_access_id
"""
from alembic import op
import sqlalchemy as sa

revision = "015"
down_revision = "014"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "claim_photo_analyses",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("claim_id", sa.String(), sa.ForeignKey("claims.id"), nullable=False),
        sa.Column("process_job_id", sa.String(), sa.ForeignKey("process_jobs.id"), nullable=True),
        sa.Column("submission_id", sa.String(), nullable=True),
        sa.Column("status", sa.String(), nullable=False, server_default="pending"),
        # Provider / model
        sa.Column("analysis_provider", sa.String(), nullable=True),
        sa.Column("model", sa.String(), nullable=True),
        # Scoring — numeric so the server owns the computation
        sa.Column("complexity_base_score", sa.Numeric(6, 4), nullable=True),
        sa.Column("complexity_ai_contribution", sa.Numeric(6, 4), nullable=True),
        sa.Column("complexity_score", sa.Numeric(6, 4), nullable=True),
        sa.Column("complessita", sa.String(), nullable=True),
        sa.Column("priority_base_score", sa.Numeric(6, 4), nullable=True),
        sa.Column("priority_ai_contribution", sa.Numeric(6, 4), nullable=True),
        sa.Column("priority_score", sa.Numeric(6, 4), nullable=True),
        sa.Column("ai_priority", sa.Integer(), nullable=True),
        sa.Column("analysis_confidence", sa.Numeric(4, 3), nullable=True),
        # PerxiaAnalisi equivalent
        sa.Column("relazione_complessiva", sa.String(), nullable=True),
        # PerxiaBene array (JSON)
        sa.Column("beni_json", sa.JSON(), nullable=True),
        sa.Column("raw_result_json", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_photo_analyses_claim", "claim_photo_analyses", ["claim_id"])
    op.create_index("ix_photo_analyses_tenant_status", "claim_photo_analyses", ["tenant_id", "status"])
    op.create_index("ix_photo_analyses_job", "claim_photo_analyses", ["process_job_id"])

    # Server-computed numeric complexity score on claims
    op.add_column(
        "claims",
        sa.Column("complexity_score", sa.Numeric(6, 4), nullable=True),
    )

    # Track which portal access session uploaded each document
    op.add_column(
        "documents",
        sa.Column("uploaded_by_portal_access_id", sa.String(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("documents", "uploaded_by_portal_access_id")
    op.drop_column("claims", "complexity_score")
    op.drop_index("ix_photo_analyses_job", table_name="claim_photo_analyses")
    op.drop_index("ix_photo_analyses_tenant_status", table_name="claim_photo_analyses")
    op.drop_index("ix_photo_analyses_claim", table_name="claim_photo_analyses")
    op.drop_table("claim_photo_analyses")
