"""Create legacy core tables that predate Alembic

Revision ID: 002b_legacy_core_tables
Revises: 002_platform_admin
Create Date: 2026-11-26

The first environments got 22 core tables (documents, emails, attachments,
audit_log, case_tasks, internal chat, AI chat, ...) through
``Base.metadata.create_all`` instead of a migration, so ``alembic upgrade head``
could not build a database from scratch: 003 already references ``documents``.

The same happened to 72 columns of ``claims`` and ``users`` (later revisions,
e.g. 020, read ``claims.metadata_json``).

This revision recreates those tables and columns as they were before 003, generated from the
models at revision 002 and frozen here. It is idempotent: every table and index
is created only when missing. Environments already past 003 (production) never
run it, because Alembic treats ancestors of the current head as applied.
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql  # noqa: F401  (used by generated column types)

revision = "002b_legacy_core_tables"
down_revision = "002_platform_admin"
branch_labels = None
depends_on = None


def _existing_tables() -> set[str]:
    return set(sa.inspect(op.get_bind()).get_table_names())


def _create_table(name, *columns, **kwargs):
    if name in _existing_tables():
        return
    op.create_table(name, *columns, **kwargs)


def _create_index(index_name, table_name, columns, **kwargs):
    inspector = sa.inspect(op.get_bind())
    if table_name not in inspector.get_table_names():
        return
    if any(index["name"] == index_name for index in inspector.get_indexes(table_name)):
        return
    op.create_index(index_name, table_name, columns, **kwargs)


def _add_column(table_name, column):
    existing = {col["name"] for col in sa.inspect(op.get_bind()).get_columns(table_name)}
    if column.name in existing:
        return
    op.add_column(table_name, column)


def upgrade() -> None:
    _create_table('emails',
    sa.Column('id', sa.String(), nullable=False),
    sa.Column('tenant_id', sa.String(), nullable=False),
    sa.Column('message_id', sa.String(), nullable=False),
    sa.Column('thread_id', sa.String(), nullable=True),
    sa.Column('from_address', sa.String(), nullable=False),
    sa.Column('to_addresses', sa.Text(), nullable=True),
    sa.Column('cc_addresses', sa.Text(), nullable=True),
    sa.Column('subject', sa.String(), nullable=True),
    sa.Column('body_text', sa.Text(), nullable=True),
    sa.Column('body_html', sa.Text(), nullable=True),
    sa.Column('received_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('ingested_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
    sa.Column('status', sa.String(), nullable=False),
    sa.Column('raw_headers', sa.Text(), nullable=True),
    sa.Column('mailbox_id', sa.String(), nullable=True),
    sa.Column('provider_id', sa.String(), nullable=True),
    sa.ForeignKeyConstraint(['tenant_id'], ['tenants.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    _create_index('idx_emails_tenant_received', 'emails', ['tenant_id', 'received_at'], unique=False)
    _create_index(op.f('ix_emails_from_address'), 'emails', ['from_address'], unique=False)
    _create_index(op.f('ix_emails_id'), 'emails', ['id'], unique=False)
    _create_index(op.f('ix_emails_mailbox_id'), 'emails', ['mailbox_id'], unique=False)
    _create_index(op.f('ix_emails_message_id'), 'emails', ['message_id'], unique=True)
    _create_index(op.f('ix_emails_received_at'), 'emails', ['received_at'], unique=False)
    _create_index(op.f('ix_emails_tenant_id'), 'emails', ['tenant_id'], unique=False)
    _create_index(op.f('ix_emails_thread_id'), 'emails', ['thread_id'], unique=False)
    _create_table('mailboxes',
    sa.Column('id', sa.String(), nullable=False),
    sa.Column('tenant_id', sa.String(), nullable=False),
    sa.Column('label', sa.String(), nullable=False),
    sa.Column('provider', sa.String(), nullable=False),
    sa.Column('email_address', sa.String(), nullable=False),
    sa.Column('auth_type', sa.String(), nullable=False),
    sa.Column('oauth_token_ref', sa.String(), nullable=True),
    sa.Column('password_secret_ref', sa.String(), nullable=True),
    sa.Column('settings_json', sa.JSON(), nullable=True),
    sa.Column('active', sa.String(), nullable=False),
    sa.ForeignKeyConstraint(['tenant_id'], ['tenants.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    _create_index(op.f('ix_mailboxes_id'), 'mailboxes', ['id'], unique=False)
    _create_index(op.f('ix_mailboxes_tenant_id'), 'mailboxes', ['tenant_id'], unique=False)
    _create_table('audit_log',
    sa.Column('id', sa.String(), nullable=False),
    sa.Column('tenant_id', sa.String(), nullable=False),
    sa.Column('user_id', sa.String(), nullable=True),
    sa.Column('action', sa.String(), nullable=False),
    sa.Column('entity_type', sa.String(), nullable=False),
    sa.Column('entity_id', sa.String(), nullable=False),
    sa.Column('timestamp', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
    sa.Column('ip_address', sa.String(), nullable=True),
    sa.Column('user_agent', sa.String(), nullable=True),
    sa.Column('details_json', sa.JSON(), nullable=True),
    sa.ForeignKeyConstraint(['tenant_id'], ['tenants.id'], ),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    _create_index('idx_audit_log_entity', 'audit_log', ['entity_type', 'entity_id'], unique=False)
    _create_index('idx_audit_log_tenant_timestamp', 'audit_log', ['tenant_id', 'timestamp'], unique=False)
    _create_index(op.f('ix_audit_log_action'), 'audit_log', ['action'], unique=False)
    _create_index(op.f('ix_audit_log_entity_id'), 'audit_log', ['entity_id'], unique=False)
    _create_index(op.f('ix_audit_log_entity_type'), 'audit_log', ['entity_type'], unique=False)
    _create_index(op.f('ix_audit_log_id'), 'audit_log', ['id'], unique=False)
    _create_index(op.f('ix_audit_log_tenant_id'), 'audit_log', ['tenant_id'], unique=False)
    _create_index(op.f('ix_audit_log_timestamp'), 'audit_log', ['timestamp'], unique=False)
    _create_index(op.f('ix_audit_log_user_id'), 'audit_log', ['user_id'], unique=False)
    _create_table('dashboard_widgets',
    sa.Column('id', sa.String(), nullable=False),
    sa.Column('tenant_id', sa.String(), nullable=False),
    sa.Column('user_id', sa.String(), nullable=False),
    sa.Column('widget_key', sa.String(), nullable=False),
    sa.Column('position', sa.Integer(), nullable=False),
    sa.Column('enabled', sa.Boolean(), nullable=False),
    sa.Column('settings_json', sa.JSON(), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
    sa.ForeignKeyConstraint(['tenant_id'], ['tenants.id'], ),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    _create_index(op.f('ix_dashboard_widgets_id'), 'dashboard_widgets', ['id'], unique=False)
    _create_index(op.f('ix_dashboard_widgets_tenant_id'), 'dashboard_widgets', ['tenant_id'], unique=False)
    _create_index(op.f('ix_dashboard_widgets_user_id'), 'dashboard_widgets', ['user_id'], unique=False)
    _create_table('user_profile_assets',
    sa.Column('id', sa.String(), nullable=False),
    sa.Column('tenant_id', sa.String(), nullable=False),
    sa.Column('user_id', sa.String(), nullable=False),
    sa.Column('asset_type', sa.String(), nullable=False),
    sa.Column('file_name', sa.String(), nullable=False),
    sa.Column('mime_type', sa.String(), nullable=True),
    sa.Column('size_bytes', sa.BigInteger(), nullable=False),
    sa.Column('storage_provider', sa.String(), nullable=False),
    sa.Column('storage_path', sa.String(), nullable=False),
    sa.Column('checksum_sha256', sa.String(), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
    sa.ForeignKeyConstraint(['tenant_id'], ['tenants.id'], ),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    _create_index(op.f('ix_user_profile_assets_id'), 'user_profile_assets', ['id'], unique=False)
    _create_index(op.f('ix_user_profile_assets_tenant_id'), 'user_profile_assets', ['tenant_id'], unique=False)
    _create_index(op.f('ix_user_profile_assets_user_id'), 'user_profile_assets', ['user_id'], unique=False)
    _create_index('uq_user_profile_assets_user_type', 'user_profile_assets', ['user_id', 'asset_type'], unique=True)
    _create_table('user_work_schedules',
    sa.Column('id', sa.String(), nullable=False),
    sa.Column('tenant_id', sa.String(), nullable=False),
    sa.Column('user_id', sa.String(), nullable=False),
    sa.Column('weekday', sa.Integer(), nullable=False),
    sa.Column('start_time', sa.Time(), nullable=False),
    sa.Column('end_time', sa.Time(), nullable=False),
    sa.Column('location', sa.String(), nullable=True),
    sa.Column('slot_type', sa.String(), nullable=False),
    sa.Column('effective_from', sa.Date(), nullable=True),
    sa.Column('effective_to', sa.Date(), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
    sa.Column('metadata_json', sa.JSON(), nullable=True),
    sa.ForeignKeyConstraint(['tenant_id'], ['tenants.id'], ),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    _create_index(op.f('ix_user_work_schedules_id'), 'user_work_schedules', ['id'], unique=False)
    _create_index(op.f('ix_user_work_schedules_tenant_id'), 'user_work_schedules', ['tenant_id'], unique=False)
    _create_index(op.f('ix_user_work_schedules_user_id'), 'user_work_schedules', ['user_id'], unique=False)
    _create_table('ai_chat_sessions',
    sa.Column('id', sa.String(), nullable=False),
    sa.Column('tenant_id', sa.String(), nullable=False),
    sa.Column('claim_id', sa.String(), nullable=True),
    sa.Column('user_id', sa.String(), nullable=False),
    sa.Column('title', sa.String(), nullable=False),
    sa.Column('model', sa.String(), nullable=True),
    sa.Column('status', sa.String(), nullable=False),
    sa.Column('context_json', sa.JSON(), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
    sa.ForeignKeyConstraint(['claim_id'], ['claims.id'], ),
    sa.ForeignKeyConstraint(['tenant_id'], ['tenants.id'], ),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    _create_index(op.f('ix_ai_chat_sessions_claim_id'), 'ai_chat_sessions', ['claim_id'], unique=False)
    _create_index(op.f('ix_ai_chat_sessions_id'), 'ai_chat_sessions', ['id'], unique=False)
    _create_index(op.f('ix_ai_chat_sessions_tenant_id'), 'ai_chat_sessions', ['tenant_id'], unique=False)
    _create_index(op.f('ix_ai_chat_sessions_user_id'), 'ai_chat_sessions', ['user_id'], unique=False)
    _create_table('attachments',
    sa.Column('id', sa.String(), nullable=False),
    sa.Column('tenant_id', sa.String(), nullable=False),
    sa.Column('email_id', sa.String(), nullable=True),
    sa.Column('claim_id', sa.String(), nullable=True),
    sa.Column('file_name', sa.String(), nullable=False),
    sa.Column('mime_type', sa.String(), nullable=True),
    sa.Column('size_bytes', sa.BigInteger(), nullable=False),
    sa.Column('storage_bucket', sa.String(), nullable=False),
    sa.Column('storage_path', sa.String(), nullable=False),
    sa.Column('checksum', sa.String(), nullable=True),
    sa.Column('uploaded_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
    sa.Column('uploaded_by_user_id', sa.String(), nullable=True),
    sa.ForeignKeyConstraint(['claim_id'], ['claims.id'], ),
    sa.ForeignKeyConstraint(['email_id'], ['emails.id'], ),
    sa.ForeignKeyConstraint(['tenant_id'], ['tenants.id'], ),
    sa.ForeignKeyConstraint(['uploaded_by_user_id'], ['users.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    _create_index(op.f('ix_attachments_claim_id'), 'attachments', ['claim_id'], unique=False)
    _create_index(op.f('ix_attachments_email_id'), 'attachments', ['email_id'], unique=False)
    _create_index(op.f('ix_attachments_id'), 'attachments', ['id'], unique=False)
    _create_index(op.f('ix_attachments_tenant_id'), 'attachments', ['tenant_id'], unique=False)
    _create_table('case_tasks',
    sa.Column('id', sa.String(), nullable=False),
    sa.Column('tenant_id', sa.String(), nullable=False),
    sa.Column('claim_id', sa.String(), nullable=False),
    sa.Column('title', sa.String(), nullable=False),
    sa.Column('description', sa.String(), nullable=True),
    sa.Column('status', sa.String(), nullable=False),
    sa.Column('assignee_user_id', sa.String(), nullable=True),
    sa.Column('created_by_user_id', sa.String(), nullable=False),
    sa.Column('due_date', sa.DateTime(timezone=True), nullable=True),
    sa.Column('completed_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('priority', sa.Integer(), nullable=False),
    sa.Column('type', sa.String(), nullable=True),
    sa.Column('metadata_json', sa.JSON(), nullable=True),
    sa.ForeignKeyConstraint(['assignee_user_id'], ['users.id'], ),
    sa.ForeignKeyConstraint(['claim_id'], ['claims.id'], ),
    sa.ForeignKeyConstraint(['created_by_user_id'], ['users.id'], ),
    sa.ForeignKeyConstraint(['tenant_id'], ['tenants.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    _create_index('idx_case_tasks_assignee_due', 'case_tasks', ['assignee_user_id', 'due_date'], unique=False)
    _create_index('idx_case_tasks_claim_status', 'case_tasks', ['claim_id', 'status'], unique=False)
    _create_index(op.f('ix_case_tasks_assignee_user_id'), 'case_tasks', ['assignee_user_id'], unique=False)
    _create_index(op.f('ix_case_tasks_claim_id'), 'case_tasks', ['claim_id'], unique=False)
    _create_index(op.f('ix_case_tasks_due_date'), 'case_tasks', ['due_date'], unique=False)
    _create_index(op.f('ix_case_tasks_id'), 'case_tasks', ['id'], unique=False)
    _create_index(op.f('ix_case_tasks_tenant_id'), 'case_tasks', ['tenant_id'], unique=False)
    _create_table('claim_assignments',
    sa.Column('id', sa.String(), nullable=False),
    sa.Column('tenant_id', sa.String(), nullable=False),
    sa.Column('claim_id', sa.String(), nullable=False),
    sa.Column('assignee_user_id', sa.String(), nullable=False),
    sa.Column('assigned_by_user_id', sa.String(), nullable=True),
    sa.Column('assigned_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
    sa.Column('unassigned_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('reason', sa.String(), nullable=True),
    sa.ForeignKeyConstraint(['assigned_by_user_id'], ['users.id'], ),
    sa.ForeignKeyConstraint(['assignee_user_id'], ['users.id'], ),
    sa.ForeignKeyConstraint(['claim_id'], ['claims.id'], ),
    sa.ForeignKeyConstraint(['tenant_id'], ['tenants.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    _create_index(op.f('ix_claim_assignments_claim_id'), 'claim_assignments', ['claim_id'], unique=False)
    _create_index(op.f('ix_claim_assignments_id'), 'claim_assignments', ['id'], unique=False)
    _create_index(op.f('ix_claim_assignments_tenant_id'), 'claim_assignments', ['tenant_id'], unique=False)
    _create_table('claim_diary_entries',
    sa.Column('id', sa.String(), nullable=False),
    sa.Column('tenant_id', sa.String(), nullable=False),
    sa.Column('claim_id', sa.String(), nullable=False),
    sa.Column('entry_type', sa.String(), nullable=False),
    sa.Column('title', sa.String(), nullable=True),
    sa.Column('body_text', sa.String(), nullable=True),
    sa.Column('visibility', sa.String(), nullable=False),
    sa.Column('happened_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
    sa.Column('created_by_user_id', sa.String(), nullable=True),
    sa.Column('metadata_json', sa.JSON(), nullable=True),
    sa.ForeignKeyConstraint(['claim_id'], ['claims.id'], ),
    sa.ForeignKeyConstraint(['created_by_user_id'], ['users.id'], ),
    sa.ForeignKeyConstraint(['tenant_id'], ['tenants.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    _create_index(op.f('ix_claim_diary_entries_claim_id'), 'claim_diary_entries', ['claim_id'], unique=False)
    _create_index('ix_claim_diary_entries_happened_at', 'claim_diary_entries', ['happened_at'], unique=False)
    _create_index(op.f('ix_claim_diary_entries_id'), 'claim_diary_entries', ['id'], unique=False)
    _create_index(op.f('ix_claim_diary_entries_tenant_id'), 'claim_diary_entries', ['tenant_id'], unique=False)
    _create_table('claim_events',
    sa.Column('id', sa.String(), nullable=False),
    sa.Column('tenant_id', sa.String(), nullable=False),
    sa.Column('claim_id', sa.String(), nullable=False),
    sa.Column('event_type', sa.String(), nullable=False),
    sa.Column('event_time', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
    sa.Column('actor_user_id', sa.String(), nullable=True),
    sa.Column('data_json', sa.JSON(), nullable=True),
    sa.Column('source', sa.String(), nullable=False),
    sa.ForeignKeyConstraint(['actor_user_id'], ['users.id'], ),
    sa.ForeignKeyConstraint(['claim_id'], ['claims.id'], ),
    sa.ForeignKeyConstraint(['tenant_id'], ['tenants.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    _create_index('idx_claim_events_tenant_time', 'claim_events', ['tenant_id', 'event_time'], unique=False)
    _create_index(op.f('ix_claim_events_claim_id'), 'claim_events', ['claim_id'], unique=False)
    _create_index(op.f('ix_claim_events_event_time'), 'claim_events', ['event_time'], unique=False)
    _create_index(op.f('ix_claim_events_event_type'), 'claim_events', ['event_type'], unique=False)
    _create_index(op.f('ix_claim_events_id'), 'claim_events', ['id'], unique=False)
    _create_index(op.f('ix_claim_events_tenant_id'), 'claim_events', ['tenant_id'], unique=False)
    _create_table('claim_folders',
    sa.Column('id', sa.String(), nullable=False),
    sa.Column('tenant_id', sa.String(), nullable=False),
    sa.Column('claim_id', sa.String(), nullable=True),
    sa.Column('parent_id', sa.String(), nullable=True),
    sa.Column('name', sa.String(), nullable=False),
    sa.Column('folder_type', sa.String(), nullable=False),
    sa.Column('path', sa.String(), nullable=False),
    sa.Column('source', sa.String(), nullable=False),
    sa.Column('external_ref', sa.String(), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
    sa.Column('metadata_json', sa.JSON(), nullable=True),
    sa.ForeignKeyConstraint(['claim_id'], ['claims.id'], ),
    sa.ForeignKeyConstraint(['parent_id'], ['claim_folders.id'], ),
    sa.ForeignKeyConstraint(['tenant_id'], ['tenants.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    _create_index(op.f('ix_claim_folders_claim_id'), 'claim_folders', ['claim_id'], unique=False)
    _create_index(op.f('ix_claim_folders_id'), 'claim_folders', ['id'], unique=False)
    _create_index(op.f('ix_claim_folders_parent_id'), 'claim_folders', ['parent_id'], unique=False)
    _create_index(op.f('ix_claim_folders_tenant_id'), 'claim_folders', ['tenant_id'], unique=False)
    _create_index('ux_claim_folders_tenant_path', 'claim_folders', ['tenant_id', 'path'], unique=True)
    _create_table('claim_states',
    sa.Column('id', sa.String(), nullable=False),
    sa.Column('tenant_id', sa.String(), nullable=False),
    sa.Column('claim_id', sa.String(), nullable=False),
    sa.Column('from_state', sa.String(), nullable=True),
    sa.Column('to_state', sa.String(), nullable=False),
    sa.Column('changed_by_user_id', sa.String(), nullable=True),
    sa.Column('changed_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
    sa.Column('reason', sa.String(), nullable=True),
    sa.Column('payload_json', sa.JSON(), nullable=True),
    sa.ForeignKeyConstraint(['changed_by_user_id'], ['users.id'], ),
    sa.ForeignKeyConstraint(['claim_id'], ['claims.id'], ),
    sa.ForeignKeyConstraint(['tenant_id'], ['tenants.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    _create_index(op.f('ix_claim_states_claim_id'), 'claim_states', ['claim_id'], unique=False)
    _create_index(op.f('ix_claim_states_id'), 'claim_states', ['id'], unique=False)
    _create_index(op.f('ix_claim_states_tenant_id'), 'claim_states', ['tenant_id'], unique=False)
    _create_table('email_claim_links',
    sa.Column('id', sa.String(), nullable=False),
    sa.Column('tenant_id', sa.String(), nullable=False),
    sa.Column('email_id', sa.String(), nullable=False),
    sa.Column('claim_id', sa.String(), nullable=False),
    sa.Column('link_type', sa.String(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
    sa.Column('created_by', sa.String(), nullable=False),
    sa.ForeignKeyConstraint(['claim_id'], ['claims.id'], ),
    sa.ForeignKeyConstraint(['email_id'], ['emails.id'], ),
    sa.ForeignKeyConstraint(['tenant_id'], ['tenants.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    _create_index(op.f('ix_email_claim_links_claim_id'), 'email_claim_links', ['claim_id'], unique=False)
    _create_index(op.f('ix_email_claim_links_email_id'), 'email_claim_links', ['email_id'], unique=False)
    _create_index(op.f('ix_email_claim_links_id'), 'email_claim_links', ['id'], unique=False)
    _create_index(op.f('ix_email_claim_links_tenant_id'), 'email_claim_links', ['tenant_id'], unique=False)
    _create_table('internal_chat_threads',
    sa.Column('id', sa.String(), nullable=False),
    sa.Column('tenant_id', sa.String(), nullable=False),
    sa.Column('claim_id', sa.String(), nullable=True),
    sa.Column('title', sa.String(), nullable=False),
    sa.Column('thread_type', sa.String(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
    sa.Column('created_by_user_id', sa.String(), nullable=True),
    sa.Column('metadata_json', sa.JSON(), nullable=True),
    sa.ForeignKeyConstraint(['claim_id'], ['claims.id'], ),
    sa.ForeignKeyConstraint(['created_by_user_id'], ['users.id'], ),
    sa.ForeignKeyConstraint(['tenant_id'], ['tenants.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    _create_index(op.f('ix_internal_chat_threads_claim_id'), 'internal_chat_threads', ['claim_id'], unique=False)
    _create_index(op.f('ix_internal_chat_threads_id'), 'internal_chat_threads', ['id'], unique=False)
    _create_index(op.f('ix_internal_chat_threads_tenant_id'), 'internal_chat_threads', ['tenant_id'], unique=False)
    _create_table('ai_chat_messages',
    sa.Column('id', sa.String(), nullable=False),
    sa.Column('tenant_id', sa.String(), nullable=False),
    sa.Column('session_id', sa.String(), nullable=False),
    sa.Column('role', sa.String(), nullable=False),
    sa.Column('body_text', sa.String(), nullable=True),
    sa.Column('payload_json', sa.JSON(), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
    sa.ForeignKeyConstraint(['session_id'], ['ai_chat_sessions.id'], ),
    sa.ForeignKeyConstraint(['tenant_id'], ['tenants.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    _create_index(op.f('ix_ai_chat_messages_id'), 'ai_chat_messages', ['id'], unique=False)
    _create_index(op.f('ix_ai_chat_messages_session_id'), 'ai_chat_messages', ['session_id'], unique=False)
    _create_index(op.f('ix_ai_chat_messages_tenant_id'), 'ai_chat_messages', ['tenant_id'], unique=False)
    _create_table('calendar_events',
    sa.Column('id', sa.String(), nullable=False),
    sa.Column('tenant_id', sa.String(), nullable=False),
    sa.Column('claim_id', sa.String(), nullable=True),
    sa.Column('task_id', sa.String(), nullable=True),
    sa.Column('owner_user_id', sa.String(), nullable=False),
    sa.Column('title', sa.String(), nullable=False),
    sa.Column('description', sa.String(), nullable=True),
    sa.Column('event_type', sa.String(), nullable=False),
    sa.Column('starts_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('ends_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('all_day', sa.Boolean(), nullable=False),
    sa.Column('location', sa.String(), nullable=True),
    sa.Column('status', sa.String(), nullable=False),
    sa.Column('visibility', sa.String(), nullable=False),
    sa.Column('source', sa.String(), nullable=False),
    sa.Column('metadata_json', sa.JSON(), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
    sa.ForeignKeyConstraint(['claim_id'], ['claims.id'], ),
    sa.ForeignKeyConstraint(['owner_user_id'], ['users.id'], ),
    sa.ForeignKeyConstraint(['task_id'], ['case_tasks.id'], ),
    sa.ForeignKeyConstraint(['tenant_id'], ['tenants.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    _create_index(op.f('ix_calendar_events_claim_id'), 'calendar_events', ['claim_id'], unique=False)
    _create_index(op.f('ix_calendar_events_id'), 'calendar_events', ['id'], unique=False)
    _create_index(op.f('ix_calendar_events_owner_user_id'), 'calendar_events', ['owner_user_id'], unique=False)
    _create_index(op.f('ix_calendar_events_starts_at'), 'calendar_events', ['starts_at'], unique=False)
    _create_index(op.f('ix_calendar_events_tenant_id'), 'calendar_events', ['tenant_id'], unique=False)
    _create_table('documents',
    sa.Column('id', sa.String(), nullable=False),
    sa.Column('tenant_id', sa.String(), nullable=False),
    sa.Column('claim_id', sa.String(), nullable=True),
    sa.Column('folder_id', sa.String(), nullable=True),
    sa.Column('attachment_id', sa.String(), nullable=True),
    sa.Column('source_type', sa.String(), nullable=False),
    sa.Column('source_id', sa.String(), nullable=True),
    sa.Column('file_name', sa.String(), nullable=False),
    sa.Column('original_file_name', sa.String(), nullable=True),
    sa.Column('mime_type', sa.String(), nullable=True),
    sa.Column('extension', sa.String(), nullable=True),
    sa.Column('size_bytes', sa.BigInteger(), nullable=False),
    sa.Column('storage_provider', sa.String(), nullable=False),
    sa.Column('storage_bucket', sa.String(), nullable=True),
    sa.Column('storage_path', sa.String(), nullable=False),
    sa.Column('logical_path', sa.String(), nullable=True),
    sa.Column('checksum_sha256', sa.String(), nullable=True),
    sa.Column('checksum_md5', sa.String(), nullable=True),
    sa.Column('version_no', sa.Integer(), nullable=False),
    sa.Column('status', sa.String(), nullable=False),
    sa.Column('category', sa.String(), nullable=True),
    sa.Column('tags_json', sa.JSON(), nullable=True),
    sa.Column('uploaded_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
    sa.Column('uploaded_by_user_id', sa.String(), nullable=True),
    sa.Column('metadata_json', sa.JSON(), nullable=True),
    sa.ForeignKeyConstraint(['attachment_id'], ['attachments.id'], ),
    sa.ForeignKeyConstraint(['claim_id'], ['claims.id'], ),
    sa.ForeignKeyConstraint(['folder_id'], ['claim_folders.id'], ),
    sa.ForeignKeyConstraint(['tenant_id'], ['tenants.id'], ),
    sa.ForeignKeyConstraint(['uploaded_by_user_id'], ['users.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    _create_index(op.f('ix_documents_attachment_id'), 'documents', ['attachment_id'], unique=False)
    _create_index(op.f('ix_documents_claim_id'), 'documents', ['claim_id'], unique=False)
    _create_index(op.f('ix_documents_folder_id'), 'documents', ['folder_id'], unique=False)
    _create_index(op.f('ix_documents_id'), 'documents', ['id'], unique=False)
    _create_index('ix_documents_storage_path', 'documents', ['storage_path'], unique=False)
    _create_index(op.f('ix_documents_tenant_id'), 'documents', ['tenant_id'], unique=False)
    _create_table('internal_chat_members',
    sa.Column('thread_id', sa.String(), nullable=False),
    sa.Column('user_id', sa.String(), nullable=False),
    sa.Column('joined_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
    sa.ForeignKeyConstraint(['thread_id'], ['internal_chat_threads.id'], ),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
    sa.PrimaryKeyConstraint('thread_id', 'user_id')
    )
    _create_table('sync_cursors',
    sa.Column('id', sa.String(), nullable=False),
    sa.Column('tenant_id', sa.String(), nullable=False),
    sa.Column('user_id', sa.String(), nullable=False),
    sa.Column('device_id', sa.String(), nullable=False),
    sa.Column('last_event_id', sa.String(), nullable=True),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
    sa.ForeignKeyConstraint(['last_event_id'], ['claim_events.id'], ),
    sa.ForeignKeyConstraint(['tenant_id'], ['tenants.id'], ),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    _create_index('idx_sync_cursors_user_device', 'sync_cursors', ['user_id', 'device_id'], unique=True)
    _create_index(op.f('ix_sync_cursors_id'), 'sync_cursors', ['id'], unique=False)
    _create_index(op.f('ix_sync_cursors_tenant_id'), 'sync_cursors', ['tenant_id'], unique=False)
    _create_index(op.f('ix_sync_cursors_user_id'), 'sync_cursors', ['user_id'], unique=False)
    _create_table('internal_chat_messages',
    sa.Column('id', sa.String(), nullable=False),
    sa.Column('tenant_id', sa.String(), nullable=False),
    sa.Column('thread_id', sa.String(), nullable=False),
    sa.Column('claim_id', sa.String(), nullable=True),
    sa.Column('sender_user_id', sa.String(), nullable=True),
    sa.Column('body_text', sa.String(), nullable=True),
    sa.Column('message_type', sa.String(), nullable=False),
    sa.Column('attachment_document_id', sa.String(), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
    sa.Column('edited_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('metadata_json', sa.JSON(), nullable=True),
    sa.ForeignKeyConstraint(['attachment_document_id'], ['documents.id'], ),
    sa.ForeignKeyConstraint(['claim_id'], ['claims.id'], ),
    sa.ForeignKeyConstraint(['sender_user_id'], ['users.id'], ),
    sa.ForeignKeyConstraint(['tenant_id'], ['tenants.id'], ),
    sa.ForeignKeyConstraint(['thread_id'], ['internal_chat_threads.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    _create_index(op.f('ix_internal_chat_messages_claim_id'), 'internal_chat_messages', ['claim_id'], unique=False)
    _create_index(op.f('ix_internal_chat_messages_id'), 'internal_chat_messages', ['id'], unique=False)
    _create_index(op.f('ix_internal_chat_messages_tenant_id'), 'internal_chat_messages', ['tenant_id'], unique=False)
    _create_index(op.f('ix_internal_chat_messages_thread_id'), 'internal_chat_messages', ['thread_id'], unique=False)

    # Legacy columns of claims/users that existed before Alembic (later revisions
    # read them, e.g. 020 reads claims.metadata_json).
    _add_column('claims', sa.Column('agenzia', sa.String(), nullable=True))
    _add_column('claims', sa.Column('codice_agenzia', sa.String(), nullable=True))
    _add_column('claims', sa.Column('email_agenzia', sa.String(), nullable=True))
    _add_column('claims', sa.Column('telefono_agenzia', sa.String(), nullable=True))
    _add_column('claims', sa.Column('nome_assicurato', sa.String(), nullable=True))
    _add_column('claims', sa.Column('email_assicurato', sa.String(), nullable=True))
    _add_column('claims', sa.Column('telefono_assicurato', sa.String(), nullable=True))
    _add_column('claims', sa.Column('indirizzo_assicurato', sa.String(), nullable=True))
    _add_column('claims', sa.Column('nome_contraente', sa.String(), nullable=True))
    _add_column('claims', sa.Column('email_contraente', sa.String(), nullable=True))
    _add_column('claims', sa.Column('telefono_contraente', sa.String(), nullable=True))
    _add_column('claims', sa.Column('indirizzo_contraente', sa.String(), nullable=True))
    _add_column('claims', sa.Column('nome_danneggiato', sa.String(), nullable=True))
    _add_column('claims', sa.Column('email_danneggiato', sa.String(), nullable=True))
    _add_column('claims', sa.Column('telefono_danneggiato', sa.String(), nullable=True))
    _add_column('claims', sa.Column('indirizzo_danneggiato', sa.String(), nullable=True))
    _add_column('claims', sa.Column('data_sinistro', sa.DateTime(timezone=True), nullable=True))
    _add_column('claims', sa.Column('data_denuncia', sa.DateTime(timezone=True), nullable=True))
    _add_column('claims', sa.Column('data_incarico', sa.DateTime(timezone=True), nullable=True))
    _add_column('claims', sa.Column('data_apertura_gestione', sa.DateTime(timezone=True), nullable=True))
    _add_column('claims', sa.Column('data_assegnazione', sa.DateTime(timezone=True), nullable=True))
    _add_column('claims', sa.Column('data_invio_atto', sa.DateTime(timezone=True), nullable=True))
    _add_column('claims', sa.Column('data_ritorno_atto', sa.DateTime(timezone=True), nullable=True))
    _add_column('claims', sa.Column('data_revoca', sa.DateTime(timezone=True), nullable=True))
    _add_column('claims', sa.Column('data_sopralluogo', sa.DateTime(timezone=True), nullable=True))
    _add_column('claims', sa.Column('richiesta', sa.Numeric(precision=12, scale=2), nullable=True))
    _add_column('claims', sa.Column('liquidato', sa.Numeric(precision=12, scale=2), nullable=True))
    _add_column('claims', sa.Column('danno_accertato', sa.Numeric(precision=12, scale=2), nullable=True))
    _add_column('claims', sa.Column('danno_accertato_netto', sa.Numeric(precision=12, scale=2), nullable=True))
    _add_column('claims', sa.Column('stima_danno', sa.Numeric(precision=12, scale=2), nullable=True))
    _add_column('claims', sa.Column('numero_polizza', sa.String(), nullable=True))
    _add_column('claims', sa.Column('tipo_polizza', sa.String(), nullable=True))
    _add_column('claims', sa.Column('divisione_compagnia', sa.String(), nullable=True))
    _add_column('claims', sa.Column('garanzia', sa.String(), server_default='Fenomeno Elettrico', nullable=False))
    _add_column('claims', sa.Column('iban', sa.Boolean(), server_default=sa.false(), nullable=False))
    _add_column('claims', sa.Column('sinistro_collegato', sa.Boolean(), server_default=sa.false(), nullable=False))
    _add_column('claims', sa.Column('id_sinistro_collegato', sa.String(), nullable=True))
    _add_column('claims', sa.Column('sopralluogo', sa.Boolean(), server_default=sa.false(), nullable=False))
    _add_column('claims', sa.Column('giustificativi', sa.Boolean(), server_default=sa.false(), nullable=False))
    _add_column('claims', sa.Column('foto', sa.Boolean(), server_default=sa.false(), nullable=False))
    _add_column('claims', sa.Column('oltre_dieci_beni', sa.Boolean(), server_default=sa.false(), nullable=False))
    _add_column('claims', sa.Column('concordata', sa.Boolean(), server_default=sa.false(), nullable=False))
    _add_column('claims', sa.Column('negativa', sa.Boolean(), server_default=sa.false(), nullable=False))
    _add_column('claims', sa.Column('ubicazione_validata', sa.Boolean(), server_default=sa.false(), nullable=False))
    _add_column('claims', sa.Column('fulminazione', sa.String(), nullable=True))
    _add_column('claims', sa.Column('gruppo', sa.String(), nullable=True))
    _add_column('claims', sa.Column('area', sa.String(), nullable=True))
    _add_column('claims', sa.Column('complessita', sa.String(), nullable=True))
    _add_column('claims', sa.Column('definizione', sa.String(), nullable=True))
    _add_column('claims', sa.Column('propensione_perito', sa.String(), nullable=True))
    _add_column('claims', sa.Column('ubicazione_note', sa.String(), nullable=True))
    _add_column('claims', sa.Column('cartella', sa.String(), nullable=True))
    _add_column('claims', sa.Column('owner_email', sa.String(), nullable=True))
    _add_column('claims', sa.Column('metadata_json', sa.JSON(), nullable=True))
    _add_column('users', sa.Column('first_name', sa.String(), nullable=True))
    _add_column('users', sa.Column('last_name', sa.String(), nullable=True))
    _add_column('users', sa.Column('job_title', sa.String(), nullable=True))
    _add_column('users', sa.Column('phone_number', sa.String(), nullable=True))
    _add_column('users', sa.Column('birth_date', sa.DateTime(timezone=True), nullable=True))
    _add_column('users', sa.Column('birthday_visibility', sa.String(), server_default='everyone', nullable=False))
    _add_column('users', sa.Column('notify_birthday', sa.Boolean(), server_default=sa.true(), nullable=False))
    _add_column('users', sa.Column('contract_type', sa.String(), nullable=True))
    _add_column('users', sa.Column('avatar_type', sa.String(), server_default='generated', nullable=False))
    _add_column('users', sa.Column('avatar_photo_base64', sa.Text(), nullable=True))
    _add_column('users', sa.Column('generated_avatar_color', sa.String(), nullable=True))
    _add_column('users', sa.Column('generated_avatar_icon', sa.String(), nullable=True))
    _add_column('users', sa.Column('avatar_gif_url', sa.String(), nullable=True))
    _add_column('users', sa.Column('enable_badges', sa.Boolean(), server_default=sa.false(), nullable=False))
    _add_column('users', sa.Column('send_read_receipts', sa.Boolean(), server_default=sa.true(), nullable=False))
    _add_column('users', sa.Column('email_signature_html', sa.Text(), nullable=True))
    _add_column('users', sa.Column('email_signature_text', sa.Text(), nullable=True))
    _add_column('users', sa.Column('settings_json', sa.JSON(), nullable=True))


def downgrade() -> None:
    # Intentionally a no-op: in existing environments these tables predate Alembic
    # and hold production data, so dropping them on downgrade would destroy it.
    pass
