-- ============================================================================
-- Batch B8 — User-side verification system
-- ============================================================================
-- Adds:
--   1. public.verification_requests — user-submitted verification attempts.
--      Stores kind (phone/selfie/id), status, storage_path for docs,
--      phone_number for phone requests, admin notes.
--      Email is auto-verified via Supabase Auth and NOT stored here.
--
--   2. RLS — users SELECT/INSERT their own; admins SELECT/UPDATE all.
--
--   3. RPCs:
--        submit_verification_request(kind, phone_number?, storage_path?)
--        admin_review_verification_request(request_id, approve, notes?)
--
--   4. Storage bucket "verification-docs" (PRIVATE) with policies:
--        users INSERT/SELECT only their own folder
--        admins SELECT all (via service role for now; per-policy bypass added)
--
--   5. admin_dashboard_metrics now also returns pending_verifications
--      and admin_user_summary now returns verification_requests array.
-- Run this in Supabase SQL editor once.
-- ============================================================================

-- ── 0. Patch: resolve is_admin() overload ambiguity ────────────────────────
-- Migration 001 created public.is_admin(uid uuid default auth.uid()).
-- Migration 005 also created public.is_admin() (no-arg).
-- Both match a zero-arg call, so Postgres raises:
--   "function public.is_admin() is not unique"
-- We drop the no-arg variant. The 1-arg version with default behaves
-- identically when called with no args, so every admin RPC from 005 still
-- works without modification.
drop function if exists public.is_admin();

-- ── 1. Table ────────────────────────────────────────────────────────────────
create table if not exists public.verification_requests (
  id            uuid primary key default gen_random_uuid(),
  profile_id    uuid not null references public.profiles(id) on delete cascade,
  kind          text not null check (kind in ('phone','selfie','id')),
  status        text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  phone_number  text,
  storage_path  text,
  submitted_at  timestamptz not null default now(),
  reviewed_at   timestamptz,
  reviewed_by   uuid references auth.users(id),
  admin_notes   text
);

create index if not exists verification_requests_profile_idx on public.verification_requests (profile_id);
create index if not exists verification_requests_status_idx  on public.verification_requests (status, submitted_at desc);

alter table public.verification_requests enable row level security;

drop policy if exists "vreq_owner_select" on public.verification_requests;
create policy "vreq_owner_select"
  on public.verification_requests for select to authenticated
  using (profile_id = public.my_profile_id());

drop policy if exists "vreq_owner_insert" on public.verification_requests;
create policy "vreq_owner_insert"
  on public.verification_requests for insert to authenticated
  with check (
    profile_id = public.my_profile_id()
    and status = 'pending'
  );

drop policy if exists "vreq_owner_update" on public.verification_requests;
create policy "vreq_owner_update"
  on public.verification_requests for update to authenticated
  using (profile_id = public.my_profile_id() and status = 'pending')
  with check (status in ('pending','cancelled'));

drop policy if exists "vreq_admin_select" on public.verification_requests;
create policy "vreq_admin_select"
  on public.verification_requests for select to authenticated
  using (public.is_admin());

drop policy if exists "vreq_admin_update" on public.verification_requests;
create policy "vreq_admin_update"
  on public.verification_requests for update to authenticated
  using (public.is_admin());

-- ── 2. RPC: submit a new request (replaces older pending of same kind) ────
create or replace function public.submit_verification_request(
  kind         text,
  phone_number text default null,
  storage_path text default null
) returns uuid
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  me uuid;
  new_id uuid;
begin
  me := public.my_profile_id();
  if me is null then raise exception 'Not authenticated'; end if;
  if kind not in ('phone','selfie','id') then
    raise exception 'Invalid verification kind: %', kind;
  end if;
  if kind = 'phone' and coalesce(phone_number, '') = '' then
    raise exception 'Phone number is required for phone verification';
  end if;
  if kind in ('selfie','id') and coalesce(storage_path, '') = '' then
    raise exception 'A document path is required for % verification', kind;
  end if;

  update public.verification_requests
     set status = 'cancelled', reviewed_at = now()
   where profile_id = me and kind = submit_verification_request.kind and status = 'pending';

  insert into public.verification_requests
    (profile_id, kind, status, phone_number, storage_path)
  values
    (me, kind, 'pending', phone_number, storage_path)
  returning id into new_id;

  return new_id;
end;
$$;
grant execute on function public.submit_verification_request(text, text, text) to authenticated;

