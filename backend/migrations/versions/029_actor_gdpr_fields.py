"""
029 - Hardening GDPR per anagrafica Actor.

  * actors.deleted_at        - soft delete (art. 17 diritto all'oblio)
  * actor_relations.legal_basis + legal_basis_note - base giuridica
    del trattamento del sub-contatto (art. 6).
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "029"
down_revision = "028"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("actors", sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True))
    op.create_index("ix_actors_deleted_at", "actors", ["deleted_at"])

    op.add_column("actor_relations", sa.Column("legal_basis", sa.String(), nullable=True))
    op.add_column("actor_relations", sa.Column("legal_basis_note", sa.String(), nullable=True))


def downgrade() -> None:
    op.drop_column("actor_relations", "legal_basis_note")
    op.drop_column("actor_relations", "legal_basis")
    op.drop_index("ix_actors_deleted_at", table_name="actors")
    op.drop_column("actors", "deleted_at")
