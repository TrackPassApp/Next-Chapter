-- =============================================================================
-- 012 — Drop the duplicate 1-arg public.is_admin(uuid) overload
-- =============================================================================
-- ROOT CAUSE
-- ----------
-- Migration 001_admin_role.sql created:
--     public.is_admin(uid uuid default auth.uid())  returns boolean
--
-- Migrations 005_b7_admin.sql and 011_admin_role_hierarchy.sql then created:
--     public.is_admin()                             returns boolean
--
-- Because the 1-arg version has a DEFAULT on its only parameter, a caller
-- writing `is_admin()` matches BOTH overloads. Postgres refuses to pick and
-- raises:
--     42725: function public.is_admin() is not unique
-- which is exactly the failure the Admin Dashboard is throwing on Overview
-- (the metrics RPC internally calls `is_admin()`).
--
-- FIX
-- ----
-- Drop the 1-arg overload from 001. Keep the 0-arg version from 011 as the
-- single authoritative admin check. This preserves every server-approved
-- role (super_admin, admin, moderator) because the 011 version already
-- delegates to `is_moderator_or_above()` — no behavioural change.
--
-- Nothing in our current codebase calls `is_admin(<uuid>)` explicitly, so
-- the drop is safe. We use IF EXISTS so this file is idempotent.
--
-- No admin_users rows are touched. No raw_app_meta_data role is touched.
-- =============================================================================


-- ── 1. Remove the ambiguous 1-arg overload ─────────────────────────────────
drop function if exists public.is_admin(uuid);


-- ── 2. Reassert the single authoritative 0-arg overload ────────────────────
-- Same semantics as migration 011: returns true when the caller's JWT
-- app_metadata.role is one of ('moderator', 'admin', 'super_admin').
-- Kept as `security definer` so it can be called from RLS policies and
-- from other `security definer` RPCs without needing extra grants.
create or replace function public.is_admin()
  returns boolean
  language sql
  stable
  security definer
  set search_path = public
as $$
  select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')
           in ('moderator', 'admin', 'super_admin');
$$;

grant execute on function public.is_admin() to authenticated;

comment on function public.is_admin() is
  'Authoritative admin/moderator check. True for moderator, admin, and '
  'super_admin roles as stored in auth.users.raw_app_meta_data->>''role''. '
  'This is the ONLY overload — the previous is_admin(uuid) from 001 was '
  'dropped in migration 012 because its default-valued argument made '
  'is_admin() ambiguous (42725).';


-- ── 3. Sanity check helper (optional, but useful for you to verify) ────────
-- Returns the number of remaining public.is_admin overloads. After this
-- migration runs cleanly, it must return exactly 1.
create or replace function public.is_admin_overload_count()
  returns int
  language sql
  stable
as $$
  select count(*)::int
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'is_admin';
$$;

grant execute on function public.is_admin_overload_count() to authenticated;

-- =============================================================================
-- End of migration 012. Idempotent — safe to re-run.
-- After running, verify with:
--     select public.is_admin_overload_count();   -- expected: 1
--     select public.is_admin();                  -- expected: true (as an admin)
-- =============================================================================
