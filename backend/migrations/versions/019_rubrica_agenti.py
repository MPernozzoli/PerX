"""
019 - rubrica agenti

Adds tenant-scoped agency contacts to the backend rubrica.
"""
from alembic import op
import sqlalchemy as sa

revision = "019"
down_revision = "018"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "rubrica_agenti",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("agenzia_id", sa.String(), sa.ForeignKey("rubrica_agenzie.id"), nullable=False),
        sa.Column("nome", sa.String(), nullable=False),
        sa.Column("cognome", sa.String(), nullable=False),
        sa.Column("ruolo", sa.String(), nullable=True),
        sa.Column("telefono", sa.String(), nullable=True),
        sa.Column("email", sa.String(), nullable=True),
        sa.Column("note", sa.String(), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), onupdate=sa.func.now(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_rubrica_agenti_tenant_id", "rubrica_agenti", ["tenant_id"])
    op.create_index("ix_rubrica_agenti_agenzia_id", "rubrica_agenti", ["agenzia_id"])
    op.create_index("ix_rubrica_agenti_tenant_agenzia", "rubrica_agenti", ["tenant_id", "agenzia_id"])


def downgrade() -> None:
    op.drop_index("ix_rubrica_agenti_tenant_agenzia", table_name="rubrica_agenti")
    op.drop_index("ix_rubrica_agenti_agenzia_id", table_name="rubrica_agenti")
    op.drop_index("ix_rubrica_agenti_tenant_id", table_name="rubrica_agenti")
    op.drop_table("rubrica_agenti")
