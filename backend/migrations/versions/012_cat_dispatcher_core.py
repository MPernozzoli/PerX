"""Add CAT Dispatcher core tables

Revision ID: 012_cat_dispatcher_core
Revises: 010_general_process_jobs
Create Date: 2026-05-22 00:00:00.000000
"""
from alembic import op
import sqlalchemy as sa


revision = "012_cat_dispatcher_core"
down_revision = "011_portal_tenant_domains"
branch_labels = None
depends_on = None


def _has_table(name: str) -> bool:
    return sa.inspect(op.get_bind()).has_table(name)


def _indexes(table_name: str) -> set[str]:
    if not _has_table(table_name):
        return set()
    return {index["name"] for index in sa.inspect(op.get_bind()).get_indexes(table_name)}


def _create_index_if_missing(name: str, table: str, columns: list[str], unique: bool = False) -> None:
    if name not in _indexes(table):
        op.create_index(name, table, columns, unique=unique)


def upgrade() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS pgcrypto")

    if not _has_table("cats"):
        op.create_table(
            "cats",
            sa.Column("id", sa.String(), primary_key=True, server_default=sa.text("gen_random_uuid()::text")),
            sa.Column("name", sa.String(), nullable=False),
            sa.Column("code", sa.String(), nullable=True),
            sa.Column("alias_jfish", sa.String(), nullable=True),
            sa.Column("color_hex", sa.String(), nullable=True),
            sa.Column("notes", sa.Text(), nullable=True),
            sa.Column("active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        )

    if not _has_table("communes"):
        op.create_table(
            "communes",
            sa.Column("id", sa.String(), primary_key=True, server_default=sa.text("gen_random_uuid()::text")),
            sa.Column("comune", sa.String(), nullable=False),
            sa.Column("alias", sa.String(), nullable=True),
            sa.Column("provincia", sa.String(), nullable=True),
            sa.Column("provincia_nome", sa.String(), nullable=True),
            sa.Column("quartiere", sa.String(), nullable=True),
            sa.Column("regione", sa.String(), nullable=True),
            sa.Column("centroid_lat", sa.Float(), nullable=True),
            sa.Column("centroid_lng", sa.Float(), nullable=True),
            sa.Column("geom", sa.JSON(), nullable=True),
            sa.Column("use_quartieri", sa.Boolean(), nullable=False, server_default=sa.text("true")),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        )

    if not _has_table("cat_commune"):
        op.create_table(
            "cat_commune",
            sa.Column("id", sa.String(), primary_key=True, server_default=sa.text("gen_random_uuid()::text")),
            sa.Column("cat_id", sa.String(), nullable=False),
            sa.Column("commune_id", sa.String(), nullable=False),
            sa.Column("is_primary", sa.Boolean(), nullable=False, server_default=sa.text("false")),
            sa.Column("intervention_type", sa.String(), nullable=False, server_default="sopralluogo"),
            sa.Column("active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
            sa.Column("notes", sa.Text(), nullable=True),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
            sa.ForeignKeyConstraint(["cat_id"], ["cats.id"], ondelete="CASCADE"),
            sa.ForeignKeyConstraint(["commune_id"], ["communes.id"], ondelete="CASCADE"),
        )

    if not _has_table("cat_suspensions"):
        op.create_table(
            "cat_suspensions",
            sa.Column("id", sa.String(), primary_key=True, server_default=sa.text("gen_random_uuid()::text")),
            sa.Column("cat_id", sa.String(), nullable=False),
            sa.Column("start_date", sa.Date(), nullable=False),
            sa.Column("end_date", sa.Date(), nullable=False),
            sa.Column("reason", sa.String(), nullable=False),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
            sa.ForeignKeyConstraint(["cat_id"], ["cats.id"], ondelete="CASCADE"),
        )

    if not _has_table("cat_availability_rules"):
        op.create_table(
            "cat_availability_rules",
            sa.Column("id", sa.String(), primary_key=True, server_default=sa.text("gen_random_uuid()::text")),
            sa.Column("cat_id", sa.String(), nullable=False),
            sa.Column("weekday", sa.Integer(), nullable=False),
            sa.Column("start_time", sa.Time(), nullable=False),
            sa.Column("end_time", sa.Time(), nullable=False),
            sa.Column("capacity", sa.Integer(), nullable=False, server_default="1"),
            sa.Column("active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
            sa.Column("notes", sa.Text(), nullable=True),
            sa.Column("metadata_json", sa.JSON(), nullable=False, server_default=sa.text("'{}'::jsonb")),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
            sa.ForeignKeyConstraint(["cat_id"], ["cats.id"], ondelete="CASCADE"),
            sa.CheckConstraint("weekday between 1 and 7", name="ck_cat_availability_rules_weekday"),
            sa.CheckConstraint("start_time < end_time", name="ck_cat_availability_rules_window"),
        )

    if not _has_table("cat_availability_overrides"):
        op.create_table(
            "cat_availability_overrides",
            sa.Column("id", sa.String(), primary_key=True, server_default=sa.text("gen_random_uuid()::text")),
            sa.Column("cat_id", sa.String(), nullable=False),
            sa.Column("availability_date", sa.Date(), nullable=False),
            sa.Column("is_available", sa.Boolean(), nullable=False, server_default=sa.text("true")),
            sa.Column("start_time", sa.Time(), nullable=True),
            sa.Column("end_time", sa.Time(), nullable=True),
            sa.Column("capacity", sa.Integer(), nullable=False, server_default="1"),
            sa.Column("reason", sa.Text(), nullable=True),
            sa.Column("metadata_json", sa.JSON(), nullable=False, server_default=sa.text("'{}'::jsonb")),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
            sa.ForeignKeyConstraint(["cat_id"], ["cats.id"], ondelete="CASCADE"),
        )

    if not _has_table("dispatch_requests"):
        op.create_table(
            "dispatch_requests",
            sa.Column("id", sa.String(), primary_key=True, server_default=sa.text("gen_random_uuid()::text")),
            sa.Column("tenant_id", sa.String(), nullable=True),
            sa.Column("external_source", sa.String(), nullable=False),
            sa.Column("tenant_domain", sa.String(), nullable=True),
            sa.Column("external_claim_id", sa.String(), nullable=True),
            sa.Column("claim_reference", sa.String(), nullable=True),
            sa.Column("intervention_type", sa.String(), nullable=False, server_default="sopralluogo"),
            sa.Column("status", sa.String(), nullable=False, server_default="open"),
            sa.Column("priority", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("address_line", sa.Text(), nullable=True),
            sa.Column("comune", sa.String(), nullable=True),
            sa.Column("provincia", sa.String(), nullable=True),
            sa.Column("commune_id", sa.String(), nullable=True),
            sa.Column("latitude", sa.Float(), nullable=True),
            sa.Column("longitude", sa.Float(), nullable=True),
            sa.Column("requested_duration_minutes", sa.Integer(), nullable=False, server_default="45"),
            sa.Column("due_at", sa.DateTime(timezone=True), nullable=True),
            sa.Column("assigned_cat_id", sa.String(), nullable=True),
            sa.Column("notes", sa.Text(), nullable=True),
            sa.Column("metadata_json", sa.JSON(), nullable=False, server_default=sa.text("'{}'::jsonb")),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
            sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
            sa.ForeignKeyConstraint(["commune_id"], ["communes.id"], ondelete="SET NULL"),
            sa.ForeignKeyConstraint(["assigned_cat_id"], ["cats.id"], ondelete="SET NULL"),
        )

    if not _has_table("insured_availability_windows"):
        op.create_table(
            "insured_availability_windows",
            sa.Column("id", sa.String(), primary_key=True, server_default=sa.text("gen_random_uuid()::text")),
            sa.Column("dispatch_request_id", sa.String(), nullable=False),
            sa.Column("window_date", sa.Date(), nullable=False),
            sa.Column("start_time", sa.Time(), nullable=False),
            sa.Column("end_time", sa.Time(), nullable=False),
            sa.Column("preference_rank", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("source", sa.String(), nullable=False, server_default="insured_portal"),
            sa.Column("notes", sa.Text(), nullable=True),
            sa.Column("metadata_json", sa.JSON(), nullable=False, server_default=sa.text("'{}'::jsonb")),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
            sa.ForeignKeyConstraint(["dispatch_request_id"], ["dispatch_requests.id"], ondelete="CASCADE"),
            sa.CheckConstraint("start_time < end_time", name="ck_insured_availability_windows_window"),
        )

    if not _has_table("cat_assignments"):
        op.create_table(
            "cat_assignments",
            sa.Column("id", sa.String(), primary_key=True, server_default=sa.text("gen_random_uuid()::text")),
            sa.Column("dispatch_request_id", sa.String(), nullable=False),
            sa.Column("cat_id", sa.String(), nullable=False),
            sa.Column("status", sa.String(), nullable=False, server_default="proposed"),
            sa.Column("scheduled_start", sa.DateTime(timezone=True), nullable=True),
            sa.Column("scheduled_end", sa.DateTime(timezone=True), nullable=True),
            sa.Column("route_plan_id", sa.String(), nullable=True),
            sa.Column("route_stop_id", sa.String(), nullable=True),
            sa.Column("score", sa.Float(), nullable=True),
            sa.Column("decision_reason", sa.Text(), nullable=True),
            sa.Column("metadata_json", sa.JSON(), nullable=False, server_default=sa.text("'{}'::jsonb")),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
            sa.ForeignKeyConstraint(["dispatch_request_id"], ["dispatch_requests.id"], ondelete="CASCADE"),
            sa.ForeignKeyConstraint(["cat_id"], ["cats.id"], ondelete="RESTRICT"),
        )

    if not _has_table("cat_route_plans"):
        op.create_table(
            "cat_route_plans",
            sa.Column("id", sa.String(), primary_key=True, server_default=sa.text("gen_random_uuid()::text")),
            sa.Column("cat_id", sa.String(), nullable=False),
            sa.Column("route_date", sa.Date(), nullable=False),
            sa.Column("status", sa.String(), nullable=False, server_default="draft"),
            sa.Column("starts_at", sa.DateTime(timezone=True), nullable=True),
            sa.Column("ends_at", sa.DateTime(timezone=True), nullable=True),
            sa.Column("total_distance_km", sa.Float(), nullable=False, server_default="0"),
            sa.Column("total_duration_minutes", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("optimizer_version", sa.String(), nullable=False, server_default="manual-v1"),
            sa.Column("metadata_json", sa.JSON(), nullable=False, server_default=sa.text("'{}'::jsonb")),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
            sa.ForeignKeyConstraint(["cat_id"], ["cats.id"], ondelete="RESTRICT"),
        )

    if not _has_table("cat_route_stops"):
        op.create_table(
            "cat_route_stops",
            sa.Column("id", sa.String(), primary_key=True, server_default=sa.text("gen_random_uuid()::text")),
            sa.Column("route_plan_id", sa.String(), nullable=False),
            sa.Column("assignment_id", sa.String(), nullable=False),
            sa.Column("stop_order", sa.Integer(), nullable=False),
            sa.Column("scheduled_start", sa.DateTime(timezone=True), nullable=True),
            sa.Column("scheduled_end", sa.DateTime(timezone=True), nullable=True),
            sa.Column("address_line", sa.Text(), nullable=True),
            sa.Column("latitude", sa.Float(), nullable=True),
            sa.Column("longitude", sa.Float(), nullable=True),
            sa.Column("distance_from_previous_km", sa.Float(), nullable=False, server_default="0"),
            sa.Column("travel_minutes_from_previous", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("metadata_json", sa.JSON(), nullable=False, server_default=sa.text("'{}'::jsonb")),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
            sa.ForeignKeyConstraint(["route_plan_id"], ["cat_route_plans.id"], ondelete="CASCADE"),
            sa.ForeignKeyConstraint(["assignment_id"], ["cat_assignments.id"], ondelete="CASCADE"),
            sa.UniqueConstraint("route_plan_id", "stop_order", name="uq_cat_route_stops_order"),
            sa.UniqueConstraint("route_plan_id", "assignment_id", name="uq_cat_route_stops_assignment"),
        )

    _create_index_if_missing("idx_communes_name_province", "communes", ["comune", "provincia"])
    _create_index_if_missing("idx_cat_commune_commune", "cat_commune", ["commune_id", "intervention_type", "active"])
    _create_index_if_missing("idx_cat_commune_cat", "cat_commune", ["cat_id"])
    _create_index_if_missing("idx_cat_suspensions_cat_dates", "cat_suspensions", ["cat_id", "start_date", "end_date"])
    _create_index_if_missing("idx_dispatch_requests_tenant_status", "dispatch_requests", ["tenant_id", "status"])
    _create_index_if_missing("idx_dispatch_requests_external", "dispatch_requests", ["external_source", "external_claim_id"])
    _create_index_if_missing("idx_insured_windows_request_date", "insured_availability_windows", ["dispatch_request_id", "window_date"])
    _create_index_if_missing("idx_cat_assignments_cat_status", "cat_assignments", ["cat_id", "status"])
    _create_index_if_missing("idx_cat_route_plans_cat_date", "cat_route_plans", ["cat_id", "route_date"])


def downgrade() -> None:
    for table in (
        "cat_route_stops",
        "cat_route_plans",
        "cat_assignments",
        "insured_availability_windows",
        "dispatch_requests",
        "cat_availability_overrides",
        "cat_availability_rules",
        "cat_suspensions",
        "cat_commune",
        "communes",
        "cats",
    ):
        if _has_table(table):
            op.drop_table(table)
