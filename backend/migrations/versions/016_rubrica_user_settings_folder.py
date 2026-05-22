"""
016 – rubrica, user_settings, shared_settings, sinistro_folder_requests

Adds:
  • rubrica_agenzie         – agency address book (tenant-scoped)
  • rubrica_liquidatori     – liquidators address book (tenant-scoped)
  • user_settings           – per-user JSON settings blob
  • shared_settings         – per-tenant JSON settings blob
  • sinistro_folder_requests – iPad→Mac ZIP folder request queue
"""
from alembic import op
import sqlalchemy as sa

revision = "016"
down_revision = "015"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ------------------------------------------------------------------
    # rubrica_agenzie
    # ------------------------------------------------------------------
    op.create_table(
        "rubrica_agenzie",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("nome", sa.String(), nullable=False),
        sa.Column("codice", sa.String(), nullable=True),
        sa.Column("indirizzo", sa.String(), nullable=True),
        sa.Column("citta", sa.String(), nullable=True),
        sa.Column("provincia", sa.String(2), nullable=True),
        sa.Column("telefono", sa.String(), nullable=True),
        sa.Column("email", sa.String(), nullable=True),
        sa.Column("compagnia", sa.String(), nullable=True),
        sa.Column("gruppo", sa.String(), nullable=True),
        sa.Column("note", sa.String(), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), onupdate=sa.func.now(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_rubrica_agenzie_tenant_id", "rubrica_agenzie", ["tenant_id"])
    op.create_index("ix_rubrica_agenzie_tenant_compagnia", "rubrica_agenzie", ["tenant_id", "compagnia"])

    # ------------------------------------------------------------------
    # rubrica_liquidatori
    # ------------------------------------------------------------------
    op.create_table(
        "rubrica_liquidatori",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("nome", sa.String(), nullable=True),
        sa.Column("cognome", sa.String(), nullable=False),
        sa.Column("email", sa.String(), nullable=True),
        sa.Column("telefono", sa.String(), nullable=True),
        sa.Column("compagnia", sa.String(), nullable=True),
        sa.Column("zona", sa.String(), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("note", sa.String(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), onupdate=sa.func.now(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_rubrica_liquidatori_tenant_id", "rubrica_liquidatori", ["tenant_id"])
    op.create_index("ix_rubrica_liquidatori_tenant_compagnia", "rubrica_liquidatori", ["tenant_id", "compagnia"])

    # ------------------------------------------------------------------
    # user_settings
    # ------------------------------------------------------------------
    op.create_table(
        "user_settings",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("user_id", sa.String(), sa.ForeignKey("users.id"), nullable=False, unique=True),
        sa.Column("tenant_id", sa.String(), nullable=False),
        sa.Column("settings_json", sa.JSON(), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), onupdate=sa.func.now(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_user_settings_user_id", "user_settings", ["user_id"])
    op.create_index("ix_user_settings_tenant_id", "user_settings", ["tenant_id"])

    # ------------------------------------------------------------------
    # shared_settings
    # ------------------------------------------------------------------
    op.create_table(
        "shared_settings",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=False, unique=True),
        sa.Column("settings_json", sa.JSON(), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), onupdate=sa.func.now(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_shared_settings_tenant_id", "shared_settings", ["tenant_id"])

    # ------------------------------------------------------------------
    # sinistro_folder_requests
    # ------------------------------------------------------------------
    op.create_table(
        "sinistro_folder_requests",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("tenant_id", sa.String(), nullable=False),
        sa.Column("claim_id", sa.String(), nullable=True),
        sa.Column("riferimento", sa.String(), nullable=False),
        sa.Column("requested_by_user_id", sa.String(), nullable=True),
        sa.Column("status", sa.String(), nullable=False, server_default="pending"),
        sa.Column("download_url", sa.String(), nullable=True),
        sa.Column("error_message", sa.String(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_sinistro_folder_requests_tenant_id", "sinistro_folder_requests", ["tenant_id"])
    op.create_index("ix_sinistro_folder_requests_tenant_status", "sinistro_folder_requests", ["tenant_id", "status"])
    op.create_index("ix_sinistro_folder_requests_claim_id", "sinistro_folder_requests", ["claim_id"])


def downgrade() -> None:
    op.drop_index("ix_sinistro_folder_requests_claim_id", table_name="sinistro_folder_requests")
    op.drop_index("ix_sinistro_folder_requests_tenant_status", table_name="sinistro_folder_requests")
    op.drop_index("ix_sinistro_folder_requests_tenant_id", table_name="sinistro_folder_requests")
    op.drop_table("sinistro_folder_requests")

    op.drop_index("ix_shared_settings_tenant_id", table_name="shared_settings")
    op.drop_table("shared_settings")

    op.drop_index("ix_user_settings_tenant_id", table_name="user_settings")
    op.drop_index("ix_user_settings_user_id", table_name="user_settings")
    op.drop_table("user_settings")

    op.drop_index("ix_rubrica_liquidatori_tenant_compagnia", table_name="rubrica_liquidatori")
    op.drop_index("ix_rubrica_liquidatori_tenant_id", table_name="rubrica_liquidatori")
    op.drop_table("rubrica_liquidatori")

    op.drop_index("ix_rubrica_agenzie_tenant_compagnia", table_name="rubrica_agenzie")
    op.drop_index("ix_rubrica_agenzie_tenant_id", table_name="rubrica_agenzie")
    op.drop_table("rubrica_agenzie")
