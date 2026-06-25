create extension if not exists pgcrypto;

create table if not exists public.entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null default '未命名的一天',
  body text not null default '',
  entry_type text not null default '随笔',
  mood text not null default '平静',
  tags text[] not null default '{}',
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.entries add column if not exists deleted_at timestamptz;

create index if not exists entries_user_occurred_idx
  on public.entries (user_id, occurred_at desc);
create index if not exists entries_user_deleted_idx
  on public.entries (user_id, deleted_at);

alter table public.entries enable row level security;

drop policy if exists "Users can read their entries" on public.entries;
create policy "Users can read their entries"
  on public.entries
  for select
  to authenticated
  using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

drop policy if exists "Users can create their entries" on public.entries;
create policy "Users can create their entries"
  on public.entries
  for insert
  to authenticated
  with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

drop policy if exists "Users can update their entries" on public.entries;
create policy "Users can update their entries"
  on public.entries
  for update
  to authenticated
  using ((select auth.uid()) is not null and (select auth.uid()) = user_id)
  with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

drop policy if exists "Users can delete their entries" on public.entries;
create policy "Users can delete their entries"
  on public.entries
  for delete
  to authenticated
  using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

revoke all on table public.entries from anon;
grant select, insert, update, delete on table public.entries to authenticated;
grant all on table public.entries to service_role;

create table if not exists public.entry_versions (
  id uuid primary key default gen_random_uuid(),
  entry_id uuid not null references public.entries(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  body text not null,
  entry_type text not null,
  mood text not null,
  tags text[] not null default '{}',
  occurred_at timestamptz not null,
  versioned_at timestamptz not null default now()
);

create index if not exists entry_versions_entry_idx
  on public.entry_versions (entry_id, versioned_at desc);
create index if not exists entry_versions_user_idx
  on public.entry_versions (user_id, versioned_at desc);

alter table public.entry_versions enable row level security;

drop policy if exists "Users can read their entry versions" on public.entry_versions;
create policy "Users can read their entry versions"
  on public.entry_versions for select to authenticated
  using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

revoke all on table public.entry_versions from anon;
revoke insert, update, delete on table public.entry_versions from authenticated;
grant select on table public.entry_versions to authenticated;
grant all on table public.entry_versions to service_role;

create or replace function public.capture_entry_version()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if row(old.title, old.body, old.entry_type, old.mood, old.tags, old.occurred_at, old.deleted_at)
     is distinct from
     row(new.title, new.body, new.entry_type, new.mood, new.tags, new.occurred_at, new.deleted_at) then
    if old.deleted_at is distinct from new.deleted_at
       or not exists (
         select 1
         from public.entry_versions
         where entry_id = old.id
           and versioned_at > now() - interval '5 minutes'
       ) then
      insert into public.entry_versions (
        entry_id, user_id, title, body, entry_type, mood, tags, occurred_at
      ) values (
        old.id, old.user_id, old.title, old.body, old.entry_type, old.mood, old.tags, old.occurred_at
      );
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.capture_entry_version() from public;

drop trigger if exists capture_entry_version_before_update on public.entries;
create trigger capture_entry_version_before_update
  before update on public.entries
  for each row execute function public.capture_entry_version();

create table if not exists public.media (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  entry_id uuid not null references public.entries(id) on delete cascade,
  storage_path text not null unique,
  file_name text not null,
  mime_type text not null,
  file_size bigint not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists media_entry_idx on public.media (entry_id, created_at);
create index if not exists media_user_idx on public.media (user_id);

alter table public.media enable row level security;

drop policy if exists "Users can read their media" on public.media;
create policy "Users can read their media"
  on public.media for select to authenticated
  using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

drop policy if exists "Users can create their media" on public.media;
create policy "Users can create their media"
  on public.media for insert to authenticated
  with check (
    (select auth.uid()) is not null
    and (select auth.uid()) = user_id
    and exists (
      select 1 from public.entries
      where entries.id = media.entry_id
        and entries.user_id = (select auth.uid())
    )
  );

drop policy if exists "Users can delete their media" on public.media;
create policy "Users can delete their media"
  on public.media for delete to authenticated
  using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

revoke all on table public.media from anon;
grant select, insert, delete on table public.media to authenticated;
grant all on table public.media to service_role;

create table if not exists public.app_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.app_admins enable row level security;

drop policy if exists "Admins can read themselves" on public.app_admins;
create policy "Admins can read themselves"
  on public.app_admins for select to authenticated
  using ((select auth.uid()) = user_id);

revoke all on table public.app_admins from anon;
revoke insert, update, delete on table public.app_admins from authenticated;
grant select on table public.app_admins to authenticated;
grant all on table public.app_admins to service_role;

create table if not exists public.invitations (
  id uuid primary key default gen_random_uuid(),
  inviter_id uuid not null references auth.users(id) on delete cascade,
  email text not null,
  name text not null default '',
  note text not null default '',
  status text not null default '待发送',
  auth_user_id uuid references auth.users(id) on delete set null,
  invited_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (inviter_id, email)
);

create index if not exists invitations_inviter_updated_idx
  on public.invitations (inviter_id, updated_at desc);
create index if not exists invitations_status_idx
  on public.invitations (status);

alter table public.invitations enable row level security;

drop policy if exists "Admins can read their invitations" on public.invitations;
create policy "Admins can read their invitations"
  on public.invitations for select to authenticated
  using (
    (select auth.uid()) = inviter_id
    and exists (
      select 1 from public.app_admins
      where app_admins.user_id = (select auth.uid())
    )
  );

drop policy if exists "Admins can create their invitations" on public.invitations;
create policy "Admins can create their invitations"
  on public.invitations for insert to authenticated
  with check (
    (select auth.uid()) = inviter_id
    and exists (
      select 1 from public.app_admins
      where app_admins.user_id = (select auth.uid())
    )
  );

drop policy if exists "Admins can update their invitations" on public.invitations;
create policy "Admins can update their invitations"
  on public.invitations for update to authenticated
  using (
    (select auth.uid()) = inviter_id
    and exists (
      select 1 from public.app_admins
      where app_admins.user_id = (select auth.uid())
    )
  )
  with check (
    (select auth.uid()) = inviter_id
    and exists (
      select 1 from public.app_admins
      where app_admins.user_id = (select auth.uid())
    )
  );

drop policy if exists "Admins can delete their invitations" on public.invitations;
create policy "Admins can delete their invitations"
  on public.invitations for delete to authenticated
  using (
    (select auth.uid()) = inviter_id
    and exists (
      select 1 from public.app_admins
      where app_admins.user_id = (select auth.uid())
    )
  );

create or replace function public.touch_invitation_updated_at()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

revoke all on function public.touch_invitation_updated_at() from public;

drop trigger if exists touch_invitation_updated_at_before_update on public.invitations;
create trigger touch_invitation_updated_at_before_update
  before update on public.invitations
  for each row execute function public.touch_invitation_updated_at();

revoke all on table public.invitations from anon;
grant select, insert, update, delete on table public.invitations to authenticated;
grant all on table public.invitations to service_role;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'diary-media',
  'diary-media',
  false,
  52428800,
  array[
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
    'video/mp4',
    'video/quicktime',
    'video/webm'
  ]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Users can read their storage objects" on storage.objects;
create policy "Users can read their storage objects"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'diary-media'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

drop policy if exists "Users can upload their storage objects" on storage.objects;
create policy "Users can upload their storage objects"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'diary-media'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

drop policy if exists "Users can delete their storage objects" on storage.objects;
create policy "Users can delete their storage objects"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'diary-media'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );
