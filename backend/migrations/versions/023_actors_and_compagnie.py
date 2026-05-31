"""
023 - Actors anagrafica + rubrica compagnie + indici cross-sinistro.

Introduce:
  * actors                  - entità unica per contraente/assicurato/danneggiato
                              (persone, aziende, condomini) con CF/PIVA come
                              chiavi naturali.
  * actor_addresses         - lista pura di indirizzi (multipli simultanei),
                              flag is_primary come preferenza UI.
  * actor_ibans             - lista pura di IBAN, idem.
  * actor_relations         - archi tra attori (figlia/padre/amministratore/...)
  * rubrica_compagnie       - rubrica strutturata delle compagnie (oggi è
                              solo una stringa libera su claims.compagnia).
  * actor_agency_links      - indice derivato actor <-> rubrica_agenzie.
  * actor_company_links     - indice derivato actor <-> rubrica_compagnie.
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "023"
down_revision = "022"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ---- actors ---------------------------------------------------------
    op.create_table(
        "actors",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("actor_type", sa.String(), nullable=False),
        sa.Column("nome", sa.String(), nullable=True),
        sa.Column("cognome", sa.String(), nullable=True),
        sa.Column("data_nascita", sa.Date(), nullable=True),
        sa.Column("luogo_nascita", sa.String(), nullable=True),
        sa.Column("sesso", sa.String(length=1), nullable=True),
        sa.Column("denominazione", sa.String(), nullable=True),
        sa.Column("codice_fiscale", sa.String(), nullable=True),
        sa.Column("partita_iva", sa.String(), nullable=True),
        sa.Column("email", sa.String(), nullable=True),
        sa.Column("telefono", sa.String(), nullable=True),
        sa.Column("pec", sa.String(), nullable=True),
        sa.Column("note", sa.String(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("tenant_id", "codice_fiscale", name="uq_actor_tenant_cf"),
        sa.UniqueConstraint("tenant_id", "partita_iva", name="uq_actor_tenant_piva"),
    )
    op.create_index("ix_actors_tenant_id", "actors", ["tenant_id"])
    op.create_index("ix_actors_actor_type", "actors", ["actor_type"])
    op.create_index("ix_actors_codice_fiscale", "actors", ["codice_fiscale"])
    op.create_index("ix_actors_partita_iva", "actors", ["partita_iva"])
    op.create_index("idx_actor_tenant_type", "actors", ["tenant_id", "actor_type"])

    # ---- actor_addresses -----------------------------------------------
    op.create_table(
        "actor_addresses",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("actor_id", sa.String(), sa.ForeignKey("actors.id", ondelete="CASCADE"), nullable=False),
        sa.Column("label", sa.String(), nullable=True),
        sa.Column("indirizzo", sa.String(), nullable=False),
        sa.Column("civico", sa.String(), nullable=True),
        sa.Column("cap", sa.String(), nullable=True),
        sa.Column("citta", sa.String(), nullable=True),
        sa.Column("provincia", sa.String(length=2), nullable=True),
        sa.Column("nazione", sa.String(), nullable=True, server_default="IT"),
        sa.Column("is_primary", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("note", sa.String(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("idx_actor_address_actor", "actor_addresses", ["actor_id"])

    # ---- actor_ibans ----------------------------------------------------
    op.create_table(
        "actor_ibans",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("actor_id", sa.String(), sa.ForeignKey("actors.id", ondelete="CASCADE"), nullable=False),
        sa.Column("iban", sa.String(), nullable=False),
        sa.Column("intestatario", sa.String(), nullable=True),
        sa.Column("banca", sa.String(), nullable=True),
        sa.Column("bic_swift", sa.String(), nullable=True),
        sa.Column("label", sa.String(), nullable=True),
        sa.Column("is_primary", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("note", sa.String(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("idx_actor_iban_actor", "actor_ibans", ["actor_id"])

    # ---- actor_relations ------------------------------------------------
    op.create_table(
        "actor_relations",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("from_actor_id", sa.String(), sa.ForeignKey("actors.id", ondelete="CASCADE"), nullable=False),
        sa.Column("to_actor_id", sa.String(), sa.ForeignKey("actors.id", ondelete="CASCADE"), nullable=False),
        sa.Column("relation_type", sa.String(), nullable=False),
        sa.Column("note", sa.String(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("from_actor_id", "to_actor_id", "relation_type", name="uq_actor_relation"),
    )
    op.create_index("ix_actor_relations_from", "actor_relations", ["from_actor_id"])
    op.create_index("ix_actor_relations_to", "actor_relations", ["to_actor_id"])

    # ---- rubrica_compagnie ---------------------------------------------
    op.create_table(
        "rubrica_compagnie",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("nome", sa.String(), nullable=False),
        sa.Column("gruppo", sa.String(), nullable=True),
        sa.Column("codice", sa.String(), nullable=True),
        sa.Column("partita_iva", sa.String(), nullable=True),
        sa.Column("pec", sa.String(), nullable=True),
        sa.Column("email", sa.String(), nullable=True),
        sa.Column("telefono", sa.String(), nullable=True),
        sa.Column("sito_web", sa.String(), nullable=True),
        sa.Column("note", sa.String(), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("tenant_id", "nome", name="uq_compagnia_tenant_nome"),
    )
    op.create_index("ix_rubrica_compagnie_tenant_id", "rubrica_compagnie", ["tenant_id"])

    # ---- actor_agency_links --------------------------------------------
    op.create_table(
        "actor_agency_links",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("actor_id", sa.String(), sa.ForeignKey("actors.id", ondelete="CASCADE"), nullable=False),
        sa.Column("agency_id", sa.String(), sa.ForeignKey("rubrica_agenzie.id", ondelete="CASCADE"), nullable=False),
        sa.Column("first_seen_claim_id", sa.String(), sa.ForeignKey("claims.id"), nullable=True),
        sa.Column("last_seen_claim_id", sa.String(), sa.ForeignKey("claims.id"), nullable=True),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("claim_count", sa.Integer(), nullable=False, server_default=sa.text("1")),
        sa.UniqueConstraint("actor_id", "agency_id", name="uq_actor_agency"),
    )
    op.create_index("ix_actor_agency_links_tenant_id", "actor_agency_links", ["tenant_id"])
    op.create_index("ix_actor_agency_links_actor_id", "actor_agency_links", ["actor_id"])
    op.create_index("ix_actor_agency_links_agency_id", "actor_agency_links", ["agency_id"])

    # ---- actor_company_links -------------------------------------------
    op.create_table(
        "actor_company_links",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("actor_id", sa.String(), sa.ForeignKey("actors.id", ondelete="CASCADE"), nullable=False),
        sa.Column("compagnia_id", sa.String(), sa.ForeignKey("rubrica_compagnie.id", ondelete="CASCADE"), nullable=False),
        sa.Column("first_seen_claim_id", sa.String(), sa.ForeignKey("claims.id"), nullable=True),
        sa.Column("last_seen_claim_id", sa.String(), sa.ForeignKey("claims.id"), nullable=True),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("claim_count", sa.Integer(), nullable=False, server_default=sa.text("1")),
        sa.UniqueConstraint("actor_id", "compagnia_id", name="uq_actor_compagnia"),
    )
    op.create_index("ix_actor_company_links_tenant_id", "actor_company_links", ["tenant_id"])
    op.create_index("ix_actor_company_links_actor_id", "actor_company_links", ["actor_id"])
    op.create_index("ix_actor_company_links_compagnia_id", "actor_company_links", ["compagnia_id"])


def downgrade() -> None:
    op.drop_table("actor_company_links")
    op.drop_table("actor_agency_links")
    op.drop_table("rubrica_compagnie")
    op.drop_table("actor_relations")
    op.drop_table("actor_ibans")
    op.drop_table("actor_addresses")
    op.drop_table("actors")
