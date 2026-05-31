"""
028 - tabelle a supporto del planner percorsi con Google Routes e storico CAT.

- `route_travel_estimates`: cache tempi di viaggio (Google Routes API).
  Chiave su grid lat/lon arrotondato a 1 decimale (~11 km) + day-of-week +
  hour bucket, così abbattiamo il numero di chiamate API per coppie ricorrenti.
- `cat_inspection_duration_stats`: mediana minuti effettivi per CAT e bucket
  numero beni, ricalcolata on-demand dai sopralluoghi chiusi.
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "028"
down_revision = "027"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "route_travel_estimates",
        sa.Column("origin_grid", sa.String(length=32), nullable=False),
        sa.Column("dest_grid", sa.String(length=32), nullable=False),
        sa.Column("dow", sa.SmallInteger, nullable=False),
        sa.Column("hour_bucket", sa.SmallInteger, nullable=False),
        sa.Column("minutes", sa.Integer, nullable=False),
        sa.Column("source", sa.String(length=32), nullable=False, server_default="google"),
        sa.Column("fetched_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.PrimaryKeyConstraint("origin_grid", "dest_grid", "dow", "hour_bucket"),
    )
    op.create_index(
        "idx_route_travel_estimates_fetched",
        "route_travel_estimates",
        ["fetched_at"],
    )

    op.create_table(
        "cat_inspection_duration_stats",
        sa.Column("tenant_id", sa.String, sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("cat_user_id", sa.String, sa.ForeignKey("users.id"), nullable=False),
        sa.Column("asset_count_bucket", sa.SmallInteger, nullable=False),
        sa.Column("median_minutes", sa.Integer, nullable=False),
        sa.Column("sample_size", sa.Integer, nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.PrimaryKeyConstraint("tenant_id", "cat_user_id", "asset_count_bucket"),
    )
    op.create_index(
        "idx_cat_duration_stats_cat",
        "cat_inspection_duration_stats",
        ["cat_user_id", "asset_count_bucket"],
    )


def downgrade() -> None:
    op.drop_index("idx_cat_duration_stats_cat", table_name="cat_inspection_duration_stats")
    op.drop_table("cat_inspection_duration_stats")
    op.drop_index("idx_route_travel_estimates_fetched", table_name="route_travel_estimates")
    op.drop_table("route_travel_estimates")
