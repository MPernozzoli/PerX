"""Add document versions table

Revision ID: 006_document_versions
Revises: 005_portal_resume_and_claim_iban
Create Date: 2026-04-08 18:30:00.000000
"""
from alembic import op
import sqlalchemy as sa


revision = "006_document_versions"
down_revision = "005_portal_resume_and_claim_iban"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)

    if not inspector.has_table("document_versions"):
        op.create_table(
            "document_versions",
            sa.Column("id", sa.String(), nullable=False),
            sa.Column("tenant_id", sa.String(), nullable=False),
            sa.Column("document_id", sa.String(), nullable=False),
            sa.Column("version_no", sa.Integer(), nullable=False),
            sa.Column("storage_path", sa.String(), nullable=False),
            sa.Column("size_bytes", sa.BigInteger(), nullable=False, server_default="0"),
            sa.Column("checksum_sha256", sa.String(), nullable=True),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
            sa.Column("created_by_user_id", sa.String(), nullable=True),
            sa.Column("metadata_json", sa.JSON(), nullable=True),
            sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="SET NULL"),
            sa.ForeignKeyConstraint(["document_id"], ["documents.id"], ondelete="CASCADE"),
            sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"], ondelete="CASCADE"),
            sa.PrimaryKeyConstraint("id"),
        )

    existing_indexes = {index["name"] for index in inspector.get_indexes("document_versions")}
    if op.f("ix_document_versions_id") not in existing_indexes:
        op.create_index(op.f("ix_document_versions_id"), "document_versions", ["id"], unique=False)
    if op.f("ix_document_versions_tenant_id") not in existing_indexes:
        op.create_index(op.f("ix_document_versions_tenant_id"), "document_versions", ["tenant_id"], unique=False)
    if op.f("ix_document_versions_document_id") not in existing_indexes:
        op.create_index(op.f("ix_document_versions_document_id"), "document_versions", ["document_id"], unique=False)
    if "ux_document_versions_doc_version" not in existing_indexes:
        op.create_index("ux_document_versions_doc_version", "document_versions", ["document_id", "version_no"], unique=True)


def downgrade() -> None:
    op.drop_index("ux_document_versions_doc_version", table_name="document_versions")
    op.drop_index(op.f("ix_document_versions_document_id"), table_name="document_versions")
    op.drop_index(op.f("ix_document_versions_tenant_id"), table_name="document_versions")
    op.drop_index(op.f("ix_document_versions_id"), table_name="document_versions")
    op.drop_table("document_versions")
