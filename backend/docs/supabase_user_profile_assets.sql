create table if not exists public.user_profile_assets (
  id text primary key,
  tenant_id text not null references public.tenants(id) on delete cascade,
  user_id text not null references public.users(id) on delete cascade,
  asset_type text not null,
  file_name text not null,
  mime_type text null,
  size_bytes bigint not null default 0,
  storage_provider text not null default 'backend-local',
  storage_path text not null,
  checksum_sha256 text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists uq_user_profile_assets_user_type
on public.user_profile_assets (user_id, asset_type);

alter table public.user_profile_assets enable row level security;

drop policy if exists user_profile_assets_select on public.user_profile_assets;
create policy user_profile_assets_select on public.user_profile_assets
for select
to authenticated
using (
  tenant_id = public.current_tenant_id() or public.is_platform_admin()
);

drop policy if exists user_profile_assets_insert on public.user_profile_assets;
create policy user_profile_assets_insert on public.user_profile_assets
for insert
to authenticated
with check (
  tenant_id = public.current_tenant_id() or public.is_platform_admin()
);

drop policy if exists user_profile_assets_update on public.user_profile_assets;
create policy user_profile_assets_update on public.user_profile_assets
for update
to authenticated
using (
  tenant_id = public.current_tenant_id() or public.is_platform_admin()
)
with check (
  tenant_id = public.current_tenant_id() or public.is_platform_admin()
);

drop policy if exists user_profile_assets_delete on public.user_profile_assets;
create policy user_profile_assets_delete on public.user_profile_assets
for delete
to authenticated
using (
  tenant_id = public.current_tenant_id() or public.is_platform_admin()
);
