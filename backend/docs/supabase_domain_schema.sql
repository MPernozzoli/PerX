create extension if not exists pgcrypto;

create or replace function public.current_app_user_id()
returns text
language sql
stable
as $$
  select u.id
  from public.users u
  where u.idp_subject = auth.uid()::text
  limit 1
$$;

create or replace function public.current_tenant_id()
returns text
language sql
stable
as $$
  select u.tenant_id
  from public.users u
  where u.idp_subject = auth.uid()::text
  limit 1
$$;

create or replace function public.is_platform_admin()
returns boolean
language sql
stable
as $$
  select coalesce((
    select u.is_platform_admin
    from public.users u
    where u.idp_subject = auth.uid()::text
    limit 1
  ), false)
$$;

alter table public.claims add column if not exists agenzia text;
alter table public.claims add column if not exists codice_agenzia text;
alter table public.claims add column if not exists email_agenzia text;
alter table public.claims add column if not exists telefono_agenzia text;
alter table public.claims add column if not exists nome_assicurato text;
alter table public.claims add column if not exists email_assicurato text;
alter table public.claims add column if not exists telefono_assicurato text;
alter table public.claims add column if not exists indirizzo_assicurato text;
alter table public.claims add column if not exists nome_contraente text;
alter table public.claims add column if not exists email_contraente text;
alter table public.claims add column if not exists telefono_contraente text;
alter table public.claims add column if not exists indirizzo_contraente text;
alter table public.claims add column if not exists nome_danneggiato text;
alter table public.claims add column if not exists email_danneggiato text;
alter table public.claims add column if not exists telefono_danneggiato text;
alter table public.claims add column if not exists indirizzo_danneggiato text;
alter table public.claims add column if not exists data_sinistro timestamptz;
alter table public.claims add column if not exists data_denuncia timestamptz;
alter table public.claims add column if not exists data_incarico timestamptz;
alter table public.claims add column if not exists data_apertura_gestione timestamptz;
alter table public.claims add column if not exists data_assegnazione timestamptz;
alter table public.claims add column if not exists data_invio_atto timestamptz;
alter table public.claims add column if not exists data_ritorno_atto timestamptz;
alter table public.claims add column if not exists data_revoca timestamptz;
alter table public.claims add column if not exists data_sopralluogo timestamptz;
alter table public.claims add column if not exists richiesta numeric(12,2);
alter table public.claims add column if not exists liquidato numeric(12,2);
alter table public.claims add column if not exists danno_accertato numeric(12,2);
alter table public.claims add column if not exists danno_accertato_netto numeric(12,2);
alter table public.claims add column if not exists stima_danno numeric(12,2);
alter table public.claims add column if not exists numero_polizza text;
alter table public.claims add column if not exists tipo_polizza text;
alter table public.claims add column if not exists divisione_compagnia text;
alter table public.claims add column if not exists iban boolean not null default false;
alter table public.claims add column if not exists sinistro_collegato boolean not null default false;
alter table public.claims add column if not exists id_sinistro_collegato text;
alter table public.claims add column if not exists sopralluogo boolean not null default false;
alter table public.claims add column if not exists giustificativi boolean not null default false;
alter table public.claims add column if not exists foto boolean not null default false;
alter table public.claims add column if not exists oltre_dieci_beni boolean not null default false;
alter table public.claims add column if not exists concordata boolean not null default false;
alter table public.claims add column if not exists negativa boolean not null default false;
alter table public.claims add column if not exists ubicazione_validata boolean not null default false;
alter table public.claims add column if not exists fulminazione text;
alter table public.claims add column if not exists gruppo text;
alter table public.claims add column if not exists area text;
alter table public.claims add column if not exists complessita text;
alter table public.claims add column if not exists definizione text;
alter table public.claims add column if not exists propensione_perito text;
alter table public.claims add column if not exists ubicazione_note text;
alter table public.claims add column if not exists cartella text;
alter table public.claims add column if not exists owner_email text;
alter table public.claims add column if not exists metadata_json jsonb default '{}'::jsonb;

create index if not exists ix_claims_external_ref on public.claims (external_ref);
create index if not exists ix_claims_numero_sinistro on public.claims (numero_sinistro);

create table if not exists public.claim_states (
  id text primary key default gen_random_uuid()::text,
  tenant_id text not null references public.tenants(id) on delete cascade,
  claim_id text not null references public.claims(id) on delete cascade,
  from_state text null,
  to_state text not null,
  changed_by_user_id text null references public.users(id) on delete set null,
  changed_at timestamptz not null default now(),
  reason text null,
  payload_json jsonb null default '{}'::jsonb
);

