-- =============================================================================
-- 012 — Resolve `is_admin()` ambiguity WITHOUT dropping any function
-- =============================================================================
-- BACKGROUND
-- ----------
-- Two overloads of public.is_admin exist:
--
--   001_admin_role.sql:68 → public.is_admin(uid uuid default auth.uid())
--                              ▲ 1-arg with default — matches a zero-arg call
--   005_b7_admin.sql:16   → public.is_admin()          ▲ 0-arg
--   011_admin_role_hierarchy.sql:62 → recreates the 0-arg version
--
-- The 1-arg overload is REFERENCED BY RLS/STORAGE POLICIES:
--   • vreq_admin_select        (on verification_requests)
--   • vreq_admin_update        (on verification_requests)
--   • verif_docs_select_admin  (on storage.objects)
-- Dropping it (even with `drop function if exists public.is_admin(uuid)`)
-- fails with "cannot drop function is_admin(uuid) because policies depend
-- on it". Using CASCADE would delete those policies — unacceptable.
--
-- Dropping the 0-arg overload is also awkward because migration 011 will
-- happily recreate it on the next replay.
--
-- SAFE STRATEGY (this file)
-- -------------------------
-- Do NOT drop either function. Rewrite every RPC that currently calls the
-- ambiguous bare `is_admin()` so it calls the **uniquely-named** helper
-- `public.is_moderator_or_above()` from 011. Because that name is not
-- overloaded, Postgres cannot get confused and 42725 goes away.
--
-- Nothing is destroyed:
--   ✓ is_admin(uuid) stays in place — vreq_* and verif_docs_* policies
--     continue to work exactly as before.
--   ✓ is_admin() (0-arg) stays in place — harmless leftover, no caller
--     references it after this migration runs.
--   ✓ admin_users rows untouched.
--   ✓ raw_app_meta_data role assignments untouched.
--   ✓ moderation_log untouched.
--
-- This migration is idempotent: every function uses `create or replace`.
-- Safe to run multiple times.
-- =============================================================================


-- ── 0. Ensure the unique helper from 011 exists (idempotent guard) ─────────
-- If a user landed here on a database that never ran 011, we still want the
-- rewrites below to compile. This block is a no-op when 011 has already run.
create or replace function public.is_moderator_or_above()
  returns boolean
  language sql
  stable
as $$
  select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')
           in ('moderator', 'admin', 'super_admin');
$$;

create or replace function public.is_admin_or_above()
  returns boolean
  language sql
  stable
as $$
  select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')
           in ('admin', 'super_admin');
$$;

grant execute on function public.is_moderator_or_above() to authenticated;
grant execute on function public.is_admin_or_above()     to authenticated;


-- ── 1. Rewrite the six RPCs that still call bare `is_admin()` ─────────────
-- Each is a CREATE OR REPLACE with the identical signature that migration
-- 005 originally created, only the internal guard changed:
--     if not public.is_admin() → if not public.is_moderator_or_above()
-- (Semantically identical — is_admin() delegated to the same three roles.)

-- 1a. admin_log — moderator+ can append to moderation_log.
create or replace function public.admin_log(
  p_target_user_id uuid,
  p_target_kind    text,
  p_action         text,
  p_reason         text default null,
  p_metadata       jsonb default '{}'::jsonb
) returns void
  language plpgsql
  security definer
  set search_path = public
as $$
begin
  if not public.is_moderator_or_above() then
    raise exception 'Admin only';
  end if;
  insert into public.moderation_log
    (actor_id, target_user_id, target_kind, action, reason, metadata)
  values (auth.uid(), p_target_user_id, p_target_kind, p_action, p_reason, p_metadata);
end;
$$;
grant execute on function public.admin_log(uuid, text, text, text, jsonb) to authenticated;


-- 1b. admin_dashboard_metrics — the one the Overview tab calls, so this
--     is the RPC whose 42725 the user actually sees.
create or replace function public.admin_dashboard_metrics()
  returns jsonb
  language plpgsql
  security definer
  set search_path = public
as $$
declare result jsonb;
begin
  if not public.is_moderator_or_above() then
    raise exception 'Admin only';
  end if;

  select jsonb_build_object(
    'total_users',          (select count(*) from public.profiles where is_deleted = false),
    'active_users',         (select count(*) from public.profiles
                              where is_deleted = false
                                and last_active > now() - interval '7 days'),
    'verified_users',       (select count(*) from public.verification_status
                              where email_verified or phone_verified
                                 or selfie_verified or id_verified),
    'pending_reports',      (select count(*) from public.reports where status = 'pending'),
    'suspended_users',      (select count(*) from public.profiles where is_suspended = true),
    'deleted_users',        (select count(*) from public.profiles where is_deleted = true),
    'new_users_today',      (select count(*) from public.profiles
                              where created_at >= date_trunc('day', now())),
    'messages_sent_today',  (select count(*) from public.messages
                              where created_at >= date_trunc('day', now())
                                and deleted_at is null)
  ) into result;

  return result;
end;
$$;
grant execute on function public.admin_dashboard_metrics() to authenticated;


