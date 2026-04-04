"""Add platform admin support

Revision ID: 002_platform_admin
Revises: 001_initial
Create Date: 2026-04-03 00:00:00.000000
"""
from alembic import op
import sqlalchemy as sa
import uuid
from passlib.context import CryptContext


revision = "002_platform_admin"
down_revision = "001_initial"
branch_labels = None
depends_on = None

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("is_platform_admin", sa.Boolean(), nullable=False, server_default=sa.false())
    )

    connection = op.get_bind()
    platform_tenant_slug = "pynkstudio"
    platform_tenant_name = "Pynk Studio"
    admin_email = "info@pynkstudio.it"
    admin_name = "Pynk Studio Admin"
    admin_password_hash = pwd_context.hash("change-me-now")

    tenant_row = connection.execute(
        sa.text("SELECT id FROM tenants WHERE slug = :slug"),
        {"slug": platform_tenant_slug}
    ).fetchone()

    if tenant_row:
        platform_tenant_id = tenant_row[0]
    else:
        platform_tenant_id = str(uuid.uuid4())
        connection.execute(
            sa.text(
                """
                INSERT INTO tenants (id, name, slug)
                VALUES (:id, :name, :slug)
                """
            ),
            {"id": platform_tenant_id, "name": platform_tenant_name, "slug": platform_tenant_slug}
        )

    admin_row = connection.execute(
        sa.text("SELECT id FROM users WHERE email = :email"),
        {"email": admin_email}
    ).fetchone()

    if admin_row:
        connection.execute(
            sa.text(
                """
                UPDATE users
                SET tenant_id = :tenant_id,
                    full_name = COALESCE(full_name, :full_name),
                    is_platform_admin = true,
                    is_active = true
                WHERE email = :email
                """
            ),
            {
                "tenant_id": platform_tenant_id,
                "full_name": admin_name,
                "email": admin_email
            }
        )
    else:
        connection.execute(
            sa.text(
                """
                INSERT INTO users (id, tenant_id, email, full_name, password_hash, is_active, is_platform_admin)
                VALUES (:id, :tenant_id, :email, :full_name, :password_hash, true, true)
                """
            ),
            {
                "id": str(uuid.uuid4()),
                "tenant_id": platform_tenant_id,
                "email": admin_email,
                "full_name": admin_name,
                "password_hash": admin_password_hash
            }
        )

    op.alter_column("users", "is_platform_admin", server_default=None)


def downgrade() -> None:
    connection = op.get_bind()
    connection.execute(
        sa.text("DELETE FROM users WHERE email = :email"),
        {"email": "info@pynkstudio.it"}
    )
    connection.execute(
        sa.text("DELETE FROM tenants WHERE slug = :slug"),
        {"slug": "pynkstudio"}
    )
    op.drop_column("users", "is_platform_admin")
