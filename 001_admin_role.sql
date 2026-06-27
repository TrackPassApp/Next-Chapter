-- =============================================================================
-- Next Chapter — Batch 1 migration: server-controlled admin role
-- =============================================================================
-- This migration is additive and safe to run on an existing Supabase project.
-- It does NOT modify or drop any existing tables, columns, or policies.
--
-- What this migration does:
--   1. Creates a `public.admin_users` audit table tracking who is an admin,
--      what role they have, when granted, and by whom.
--   2. Creates `public.is_admin(uid)` SECURITY DEFINER helper for future RLS.
--
-- What this migration intentionally does NOT do (deferred to later batches):
--   - It does not touch the `reports` table policies.
--   - It does not change `verification_status` policies.
--   - It does not add date_of_birth or reporter/reported CHECK constraints.
--   - It does not add storage bucket policies.
--   - It does not create `moderation_log`.
-- These are intentionally postponed per the approved Batch 1 scope.
--
-- IMPORTANT: After running this file, you must manually elevate your own
-- account to admin. See the section at the bottom of this file.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. admin_users — record of who is admin and at what level.
-- -----------------------------------------------------------------------------

create table if not exists public.admin_users (
  user_id     uuid        primary key references auth.users(id) on delete cascade,
  role        text        not null default 'admin'
                          check (role in ('moderator', 'admin', 'super_admin')),
  granted_at  timestamptz not null default now(),
  granted_by  uuid        references auth.users(id),
  notes       text
);

comment on table public.admin_users is
  'Audit record of admin role grants. The authoritative admin check is on '
  'auth.users.raw_app_meta_data->>''role''; this table mirrors it for ops.';


-- -----------------------------------------------------------------------------
-- 2. RLS on admin_users — only admins can see it.
-- -----------------------------------------------------------------------------

alter table public.admin_users enable row level security;

drop policy if exists "admin_users_select_admins_only" on public.admin_users;
create policy "admin_users_select_admins_only"
  on public.admin_users
  for select
  to authenticated
  using (
    coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')
      in ('admin', 'super_admin')
  );

-- No INSERT/UPDATE/DELETE policies are defined here. Writes are intentionally
-- restricted to the service_role connection (Supabase SQL editor or a server
-- using the service key). The Flutter client cannot write to this table.


-- -----------------------------------------------------------------------------
-- 3. is_admin() helper for future RLS policies.
-- -----------------------------------------------------------------------------

create or replace function public.is_admin(uid uuid default auth.uid())
  returns boolean
  language sql
  stable
  security definer
  set search_path = public
as $$
  select coalesce(
    (
      select (raw_app_meta_data ->> 'role') in ('admin', 'super_admin', 'moderator')
      from auth.users
      where id = uid
    ),
    false
  );
$$;

comment on function public.is_admin(uuid) is
  'Returns true if the given user has an admin role in app_metadata. '
  'app_metadata is service-role-only; users cannot self-elevate.';


-- =============================================================================
-- MANUAL STEP — RUN THIS YOURSELF AFTER THE MIGRATION
-- =============================================================================
-- Replace 'your_email@example.com' with the email you used to sign up.
-- This sets your account's app_metadata role to 'admin' and records it in
-- admin_users. You must then SIGN OUT and SIGN BACK IN so the JWT is reissued
-- with the new role.
-- =============================================================================
--
-- update auth.users
--   set raw_app_meta_data =
--     coalesce(raw_app_meta_data, '{}'::jsonb) || '{"role":"admin"}'::jsonb
-- where email = 'your_email@example.com';
--
-- insert into public.admin_users (user_id, role, granted_by, notes)
-- select id, 'admin', id, 'initial bootstrap admin'
--   from auth.users
--   where email = 'your_email@example.com'
-- on conflict (user_id) do nothing;
--
-- =============================================================================
-- TO REVOKE ADMIN later:
-- =============================================================================
-- update auth.users
--   set raw_app_meta_data = raw_app_meta_data - 'role'
-- where email = 'their_email@example.com';
--
-- delete from public.admin_users
-- where user_id = (select id from auth.users where email = 'their_email@example.com');
-- =============================================================================
