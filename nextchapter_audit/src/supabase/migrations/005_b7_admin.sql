-- ============================================================================
-- Batch B7 — Admin Dashboard (real Supabase admin)
-- ============================================================================
-- All writes go through SECURITY DEFINER RPCs that:
--   1. Re-check the caller is an admin (defence-in-depth alongside RLS).
--   2. Perform the table mutation.
--   3. Append a row to public.moderation_log so we have a full audit trail.
--
-- Reads stay as plain queries against the underlying tables — the existing
-- admin SELECT policies (from migrations 002 / 004) already allow it.
--
-- Run this in Supabase SQL editor once.
-- ============================================================================

-- ── 0. Helpers ──────────────────────────────────────────────────────────────
create or replace function public.is_admin()
  returns boolean
  language sql stable security definer set search_path = public
as $$
  select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')
           in ('admin','super_admin','moderator');
$$;
grant execute on function public.is_admin() to authenticated;

-- ── 1. Append to moderation_log from authenticated admins ──────────────────
-- The log table has no INSERT policy (service role only). We still want
-- authenticated admins to append entries through this RPC.
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
  if not public.is_admin() then raise exception 'Admin only'; end if;
  insert into public.moderation_log
    (actor_id, target_user_id, target_kind, action, reason, metadata)
  values (auth.uid(), p_target_user_id, p_target_kind, p_action, p_reason, p_metadata);
end;
$$;
grant execute on function public.admin_log(uuid, text, text, text, jsonb) to authenticated;

-- ── 2. Suspend / unsuspend / soft-delete / restore ─────────────────────────
create or replace function public.admin_suspend_user(
  target_profile_id uuid,
  reason            text default null
) returns void
  language plpgsql
  security definer
  set search_path = public
as $$
declare target_user uuid;
begin
  if not public.is_admin() then raise exception 'Admin only'; end if;
  update public.profiles set is_suspended = true where id = target_profile_id
    returning user_id into target_user;
  if target_user is null then raise exception 'Profile not found'; end if;
  perform public.admin_log(target_user, 'user', 'suspend', reason, jsonb_build_object('profile_id', target_profile_id));
end;
$$;
grant execute on function public.admin_suspend_user(uuid, text) to authenticated;

create or replace function public.admin_unsuspend_user(
  target_profile_id uuid,
  reason            text default null
) returns void
  language plpgsql
  security definer
  set search_path = public
as $$
declare target_user uuid;
begin
  if not public.is_admin() then raise exception 'Admin only'; end if;
  update public.profiles set is_suspended = false where id = target_profile_id
    returning user_id into target_user;
  if target_user is null then raise exception 'Profile not found'; end if;
  perform public.admin_log(target_user, 'user', 'unsuspend', reason, jsonb_build_object('profile_id', target_profile_id));
end;
$$;
grant execute on function public.admin_unsuspend_user(uuid, text) to authenticated;

create or replace function public.admin_soft_delete_user(
  target_profile_id uuid,
  reason            text default null
) returns void
  language plpgsql
  security definer
  set search_path = public
as $$
declare target_user uuid;
begin
  if not public.is_admin() then raise exception 'Admin only'; end if;
  update public.profiles set is_deleted = true where id = target_profile_id
    returning user_id into target_user;
  if target_user is null then raise exception 'Profile not found'; end if;
  perform public.admin_log(target_user, 'user', 'soft_delete', reason, jsonb_build_object('profile_id', target_profile_id));
end;
$$;
grant execute on function public.admin_soft_delete_user(uuid, text) to authenticated;

create or replace function public.admin_restore_user(
  target_profile_id uuid,
  reason            text default null
) returns void
  language plpgsql
  security definer
  set search_path = public
as $$
declare target_user uuid;
begin
  if not public.is_admin() then raise exception 'Admin only'; end if;
  update public.profiles set is_deleted = false where id = target_profile_id
    returning user_id into target_user;
  if target_user is null then raise exception 'Profile not found'; end if;
  perform public.admin_log(target_user, 'user', 'restore', reason, jsonb_build_object('profile_id', target_profile_id));
end;
$$;
grant execute on function public.admin_restore_user(uuid, text) to authenticated;

-- ── 3. Verification — admin set / clear individual flags ───────────────────
-- kind ∈ ('email','phone','selfie','id')
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
  if not public.is_admin() then raise exception 'Admin only'; end if;
  if kind not in ('email','phone','selfie','id') then
    raise exception 'Invalid verification kind: %', kind;
  end if;

  col_name    := kind || '_verified';
  ts_col_name := kind || '_verified_at';

  -- Ensure row exists.
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

-- ── 4. Reports — resolve / dismiss ──────────────────────────────────────────
create or replace function public.admin_resolve_report(
  report_id    uuid,
  action_taken text,
  notes        text default null
) returns void
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  rep record;
begin
  if not public.is_admin() then raise exception 'Admin only'; end if;

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

create or replace function public.admin_dismiss_report(
  report_id uuid,
  notes     text default null
) returns void
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  rep record;
begin
  if not public.is_admin() then raise exception 'Admin only'; end if;

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

-- Allow admins to write report severity / admin_notes via the existing
-- admin_update policy (already in 002). Add admin_notes column if missing.
alter table public.reports
  add column if not exists admin_notes text;

-- ── 5. Dashboard metrics ───────────────────────────────────────────────────
create or replace function public.admin_dashboard_metrics()
  returns jsonb
  language plpgsql
  security definer
  set search_path = public
as $$
declare result jsonb;
begin
  if not public.is_admin() then raise exception 'Admin only'; end if;

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

-- ── 6. User detail bundle (single round-trip for the admin user dialog) ───
create or replace function public.admin_user_summary(target_profile_id uuid)
  returns jsonb
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  result jsonb;
begin
  if not public.is_admin() then raise exception 'Admin only'; end if;

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
