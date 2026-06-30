-- =============================================================================
-- 010 — Fix profile-read RLS + diagnostic helper using UUID equality
-- =============================================================================
-- ROOT CAUSE FIXED HERE
-- --------------------
-- The Profile Detail screen has been rendering blank because the Flutter
-- client could fetch the user's own `profiles` row but NOT any other user's
-- row (Sarah, James, etc.) — and could not fetch ANY of the child rows
-- (profile_photos, profile_interests, profile_looking_for,
-- profile_life_situation) for *any* profile because none of those tables
-- had a SELECT policy in our 001..009 migrations.
--
-- Concretely:
--   - migrations 001..009 enabled RLS but only ever defined:
--       profile_prompts        SELECT (true)             ✓
--       verification_status    SELECT (true)             ✓
--       conversations / messages / message_reads / reports / moderation_log ✓
--       admin_users            SELECT admins-only         ✓
--       profiles               UPDATE admins              ← only this, no SELECT
--   - profiles SELECT was relying on whatever existed before our batches.
--     On the live project that pre-existing policy was restrictive
--     (USING auth.uid() = user_id), which is why Browse returned only the
--     signed-in user's own row and fetchProfileById on a demo UUID returned
--     null → "Could not load profile."
--   - profile_photos / profile_interests / profile_looking_for /
--     profile_life_situation had RLS enabled but no SELECT policy, so they
--     defaulted to deny-all → the Profile Detail body had no photos,
--     no interests, etc., which looked like "blank".
--
-- This migration:
--   1. Replaces any restrictive profiles SELECT policy with the correct one:
--        - signed-in users can read their own row, AND
--        - signed-in users can read any other row that is is_complete = true,
--          NOT is_suspended, NOT is_deleted.
--   2. Adds explicit, permissive SELECT policies on the four child tables
--      that feed the Profile Detail (matching the existing pattern used by
--      profile_prompts and verification_status).
--   3. Replaces the diagnostic LIKE-on-uuid call in the Flutter client with
--      a proper SECURITY DEFINER RPC `public.demo_seed_count()` that uses
--      UUID **equality** against the deterministic demo ids.
--
-- This migration is additive and idempotent. Safe to run on the live project.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. profiles SELECT policy — own row + public-browse rows
-- -----------------------------------------------------------------------------

-- Make sure RLS is on (it already should be; harmless if it is).
alter table public.profiles enable row level security;

-- Drop ALL previously-installed SELECT policies on profiles so the new one
-- is authoritative. We name-list the common variants that we have ever
-- introduced or that the original Supabase template installed.
drop policy if exists "profiles_select_self"           on public.profiles;
drop policy if exists "profiles_select_own"            on public.profiles;
drop policy if exists "profiles_select_authenticated"  on public.profiles;
drop policy if exists "profiles_select_public"         on public.profiles;
drop policy if exists "profiles_select_all"            on public.profiles;
drop policy if exists "profiles_read_public"           on public.profiles;
drop policy if exists "Users can view own profile"     on public.profiles;
drop policy if exists "Users can view their own profile" on public.profiles;
drop policy if exists "Authenticated can read profiles" on public.profiles;
drop policy if exists "Enable read access for all users" on public.profiles;

-- The authoritative SELECT policy:
--   * the user's own row is always visible (including incomplete drafts);
--   * any other row is visible only when it is publishable
--     (is_complete = true AND NOT is_suspended AND NOT is_deleted).
-- Admins keep a separate UPDATE policy from migration 002.
create policy "profiles_select_self_or_public"
  on public.profiles
  for select
  to authenticated
  using (
    auth.uid() = user_id
    or (
      coalesce(is_complete,    false) = true
      and coalesce(is_suspended, false) = false
      and coalesce(is_deleted,   false) = false
    )
  );


-- -----------------------------------------------------------------------------
-- 2. Child-table SELECT policies — profile_photos / interests / looking_for /
--    life_situation
-- -----------------------------------------------------------------------------
-- Pattern mirrors the existing profile_prompts / verification_status policies:
-- any authenticated user can read all rows; writes remain owner-only via
-- pre-existing policies (or service_role for the demo seed).

