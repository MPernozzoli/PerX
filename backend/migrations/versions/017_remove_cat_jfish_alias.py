"""Remove legacy JFish CAT alias column.

Revision ID: 017
Revises: 016
"""
from alembic import op
import sqlalchemy as sa

revision = "017"
down_revision = "016"
branch_labels = None
depends_on = None


def _has_column(table_name: str, column_name: str) -> bool:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    return any(column["name"] == column_name for column in inspector.get_columns(table_name))


def upgrade() -> None:
    if _has_column("cats", "alias_jfish"):
        op.drop_column("cats", "alias_jfish")


def downgrade() -> None:
    if not _has_column("cats", "alias_jfish"):
        op.add_column("cats", sa.Column("alias_jfish", sa.String(), nullable=True))
