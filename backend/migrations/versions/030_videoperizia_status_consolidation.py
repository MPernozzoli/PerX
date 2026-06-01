"""
030 - Consolidate videoperizia status into a single canonical state with substati.

Pre-cut-over the canonical status was `videoperizia_da_eseguire` with no substato,
plus a separate `da_gestire_video` reached after expert assignment. We now follow
the sopralluogo pattern: a single state `videoperizia` whose lifecycle is tracked
via three reserved substati:

  - da_fissare → insured must pick a slot from the portal
  - fissata    → slot confirmed, waiting for the inspection day
  - da_eseguire → inspection day, expert assigned, call imminent

Rules applied to existing claims:
  - `stato_corrente = 'videoperizia_da_eseguire'` → `'videoperizia'`.
    Substato is derived from metadata:
      * metadata.video_inspection_preferences.confirmed_at present → "fissata"
      * otherwise → "da_fissare"
  - Claims in `da_gestire_video` that were already assigned but the inspection
    has not been performed yet remain in `da_gestire_video` (mid-flow state for
    expert handling); only the legacy SV014 mapping is updated for new data.
"""
from __future__ import annotations

from alembic import op


revision = "030"
down_revision = "029"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Re-tag any pending videoperizia claims under the unified state + substati.
    op.execute(
        """
        UPDATE claims
        SET
            stato_corrente = 'videoperizia',
            stato_substati = CASE
                WHEN (metadata_json #> '{video_inspection_preferences,confirmed_at}') IS NOT NULL
                    THEN jsonb_build_array(jsonb_build_object(
                        'tag', 'fissata',
                        'source', 'system',
                        'added_at', to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
                    ))
                ELSE jsonb_build_array(jsonb_build_object(
                    'tag', 'da_fissare',
                    'source', 'system',
                    'added_at', to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
                ))
            END
        WHERE stato_corrente = 'videoperizia_da_eseguire'
        """
    )


def downgrade() -> None:
    # Best-effort revert: any claim in videoperizia (any substato) goes back to
    # the legacy 'videoperizia_da_eseguire' state with empty substati.
    op.execute(
        """
        UPDATE claims
        SET stato_corrente = 'videoperizia_da_eseguire',
            stato_substati = '[]'::jsonb
        WHERE stato_corrente = 'videoperizia'
        """
    )
