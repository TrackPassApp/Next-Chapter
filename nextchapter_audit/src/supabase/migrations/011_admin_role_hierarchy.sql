-- =============================================================================
-- 011 — Admin role hierarchy + moderator role management
-- =============================================================================
-- Splits the previously flat "admin" pass into three server-approved tiers:
--
--   super_admin  — full rights, only super_admins can grant/revoke roles
--   admin        — moderation + verification + suspend/delete users
--   moderator    — read-only + report triage + verification review; NO ability
--                  to suspend/delete users and NO ability to change roles
--
-- Every existing admin RPC re-checks the role tier server-side. Nothing here
-- relies on the client asserting who it is. app_metadata.role is the source
-- of truth; the admin_users table is a mirror + audit trail.
--
-- Safe to run multiple times; every function is CREATE OR REPLACE and every
-- policy uses DROP IF EXISTS.
-- =============================================================================


-- ── Helpers ──────────────────────────────────────────────────────────────────

create or replace function public.jwt_role()
  returns text
  language sql
  stable
as $$
  select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '');
$$;

create or replace function public.is_moderator_or_above()
  returns boolean
  language sql
  stable
as $$
  select public.jwt_role() in ('moderator', 'admin', 'super_admin');
$$;

create or replace function public.is_admin_or_above()
  returns boolean
  language sql
  stable
as $$
  select public.jwt_role() in ('admin', 'super_admin');
$$;

create or replace function public.is_super_admin()
  returns boolean
  language sql
  stable
as $$
  select public.jwt_role() = 'super_admin';
$$;

grant execute on function public.jwt_role()             to authenticated;
grant execute on function public.is_moderator_or_above() to authenticated;
grant execute on function public.is_admin_or_above()     to authenticated;
grant execute on function public.is_super_admin()        to authenticated;

-- Redefine the old is_admin() to preserve the previous permissive behaviour
-- (any role) for backwards compat with 005's RPC guards — we then upgrade the
-- specific guards below so writes are properly tier-gated.
create or replace function public.is_admin()
  returns boolean
  language sql
  stable
as $$
  select public.is_moderator_or_above();
$$;


-- ── Tier gates on existing RPCs ─────────────────────────────────────────────
-- Moderators can VIEW everything (already true since RLS reads use is_admin()).
-- They can also RESOLVE / DISMISS reports and edit verification. They CANNOT
-- suspend / delete users. Those two RPCs now require admin_or_above.

create or replace function public.admin_suspend_user(
  target_profile_id uuid,
  reason            text default null
) returns void
  language plpgsql security definer set search_path = public
as $$
declare target_user uuid;
begin
  if not public.is_admin_or_above() then
    raise exception 'Admins only: moderators cannot suspend users.';
  end if;
  update public.profiles set is_suspended = true where id = target_profile_id
    returning user_id into target_user;
  if target_user is null then raise exception 'Profile not found'; end if;
  perform public.admin_log(target_user, 'user', 'suspend', reason,
    jsonb_build_object('profile_id', target_profile_id));
end;
$$;

create or replace function public.admin_unsuspend_user(
  target_profile_id uuid,
  reason            text default null
) returns void
  language plpgsql security definer set search_path = public
as $$
declare target_user uuid;
begin
  if not public.is_admin_or_above() then
    raise exception 'Admins only: moderators cannot unsuspend users.';
  end if;
  update public.profiles set is_suspended = false where id = target_profile_id
    returning user_id into target_user;
  if target_user is null then raise exception 'Profile not found'; end if;
  perform public.admin_log(target_user, 'user', 'unsuspend', reason,
    jsonb_build_object('profile_id', target_profile_id));
end;
$$;

create or replace function public.admin_soft_delete_user(
  target_profile_id uuid,
  reason            text default null
) returns void
  language plpgsql security definer set search_path = public
as $$
declare target_user uuid;
begin
  if not public.is_admin_or_above() then
    raise exception 'Admins only: moderators cannot delete users.';
  end if;
  update public.profiles set is_deleted = true where id = target_profile_id
    returning user_id into target_user;
  if target_user is null then raise exception 'Profile not found'; end if;
  perform public.admin_log(target_user, 'user', 'soft_delete', reason,
    jsonb_build_object('profile_id', target_profile_id));
end;
$$;

create or replace function public.admin_restore_user(
  target_profile_id uuid,
  reason            text default null
) returns void
  language plpgsql security definer set search_path = public
