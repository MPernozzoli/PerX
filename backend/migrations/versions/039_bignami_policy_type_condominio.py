"""
039 - bignami.policies.type: aggiunge 'condominio' (polizze globali fabbricati / condomini).

Richiesto dal flusso sinistri Chiari (db/polizze.json → blocco bignami): le polizze condominiali
non sono né domestiche né aziendali.
"""
from __future__ import annotations

from alembic import op


revision = "039_bignami_policy_type_condominio"
down_revision = "038_platform_error_log"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE bignami.policies DROP CONSTRAINT IF EXISTS policies_type_check")
    op.execute(
        "ALTER TABLE bignami.policies ADD CONSTRAINT policies_type_check "
        "CHECK (type IN ('domestica', 'condominio', 'azienda', 'agricola'))"
    )


def downgrade() -> None:
    op.execute("UPDATE bignami.policies SET type = 'domestica' WHERE type = 'condominio'")
    op.execute("ALTER TABLE bignami.policies DROP CONSTRAINT IF EXISTS policies_type_check")
    op.execute(
        "ALTER TABLE bignami.policies ADD CONSTRAINT policies_type_check "
        "CHECK (type IN ('domestica', 'azienda', 'agricola'))"
    )
