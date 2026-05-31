"""
025 - Aggiunge a claims i riferimenti ad Actor (contraente/assicurato/
danneggiato), agency/compagnia strutturate, e gli snapshot JSON di
indirizzo/IBAN al momento della creazione del sinistro.

Strategia additiva: i campi piatti esistenti (nome_assicurato, ecc.)
restano e verranno rimossi in una migration successiva, quando tutti
i client useranno il nuovo flusso.
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "025"
down_revision = "024"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("claims", sa.Column("contraente_id", sa.String(), nullable=True))
    op.add_column("claims", sa.Column("assicurato_id", sa.String(), nullable=True))
    op.add_column("claims", sa.Column("danneggiato_id", sa.String(), nullable=True))
    op.add_column("claims", sa.Column("agency_id", sa.String(), nullable=True))
    op.add_column("claims", sa.Column("compagnia_id", sa.String(), nullable=True))
    op.add_column("claims", sa.Column("contraente_address_snapshot", sa.JSON(), nullable=True))
    op.add_column("claims", sa.Column("assicurato_address_snapshot", sa.JSON(), nullable=True))
    op.add_column("claims", sa.Column("danneggiato_address_snapshot", sa.JSON(), nullable=True))
    op.add_column("claims", sa.Column("iban_snapshot", sa.JSON(), nullable=True))

    op.create_foreign_key("fk_claims_contraente", "claims", "actors", ["contraente_id"], ["id"])
    op.create_foreign_key("fk_claims_assicurato", "claims", "actors", ["assicurato_id"], ["id"])
    op.create_foreign_key("fk_claims_danneggiato", "claims", "actors", ["danneggiato_id"], ["id"])
    op.create_foreign_key("fk_claims_agency", "claims", "rubrica_agenzie", ["agency_id"], ["id"])
    op.create_foreign_key("fk_claims_compagnia", "claims", "rubrica_compagnie", ["compagnia_id"], ["id"])

    op.create_index("ix_claims_contraente_id", "claims", ["contraente_id"])
    op.create_index("ix_claims_assicurato_id", "claims", ["assicurato_id"])
    op.create_index("ix_claims_danneggiato_id", "claims", ["danneggiato_id"])
    op.create_index("ix_claims_agency_id", "claims", ["agency_id"])
    op.create_index("ix_claims_compagnia_id", "claims", ["compagnia_id"])


def downgrade() -> None:
    op.drop_index("ix_claims_compagnia_id", table_name="claims")
    op.drop_index("ix_claims_agency_id", table_name="claims")
    op.drop_index("ix_claims_danneggiato_id", table_name="claims")
    op.drop_index("ix_claims_assicurato_id", table_name="claims")
    op.drop_index("ix_claims_contraente_id", table_name="claims")
    op.drop_constraint("fk_claims_compagnia", "claims", type_="foreignkey")
    op.drop_constraint("fk_claims_agency", "claims", type_="foreignkey")
    op.drop_constraint("fk_claims_danneggiato", "claims", type_="foreignkey")
    op.drop_constraint("fk_claims_assicurato", "claims", type_="foreignkey")
    op.drop_constraint("fk_claims_contraente", "claims", type_="foreignkey")
    op.drop_column("claims", "iban_snapshot")
    op.drop_column("claims", "danneggiato_address_snapshot")
    op.drop_column("claims", "assicurato_address_snapshot")
    op.drop_column("claims", "contraente_address_snapshot")
    op.drop_column("claims", "compagnia_id")
    op.drop_column("claims", "agency_id")
    op.drop_column("claims", "danneggiato_id")
    op.drop_column("claims", "assicurato_id")
    op.drop_column("claims", "contraente_id")