-- ── 3. RPC: admin review (approves or rejects a request) ──────────────────
create or replace function public.admin_review_verification_request(
  request_id uuid,
  approve    boolean,
  notes      text default null
) returns void
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  req record;
begin
  if not public.is_admin() then raise exception 'Admin only'; end if;

  select * into req from public.verification_requests where id = request_id;
  if req.id is null then raise exception 'Request not found'; end if;

  update public.verification_requests
     set status      = case when approve then 'approved' else 'rejected' end,
         reviewed_at = now(),
         reviewed_by = auth.uid(),
         admin_notes = notes
   where id = request_id;

  if approve then
    perform public.admin_set_verification(req.profile_id, req.kind, true, notes);
  end if;

  perform public.admin_log(
    (select user_id from public.profiles where id = req.profile_id),
    'user',
    case when approve then 'verify_' || req.kind else 'reject_' || req.kind end,
    notes,
    jsonb_build_object('request_id', request_id, 'profile_id', req.profile_id, 'kind', req.kind)
  );
end;
$$;
grant execute on function public.admin_review_verification_request(uuid, boolean, text) to authenticated;

-- ── 4. Storage bucket: verification-docs (PRIVATE) ─────────────────────────
do $$
begin
  if not exists (select 1 from storage.buckets where id = 'verification-docs') then
    insert into storage.buckets (id, name, public) values ('verification-docs', 'verification-docs', false);
  end if;
end$$;

drop policy if exists "verif_docs_insert_own" on storage.objects;
create policy "verif_docs_insert_own"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'verification-docs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "verif_docs_select_own" on storage.objects;
create policy "verif_docs_select_own"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'verification-docs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "verif_docs_select_admin" on storage.objects;
create policy "verif_docs_select_admin"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'verification-docs' and public.is_admin()
  );

drop policy if exists "verif_docs_delete_own" on storage.objects;
create policy "verif_docs_delete_own"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'verification-docs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ── 5. Extended admin_dashboard_metrics ───────────────────────────────────
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
    'total_users',           (select count(*) from public.profiles where is_deleted = false),
    'active_users',          (select count(*) from public.profiles where is_deleted = false and last_active > now() - interval '7 days'),
    'verified_users',        (select count(*) from public.verification_status
                               where email_verified or phone_verified or selfie_verified or id_verified),
    'pending_reports',       (select count(*) from public.reports where status = 'pending'),
    'pending_verifications', (select count(*) from public.verification_requests where status = 'pending'),
    'suspended_users',       (select count(*) from public.profiles where is_suspended = true),
    'deleted_users',         (select count(*) from public.profiles where is_deleted = true),
    'new_users_today',       (select count(*) from public.profiles where created_at >= date_trunc('day', now())),
    'messages_sent_today',   (select count(*) from public.messages
                               where created_at >= date_trunc('day', now()) and deleted_at is null)
  ) into result;

  return result;
end;
$$;

-- ── 6. Extended admin_user_summary (adds verification_requests array) ─────
create or replace function public.admin_user_summary(target_profile_id uuid)
  returns jsonb
  language plpgsql
  security definer
  set search_path = public
as $$
declare result jsonb;
begin
  if not public.is_admin() then raise exception 'Admin only'; end if;

  select jsonb_build_object(
    'profile',         (select to_jsonb(p) from public.profiles p where p.id = target_profile_id),
    'verification',    (select to_jsonb(v) from public.verification_status v where v.profile_id = target_profile_id),
    'verification_requests',
                       coalesce((select jsonb_agg(to_jsonb(r) order by r.submitted_at desc)
                                   from public.verification_requests r
                                  where r.profile_id = target_profile_id), '[]'::jsonb),
    'reports_against', coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc)
                                   from public.reports r
                                  where r.reported_user_id = target_profile_id), '[]'::jsonb),
    'reports_filed',   coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc)
                                   from public.reports r
                                  where r.reporter_id = target_profile_id), '[]'::jsonb),
    'i_have_blocked',  coalesce((select jsonb_agg(blocked_id) from public.user_blocks
                                  where blocker_id = target_profile_id), '[]'::jsonb),
    'blocked_me',      coalesce((select jsonb_agg(blocker_id) from public.user_blocks
                                  where blocked_id = target_profile_id), '[]'::jsonb),
    'photo_count',     (select count(*) from public.profile_photos where profile_id = target_profile_id)
  ) into result;

  return result;
end;
$$;