as $$
declare target_user uuid;
begin
  if not public.is_admin_or_above() then
    raise exception 'Admins only: moderators cannot restore users.';
  end if;
  update public.profiles set is_deleted = false where id = target_profile_id
    returning user_id into target_user;
  if target_user is null then raise exception 'Profile not found'; end if;
  perform public.admin_log(target_user, 'user', 'restore', reason,
    jsonb_build_object('profile_id', target_profile_id));
end;
$$;


-- ── Role management (super_admin only) ──────────────────────────────────────

create or replace function public.admin_list_admins()
  returns table (
    user_id    uuid,
    role       text,
    granted_at timestamptz,
    granted_by uuid,
    notes      text,
    email      text
  )
  language sql
  stable
  security definer
  set search_path = public
as $$
  -- Any tier can see the list; only super_admin can grant/revoke via the
  -- other RPCs below.
  select a.user_id, a.role, a.granted_at, a.granted_by, a.notes, u.email
    from public.admin_users a
    join auth.users u on u.id = a.user_id
   where public.is_moderator_or_above()
   order by a.granted_at desc;
$$;

grant execute on function public.admin_list_admins() to authenticated;

-- Grant a role. `new_role` must be one of 'moderator' | 'admin' | 'super_admin'.
-- Only super_admins can call this. Records the change in admin_users AND
-- updates auth.users.raw_app_meta_data so the caller's next JWT reflects it.
create or replace function public.admin_grant_role(
  target_user_id uuid,
  new_role       text,
  reason         text default null
) returns void
  language plpgsql
  security definer
  set search_path = public
as $$
begin
  if not public.is_super_admin() then
    raise exception 'Super-admin only.';
  end if;
  if new_role not in ('moderator', 'admin', 'super_admin') then
    raise exception 'Invalid role: %', new_role;
  end if;

  -- Upsert admin_users mirror row.
  insert into public.admin_users (user_id, role, granted_by, notes)
  values (target_user_id, new_role, auth.uid(), reason)
  on conflict (user_id) do update
    set role       = excluded.role,
        granted_by = excluded.granted_by,
        granted_at = now(),
        notes      = excluded.notes;

  -- Update the JWT source of truth so the next sign-in / token refresh
  -- carries the new role.
  update auth.users
     set raw_app_meta_data =
           coalesce(raw_app_meta_data, '{}'::jsonb) || jsonb_build_object('role', new_role)
   where id = target_user_id;

  perform public.admin_log(target_user_id, 'admin', 'grant_role', reason,
    jsonb_build_object('role', new_role));
end;
$$;

grant execute on function public.admin_grant_role(uuid, text, text) to authenticated;

-- Revoke all roles from a target user. Only super_admins can call this.
create or replace function public.admin_revoke_role(
  target_user_id uuid,
  reason         text default null
) returns void
  language plpgsql
  security definer
  set search_path = public
as $$
begin
  if not public.is_super_admin() then
    raise exception 'Super-admin only.';
  end if;
  -- Cannot revoke your own super_admin — safety net.
  if target_user_id = auth.uid() then
    raise exception 'You cannot revoke your own super_admin role.';
  end if;

  delete from public.admin_users where user_id = target_user_id;

  update auth.users
     set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) - 'role'
   where id = target_user_id;

  perform public.admin_log(target_user_id, 'admin', 'revoke_role', reason, '{}'::jsonb);
end;
$$;

grant execute on function public.admin_revoke_role(uuid, text) to authenticated;


-- ── Convenience: current-caller role bundle ─────────────────────────────────
-- Used by the Flutter side to render or hide UI without waiting for a JWT
-- decode round-trip.
create or replace function public.admin_my_role()
  returns table (
    role                text,
    can_moderate        boolean,
    can_admin           boolean,
    is_super_admin      boolean
  )
  language sql
  stable
  security definer
  set search_path = public
as $$
  select
    public.jwt_role()               as role,
    public.is_moderator_or_above()  as can_moderate,
    public.is_admin_or_above()      as can_admin,
    public.is_super_admin()         as is_super_admin;
$$;

grant execute on function public.admin_my_role() to authenticated;


-- ── admin_users SELECT policy — extend to all tiers (was admin+super only) ──
drop policy if exists "admin_users_select_admins_only" on public.admin_users;
create policy "admin_users_select_admins_only"
  on public.admin_users
  for select
  to authenticated
  using (public.is_moderator_or_above());

-- =============================================================================
-- End of migration 011
-- =============================================================================
