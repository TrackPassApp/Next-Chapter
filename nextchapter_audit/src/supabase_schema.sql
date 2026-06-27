-- =============================================================================
-- Next Chapter — Supabase Schema
-- Run this entire script in your Supabase SQL Editor (Dashboard → SQL Editor → New Query)
-- =============================================================================

-- ─── 1. profiles ─────────────────────────────────────────────────────────────
create table if not exists public.profiles (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  first_name      text not null default '',
  date_of_birth   date,
  city            text not null default '',
  state           text not null default '',
  gender          text not null default '',
  relationship_status text not null default '',
  about_me        text not null default '',
  is_online       boolean not null default false,
  last_active     timestamptz not null default now(),
  is_suspended    boolean not null default false,
  is_deleted      boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint profiles_user_id_unique unique (user_id)
);

alter table public.profiles enable row level security;

-- Anyone logged in can read active, non-suspended, non-deleted profiles.
create policy "Public profiles are viewable by authenticated users"
  on public.profiles for select
  to authenticated
  using (is_suspended = false and is_deleted = false);

-- A user can insert their own profile row only.
create policy "Users can insert own profile"
  on public.profiles for insert
  to authenticated
  with check (auth.uid() = user_id);

-- A user can update only their own profile row.
create policy "Users can update own profile"
  on public.profiles for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- A user can delete (soft-delete via is_deleted flag) their own profile.
create policy "Users can delete own profile"
  on public.profiles for delete
  to authenticated
  using (auth.uid() = user_id);

-- Auto-update updated_at on every row change.
create or replace function public.handle_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_updated_at
  before update on public.profiles
  for each row execute function public.handle_updated_at();


-- ─── 2. profile_photos ───────────────────────────────────────────────────────
create table if not exists public.profile_photos (
  id              uuid primary key default gen_random_uuid(),
  profile_id      uuid not null references public.profiles(id) on delete cascade,
  storage_path    text not null,
  display_url     text not null,
  display_order   int not null default 0,
  created_at      timestamptz not null default now()
);

alter table public.profile_photos enable row level security;

create policy "Anyone authenticated can view profile photos"
  on public.profile_photos for select
  to authenticated
  using (true);

create policy "Users can insert their own photos"
  on public.profile_photos for insert
  to authenticated
  with check (
    profile_id in (
      select id from public.profiles where user_id = auth.uid()
    )
  );

create policy "Users can delete their own photos"
  on public.profile_photos for delete
  to authenticated
  using (
    profile_id in (
      select id from public.profiles where user_id = auth.uid()
    )
  );


-- ─── 3. profile_interests ────────────────────────────────────────────────────
create table if not exists public.profile_interests (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null references public.profiles(id) on delete cascade,
  interest    text not null
);

alter table public.profile_interests enable row level security;

create policy "Anyone authenticated can view interests"
  on public.profile_interests for select
  to authenticated
  using (true);

create policy "Users can manage their own interests"
  on public.profile_interests for all
  to authenticated
  using (
    profile_id in (select id from public.profiles where user_id = auth.uid())
  )
  with check (
    profile_id in (select id from public.profiles where user_id = auth.uid())
  );


-- ─── 4. profile_looking_for ──────────────────────────────────────────────────
create table if not exists public.profile_looking_for (
  id              uuid primary key default gen_random_uuid(),
  profile_id      uuid not null references public.profiles(id) on delete cascade,
  looking_for     text not null
);

alter table public.profile_looking_for enable row level security;

create policy "Anyone authenticated can view looking_for"
  on public.profile_looking_for for select
  to authenticated
  using (true);

create policy "Users can manage their own looking_for"
  on public.profile_looking_for for all
  to authenticated
  using (
    profile_id in (select id from public.profiles where user_id = auth.uid())
  )
  with check (
    profile_id in (select id from public.profiles where user_id = auth.uid())
  );


-- ─── 5. profile_life_situation ───────────────────────────────────────────────
create table if not exists public.profile_life_situation (
  id              uuid primary key default gen_random_uuid(),
  profile_id      uuid not null references public.profiles(id) on delete cascade,
  life_situation  text not null
);

alter table public.profile_life_situation enable row level security;

create policy "Anyone authenticated can view life_situation"
  on public.profile_life_situation for select
  to authenticated
  using (true);