create index if not exists ix_claim_states_tenant_id on public.claim_states (tenant_id);
create index if not exists ix_claim_states_claim_id on public.claim_states (claim_id);

create table if not exists public.claim_events (
  id text primary key default gen_random_uuid()::text,
  tenant_id text not null references public.tenants(id) on delete cascade,
  claim_id text not null references public.claims(id) on delete cascade,
  event_type text not null,
  event_time timestamptz not null default now(),
  actor_user_id text null references public.users(id) on delete set null,
  data_json jsonb null default '{}'::jsonb,
  source text not null
);

create index if not exists ix_claim_events_tenant_id on public.claim_events (tenant_id);
create index if not exists ix_claim_events_claim_id on public.claim_events (claim_id);
create index if not exists ix_claim_events_event_type on public.claim_events (event_type);
create index if not exists idx_claim_events_tenant_time on public.claim_events (tenant_id, event_time);

create table if not exists public.claim_assignments (
  id text primary key default gen_random_uuid()::text,
  tenant_id text not null references public.tenants(id) on delete cascade,
  claim_id text not null references public.claims(id) on delete cascade,
  assignee_user_id text not null references public.users(id) on delete cascade,
  assigned_by_user_id text null references public.users(id) on delete set null,
  assigned_at timestamptz not null default now(),
  unassigned_at timestamptz null,
  reason text null
);

create index if not exists ix_claim_assignments_tenant_id on public.claim_assignments (tenant_id);
create index if not exists ix_claim_assignments_claim_id on public.claim_assignments (claim_id);
create index if not exists ix_claim_assignments_assignee_user_id on public.claim_assignments (assignee_user_id);

create table if not exists public.case_tasks (
  id text primary key default gen_random_uuid()::text,
  tenant_id text not null references public.tenants(id) on delete cascade,
  claim_id text not null references public.claims(id) on delete cascade,
  title text not null,
  description text null,
  status text not null default 'open',
  assignee_user_id text null references public.users(id) on delete set null,
  created_by_user_id text not null references public.users(id) on delete restrict,
  due_date timestamptz null,
  completed_at timestamptz null,
  priority integer not null default 0,
  type text null,
  metadata_json jsonb null default '{}'::jsonb
);

create index if not exists ix_case_tasks_tenant_id on public.case_tasks (tenant_id);
create index if not exists ix_case_tasks_claim_id on public.case_tasks (claim_id);
create index if not exists ix_case_tasks_assignee_user_id on public.case_tasks (assignee_user_id);
create index if not exists idx_case_tasks_claim_status on public.case_tasks (claim_id, status);
create index if not exists idx_case_tasks_assignee_due on public.case_tasks (assignee_user_id, due_date);

alter table public.claims add column if not exists garanzia text not null default 'Fenomeno Elettrico';

create table if not exists public.mailboxes (
  id text primary key default gen_random_uuid()::text,
  tenant_id text not null references public.tenants(id) on delete cascade,
  label text not null,
  provider text not null,
  email_address text not null,
  auth_type text not null,
  oauth_token_ref text null,
  password_secret_ref text null,
  settings_json jsonb null default '{}'::jsonb,
  active boolean not null default true
);

create index if not exists ix_mailboxes_tenant_id on public.mailboxes (tenant_id);
create index if not exists ix_mailboxes_email_address on public.mailboxes (email_address);

create table if not exists public.emails (
  id text primary key default gen_random_uuid()::text,
  tenant_id text not null references public.tenants(id) on delete cascade,
  message_id text not null unique,
  thread_id text null,
  from_address text not null,
  to_addresses text null,
  cc_addresses text null,
  subject text null,
  body_text text null,
  body_html text null,
  received_at timestamptz not null,
  ingested_at timestamptz not null default now(),
  status text not null default 'ingested',
  raw_headers text null,
  mailbox_id text null references public.mailboxes(id) on delete set null,
  provider_id text null
);

create index if not exists ix_emails_tenant_id on public.emails (tenant_id);
create index if not exists ix_emails_message_id on public.emails (message_id);
create index if not exists ix_emails_thread_id on public.emails (thread_id);
create index if not exists idx_emails_tenant_received on public.emails (tenant_id, received_at);

create table if not exists public.email_claim_links (
  id text primary key default gen_random_uuid()::text,
  tenant_id text not null references public.tenants(id) on delete cascade,
  email_id text not null references public.emails(id) on delete cascade,
  claim_id text not null references public.claims(id) on delete cascade,
  link_type text not null,
  created_at timestamptz not null default now(),
  created_by text not null
);

create index if not exists ix_email_claim_links_tenant_id on public.email_claim_links (tenant_id);
create index if not exists ix_email_claim_links_email_id on public.email_claim_links (email_id);
create index if not exists ix_email_claim_links_claim_id on public.email_claim_links (claim_id);