-- profile_photos
do $$
begin
  if exists (select 1 from pg_tables where schemaname='public' and tablename='profile_photos') then
    execute 'alter table public.profile_photos enable row level security';
    execute 'drop policy if exists "photos_select_all" on public.profile_photos';
    execute 'create policy "photos_select_all" on public.profile_photos
               for select to authenticated using (true)';

    execute 'drop policy if exists "photos_owner_write" on public.profile_photos';
    execute 'create policy "photos_owner_write" on public.profile_photos
               for all to authenticated
               using (
                 exists (select 1 from public.profiles p
                          where p.id = profile_photos.profile_id
                            and p.user_id = auth.uid())
               )
               with check (
                 exists (select 1 from public.profiles p
                          where p.id = profile_photos.profile_id
                            and p.user_id = auth.uid())
               )';
  end if;
end$$;

-- profile_interests
do $$
begin
  if exists (select 1 from pg_tables where schemaname='public' and tablename='profile_interests') then
    execute 'alter table public.profile_interests enable row level security';
    execute 'drop policy if exists "interests_select_all" on public.profile_interests';
    execute 'create policy "interests_select_all" on public.profile_interests
               for select to authenticated using (true)';

    execute 'drop policy if exists "interests_owner_write" on public.profile_interests';
    execute 'create policy "interests_owner_write" on public.profile_interests
               for all to authenticated
               using (
                 exists (select 1 from public.profiles p
                          where p.id = profile_interests.profile_id
                            and p.user_id = auth.uid())
               )
               with check (
                 exists (select 1 from public.profiles p
                          where p.id = profile_interests.profile_id
                            and p.user_id = auth.uid())
               )';
  end if;
end$$;

-- profile_looking_for
do $$
begin
  if exists (select 1 from pg_tables where schemaname='public' and tablename='profile_looking_for') then
    execute 'alter table public.profile_looking_for enable row level security';
    execute 'drop policy if exists "lookingfor_select_all" on public.profile_looking_for';
    execute 'create policy "lookingfor_select_all" on public.profile_looking_for
               for select to authenticated using (true)';

    execute 'drop policy if exists "lookingfor_owner_write" on public.profile_looking_for';
    execute 'create policy "lookingfor_owner_write" on public.profile_looking_for
               for all to authenticated
               using (
                 exists (select 1 from public.profiles p
                          where p.id = profile_looking_for.profile_id
                            and p.user_id = auth.uid())
               )
               with check (
                 exists (select 1 from public.profiles p
                          where p.id = profile_looking_for.profile_id
                            and p.user_id = auth.uid())
               )';
  end if;
end$$;

-- profile_life_situation
do $$
begin
  if exists (select 1 from pg_tables where schemaname='public' and tablename='profile_life_situation') then
    execute 'alter table public.profile_life_situation enable row level security';
    execute 'drop policy if exists "lifesit_select_all" on public.profile_life_situation';
    execute 'create policy "lifesit_select_all" on public.profile_life_situation
               for select to authenticated using (true)';

    execute 'drop policy if exists "lifesit_owner_write" on public.profile_life_situation';
    execute 'create policy "lifesit_owner_write" on public.profile_life_situation
               for all to authenticated
               using (
                 exists (select 1 from public.profiles p
                          where p.id = profile_life_situation.profile_id
                            and p.user_id = auth.uid())
               )
               with check (
                 exists (select 1 from public.profiles p
                          where p.id = profile_life_situation.profile_id
                            and p.user_id = auth.uid())
               )';
  end if;
end$$;


-- -----------------------------------------------------------------------------
-- 3. demo_seed_count() — diagnostic RPC, uuid-equality (not LIKE)
-- -----------------------------------------------------------------------------
-- The previous diagnostic check used `.like('id', '%-aaaa-%')` on a uuid
-- column. Postgres does not have a LIKE operator on uuid, so the call
-- failed with `42883 operator does not exist: uuid ~~ unknown` and the
-- diagnostics screen reported "Demo seed check: FAIL" even when the seed
-- was perfectly intact. This RPC uses straight equality against the six
-- deterministic demo uuids defined by migration 007.

create or replace function public.demo_seed_count()
  returns table (count int, names text)
  language sql
  stable
  security definer
  set search_path = public
as $$
  select
    count(*)::int                            as count,
    coalesce(string_agg(first_name, ', '), '') as names
  from public.profiles
  where user_id in (
    '00000000-0000-4000-8000-000000000001'::uuid,
    '00000000-0000-4000-8000-000000000002'::uuid,
    '00000000-0000-4000-8000-000000000003'::uuid,
    '00000000-0000-4000-8000-000000000004'::uuid,
    '00000000-0000-4000-8000-000000000005'::uuid,
    '00000000-0000-4000-8000-000000000006'::uuid
  );
$$;

grant execute on function public.demo_seed_count() to anon, authenticated;

-- =============================================================================
-- End of migration 010
-- =============================================================================
