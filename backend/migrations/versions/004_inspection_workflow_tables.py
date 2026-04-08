"""Add inspection workflow normalized tables

Revision ID: 004_inspection_workflow
Revises: 003_portal_architecture
Create Date: 2026-04-08 00:00:00.000000
"""
from alembic import op
import sqlalchemy as sa


revision = "004_inspection_workflow"
down_revision = "003_portal_architecture"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "inspection_preferences",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("tenant_id", sa.String(), nullable=False),
        sa.Column("claim_id", sa.String(), nullable=False),
        sa.Column("address_line", sa.String(), nullable=True),
        sa.Column("municipality", sa.String(), nullable=True),
        sa.Column("province", sa.String(), nullable=True),
        sa.Column("region", sa.String(), nullable=True),
        sa.Column("latitude", sa.Numeric(10, 6), nullable=True),
        sa.Column("longitude", sa.Numeric(10, 6), nullable=True),
        sa.Column("confirmed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("requested_duration_minutes", sa.Integer(), nullable=True),
        sa.Column("notes", sa.String(), nullable=True),
        sa.Column("source", sa.String(), nullable=False, server_default="portal"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["claim_id"], ["claims.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_inspection_preferences_id"), "inspection_preferences", ["id"], unique=False)
    op.create_index(op.f("ix_inspection_preferences_tenant_id"), "inspection_preferences", ["tenant_id"], unique=False)
    op.create_index(op.f("ix_inspection_preferences_claim_id"), "inspection_preferences", ["claim_id"], unique=False)
    op.create_index("uq_inspection_preferences_claim", "inspection_preferences", ["claim_id"], unique=True)

    op.create_table(
        "inspection_preference_slots",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("tenant_id", sa.String(), nullable=False),
        sa.Column("preference_id", sa.String(), nullable=False),
        sa.Column("slot_date", sa.Date(), nullable=False),
        sa.Column("start_time", sa.Time(), nullable=False),
        sa.Column("end_time", sa.Time(), nullable=False),
        sa.Column("label", sa.String(), nullable=True),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["preference_id"], ["inspection_preferences.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_inspection_preference_slots_id"), "inspection_preference_slots", ["id"], unique=False)
    op.create_index(op.f("ix_inspection_preference_slots_tenant_id"), "inspection_preference_slots", ["tenant_id"], unique=False)
    op.create_index(op.f("ix_inspection_preference_slots_preference_id"), "inspection_preference_slots", ["preference_id"], unique=False)
    op.create_index(op.f("ix_inspection_preference_slots_slot_date"), "inspection_preference_slots", ["slot_date"], unique=False)
    op.create_index("idx_inspection_pref_slots_pref_date", "inspection_preference_slots", ["preference_id", "slot_date"], unique=False)

    op.create_table(
        "inspection_availability_overrides",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("tenant_id", sa.String(), nullable=False),
        sa.Column("user_id", sa.String(), nullable=False),
        sa.Column("override_date", sa.Date(), nullable=False),
        sa.Column("is_available", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("note", sa.String(), nullable=True),
        sa.Column("source", sa.String(), nullable=False, server_default="cat_ipad"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_inspection_availability_overrides_id"), "inspection_availability_overrides", ["id"], unique=False)
    op.create_index(op.f("ix_inspection_availability_overrides_tenant_id"), "inspection_availability_overrides", ["tenant_id"], unique=False)
    op.create_index(op.f("ix_inspection_availability_overrides_user_id"), "inspection_availability_overrides", ["user_id"], unique=False)
    op.create_index(op.f("ix_inspection_availability_overrides_override_date"), "inspection_availability_overrides", ["override_date"], unique=False)
    op.create_index(
        "uq_inspection_availability_override_user_date",
        "inspection_availability_overrides",
        ["user_id", "override_date"],
        unique=True,
    )

    op.create_table(
        "inspection_availability_windows",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("tenant_id", sa.String(), nullable=False),
        sa.Column("override_id", sa.String(), nullable=False),
        sa.Column("start_time", sa.Time(), nullable=False),
        sa.Column("end_time", sa.Time(), nullable=False),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["override_id"], ["inspection_availability_overrides.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_inspection_availability_windows_id"), "inspection_availability_windows", ["id"], unique=False)
    op.create_index(op.f("ix_inspection_availability_windows_tenant_id"), "inspection_availability_windows", ["tenant_id"], unique=False)
    op.create_index(op.f("ix_inspection_availability_windows_override_id"), "inspection_availability_windows", ["override_id"], unique=False)
    op.create_index("idx_inspection_availability_windows_override", "inspection_availability_windows", ["override_id", "sort_order"], unique=False)

    op.create_table(
        "inspection_route_proposals",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("tenant_id", sa.String(), nullable=False),
        sa.Column("owner_user_id", sa.String(), nullable=False),
        sa.Column("title", sa.String(), nullable=False),
        sa.Column("description", sa.String(), nullable=True),
        sa.Column("plan_date", sa.Date(), nullable=False),
        sa.Column("status", sa.String(), nullable=False, server_default="proposed"),
        sa.Column("generated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("review_deadline", sa.DateTime(timezone=True), nullable=True),
        sa.Column("accepted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("accepted_by_user_id", sa.String(), nullable=True),
        sa.Column("rejection_reason_code", sa.String(), nullable=True),
        sa.Column("rejection_reason", sa.String(), nullable=True),
        sa.Column("source", sa.String(), nullable=False, server_default="inspection_automation"),
        sa.Column("has_configured_poi", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("total_distance_km", sa.Numeric(10, 2), nullable=False, server_default="0"),
        sa.Column("total_duration_minutes", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("tenant_names_json", sa.JSON(), nullable=True),
        sa.Column("metadata_json", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["accepted_by_user_id"], ["users.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["owner_user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_inspection_route_proposals_id"), "inspection_route_proposals", ["id"], unique=False)
    op.create_index(op.f("ix_inspection_route_proposals_tenant_id"), "inspection_route_proposals", ["tenant_id"], unique=False)
    op.create_index(op.f("ix_inspection_route_proposals_owner_user_id"), "inspection_route_proposals", ["owner_user_id"], unique=False)
    op.create_index(op.f("ix_inspection_route_proposals_plan_date"), "inspection_route_proposals", ["plan_date"], unique=False)
    op.create_index(op.f("ix_inspection_route_proposals_status"), "inspection_route_proposals", ["status"], unique=False)
    op.create_index(op.f("ix_inspection_route_proposals_review_deadline"), "inspection_route_proposals", ["review_deadline"], unique=False)
    op.create_index("idx_inspection_route_proposals_tenant_plan", "inspection_route_proposals", ["tenant_id", "plan_date"], unique=False)

    op.create_table(
        "inspection_route_stops",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("tenant_id", sa.String(), nullable=False),
        sa.Column("proposal_id", sa.String(), nullable=False),
        sa.Column("claim_id", sa.String(), nullable=False),
        sa.Column("claim_reference", sa.String(), nullable=True),
        sa.Column("starts_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ends_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("municipality", sa.String(), nullable=True),
        sa.Column("province", sa.String(), nullable=True),
        sa.Column("region", sa.String(), nullable=True),
        sa.Column("latitude", sa.Numeric(10, 6), nullable=True),
        sa.Column("longitude", sa.Numeric(10, 6), nullable=True),
        sa.Column("masked_location", sa.String(), nullable=True),
        sa.Column("outside_zone", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("distance_from_previous_km", sa.Numeric(10, 2), nullable=False, server_default="0"),
        sa.Column("duration_minutes", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("asset_count", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("complexity", sa.String(), nullable=True),
        sa.Column("manually_fixed", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("note", sa.String(), nullable=True),
        sa.Column("preferred_windows_json", sa.JSON(), nullable=True),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["claim_id"], ["claims.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["proposal_id"], ["inspection_route_proposals.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_inspection_route_stops_id"), "inspection_route_stops", ["id"], unique=False)
    op.create_index(op.f("ix_inspection_route_stops_tenant_id"), "inspection_route_stops", ["tenant_id"], unique=False)
    op.create_index(op.f("ix_inspection_route_stops_proposal_id"), "inspection_route_stops", ["proposal_id"], unique=False)
    op.create_index(op.f("ix_inspection_route_stops_claim_id"), "inspection_route_stops", ["claim_id"], unique=False)
    op.create_index(op.f("ix_inspection_route_stops_starts_at"), "inspection_route_stops", ["starts_at"], unique=False)
    op.create_index("idx_inspection_route_stops_proposal_order", "inspection_route_stops", ["proposal_id", "sort_order"], unique=False)
    op.create_index("idx_inspection_route_stops_claim", "inspection_route_stops", ["claim_id", "proposal_id"], unique=False)

    op.create_table(
        "inspection_tenant_automation_states",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("tenant_id", sa.String(), nullable=False),
        sa.Column("last_route_generation_date", sa.Date(), nullable=True),
        sa.Column("last_route_generation_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_inspection_tenant_automation_states_id"), "inspection_tenant_automation_states", ["id"], unique=False)
    op.create_index(op.f("ix_inspection_tenant_automation_states_tenant_id"), "inspection_tenant_automation_states", ["tenant_id"], unique=False)
    op.create_index("uq_inspection_tenant_automation_state_tenant", "inspection_tenant_automation_states", ["tenant_id"], unique=True)


def downgrade() -> None:
    op.drop_index("uq_inspection_tenant_automation_state_tenant", table_name="inspection_tenant_automation_states")
    op.drop_index(op.f("ix_inspection_tenant_automation_states_tenant_id"), table_name="inspection_tenant_automation_states")
    op.drop_index(op.f("ix_inspection_tenant_automation_states_id"), table_name="inspection_tenant_automation_states")
    op.drop_table("inspection_tenant_automation_states")

    op.drop_index("idx_inspection_route_stops_claim", table_name="inspection_route_stops")
    op.drop_index("idx_inspection_route_stops_proposal_order", table_name="inspection_route_stops")
    op.drop_index(op.f("ix_inspection_route_stops_starts_at"), table_name="inspection_route_stops")
    op.drop_index(op.f("ix_inspection_route_stops_claim_id"), table_name="inspection_route_stops")
    op.drop_index(op.f("ix_inspection_route_stops_proposal_id"), table_name="inspection_route_stops")
    op.drop_index(op.f("ix_inspection_route_stops_tenant_id"), table_name="inspection_route_stops")
    op.drop_index(op.f("ix_inspection_route_stops_id"), table_name="inspection_route_stops")
    op.drop_table("inspection_route_stops")

    op.drop_index("idx_inspection_route_proposals_tenant_plan", table_name="inspection_route_proposals")
    op.drop_index(op.f("ix_inspection_route_proposals_review_deadline"), table_name="inspection_route_proposals")
    op.drop_index(op.f("ix_inspection_route_proposals_status"), table_name="inspection_route_proposals")
    op.drop_index(op.f("ix_inspection_route_proposals_plan_date"), table_name="inspection_route_proposals")
    op.drop_index(op.f("ix_inspection_route_proposals_owner_user_id"), table_name="inspection_route_proposals")
    op.drop_index(op.f("ix_inspection_route_proposals_tenant_id"), table_name="inspection_route_proposals")
    op.drop_index(op.f("ix_inspection_route_proposals_id"), table_name="inspection_route_proposals")
    op.drop_table("inspection_route_proposals")

    op.drop_index("idx_inspection_availability_windows_override", table_name="inspection_availability_windows")
    op.drop_index(op.f("ix_inspection_availability_windows_override_id"), table_name="inspection_availability_windows")
    op.drop_index(op.f("ix_inspection_availability_windows_tenant_id"), table_name="inspection_availability_windows")
    op.drop_index(op.f("ix_inspection_availability_windows_id"), table_name="inspection_availability_windows")
    op.drop_table("inspection_availability_windows")

    op.drop_index("uq_inspection_availability_override_user_date", table_name="inspection_availability_overrides")
    op.drop_index(op.f("ix_inspection_availability_overrides_override_date"), table_name="inspection_availability_overrides")
    op.drop_index(op.f("ix_inspection_availability_overrides_user_id"), table_name="inspection_availability_overrides")
    op.drop_index(op.f("ix_inspection_availability_overrides_tenant_id"), table_name="inspection_availability_overrides")
    op.drop_index(op.f("ix_inspection_availability_overrides_id"), table_name="inspection_availability_overrides")
    op.drop_table("inspection_availability_overrides")

    op.drop_index("idx_inspection_pref_slots_pref_date", table_name="inspection_preference_slots")
    op.drop_index(op.f("ix_inspection_preference_slots_slot_date"), table_name="inspection_preference_slots")
    op.drop_index(op.f("ix_inspection_preference_slots_preference_id"), table_name="inspection_preference_slots")
    op.drop_index(op.f("ix_inspection_preference_slots_tenant_id"), table_name="inspection_preference_slots")
    op.drop_index(op.f("ix_inspection_preference_slots_id"), table_name="inspection_preference_slots")
    op.drop_table("inspection_preference_slots")

    op.drop_index("uq_inspection_preferences_claim", table_name="inspection_preferences")
    op.drop_index(op.f("ix_inspection_preferences_claim_id"), table_name="inspection_preferences")
    op.drop_index(op.f("ix_inspection_preferences_tenant_id"), table_name="inspection_preferences")
    op.drop_index(op.f("ix_inspection_preferences_id"), table_name="inspection_preferences")
    op.drop_table("inspection_preferences")
