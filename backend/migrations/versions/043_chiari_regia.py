"""Regia: stati del tenant, revisioni, questioni, regole e job.

Revision ID: 043_chiari_regia
Revises: 042_enable_rls_remaining
"""
from alembic import op
import sqlalchemy as sa


revision = "043_chiari_regia"
down_revision = "042_enable_rls_remaining"
branch_labels = None
depends_on = None


def _has_column(table_name: str, column_name: str) -> bool:
    inspector = sa.inspect(op.get_bind())
    if not inspector.has_table(table_name):
        return False
    return column_name in {column["name"] for column in inspector.get_columns(table_name)}


def upgrade() -> None:
    inspector = sa.inspect(op.get_bind())

    if not inspector.has_table("tenant_claim_states"):
        op.create_table(
            "tenant_claim_states",
            sa.Column("id", sa.String(), nullable=False),
            sa.Column("tenant_id", sa.String(), nullable=False),
            sa.Column("code", sa.String(), nullable=False),
            sa.Column("label", sa.String(), nullable=False),
            sa.Column("description", sa.Text(), nullable=True),
            sa.Column("actor", sa.String(), nullable=True),
            sa.Column("is_meta", sa.Boolean(), nullable=False, server_default=sa.false()),
            sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("active", sa.Boolean(), nullable=False, server_default=sa.true()),
            sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint("tenant_id", "code", name="uq_tenant_claim_states_code"),
        )
        op.create_index("ix_tenant_claim_states_tenant_id", "tenant_claim_states", ["tenant_id"])

    if not inspector.has_table("claim_workflows"):
        op.create_table(
            "claim_workflows",
            sa.Column("claim_id", sa.String(), nullable=False),
            sa.Column("tenant_id", sa.String(), nullable=False),
            sa.Column("salesforce_id", sa.String(), nullable=True),
            sa.Column("company_claim_number", sa.String(), nullable=True),
            sa.Column("ispettorato", sa.String(), nullable=True),
            sa.Column("liquidatore", sa.String(), nullable=True),
            sa.Column("salesforce_status", sa.String(), nullable=True),
            sa.Column("closed_on", sa.String(), nullable=True),
            sa.Column("outcome", sa.String(), nullable=True),
            sa.Column("expected_close_on", sa.String(), nullable=True),
            sa.Column("passages_json", sa.JSON(), nullable=True),
            sa.Column("checks_json", sa.JSON(), nullable=True),
            sa.Column("reclaim_model", sa.String(), nullable=True),
            sa.Column("manual_state_code", sa.String(), nullable=True),
            sa.Column("manual_state_at", sa.DateTime(timezone=True), nullable=True),
            sa.ForeignKeyConstraint(["claim_id"], ["claims.id"], ondelete="CASCADE"),
            sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
            sa.PrimaryKeyConstraint("claim_id"),
        )
        op.create_index("ix_claim_workflows_tenant_id", "claim_workflows", ["tenant_id"])
        op.create_index("ix_claim_workflows_salesforce_id", "claim_workflows", ["salesforce_id"])

    if not inspector.has_table("claim_groups"):
        op.create_table(
            "claim_groups",
            sa.Column("id", sa.String(), nullable=False),
            sa.Column("tenant_id", sa.String(), nullable=False),
            sa.Column("kind", sa.String(), nullable=False),
            sa.Column("external_key", sa.String(), nullable=False),
            sa.Column("reason", sa.Text(), nullable=True),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
            sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint("tenant_id", "kind", "external_key", name="uq_claim_groups_key"),
        )
        op.create_index("ix_claim_groups_tenant_id", "claim_groups", ["tenant_id"])

    if not inspector.has_table("claim_group_members"):
        op.create_table(
            "claim_group_members",
            sa.Column("id", sa.String(), nullable=False),
            sa.Column("tenant_id", sa.String(), nullable=False),
            sa.Column("group_id", sa.String(), nullable=False),
            sa.Column("claim_id", sa.String(), nullable=False),
            sa.ForeignKeyConstraint(["claim_id"], ["claims.id"], ondelete="CASCADE"),
            sa.ForeignKeyConstraint(["group_id"], ["claim_groups.id"], ondelete="CASCADE"),
            sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint("group_id", "claim_id", name="uq_claim_group_member"),
        )
        op.create_index("ix_claim_group_members_tenant_id", "claim_group_members", ["tenant_id"])
        op.create_index("ix_claim_group_members_group_id", "claim_group_members", ["group_id"])
        op.create_index("ix_claim_group_members_claim_id", "claim_group_members", ["claim_id"])

    if not inspector.has_table("claim_estimate_revisions"):
        op.create_table(
            "claim_estimate_revisions",
            sa.Column("id", sa.String(), nullable=False),
            sa.Column("tenant_id", sa.String(), nullable=False),
            sa.Column("claim_id", sa.String(), nullable=False),
            sa.Column("revision_number", sa.Integer(), nullable=False),
            sa.Column("input_json", sa.JSON(), nullable=False),
            sa.Column("calculation_json", sa.JSON(), nullable=False),
            sa.Column("calculation_hash", sa.String(), nullable=True),
            sa.Column("economic_hash", sa.String(), nullable=True),
            sa.Column("liquidabile", sa.Numeric(12, 2), nullable=True),
            sa.Column("approved_at", sa.DateTime(timezone=True), nullable=True),
            sa.Column("approved_by_user_id", sa.String(), nullable=True),
            sa.Column("inherited_from_revision_id", sa.String(), nullable=True),
            sa.Column("superseded_at", sa.DateTime(timezone=True), nullable=True),
            sa.Column("amount_exception_reason", sa.Text(), nullable=True),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
            sa.ForeignKeyConstraint(["approved_by_user_id"], ["users.id"], ondelete="SET NULL"),
            sa.ForeignKeyConstraint(["claim_id"], ["claims.id"], ondelete="CASCADE"),
            sa.ForeignKeyConstraint(["inherited_from_revision_id"], ["claim_estimate_revisions.id"], ondelete="SET NULL"),
            sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint("claim_id", "revision_number", name="uq_claim_estimate_revision"),
        )
        op.create_index("ix_claim_estimate_revisions_tenant_id", "claim_estimate_revisions", ["tenant_id"])
        op.create_index("ix_claim_estimate_revisions_claim_id", "claim_estimate_revisions", ["claim_id"])
        op.create_index("ix_claim_estimate_revisions_economic_hash", "claim_estimate_revisions", ["economic_hash"])

    if not inspector.has_table("claim_atti"):
        op.create_table(
            "claim_atti",
            sa.Column("id", sa.String(), nullable=False),
            sa.Column("tenant_id", sa.String(), nullable=False),
            sa.Column("claim_id", sa.String(), nullable=False),
            sa.Column("kind", sa.String(), nullable=False),
            sa.Column("amount", sa.Numeric(12, 2), nullable=True),
            sa.Column("sent_at", sa.DateTime(timezone=True), nullable=True),
            sa.Column("signed_at", sa.DateTime(timezone=True), nullable=True),
            sa.Column("iban", sa.String(), nullable=True),
            sa.Column("iban_verified", sa.Boolean(), nullable=False, server_default=sa.false()),
            sa.Column("beneficiary", sa.String(), nullable=True),
            sa.Column("fingerprint", sa.String(), nullable=True),
            sa.Column("metadata_json", sa.JSON(), nullable=True),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
            sa.ForeignKeyConstraint(["claim_id"], ["claims.id"], ondelete="CASCADE"),
            sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
            sa.PrimaryKeyConstraint("id"),
        )
        op.create_index("ix_claim_atti_tenant_id", "claim_atti", ["tenant_id"])
        op.create_index("ix_claim_atti_claim_id", "claim_atti", ["claim_id"])

    if not inspector.has_table("claim_questions"):
        op.create_table(
            "claim_questions",
            sa.Column("id", sa.String(), nullable=False),
            sa.Column("tenant_id", sa.String(), nullable=False),
            sa.Column("claim_id", sa.String(), nullable=True),
            sa.Column("job_id", sa.String(), nullable=True),
            sa.Column("question_type", sa.String(), nullable=False),
            sa.Column("raised_level", sa.String(), nullable=True),
            sa.Column("description", sa.Text(), nullable=False),
            sa.Column("evidence_json", sa.JSON(), nullable=True),
            sa.Column("options_json", sa.JSON(), nullable=True),
            sa.Column("recommendation", sa.Text(), nullable=True),
            sa.Column("answer_text", sa.Text(), nullable=True),
            sa.Column("answer_scope", sa.String(), nullable=True),
            sa.Column("answered_by_user_id", sa.String(), nullable=True),
            sa.Column("answered_at", sa.DateTime(timezone=True), nullable=True),
            sa.Column("outcome", sa.String(), nullable=True),
            sa.Column("status", sa.String(), nullable=False, server_default="aperta"),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
            sa.ForeignKeyConstraint(["answered_by_user_id"], ["users.id"], ondelete="SET NULL"),
            sa.ForeignKeyConstraint(["claim_id"], ["claims.id"], ondelete="CASCADE"),
            sa.ForeignKeyConstraint(["job_id"], ["process_jobs.id"], ondelete="SET NULL"),
            sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
            sa.PrimaryKeyConstraint("id"),
        )
        op.create_index("ix_claim_questions_tenant_id", "claim_questions", ["tenant_id"])
        op.create_index("ix_claim_questions_claim_id", "claim_questions", ["claim_id"])
        op.create_index("ix_claim_questions_job_id", "claim_questions", ["job_id"])
        op.create_index("ix_claim_questions_status", "claim_questions", ["status"])

    if not inspector.has_table("tenant_rules"):
        op.create_table(
            "tenant_rules",
            sa.Column("id", sa.String(), nullable=False),
            sa.Column("tenant_id", sa.String(), nullable=False),
            sa.Column("body", sa.Text(), nullable=False),
            sa.Column("rule_type", sa.String(), nullable=False),
            sa.Column("scope", sa.String(), nullable=True),
            sa.Column("author", sa.String(), nullable=True),
            sa.Column("origin_label", sa.String(), nullable=True),
            sa.Column("originated_on", sa.Date(), nullable=True),
            sa.Column("origin_claim_ref", sa.String(), nullable=True),
            sa.Column("status", sa.String(), nullable=False, server_default="proposta"),
            sa.Column("version", sa.Integer(), nullable=False, server_default="1"),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
            sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
            sa.PrimaryKeyConstraint("id"),
        )
        op.create_index("ix_tenant_rules_tenant_id", "tenant_rules", ["tenant_id"])
        op.create_index("ix_tenant_rules_status", "tenant_rules", ["status"])

    job_columns = {
        "phase": sa.Column("phase", sa.String(), nullable=True),
        "resource": sa.Column("resource", sa.String(), nullable=True),
        "model_level": sa.Column("model_level", sa.String(), nullable=True),
        "duration_ms": sa.Column("duration_ms", sa.Integer(), nullable=True),
        "cost_amount": sa.Column("cost_amount", sa.Numeric(12, 4), nullable=True),
        "outcome": sa.Column("outcome", sa.String(), nullable=True),
        "activity_json": sa.Column("activity_json", sa.JSON(), nullable=True),
    }
    for name, column in job_columns.items():
        if not _has_column("process_jobs", name):
            op.add_column("process_jobs", column)

    if "uq_regia_one_open_job_per_claim" not in {index["name"] for index in sa.inspect(op.get_bind()).get_indexes("process_jobs")}:
        op.create_index(
            "uq_regia_one_open_job_per_claim",
            "process_jobs",
            ["tenant_id", "claim_id"],
            unique=True,
            postgresql_where=sa.text("phase IS NOT NULL AND status IN ('pending', 'processing', 'retry')"),
        )

    if not _has_column("mailboxes", "gmail_history_id"):
        op.add_column("mailboxes", sa.Column("gmail_history_id", sa.String(), nullable=True))
    if not _has_column("mailboxes", "gmail_watch_expiration"):
        op.add_column("mailboxes", sa.Column("gmail_watch_expiration", sa.DateTime(timezone=True), nullable=True))

    op.execute(
        """
        DO $$
        DECLARE
            tbl text;
        BEGIN
            FOREACH tbl IN ARRAY ARRAY[
                'tenant_claim_states',
                'claim_workflows',
                'claim_groups',
                'claim_group_members',
                'claim_estimate_revisions',
                'claim_atti',
                'claim_questions',
                'tenant_rules'
            ]
            LOOP
                IF EXISTS (
                    SELECT 1
                    FROM pg_class c
                    JOIN pg_namespace n ON n.oid = c.relnamespace
                    WHERE n.nspname = 'public'
                      AND c.relname = tbl
                      AND c.relkind = 'r'
                      AND NOT c.relrowsecurity
                ) THEN
                    EXECUTE 'ALTER TABLE public.' || quote_ident(tbl) || ' ENABLE ROW LEVEL SECURITY';
                END IF;
            END LOOP;
        END
        $$;
        """
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS uq_regia_one_open_job_per_claim")
    for column_name in (
        "activity_json",
        "outcome",
        "cost_amount",
        "duration_ms",
        "model_level",
        "resource",
        "phase",
    ):
        if _has_column("process_jobs", column_name):
            op.drop_column("process_jobs", column_name)
    for column_name in ("gmail_watch_expiration", "gmail_history_id"):
        if _has_column("mailboxes", column_name):
            op.drop_column("mailboxes", column_name)
    for table_name in (
        "tenant_rules",
        "claim_questions",
        "claim_atti",
        "claim_estimate_revisions",
        "claim_group_members",
        "claim_groups",
        "claim_workflows",
        "tenant_claim_states",
    ):
        if sa.inspect(op.get_bind()).has_table(table_name):
            op.drop_table(table_name)