create table if not exists public.attachments (
  id text primary key default gen_random_uuid()::text,
  tenant_id text not null references public.tenants(id) on delete cascade,
  email_id text null references public.emails(id) on delete cascade,
  claim_id text null references public.claims(id) on delete cascade,
  file_name text not null,
  mime_type text null,
  size_bytes bigint not null default 0,
  storage_bucket text not null,
  storage_path text not null,
  checksum text null,
  uploaded_at timestamptz not null default now(),
  uploaded_by_user_id text null references public.users(id) on delete set null
);

create index if not exists ix_attachments_tenant_id on public.attachments (tenant_id);
create index if not exists ix_attachments_email_id on public.attachments (email_id);
create index if not exists ix_attachments_claim_id on public.attachments (claim_id);
create index if not exists ix_attachments_storage_path on public.attachments (storage_path);

create table if not exists public.claim_folders (
  id text primary key default gen_random_uuid()::text,
  tenant_id text not null references public.tenants(id) on delete cascade,
  claim_id text null references public.claims(id) on delete cascade,
  parent_id text null references public.claim_folders(id) on delete cascade,
  name text not null,
  folder_type text not null default 'generic',
  path text not null,
  source text not null default 'hub',
  external_ref text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata_json jsonb null default '{}'::jsonb
);

create index if not exists ix_claim_folders_tenant_id on public.claim_folders (tenant_id);
create index if not exists ix_claim_folders_claim_id on public.claim_folders (claim_id);
create index if not exists ix_claim_folders_parent_id on public.claim_folders (parent_id);
create unique index if not exists ux_claim_folders_tenant_path on public.claim_folders (tenant_id, path);

create table if not exists public.documents (
  id text primary key default gen_random_uuid()::text,
  tenant_id text not null references public.tenants(id) on delete cascade,
  claim_id text null references public.claims(id) on delete cascade,
  folder_id text null references public.claim_folders(id) on delete set null,
  attachment_id text null references public.attachments(id) on delete set null,
  source_type text not null default 'hub',
  source_id text null,
  file_name text not null,
  original_file_name text null,
  mime_type text null,
  extension text null,
  size_bytes bigint not null default 0,
  storage_provider text not null default 'hub',
  storage_bucket text null,
  storage_path text not null,
  logical_path text null,
  checksum_sha256 text null,
  checksum_md5 text null,
  version_no integer not null default 1,
  status text not null default 'active',
  category text null,
  tags_json jsonb null default '[]'::jsonb,
  uploaded_at timestamptz not null default now(),
  uploaded_by_user_id text null references public.users(id) on delete set null,
  metadata_json jsonb null default '{}'::jsonb
);

create index if not exists ix_documents_tenant_id on public.documents (tenant_id);
create index if not exists ix_documents_claim_id on public.documents (claim_id);
create index if not exists ix_documents_folder_id on public.documents (folder_id);
create index if not exists ix_documents_attachment_id on public.documents (attachment_id);
create index if not exists ix_documents_storage_path on public.documents (storage_path);

create table if not exists public.document_versions (
  id text primary key default gen_random_uuid()::text,
  tenant_id text not null references public.tenants(id) on delete cascade,
  document_id text not null references public.documents(id) on delete cascade,
  version_no integer not null,
  storage_path text not null,
  size_bytes bigint not null default 0,
  checksum_sha256 text null,
  created_at timestamptz not null default now(),
  created_by_user_id text null references public.users(id) on delete set null,
  metadata_json jsonb null default '{}'::jsonb
);

create unique index if not exists ux_document_versions_doc_version on public.document_versions (document_id, version_no);
create index if not exists ix_document_versions_tenant_id on public.document_versions (tenant_id);

create table if not exists public.document_analysis (
  id text primary key default gen_random_uuid()::text,
  tenant_id text not null references public.tenants(id) on delete cascade,
  document_id text not null references public.documents(id) on delete cascade,
  analysis_type text not null,
  engine text null,
  status text not null default 'queued',
  extracted_text text null,
  summary_text text null,
  result_json jsonb null default '{}'::jsonb,
  embedding_ref text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_user_id text null references public.users(id) on delete set null
);

create index if not exists ix_document_analysis_tenant_id on public.document_analysis (tenant_id);
create index if not exists ix_document_analysis_document_id on public.document_analysis (document_id);
create index if not exists ix_document_analysis_status on public.document_analysis (status);

