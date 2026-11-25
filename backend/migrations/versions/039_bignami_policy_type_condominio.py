"""
039 - bignami.policies.type: aggiunge 'condominio' (polizze globali fabbricati / condomini).

Richiesto dal flusso sinistri Chiari (db/polizze.json → blocco bignami): le polizze condominiali
non sono né domestiche né aziendali.
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "039_bignami_policy_type_condominio"
down_revision = "038_platform_error_log"
branch_labels = None
depends_on = None


def _has_bignami_policies() -> bool:
    return sa.inspect(op.get_bind()).has_table("policies", schema="bignami")


def upgrade() -> None:
    # Bignami is an optional satellite schema. Some PerX production databases
    # are stamped through the shared migration chain without hosting that app.
    if not _has_bignami_policies():
        return
    op.execute("ALTER TABLE bignami.policies DROP CONSTRAINT IF EXISTS policies_type_check")
    op.execute(
        "ALTER TABLE bignami.policies ADD CONSTRAINT policies_type_check "
        "CHECK (type IN ('domestica', 'condominio', 'azienda', 'agricola'))"
    )


def downgrade() -> None:
    if not _has_bignami_policies():
        return
    op.execute("UPDATE bignami.policies SET type = 'domestica' WHERE type = 'condominio'")
    op.execute("ALTER TABLE bignami.policies DROP CONSTRAINT IF EXISTS policies_type_check")
    op.execute(
        "ALTER TABLE bignami.policies ADD CONSTRAINT policies_type_check "
        "CHECK (type IN ('domestica', 'azienda', 'agricola'))"
    )
