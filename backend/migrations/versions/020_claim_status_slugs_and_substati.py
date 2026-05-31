"""
020 - claim status slugs + substati as JSONB tag list

Cut-over from legacy SVxxx codes to human-readable slugs and from a single
metadata_json.stato_detail string to a structured tag list. The system is in
pre-beta with no production users, so we rewrite data in place with no
backward-compatibility shim.

- Rewrite claims.stato_corrente from SVxxx to the new slug using LEGACY_SV_TO_SLUG.
- Add claims.stato_substati JSONB NOT NULL DEFAULT '[]'.
- Backfill stato_substati from metadata_json.stato_detail (if present) and from
  the substato implied by the legacy state split (e.g. SV022 -> "assicurato").
- Strip stato_detail from metadata_json once moved.
- Rewrite claim_states.from_state and claim_states.to_state with the same map.
- Add a GIN index on stato_substati for tag-based filtering.
"""
from __future__ import annotations

import json

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision = "020"
down_revision = "019"
branch_labels = None
depends_on = None


LEGACY_SV_TO_SLUG: dict[str, tuple[str, str | None]] = {
    "SV001": ("istruzione", None),
    "SV002": ("in_attesa_documentale", None),
    "SV003": ("da_gestire_tradizionale", None),
    "SV004": ("videoperizia_da_eseguire", None),
    "SV005": ("da_gestire_no_residui", None),
    "SV006": ("istruzione", None),
    "SV007": ("primo_contatto", None),
    "SV008": ("secondo_contatto", None),
    "SV009": ("in_attesa_assegnazione", None),
    "SV010": ("da_gestire_documentale", "da_aprire"),
    "SV011": ("da_gestire_documentale", None),
    "SV012": ("in_gestione", None),
    "SV013": ("da_gestire_video", None),
    "SV014": ("da_gestire_video", "fissata"),
    "SV020": ("atto_da_inviare", None),
    "SV021": ("esito_da_comunicare", None),
    "SV022": ("in_attesa_terzi", "assicurato"),
    "SV023": ("in_attesa_terzi", "agenzia"),
    "SV030": ("esito_comunicato", None),
    "SV031": ("atto_inviato", None),
    "SV032": ("atto_ricevuto", "sottoscritto"),
    "SV033": ("atto_ricevuto", "verbale"),
    "SV040": ("da_controllare", None),
    "SV041": ("controllata", None),
    "SV050": ("sopralluogo", "fissato"),
    "SV051": ("sopralluogo", "da_rifissare"),
    "SV052": ("sopralluogo", "da_fissare"),
    "SV053": ("sopralluogo", "da_concordare"),
    "SV090": ("chiusa", None),
    "SV091": ("da_revisionare", None),
    "SV042": ("richiesta_autorizzazione", None),
    "SV043": ("supervisione_non_concordata", None),
}


def upgrade() -> None:
    bind = op.get_bind()

    op.add_column(
        "claims",
        sa.Column(
            "stato_substati",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
    )

    rows = bind.execute(
        sa.text("SELECT id, stato_corrente, metadata_json FROM claims")
    ).fetchall()

    for row in rows:
        claim_id = row[0]
        legacy_state = row[1]
        metadata = row[2] or {}
        if isinstance(metadata, str):
            try:
                metadata = json.loads(metadata)
            except (TypeError, ValueError):
                metadata = {}

        mapping = LEGACY_SV_TO_SLUG.get(legacy_state)
        if mapping is None:
            # Unknown legacy code: park in istruzione with a system tag so it
            # surfaces in review queues rather than silently breaking.
            new_state = "istruzione"
            implied_substato = f"legacy_{legacy_state.lower()}" if legacy_state else "legacy_unknown"
        else:
            new_state, implied_substato = mapping

        substati: list[dict] = []
        if implied_substato:
            substati.append({
                "tag": implied_substato,
                "source": "system",
                "added_at": "1970-01-01T00:00:00Z",
            })

        legacy_detail = metadata.pop("stato_detail", None)
        if isinstance(legacy_detail, str) and legacy_detail.strip():
            tag = legacy_detail.strip().lower().replace(" ", "_")
            if not any(s["tag"] == tag for s in substati):
                substati.append({
                    "tag": tag,
                    "source": "system",
                    "added_at": "1970-01-01T00:00:00Z",
                })

        bind.execute(
            sa.text(
                "UPDATE claims "
                "SET stato_corrente = :new_state, "
                "    stato_substati = CAST(:substati AS JSONB), "
                "    metadata_json = CAST(:metadata AS JSONB) "
                "WHERE id = :id"
            ),
            {
                "new_state": new_state,
                "substati": json.dumps(substati),
                "metadata": json.dumps(metadata) if metadata else None,
                "id": claim_id,
            },
        )

    # Rewrite history table so reading old transitions doesn't require a mapping
    # layer in app code.
    history_rows = bind.execute(
        sa.text("SELECT id, from_state, to_state FROM claim_states")
    ).fetchall()
    for hrow in history_rows:
        hid, from_legacy, to_legacy = hrow[0], hrow[1], hrow[2]
        from_new = LEGACY_SV_TO_SLUG.get(from_legacy, (None, None))[0] if from_legacy else None
        to_new = LEGACY_SV_TO_SLUG.get(to_legacy, (to_legacy, None))[0] if to_legacy else to_legacy
        bind.execute(
            sa.text(
                "UPDATE claim_states SET from_state = :f, to_state = :t WHERE id = :id"
            ),
            {"f": from_new, "t": to_new, "id": hid},
        )

    op.create_index(
        "idx_claims_substati_gin",
        "claims",
        ["stato_substati"],
        postgresql_using="gin",
    )


def downgrade() -> None:
    # Cut-over migration. Pre-beta with no production data we care about; the
    # legacy code list is preserved in git history if a forensic rollback is
    # ever needed.
    op.drop_index("idx_claims_substati_gin", table_name="claims")
    op.drop_column("claims", "stato_substati")