create table if not exists public.claim_reports (
  id text primary key default gen_random_uuid()::text,
  tenant_id text not null references public.tenants(id) on delete cascade,
  claim_id text not null references public.claims(id) on delete cascade,
  document_id text null references public.documents(id) on delete set null,
  report_type text not null default 'perizia',
  title text not null,
  status text not null default 'draft',
  version_no integer not null default 1,
  content_json jsonb null default '{}'::jsonb,
  generated_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_user_id text null references public.users(id) on delete set null
);

create index if not exists ix_claim_reports_tenant_id on public.claim_reports (tenant_id);
create index if not exists ix_claim_reports_claim_id on public.claim_reports (claim_id);

create table if not exists public.claim_diary_entries (
  id text primary key default gen_random_uuid()::text,
  tenant_id text not null references public.tenants(id) on delete cascade,
  claim_id text not null references public.claims(id) on delete cascade,
  entry_type text not null default 'note',
  title text null,
  body_text text null,
  visibility text not null default 'internal',
  happened_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  created_by_user_id text null references public.users(id) on delete set null,
  metadata_json jsonb null default '{}'::jsonb
);

create index if not exists ix_claim_diary_entries_tenant_id on public.claim_diary_entries (tenant_id);
create index if not exists ix_claim_diary_entries_claim_id on public.claim_diary_entries (claim_id);
create index if not exists ix_claim_diary_entries_happened_at on public.claim_diary_entries (happened_at);

create table if not exists public.claim_lightning_outcomes (
  id text primary key default gen_random_uuid()::text,
  tenant_id text not null references public.tenants(id) on delete cascade,
  claim_id text not null references public.claims(id) on delete cascade,
  outcome_code text not null,
  outcome_label text null,
  confidence numeric(5,2) null,
  source text not null default 'manual',
  notes text null,
  payload_json jsonb null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  created_by_user_id text null references public.users(id) on delete set null
);

create index if not exists ix_claim_lightning_outcomes_tenant_id on public.claim_lightning_outcomes (tenant_id);
create index if not exists ix_claim_lightning_outcomes_claim_id on public.claim_lightning_outcomes (claim_id);