create policy "Users can manage their own life_situation"
  on public.profile_life_situation for all
  to authenticated
  using (
    profile_id in (select id from public.profiles where user_id = auth.uid())
  )
  with check (
    profile_id in (select id from public.profiles where user_id = auth.uid())
  );


-- ─── 6. verification_status ──────────────────────────────────────────────────
create table if not exists public.verification_status (
  id              uuid primary key default gen_random_uuid(),
  profile_id      uuid not null references public.profiles(id) on delete cascade,
  email_verified  boolean not null default false,
  phone_verified  boolean not null default false,
  selfie_verified boolean not null default false,
  id_verified     boolean not null default false,
  updated_at      timestamptz not null default now(),
  constraint verification_status_profile_id_unique unique (profile_id)
);

alter table public.verification_status enable row level security;

create policy "Anyone authenticated can view verification_status"
  on public.verification_status for select
  to authenticated
  using (true);

create policy "Users can manage their own verification_status"
  on public.verification_status for all
  to authenticated
  using (
    profile_id in (select id from public.profiles where user_id = auth.uid())
  )
  with check (
    profile_id in (select id from public.profiles where user_id = auth.uid())
  );


-- ─── 7. user_settings ────────────────────────────────────────────────────────
create table if not exists public.user_settings (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  show_online_status boolean not null default true,
  allow_messages_from text not null default 'everyone',
  updated_at      timestamptz not null default now(),
  constraint user_settings_user_id_unique unique (user_id)
);

alter table public.user_settings enable row level security;

create policy "Users can view their own settings"
  on public.user_settings for select
  to authenticated
  using (auth.uid() = user_id);

create policy "Users can manage their own settings"
  on public.user_settings for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);


-- ─── 8. blocks ───────────────────────────────────────────────────────────────
create table if not exists public.blocks (
  id          uuid primary key default gen_random_uuid(),
  blocker_id  uuid not null references public.profiles(id) on delete cascade,
  blocked_id  uuid not null references public.profiles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  constraint blocks_unique unique (blocker_id, blocked_id)
);

alter table public.blocks enable row level security;

create policy "Users can view their own blocks"
  on public.blocks for select
  to authenticated
  using (
    blocker_id in (select id from public.profiles where user_id = auth.uid())
  );

create policy "Users can manage their own blocks"
  on public.blocks for all
  to authenticated
  using (
    blocker_id in (select id from public.profiles where user_id = auth.uid())
  )
  with check (
    blocker_id in (select id from public.profiles where user_id = auth.uid())
  );


-- ─── 9. reports ──────────────────────────────────────────────────────────────
create table if not exists public.reports (
  id                  uuid primary key default gen_random_uuid(),
  reporter_id         uuid not null references public.profiles(id) on delete cascade,
  reported_user_id    uuid not null references public.profiles(id) on delete cascade,
  reason              text not null,
  details             text not null default '',
  status              text not null default 'pending',
  created_at          timestamptz not null default now()
);

alter table public.reports enable row level security;

create policy "Users can insert reports"
  on public.reports for insert
  to authenticated
  with check (
    reporter_id in (select id from public.profiles where user_id = auth.uid())
  );

create policy "Users can view their own reports"
  on public.reports for select
  to authenticated
  using (
    reporter_id in (select id from public.profiles where user_id = auth.uid())
  );


-- ─── 10. Storage bucket (run separately or via the Supabase dashboard) ───────
-- Create a bucket named: profile-photos
-- Settings: Public = false (signed URLs only), File size limit = 5MB, Allowed MIME: image/*
--
-- After creating the bucket, run these storage policies:
--
-- insert (upload):
--   bucket_id = 'profile-photos' AND auth.uid()::text = (storage.foldername(name))[1]
--
-- select (download):
--   bucket_id = 'profile-photos' AND auth.role() = 'authenticated'
--
-- delete:
--   bucket_id = 'profile-photos' AND auth.uid()::text = (storage.foldername(name))[1]
--
-- The Flutter app uploads to path: {user_id}/{uuid}.jpg
-- This ensures each user can only manage files inside their own folder.

-- =============================================================================
-- Done. All tables created with RLS enabled.
-- =============================================================================
