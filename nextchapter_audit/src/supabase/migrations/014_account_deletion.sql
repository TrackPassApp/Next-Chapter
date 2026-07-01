-- =============================================================================
-- 014 — Real soft-delete account pipeline (B10)
-- =============================================================================
-- Adds one user-callable RPC and hardens message insertion so a soft-deleted
-- account cannot send new messages. Existing rows (profiles, messages,
-- reports, moderation_log) are preserved so admins retain full history.
--
-- Retention: `profiles.deleted_at` is set when the RPC runs. This migration
-- adds the column if it is missing (older installs never had it). A future
-- hard-delete cron / RPC can scan for rows where
-- `deleted_at < now() - interval '30 days'` and permanently purge. Not built
-- here per user instruction.
--
-- Idempotent — safe to re-run.
-- =============================================================================


-- ── 1. Ensure required columns exist on public.profiles ──────────────────
-- Older installs never had `deleted_at` added to `profiles` (the column
-- with that name lives on `public.messages`). Add anything that might be
-- missing before we try to use it. All are additive + idempotent.
alter table public.profiles
  add column if not exists is_deleted   boolean     not null default false,
  add column if not exists is_suspended boolean     not null default false,
  add column if not exists deleted_at   timestamptz;

-- Ensure the deleted_at column has an index for the future 30-day cron.
create index if not exists profiles_deleted_at_idx
  on public.profiles (deleted_at)
  where is_deleted = true;


-- ── 2. RPC: request_account_deletion — the user's Delete Account button ─
--
-- Behaviour (immediate, single transaction):
--   • Marks the caller's profile as deleted (is_deleted=true, deleted_at=now).
--   • Redacts PII on the profile row: first_name → 'Deleted User',
--     about_me → NULL, city/state cleared, gender/relationship_status/date_of_birth
--     retained (needed for demographic metrics; not personally identifying).
--   • Removes photo rows (profile_photos) so their public URLs stop resolving
--     in any cached list. The storage bucket blobs remain until the hard-delete
--     cron cleans them; we can add that in a follow-up migration if you want.
--   • Purges the caller's own profile_prompts / profile_interests /
--     profile_looking_for / profile_life_situation rows (privacy).
--   • KEEPS: messages, conversation memberships, reports (both filed by and
--     against), moderation_log entries. All remain visible to admins/moderators
--     via existing RLS.
--   • Writes a moderation_log entry with action='self_delete' and reason.
--
-- Signature: request_account_deletion(reason text default null) → jsonb
create or replace function public.request_account_deletion(
  reason text default null
) returns jsonb
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  caller uuid := auth.uid();
  my_profile_id uuid;
begin
  if caller is null then
    raise exception 'Not authenticated.';
  end if;

  select id into my_profile_id from public.profiles where user_id = caller;
  if my_profile_id is null then
    raise exception 'No profile to delete.';
  end if;

  -- Redact PII + flip flags. Note we set is_complete=false so the row can
  -- never re-appear in Browse regardless of the profiles_select policy.
  update public.profiles
     set is_deleted   = true,
         deleted_at   = now(),
         is_complete  = false,
         first_name   = 'Deleted User',
         about_me     = null,
         city         = '',
         state        = ''
   where id = my_profile_id;

  -- Purge PII-bearing child rows so nothing leaks via a cached client.
  delete from public.profile_photos          where profile_id = my_profile_id;
  delete from public.profile_prompts         where profile_id = my_profile_id;
  delete from public.profile_interests       where profile_id = my_profile_id;
  delete from public.profile_looking_for     where profile_id = my_profile_id;
  delete from public.profile_life_situation  where profile_id = my_profile_id;

  -- Audit trail — admin-visible. actor and target are both the caller.
  insert into public.moderation_log
    (actor_id, target_user_id, target_kind, action, reason, metadata)
  values
    (caller, caller, 'user', 'self_delete', reason,
     jsonb_build_object('profile_id', my_profile_id, 'at', now()));

  return jsonb_build_object(
    'deleted',    true,
    'profile_id', my_profile_id,
    'deleted_at', now(),
    'hard_delete_after',
      -- Advisory only — no cron built yet. Client uses this in the copy.
      (now() + interval '30 days')
  );
end;
$$;

grant execute on function public.request_account_deletion(text) to authenticated;


-- ── 3. Admin/moderator bypass: read profiles regardless of flags ─────────
-- The existing profiles SELECT policy from 010 hides is_suspended/is_deleted
-- rows from everyone. That is correct for regular users, but it breaks the
-- admin dashboard: after this migration a self-deleted user must still be
-- visible in AdminUsersTab so mods can inspect message history and reports.
-- Multiple SELECT policies OR together, so this adds an admin fast path
-- without touching the regular-user policy.
drop policy if exists "profiles_select_admins" on public.profiles;
create policy "profiles_select_admins"
  on public.profiles for select to authenticated
  using (public.is_moderator_or_above());


-- ── 4. Harden msg_insert_participants — deleted senders cannot post ──────
-- Replaces the pre-existing policy from 002 (unchanged apart from adding the
-- `is_deleted = false` predicate on the sender profile lookup). Recipients
-- who have been soft-deleted can still be read by their historical partners
-- (existing rows are preserved) but no new messages can be sent from a
-- deleted account.

drop policy if exists "msg_insert_participants" on public.messages;
create policy "msg_insert_participants"
  on public.messages for insert to authenticated
  with check (
    public.is_conversation_participant(conversation_id)
    and sender_id in (
      select id from public.profiles
       where user_id = auth.uid()
         and coalesce(is_deleted, false) = false
    )
  );

-- =============================================================================
-- Verification after running:
--   -- 1. Confirm the RPC exists and is grant-executable:
--   select proname, prosecdef from pg_proc
--    where proname = 'request_account_deletion';
--
--   -- 2. Confirm the deleted-sender guard:
--   select polname, pg_get_expr(polqual, polrelid) as using_expr,
--          pg_get_expr(polwithcheck, polrelid) as with_check_expr
--     from pg_policy
--    where polname = 'msg_insert_participants';
-- =============================================================================