create table if not exists public.whatsapp_accounts (
  id text primary key default gen_random_uuid()::text,
  tenant_id text not null references public.tenants(id) on delete cascade,
  label text not null,
  phone_number text null,
  provider text not null default 'hub',
  provider_account_ref text null,
  status text not null default 'active',
  metadata_json jsonb null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists ix_whatsapp_accounts_tenant_id on public.whatsapp_accounts (tenant_id);

create table if not exists public.whatsapp_threads (
  id text primary key default gen_random_uuid()::text,
  tenant_id text not null references public.tenants(id) on delete cascade,
  claim_id text null references public.claims(id) on delete set null,
  account_id text null references public.whatsapp_accounts(id) on delete set null,
  external_thread_ref text null,
  contact_name text null,
  contact_phone text null,
  status text not null default 'open',
  last_message_at timestamptz null,
  metadata_json jsonb null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists ix_whatsapp_threads_tenant_id on public.whatsapp_threads (tenant_id);
create index if not exists ix_whatsapp_threads_claim_id on public.whatsapp_threads (claim_id);

create table if not exists public.whatsapp_messages (
  id text primary key default gen_random_uuid()::text,
  tenant_id text not null references public.tenants(id) on delete cascade,
  thread_id text not null references public.whatsapp_threads(id) on delete cascade,
  claim_id text null references public.claims(id) on delete set null,
  direction text not null,
  message_type text not null default 'text',
  provider_message_id text null,
  sender_user_id text null references public.users(id) on delete set null,
  sender_label text null,
  body_text text null,
  media_document_id text null references public.documents(id) on delete set null,
  sent_at timestamptz not null default now(),
  delivered_at timestamptz null,
  read_at timestamptz null,
  status text not null default 'sent',
  metadata_json jsonb null default '{}'::jsonb
);

create index if not exists ix_whatsapp_messages_tenant_id on public.whatsapp_messages (tenant_id);
create index if not exists ix_whatsapp_messages_thread_id on public.whatsapp_messages (thread_id);
create index if not exists ix_whatsapp_messages_claim_id on public.whatsapp_messages (claim_id);

create table if not exists public.internal_chat_threads (
  id text primary key default gen_random_uuid()::text,
  tenant_id text not null references public.tenants(id) on delete cascade,
  claim_id text null references public.claims(id) on delete cascade,
  title text not null,
  thread_type text not null default 'claim',
  created_at timestamptz not null default now(),
  created_by_user_id text null references public.users(id) on delete set null,
  metadata_json jsonb null default '{}'::jsonb
);

create index if not exists ix_internal_chat_threads_tenant_id on public.internal_chat_threads (tenant_id);
create index if not exists ix_internal_chat_threads_claim_id on public.internal_chat_threads (claim_id);

create table if not exists public.internal_chat_members (
  thread_id text not null references public.internal_chat_threads(id) on delete cascade,
  user_id text not null references public.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (thread_id, user_id)
);

create table if not exists public.internal_chat_messages (
  id text primary key default gen_random_uuid()::text,
  tenant_id text not null references public.tenants(id) on delete cascade,
  thread_id text not null references public.internal_chat_threads(id) on delete cascade,
  claim_id text null references public.claims(id) on delete set null,
  sender_user_id text null references public.users(id) on delete set null,
  body_text text null,
  message_type text not null default 'text',
  attachment_document_id text null references public.documents(id) on delete set null,
  created_at timestamptz not null default now(),
  edited_at timestamptz null,
  metadata_json jsonb null default '{}'::jsonb
);

create index if not exists ix_internal_chat_messages_tenant_id on public.internal_chat_messages (tenant_id);
create index if not exists ix_internal_chat_messages_thread_id on public.internal_chat_messages (thread_id);
create index if not exists ix_internal_chat_messages_claim_id on public.internal_chat_messages (claim_id);

create table if not exists public.ai_chat_sessions (
  id text primary key default gen_random_uuid()::text,
  tenant_id text not null references public.tenants(id) on delete cascade,
  claim_id text null references public.claims(id) on delete cascade,
  user_id text not null references public.users(id) on delete cascade,
  title text not null,
  model text null,
  status text not null default 'active',
  context_json jsonb null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists ix_ai_chat_sessions_tenant_id on public.ai_chat_sessions (tenant_id);
create index if not exists ix_ai_chat_sessions_claim_id on public.ai_chat_sessions (claim_id);
create index if not exists ix_ai_chat_sessions_user_id on public.ai_chat_sessions (user_id);

create table if not exists public.ai_chat_messages (
  id text primary key default gen_random_uuid()::text,
  tenant_id text not null references public.tenants(id) on delete cascade,
  session_id text not null references public.ai_chat_sessions(id) on delete cascade,
  role text not null,
  body_text text null,
  payload_json jsonb null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists ix_ai_chat_messages_tenant_id on public.ai_chat_messages (tenant_id);
create index if not exists ix_ai_chat_messages_session_id on public.ai_chat_messages (session_id);

create table if not exists public.user_work_schedules (
  id text primary key default gen_random_uuid()::text,
  tenant_id text not null references public.tenants(id) on delete cascade,
  user_id text not null references public.users(id) on delete cascade,
  weekday smallint not null,
  start_time time not null,
  end_time time not null,
  location text null,
  slot_type text not null default 'work',
  effective_from date null,
  effective_to date null,
  created_at timestamptz not null default now(),
  metadata_json jsonb null default '{}'::jsonb
);

create index if not exists ix_user_work_schedules_tenant_id on public.user_work_schedules (tenant_id);
create index if not exists ix_user_work_schedules_user_id on public.user_work_schedules (user_id);

create table if not exists public.calendar_events (
  id text primary key default gen_random_uuid()::text,
  tenant_id text not null references public.tenants(id) on delete cascade,
  claim_id text null references public.claims(id) on delete set null,
  task_id text null references public.case_tasks(id) on delete set null,
  owner_user_id text not null references public.users(id) on delete cascade,
  title text not null,
  description text null,
  event_type text not null default 'appointment',
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  all_day boolean not null default false,
  location text null,
  status text not null default 'confirmed',
  visibility text not null default 'tenant',
  source text not null default 'manual',
  metadata_json jsonb null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists ix_calendar_events_tenant_id on public.calendar_events (tenant_id);
create index if not exists ix_calendar_events_owner_user_id on public.calendar_events (owner_user_id);
create index if not exists ix_calendar_events_claim_id on public.calendar_events (claim_id);
create index if not exists ix_calendar_events_starts_at on public.calendar_events (starts_at);

create table if not exists public.dashboard_widgets (
  id text primary key default gen_random_uuid()::text,
  tenant_id text not null references public.tenants(id) on delete cascade,
  user_id text not null references public.users(id) on delete cascade,
  widget_key text not null,
  position integer not null default 0,
  enabled boolean not null default true,
  settings_json jsonb null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists ux_dashboard_widgets_user_key on public.dashboard_widgets (user_id, widget_key);
create index if not exists ix_dashboard_widgets_tenant_id on public.dashboard_widgets (tenant_id);

create table if not exists public.audit_log (
  id text primary key default gen_random_uuid()::text,
  tenant_id text not null references public.tenants(id) on delete cascade,
  user_id text null references public.users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id text not null,
  timestamp timestamptz not null default now(),
  ip_address text null,
  user_agent text null,
  details_json jsonb null default '{}'::jsonb
);

create index if not exists idx_audit_log_tenant_timestamp on public.audit_log (tenant_id, timestamp);
create index if not exists idx_audit_log_entity on public.audit_log (entity_type, entity_id);

create table if not exists public.sync_cursors (
  id text primary key default gen_random_uuid()::text,
  tenant_id text not null references public.tenants(id) on delete cascade,
  user_id text not null references public.users(id) on delete cascade,
  device_id text not null,
  last_event_id text null references public.claim_events(id) on delete set null,
  updated_at timestamptz not null default now()
);

create unique index if not exists idx_sync_cursors_user_device on public.sync_cursors (user_id, device_id);

alter table public.tenants enable row level security;
alter table public.users enable row level security;
alter table public.claims enable row level security;
alter table public.claim_states enable row level security;
alter table public.claim_events enable row level security;
alter table public.claim_assignments enable row level security;
alter table public.case_tasks enable row level security;
alter table public.mailboxes enable row level security;
alter table public.emails enable row level security;
alter table public.email_claim_links enable row level security;
alter table public.attachments enable row level security;
alter table public.claim_folders enable row level security;
alter table public.documents enable row level security;
alter table public.document_versions enable row level security;
alter table public.document_analysis enable row level security;
alter table public.claim_reports enable row level security;
alter table public.claim_diary_entries enable row level security;
alter table public.claim_lightning_outcomes enable row level security;
alter table public.whatsapp_accounts enable row level security;
alter table public.whatsapp_threads enable row level security;
alter table public.whatsapp_messages enable row level security;
alter table public.internal_chat_threads enable row level security;
alter table public.internal_chat_members enable row level security;
alter table public.internal_chat_messages enable row level security;
alter table public.ai_chat_sessions enable row level security;
alter table public.ai_chat_messages enable row level security;
alter table public.user_work_schedules enable row level security;
alter table public.calendar_events enable row level security;
alter table public.dashboard_widgets enable row level security;
alter table public.audit_log enable row level security;
alter table public.sync_cursors enable row level security;

drop policy if exists tenants_select on public.tenants;
create policy tenants_select on public.tenants
for select to authenticated
using (id = public.current_tenant_id() or public.is_platform_admin());

drop policy if exists users_select on public.users;
create policy users_select on public.users
for select to authenticated
using (tenant_id = public.current_tenant_id() or public.is_platform_admin());

drop policy if exists users_update_self on public.users;
create policy users_update_self on public.users
for update to authenticated
using (id = public.current_app_user_id() or public.is_platform_admin())
with check (tenant_id = public.current_tenant_id() or public.is_platform_admin());

drop policy if exists claims_select on public.claims;
create policy claims_select on public.claims
for select to authenticated
using (tenant_id = public.current_tenant_id() or public.is_platform_admin());

drop policy if exists claims_write on public.claims;
create policy claims_write on public.claims
for all to authenticated
using (tenant_id = public.current_tenant_id() or public.is_platform_admin())
with check (tenant_id = public.current_tenant_id() or public.is_platform_admin());

drop policy if exists tenant_scoped_claim_states on public.claim_states;
create policy tenant_scoped_claim_states on public.claim_states
for all to authenticated
using (tenant_id = public.current_tenant_id() or public.is_platform_admin())
with check (tenant_id = public.current_tenant_id() or public.is_platform_admin());

drop policy if exists tenant_scoped_claim_events on public.claim_events;
create policy tenant_scoped_claim_events on public.claim_events
for all to authenticated
using (tenant_id = public.current_tenant_id() or public.is_platform_admin())
with check (tenant_id = public.current_tenant_id() or public.is_platform_admin());

drop policy if exists tenant_scoped_claim_assignments on public.claim_assignments;
create policy tenant_scoped_claim_assignments on public.claim_assignments
for all to authenticated
using (tenant_id = public.current_tenant_id() or public.is_platform_admin())
with check (tenant_id = public.current_tenant_id() or public.is_platform_admin());

drop policy if exists tenant_scoped_case_tasks on public.case_tasks;
create policy tenant_scoped_case_tasks on public.case_tasks
for all to authenticated
using (tenant_id = public.current_tenant_id() or public.is_platform_admin())
with check (tenant_id = public.current_tenant_id() or public.is_platform_admin());

drop policy if exists tenant_scoped_mailboxes on public.mailboxes;
create policy tenant_scoped_mailboxes on public.mailboxes
for all to authenticated
using (tenant_id = public.current_tenant_id() or public.is_platform_admin())
with check (tenant_id = public.current_tenant_id() or public.is_platform_admin());

drop policy if exists tenant_scoped_emails on public.emails;
create policy tenant_scoped_emails on public.emails
for all to authenticated
using (tenant_id = public.current_tenant_id() or public.is_platform_admin())
with check (tenant_id = public.current_tenant_id() or public.is_platform_admin());

drop policy if exists tenant_scoped_email_claim_links on public.email_claim_links;
create policy tenant_scoped_email_claim_links on public.email_claim_links
for all to authenticated
using (tenant_id = public.current_tenant_id() or public.is_platform_admin())
with check (tenant_id = public.current_tenant_id() or public.is_platform_admin());

drop policy if exists tenant_scoped_attachments on public.attachments;
create policy tenant_scoped_attachments on public.attachments
for all to authenticated
using (tenant_id = public.current_tenant_id() or public.is_platform_admin())
with check (tenant_id = public.current_tenant_id() or public.is_platform_admin());

drop policy if exists tenant_scoped_claim_folders on public.claim_folders;
create policy tenant_scoped_claim_folders on public.claim_folders
for all to authenticated
using (tenant_id = public.current_tenant_id() or public.is_platform_admin())
with check (tenant_id = public.current_tenant_id() or public.is_platform_admin());

drop policy if exists tenant_scoped_documents on public.documents;
create policy tenant_scoped_documents on public.documents
for all to authenticated
using (tenant_id = public.current_tenant_id() or public.is_platform_admin())
with check (tenant_id = public.current_tenant_id() or public.is_platform_admin());

drop policy if exists tenant_scoped_document_versions on public.document_versions;
create policy tenant_scoped_document_versions on public.document_versions
for all to authenticated
using (tenant_id = public.current_tenant_id() or public.is_platform_admin())
with check (tenant_id = public.current_tenant_id() or public.is_platform_admin());

drop policy if exists tenant_scoped_document_analysis on public.document_analysis;
create policy tenant_scoped_document_analysis on public.document_analysis
for all to authenticated
using (tenant_id = public.current_tenant_id() or public.is_platform_admin())
with check (tenant_id = public.current_tenant_id() or public.is_platform_admin());

drop policy if exists tenant_scoped_claim_reports on public.claim_reports;
create policy tenant_scoped_claim_reports on public.claim_reports
for all to authenticated
using (tenant_id = public.current_tenant_id() or public.is_platform_admin())
with check (tenant_id = public.current_tenant_id() or public.is_platform_admin());

drop policy if exists tenant_scoped_claim_diary_entries on public.claim_diary_entries;
create policy tenant_scoped_claim_diary_entries on public.claim_diary_entries
for all to authenticated
using (tenant_id = public.current_tenant_id() or public.is_platform_admin())
with check (tenant_id = public.current_tenant_id() or public.is_platform_admin());

drop policy if exists tenant_scoped_claim_lightning_outcomes on public.claim_lightning_outcomes;
create policy tenant_scoped_claim_lightning_outcomes on public.claim_lightning_outcomes
for all to authenticated
using (tenant_id = public.current_tenant_id() or public.is_platform_admin())
with check (tenant_id = public.current_tenant_id() or public.is_platform_admin());

drop policy if exists tenant_scoped_whatsapp_accounts on public.whatsapp_accounts;
create policy tenant_scoped_whatsapp_accounts on public.whatsapp_accounts
for all to authenticated
using (tenant_id = public.current_tenant_id() or public.is_platform_admin())
with check (tenant_id = public.current_tenant_id() or public.is_platform_admin());

drop policy if exists tenant_scoped_whatsapp_threads on public.whatsapp_threads;
create policy tenant_scoped_whatsapp_threads on public.whatsapp_threads
for all to authenticated
using (tenant_id = public.current_tenant_id() or public.is_platform_admin())
with check (tenant_id = public.current_tenant_id() or public.is_platform_admin());

drop policy if exists tenant_scoped_whatsapp_messages on public.whatsapp_messages;
create policy tenant_scoped_whatsapp_messages on public.whatsapp_messages
for all to authenticated
using (tenant_id = public.current_tenant_id() or public.is_platform_admin())
with check (tenant_id = public.current_tenant_id() or public.is_platform_admin());

drop policy if exists tenant_scoped_internal_chat_threads on public.internal_chat_threads;
create policy tenant_scoped_internal_chat_threads on public.internal_chat_threads
for all to authenticated
using (tenant_id = public.current_tenant_id() or public.is_platform_admin())
with check (tenant_id = public.current_tenant_id() or public.is_platform_admin());

drop policy if exists internal_chat_members_select on public.internal_chat_members;
create policy internal_chat_members_select on public.internal_chat_members
for select to authenticated
using (
  exists (
    select 1
    from public.internal_chat_threads t
    where t.id = thread_id
      and (t.tenant_id = public.current_tenant_id() or public.is_platform_admin())
  )
);

drop policy if exists internal_chat_members_write on public.internal_chat_members;
create policy internal_chat_members_write on public.internal_chat_members
for all to authenticated
using (
  exists (
    select 1
    from public.internal_chat_threads t
    where t.id = thread_id
      and (t.tenant_id = public.current_tenant_id() or public.is_platform_admin())
  )
)
with check (
  exists (
    select 1
    from public.internal_chat_threads t
    where t.id = thread_id
      and (t.tenant_id = public.current_tenant_id() or public.is_platform_admin())
  )
);

drop policy if exists tenant_scoped_internal_chat_messages on public.internal_chat_messages;
create policy tenant_scoped_internal_chat_messages on public.internal_chat_messages
for all to authenticated
using (tenant_id = public.current_tenant_id() or public.is_platform_admin())
with check (tenant_id = public.current_tenant_id() or public.is_platform_admin());

drop policy if exists ai_chat_sessions_select on public.ai_chat_sessions;
create policy ai_chat_sessions_select on public.ai_chat_sessions
for select to authenticated
using (
  tenant_id = public.current_tenant_id()
  and (user_id = public.current_app_user_id() or public.is_platform_admin())
);

drop policy if exists ai_chat_sessions_write on public.ai_chat_sessions;
create policy ai_chat_sessions_write on public.ai_chat_sessions
for all to authenticated
using (
  tenant_id = public.current_tenant_id()
  and (user_id = public.current_app_user_id() or public.is_platform_admin())
)
with check (
  tenant_id = public.current_tenant_id()
  and (user_id = public.current_app_user_id() or public.is_platform_admin())
);

drop policy if exists ai_chat_messages_policy on public.ai_chat_messages;
create policy ai_chat_messages_policy on public.ai_chat_messages
for all to authenticated
using (
  exists (
    select 1
    from public.ai_chat_sessions s
    where s.id = session_id
      and s.tenant_id = public.current_tenant_id()
      and (s.user_id = public.current_app_user_id() or public.is_platform_admin())
  )
)
with check (
  exists (
    select 1
    from public.ai_chat_sessions s
    where s.id = session_id
      and s.tenant_id = public.current_tenant_id()
      and (s.user_id = public.current_app_user_id() or public.is_platform_admin())
  )
);

drop policy if exists user_work_schedules_policy on public.user_work_schedules;
create policy user_work_schedules_policy on public.user_work_schedules
for all to authenticated
using (
  tenant_id = public.current_tenant_id()
  and (user_id = public.current_app_user_id() or public.is_platform_admin())
)
with check (
  tenant_id = public.current_tenant_id()
  and (user_id = public.current_app_user_id() or public.is_platform_admin())
);

drop policy if exists calendar_events_select on public.calendar_events;
create policy calendar_events_select on public.calendar_events
for select to authenticated
using (
  tenant_id = public.current_tenant_id()
  and (
    visibility = 'tenant'
    or owner_user_id = public.current_app_user_id()
    or public.is_platform_admin()
  )
);

drop policy if exists calendar_events_write on public.calendar_events;
create policy calendar_events_write on public.calendar_events
for all to authenticated
using (
  tenant_id = public.current_tenant_id()
  and (
    owner_user_id = public.current_app_user_id()
    or public.is_platform_admin()
  )
)
with check (
  tenant_id = public.current_tenant_id()
  and (
    owner_user_id = public.current_app_user_id()
    or public.is_platform_admin()
  )
);

drop policy if exists dashboard_widgets_policy on public.dashboard_widgets;
create policy dashboard_widgets_policy on public.dashboard_widgets
for all to authenticated
using (
  tenant_id = public.current_tenant_id()
  and (user_id = public.current_app_user_id() or public.is_platform_admin())
)
with check (
  tenant_id = public.current_tenant_id()
  and (user_id = public.current_app_user_id() or public.is_platform_admin())
);

drop policy if exists audit_log_select on public.audit_log;
create policy audit_log_select on public.audit_log
for select to authenticated
using (tenant_id = public.current_tenant_id() or public.is_platform_admin());

drop policy if exists sync_cursors_policy on public.sync_cursors;
create policy sync_cursors_policy on public.sync_cursors
for all to authenticated
using (
  tenant_id = public.current_tenant_id()
  and (user_id = public.current_app_user_id() or public.is_platform_admin())
)
with check (
  tenant_id = public.current_tenant_id()
  and (user_id = public.current_app_user_id() or public.is_platform_admin())
);
