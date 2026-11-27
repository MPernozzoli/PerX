"""Crea il bucket Storage usato da portale, videoperizia e allegati Gmail.

Revision ID: 044_portal_uploads_bucket
Revises: 043_chiari_regia

Senza questa riga Storage risponde 400 a ogni upload: il bucket era documentato
ma non era mai stato creato.
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "044_portal_uploads_bucket"
down_revision = "043_chiari_regia"
branch_labels = None
depends_on = None


def _scalar(sql: str):
    return op.get_bind().execute(sa.text(sql)).scalar()


def upgrade() -> None:
    if not bool(_scalar("SELECT to_regclass('storage.buckets') IS NOT NULL")):
        return
    op.execute(
        """
        INSERT INTO storage.buckets (id, name, public)
        VALUES ('perx-portal-uploads', 'perx-portal-uploads', false)
        ON CONFLICT (id) DO NOTHING
        """
    )


def downgrade() -> None:
    if not bool(_scalar("SELECT to_regclass('storage.buckets') IS NOT NULL")):
        return
    op.execute(
        """
        DELETE FROM storage.buckets
        WHERE id = 'perx-portal-uploads'
          AND NOT EXISTS (
              SELECT 1 FROM storage.objects WHERE bucket_id = 'perx-portal-uploads'
          )
        """
    )