-- 1c. admin_user_summary — user detail bundle for the admin dialog.
create or replace function public.admin_user_summary(target_profile_id uuid)
  returns jsonb
  language plpgsql
  security definer
  set search_path = public
as $$
declare result jsonb;
begin
  if not public.is_moderator_or_above() then
    raise exception 'Admin only';
  end if;

  select jsonb_build_object(
    'profile',            (select to_jsonb(p) from public.profiles p where p.id = target_profile_id),
    'verification',       (select to_jsonb(v) from public.verification_status v where v.profile_id = target_profile_id),
    'reports_against',    coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc)
                                      from public.reports r
                                     where r.reported_user_id = target_profile_id), '[]'::jsonb),
    'reports_filed',      coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc)
                                      from public.reports r
                                     where r.reporter_id = target_profile_id), '[]'::jsonb),
    'i_have_blocked',     coalesce((select jsonb_agg(blocked_id) from public.user_blocks
                                     where blocker_id = target_profile_id), '[]'::jsonb),
    'blocked_me',         coalesce((select jsonb_agg(blocker_id) from public.user_blocks
                                     where blocked_id = target_profile_id), '[]'::jsonb),
    'photo_count',        (select count(*) from public.profile_photos where profile_id = target_profile_id)
  ) into result;

  return result;
end;
$$;
grant execute on function public.admin_user_summary(uuid) to authenticated;


-- 1d. admin_resolve_report — moderator+ can resolve a report.
--     Body identical to 005; only the guard changed.
create or replace function public.admin_resolve_report(
  report_id    uuid,
  action_taken text,
  notes        text default null
) returns void
  language plpgsql
  security definer
  set search_path = public
as $$
declare rep record;
begin
  if not public.is_moderator_or_above() then
    raise exception 'Admin only';
  end if;

  update public.reports
     set status        = 'resolved',
         resolved_at   = now(),
         resolved_by   = auth.uid(),
         action_taken  = admin_resolve_report.action_taken
   where id = report_id
   returning reported_user_id into rep;

  if rep.reported_user_id is null then raise exception 'Report not found'; end if;

  perform public.admin_log(
    (select user_id from public.profiles where id = rep.reported_user_id),
    'report', 'resolve', notes,
    jsonb_build_object('report_id', report_id, 'action_taken', action_taken)
  );
end;
$$;
grant execute on function public.admin_resolve_report(uuid, text, text) to authenticated;


-- 1e. admin_dismiss_report — moderator+ can dismiss a report.
--     Body identical to 005; only the guard changed.
create or replace function public.admin_dismiss_report(
  report_id uuid,
  notes     text default null
) returns void
  language plpgsql
  security definer
  set search_path = public
as $$
declare rep record;
begin
  if not public.is_moderator_or_above() then
    raise exception 'Admin only';
  end if;

  update public.reports
     set status        = 'dismissed',
         resolved_at   = now(),
         resolved_by   = auth.uid(),
         action_taken  = 'dismissed'
   where id = report_id
   returning reported_user_id into rep;

  if rep.reported_user_id is null then raise exception 'Report not found'; end if;

  perform public.admin_log(
    (select user_id from public.profiles where id = rep.reported_user_id),
    'report', 'dismiss', notes,
    jsonb_build_object('report_id', report_id)
  );
end;
$$;
grant execute on function public.admin_dismiss_report(uuid, text) to authenticated;


-- 1f. admin_set_verification — moderator+ can flip a verification flag.
--     Body identical to 005 (upsert + timestamp column); only guard changed.
create or replace function public.admin_set_verification(
  target_profile_id uuid,
  kind              text,
  value             boolean,
  notes             text default null
) returns void
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  target_user uuid;
  col_name    text;
  ts_col_name text;
begin
  if not public.is_moderator_or_above() then
    raise exception 'Admin only';
  end if;
  if kind not in ('email','phone','selfie','id') then
    raise exception 'Invalid verification kind: %', kind;
  end if;

  col_name    := kind || '_verified';
  ts_col_name := kind || '_verified_at';

  insert into public.verification_status (profile_id)
    values (target_profile_id)
    on conflict (profile_id) do nothing;

  execute format(
    'update public.verification_status
        set %I = $1,
            %I = case when $1 then now() else null end
      where profile_id = $2',
    col_name, ts_col_name
  ) using value, target_profile_id;

  select user_id into target_user from public.profiles where id = target_profile_id;
  perform public.admin_log(
    target_user, 'user',
    case when value then 'verify_' || kind else 'unverify_' || kind end,
    notes,
    jsonb_build_object('profile_id', target_profile_id, 'kind', kind, 'value', value)
  );
end;
$$;
grant execute on function public.admin_set_verification(uuid, text, boolean, text) to authenticated;


-- =============================================================================
-- End of migration 012 (rewritten).
--
-- Verification after running:
--   -- Overview RPC — no more 42725:
--   select public.admin_dashboard_metrics();
--
-- If you want to belt-and-braces confirm the resolvers used inside each RPC
-- are unambiguous, this returns 0:
--   select count(*)
--     from pg_proc p
--     join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public'
--      and p.proname = 'is_moderator_or_above';   -- always 1 overload
-- =============================================================================
