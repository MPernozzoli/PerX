"""Add claim iban value and portal resume structures

Revision ID: 005_portal_resume_and_claim_iban
Revises: 004_inspection_workflow
Create Date: 2026-04-08 00:00:00.000000
"""
from alembic import op
import sqlalchemy as sa


revision = "005_portal_resume_and_claim_iban"
down_revision = "004_inspection_workflow"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("claims", sa.Column("iban_value", sa.String(), nullable=True))


def downgrade() -> None:
    op.drop_column("claims", "iban_value")
