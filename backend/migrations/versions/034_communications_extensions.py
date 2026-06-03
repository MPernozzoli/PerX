"""
034 - Communications virtual extensions on users.
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "034_communications_extensions"
down_revision = "030_portal_gdpr"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("users", sa.Column("extension_number", sa.String(length=3), nullable=True))
    op.add_column("users", sa.Column("extension_enabled", sa.Boolean(), nullable=False, server_default=sa.false()))
    op.add_column("users", sa.Column("extension_assigned_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("users", sa.Column("extension_display_name", sa.String(), nullable=True))
    op.add_column("users", sa.Column("availability_status", sa.String(), nullable=False, server_default="available"))
    op.add_column("users", sa.Column("communication_status", sa.String(), nullable=False, server_default="idle"))
    op.create_index("ix_users_extension_number", "users", ["extension_number"])
    op.create_unique_constraint(
        "uq_users_tenant_extension_number",
        "users",
        ["tenant_id", "extension_number"],
    )


def downgrade() -> None:
    op.drop_constraint("uq_users_tenant_extension_number", "users", type_="unique")
    op.drop_index("ix_users_extension_number", table_name="users")
    op.drop_column("users", "communication_status")
    op.drop_column("users", "availability_status")
    op.drop_column("users", "extension_display_name")
    op.drop_column("users", "extension_assigned_at")
    op.drop_column("users", "extension_enabled")
    op.drop_column("users", "extension_number")
