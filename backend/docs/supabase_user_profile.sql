alter table public.users add column if not exists first_name text;
alter table public.users add column if not exists last_name text;
alter table public.users add column if not exists job_title text;
alter table public.users add column if not exists phone_number text;
alter table public.users add column if not exists birth_date timestamptz;
alter table public.users add column if not exists birthday_visibility text not null default 'everyone';
alter table public.users add column if not exists notify_birthday boolean not null default true;
alter table public.users add column if not exists contract_type text;
alter table public.users add column if not exists avatar_type text not null default 'generated';
alter table public.users add column if not exists avatar_photo_base64 text;
alter table public.users add column if not exists generated_avatar_color text;
alter table public.users add column if not exists generated_avatar_icon text;
alter table public.users add column if not exists avatar_gif_url text;
alter table public.users add column if not exists enable_badges boolean not null default false;
alter table public.users add column if not exists send_read_receipts boolean not null default true;
alter table public.users add column if not exists email_signature_html text;
alter table public.users add column if not exists email_signature_text text;
alter table public.users add column if not exists settings_json jsonb default '{}'::jsonb;

-- Interno PerX (telefonia / LiveKit). Persistito per account.
alter table public.users add column if not exists extension_number text;
alter table public.users add column if not exists extension_enabled boolean not null default true;
alter table public.users add column if not exists extension_assigned_at timestamptz;
alter table public.users add column if not exists extension_display_name text;
alter table public.users add column if not exists availability_status text;
alter table public.users add column if not exists communication_status text;

create unique index if not exists users_extension_number_unique
    on public.users (extension_number)
    where extension_number is not null;

-- Restituisce il prossimo interno libero (>= 100, fino a 9999).
create or replace function public.next_available_extension()
returns text
language plpgsql
as $$
declare
    candidate int := 100;
begin
    while candidate <= 9999 loop
        if not exists (
            select 1 from public.users
            where extension_number = candidate::text
        ) then
            return candidate::text;
        end if;
        candidate := candidate + 1;
    end loop;
    return null;
end;
$$;

-- Assegna automaticamente l'interno alla creazione account (se non già impostato).
create or replace function public.assign_extension_on_user_insert()
returns trigger
language plpgsql
as $$
begin
    if new.extension_number is null then
        new.extension_number := public.next_available_extension();
        new.extension_assigned_at := now();
        new.extension_enabled := coalesce(new.extension_enabled, true);
    end if;
    return new;
end;
$$;

drop trigger if exists trg_users_assign_extension on public.users;
create trigger trg_users_assign_extension
    before insert on public.users
    for each row execute function public.assign_extension_on_user_insert();

-- Backfill manuale interni per gli account già esistenti (demo + reali).
update public.users
    set extension_number = '101',
        extension_enabled = true,
        extension_assigned_at = coalesce(extension_assigned_at, now()),
        extension_display_name = coalesce(extension_display_name, 'Perito PerX')
    where lower(email) = 'perito@perx.it' and extension_number is null;

update public.users
    set extension_number = '102',
        extension_enabled = true,
        extension_assigned_at = coalesce(extension_assigned_at, now()),
        extension_display_name = coalesce(extension_display_name, 'Admin PerX')
    where lower(email) = 'admin@perx.it' and extension_number is null;

update public.users
    set extension_number = '103',
        extension_enabled = true,
        extension_assigned_at = coalesce(extension_assigned_at, now()),
        extension_display_name = coalesce(extension_display_name, 'CAT PerX')
    where lower(email) = 'cat@perx.it' and extension_number is null;

-- Per ogni utente preesistente senza interno: assegnane uno disponibile.
update public.users
    set extension_number = public.next_available_extension(),
        extension_assigned_at = now(),
        extension_enabled = coalesce(extension_enabled, true)
    where extension_number is null;
