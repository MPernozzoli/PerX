"""
030 - Portale assicurato: privacy, notifiche, sessioni, richieste cancellazione.

  * portal_privacy_policies     - versioning markdown per tenant
  * portal_consents             - registro accettazioni con IP/UA/timestamp
  * portal_deletion_requests    - richieste art. 17 con countdown 5 anni
  * portal_notification_prefs   - preferenze contatto (legate all'Actor)
  * portal_sessions             - sessioni attive per "disconnetti dispositivi"
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "030_portal_gdpr"
down_revision = "033_seed_sinistri_ai"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ---- portal_privacy_policies --------------------------------------
    op.create_table(
        "portal_privacy_policies",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("version", sa.Integer(), nullable=False),
        sa.Column("content_md", sa.Text(), nullable=False),
        sa.Column("title", sa.String(), nullable=True),
        sa.Column("summary", sa.String(), nullable=True),
        sa.Column("effective_from", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("created_by_user_id", sa.String(), sa.ForeignKey("users.id"), nullable=True),
        sa.UniqueConstraint("tenant_id", "version", name="uq_privacy_policy_tenant_version"),
    )
    op.create_index("ix_portal_privacy_policies_tenant_id", "portal_privacy_policies", ["tenant_id"])

    # ---- portal_consents ----------------------------------------------
    op.create_table(
        "portal_consents",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("portal_access_id", sa.String(), sa.ForeignKey("portal_claim_accesses.id"), nullable=False),
        sa.Column("actor_id", sa.String(), sa.ForeignKey("actors.id"), nullable=True),
        sa.Column("policy_id", sa.String(), sa.ForeignKey("portal_privacy_policies.id"), nullable=False),
        sa.Column("policy_version", sa.Integer(), nullable=False),
        sa.Column("accepted_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("ip_address", sa.String(), nullable=True),
        sa.Column("user_agent", sa.String(), nullable=True),
        sa.Column("consent_type", sa.String(), nullable=False, server_default="privacy"),
    )
    op.create_index("ix_portal_consents_tenant_id", "portal_consents", ["tenant_id"])
    op.create_index("ix_portal_consents_portal_access_id", "portal_consents", ["portal_access_id"])
    op.create_index("ix_portal_consents_actor_id", "portal_consents", ["actor_id"])
    op.create_index("idx_portal_consent_actor", "portal_consents", ["actor_id"])
    op.create_index("idx_portal_consent_tenant_accepted", "portal_consents", ["tenant_id", "accepted_at"])

    # ---- portal_deletion_requests -------------------------------------
    op.create_table(
        "portal_deletion_requests",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("portal_access_id", sa.String(), sa.ForeignKey("portal_claim_accesses.id"), nullable=False),
        sa.Column("actor_id", sa.String(), sa.ForeignKey("actors.id"), nullable=True),
        sa.Column("requested_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("requested_ip", sa.String(), nullable=True),
        sa.Column("requested_user_agent", sa.String(), nullable=True),
        sa.Column("eligible_from", sa.DateTime(timezone=True), nullable=False),
        sa.Column("status", sa.String(), nullable=False, server_default="pending"),
        sa.Column("processed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("processed_by_user_id", sa.String(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("reason", sa.String(), nullable=True),
        sa.Column("note", sa.String(), nullable=True),
    )
    op.create_index("ix_portal_deletion_requests_tenant_id", "portal_deletion_requests", ["tenant_id"])
    op.create_index("ix_portal_deletion_requests_portal_access_id", "portal_deletion_requests", ["portal_access_id"])
    op.create_index("ix_portal_deletion_requests_actor_id", "portal_deletion_requests", ["actor_id"])
    op.create_index("ix_portal_deletion_requests_eligible_from", "portal_deletion_requests", ["eligible_from"])
    op.create_index("ix_portal_deletion_requests_status", "portal_deletion_requests", ["status"])
    op.create_index("idx_deletion_request_status_eligible", "portal_deletion_requests", ["status", "eligible_from"])

    # ---- portal_notification_prefs ------------------------------------
    op.create_table(
        "portal_notification_prefs",
        sa.Column("actor_id", sa.String(), sa.ForeignKey("actors.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("channel_push", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("channel_email", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("channel_whatsapp", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("channel_sms", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("preferred_channel", sa.String(), nullable=False, server_default="email"),
        sa.Column("allow_phone_calls", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("call_window_start", sa.Time(), nullable=True),
        sa.Column("call_window_end", sa.Time(), nullable=True),
        sa.Column("quiet_hours_start", sa.Time(), nullable=True),
        sa.Column("quiet_hours_end", sa.Time(), nullable=True),
        sa.Column("documents_via_email", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_portal_notification_prefs_tenant_id", "portal_notification_prefs", ["tenant_id"])

    # ---- portal_sessions ----------------------------------------------
    op.create_table(
        "portal_sessions",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("tenant_id", sa.String(), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("portal_access_id", sa.String(), sa.ForeignKey("portal_claim_accesses.id"), nullable=False),
        sa.Column("actor_id", sa.String(), sa.ForeignKey("actors.id"), nullable=True),
        sa.Column("token_hash", sa.String(), nullable=False),
        sa.Column("device_label", sa.String(), nullable=True),
        sa.Column("ip_address", sa.String(), nullable=True),
        sa.Column("user_agent", sa.String(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint("token_hash", name="uq_portal_session_token_hash"),
    )
    op.create_index("ix_portal_sessions_tenant_id", "portal_sessions", ["tenant_id"])
    op.create_index("ix_portal_sessions_portal_access_id", "portal_sessions", ["portal_access_id"])
    op.create_index("ix_portal_sessions_actor_id", "portal_sessions", ["actor_id"])
    op.create_index("idx_portal_session_active", "portal_sessions", ["portal_access_id", "revoked_at"])


def downgrade() -> None:
    op.drop_table("portal_sessions")
    op.drop_table("portal_notification_prefs")
    op.drop_table("portal_deletion_requests")
    op.drop_table("portal_consents")
    op.drop_table("portal_privacy_policies")
