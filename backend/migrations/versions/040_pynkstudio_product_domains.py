"""Add PynkStudio product-domain aliases and merge migration heads.

Revision ID: 040_pynkstudio_domains
Revises: 014_domain_routing_apps, 039_bignami_policy_type_condominio
"""

from __future__ import annotations

from alembic import op


revision = "040_pynkstudio_domains"
down_revision = ("014_domain_routing_apps", "039_bignami_policy_type_condominio")
branch_labels = None
depends_on = None


PRODUCT_DOMAIN_ROUTES = (
    ("perx.pynkstudio.eu", "insight_studio", "PerX public product portal"),
    ("catdispatcher.pynkstudio.eu", "catdispatcher", "CAT Dispatcher product portal"),
    ("bignamionline.pynkstudio.eu", "bignami", "Bignami Online product portal"),
)


def upgrade() -> None:
    for hostname, app, notes in PRODUCT_DOMAIN_ROUTES:
        op.execute(
            f"""
            INSERT INTO domain_routes (hostname, app, destination_url, notes)
            VALUES ('{hostname}', '{app}', NULL, '{notes}')
            ON CONFLICT (hostname) DO UPDATE
            SET app = EXCLUDED.app,
                notes = EXCLUDED.notes,
                is_active = true,
                updated_at = now()
            """
        )


def downgrade() -> None:
    hostnames = ", ".join(f"'{hostname}'" for hostname, _, _ in PRODUCT_DOMAIN_ROUTES)
    op.execute(f"DELETE FROM domain_routes WHERE hostname IN ({hostnames})")
