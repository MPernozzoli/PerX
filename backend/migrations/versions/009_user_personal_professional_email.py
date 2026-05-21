"""Add personal and professional user email identities

Revision ID: 009_user_personal_professional_email
Revises: 008_server_automation_trigger_states
Create Date: 2026-05-21 00:00:00.000000
"""
from alembic import op
import sqlalchemy as sa


revision = "009_user_personal_professional_email"
down_revision = "008_server_automation_trigger_states"
branch_labels = None
depends_on = None


def _columns(table_name: str) -> set[str]:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return {column["name"] for column in inspector.get_columns(table_name)}


def _indexes(table_name: str) -> set[str]:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if not inspector.has_table(table_name):
        return set()
    return {index["name"] for index in inspector.get_indexes(table_name)}


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    user_columns = _columns("users")

    if "personal_email" not in user_columns:
        op.add_column("users", sa.Column("personal_email", sa.String(), nullable=True))
        op.execute("UPDATE users SET personal_email = lower(email) WHERE personal_email IS NULL")

    if "professional_email" not in user_columns:
        op.add_column("users", sa.Column("professional_email", sa.String(), nullable=True))

    existing_user_indexes = _indexes("users")
    if op.f("ix_users_personal_email") not in existing_user_indexes:
        op.create_index(op.f("ix_users_personal_email"), "users", ["personal_email"], unique=True)
    if op.f("ix_users_professional_email") not in existing_user_indexes:
        op.create_index(op.f("ix_users_professional_email"), "users", ["professional_email"], unique=True)

    if not inspector.has_table("email_aliases"):
        op.create_table(
            "email_aliases",
            sa.Column("id", sa.String(), nullable=False),
            sa.Column("tenant_id", sa.String(), nullable=False),
            sa.Column("domain_id", sa.String(), nullable=True),
            sa.Column("address", sa.String(), nullable=False),
            sa.Column("local_part", sa.String(), nullable=False),
            sa.Column("target_type", sa.String(), nullable=False, server_default="user"),
            sa.Column("target_id", sa.String(), nullable=True),
            sa.Column("is_primary", sa.String(), nullable=False, server_default="false"),
            sa.Column("is_active", sa.String(), nullable=False, server_default="true"),
            sa.Column("source", sa.String(), nullable=False, server_default="auto"),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
            sa.Column("retired_at", sa.DateTime(timezone=True), nullable=True),
            sa.ForeignKeyConstraint(["domain_id"], ["tenant_email_domains.id"], ondelete="SET NULL"),
            sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint("address", name="uq_email_aliases_address"),
        )

    existing_alias_indexes = _indexes("email_aliases")
    for name, columns, unique in (
        (op.f("ix_email_aliases_id"), ["id"], False),
        (op.f("ix_email_aliases_tenant_id"), ["tenant_id"], False),
        (op.f("ix_email_aliases_domain_id"), ["domain_id"], False),
        (op.f("ix_email_aliases_address"), ["address"], True),
        (op.f("ix_email_aliases_local_part"), ["local_part"], False),
        (op.f("ix_email_aliases_target_type"), ["target_type"], False),
        (op.f("ix_email_aliases_target_id"), ["target_id"], False),
        ("idx_email_aliases_tenant_target", ["tenant_id", "target_type", "target_id"], False),
        ("idx_email_aliases_tenant_local_part", ["tenant_id", "local_part"], False),
    ):
        if name not in existing_alias_indexes:
            op.create_index(name, "email_aliases", columns, unique=unique)


def downgrade() -> None:
    if sa.inspect(op.get_bind()).has_table("email_aliases"):
        for name in (
            "idx_email_aliases_tenant_local_part",
            "idx_email_aliases_tenant_target",
            op.f("ix_email_aliases_target_id"),
            op.f("ix_email_aliases_target_type"),
            op.f("ix_email_aliases_local_part"),
            op.f("ix_email_aliases_address"),
            op.f("ix_email_aliases_domain_id"),
            op.f("ix_email_aliases_tenant_id"),
            op.f("ix_email_aliases_id"),
        ):
            op.drop_index(name, table_name="email_aliases")
        op.drop_table("email_aliases")

    existing_user_indexes = _indexes("users")
    if op.f("ix_users_professional_email") in existing_user_indexes:
        op.drop_index(op.f("ix_users_professional_email"), table_name="users")
    if op.f("ix_users_personal_email") in existing_user_indexes:
        op.drop_index(op.f("ix_users_personal_email"), table_name="users")

    user_columns = _columns("users")
    if "professional_email" in user_columns:
        op.drop_column("users", "professional_email")
    if "personal_email" in user_columns:
        op.drop_column("users", "personal_email")
