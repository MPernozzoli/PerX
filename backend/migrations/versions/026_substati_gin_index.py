"""
026 - GIN index su claims.stato_substati

Migration 020 introduceva l'index ma una versione precedente del file
era stata applicata al DB senza crearlo. Ricreiamo qui in modo idempotente.
"""
from alembic import op


revision = "026"
down_revision = "025"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        "CREATE INDEX IF NOT EXISTS idx_claims_substati_gin "
        "ON claims USING gin (stato_substati)"
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS idx_claims_substati_gin")
