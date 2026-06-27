-- ============================================================================
-- Batch B6 — Block & Report enforcement
-- ============================================================================
-- Adds:
--
--   1. public.user_blocks (blocker_id, blocked_id)
--      A user can block any other user. Both directions matter for hiding
--      conversations and browse results.
--
--   2. RLS on user_blocks
--      - Users SELECT/INSERT/DELETE only their OWN blocks (blocker_id = me).
--      - Admins can SELECT all (for moderation visibility).
--
--   3. is_conversation_participant(c_id)  —  REPLACED
--      Now also returns FALSE whenever the caller has blocked, or is blocked
--      by, any other participant in that conversation. Result: blocked DMs
--      disappear from both inboxes and `/messages/:id` 404s — but the rows
--      stay intact in public.messages so admins (service role) still see
--      the full history.
--
--   4. block_user(profile_id), unblock_user(profile_id)
--      Convenience RPCs so the client doesn't have to fetch my_profile_id
--      separately.
--
--   5. report_user(reported_profile_id, reason, details)
--      RPC that inserts into public.reports with the caller's profile id
--      as reporter. Saves the client a round-trip.
--
-- Run this in Supabase SQL editor once.
-- ============================================================================

-- ── 1. user_blocks table ────────────────────────────────────────────────────
create table if not exists public.user_blocks (
  blocker_id  uuid not null references public.profiles(id) on delete cascade,
  blocked_id  uuid not null references public.profiles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint user_blocks_not_self check (blocker_id <> blocked_id)
);

create index if not exists user_blocks_blocked_idx on public.user_blocks (blocked_id);

alter table public.user_blocks enable row level security;

-- Users see, add, and remove only their own blocks.
drop policy if exists "blocks_self_select" on public.user_blocks;
create policy "blocks_self_select"
  on public.user_blocks for select to authenticated
  using (blocker_id = public.my_profile_id());

drop policy if exists "blocks_self_insert" on public.user_blocks;
create policy "blocks_self_insert"
  on public.user_blocks for insert to authenticated
  with check (blocker_id = public.my_profile_id());

drop policy if exists "blocks_self_delete" on public.user_blocks;
create policy "blocks_self_delete"
  on public.user_blocks for delete to authenticated
  using (blocker_id = public.my_profile_id());

-- Admins can read all blocks (for moderation context).
drop policy if exists "blocks_admin_select" on public.user_blocks;
create policy "blocks_admin_select"
  on public.user_blocks for select to authenticated
  using (
    coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')
      in ('admin','super_admin','moderator')
  );

-- ── 2. is_conversation_participant — replaced to honour blocks ──────────────
create or replace function public.is_conversation_participant(c_id uuid)
  returns boolean
  language sql stable security definer set search_path = public
as $$
  with me as (
    select id from public.profiles where user_id = auth.uid() limit 1
  )
  select exists(
            select 1
              from public.conversation_participants cp
             where cp.conversation_id = c_id
               and cp.profile_id      = (select id from me)
         )
     and not exists(
            -- Any block in either direction between me and any OTHER
            -- participant hides this conversation from me.
            select 1
              from public.conversation_participants cp_other
              join public.user_blocks ub
                on  (ub.blocker_id = (select id from me) and ub.blocked_id = cp_other.profile_id)
                 or (ub.blocked_id = (select id from me) and ub.blocker_id = cp_other.profile_id)
             where cp_other.conversation_id = c_id
               and cp_other.profile_id     <> (select id from me)
         );
$$;

-- ── 3. block_user / unblock_user RPCs ───────────────────────────────────────
create or replace function public.block_user(target_profile_id uuid)
  returns void
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  me uuid;
begin
  me := public.my_profile_id();
  if me is null then raise exception 'Not authenticated'; end if;
  if me = target_profile_id then raise exception 'Cannot block yourself'; end if;

  insert into public.user_blocks (blocker_id, blocked_id)
    values (me, target_profile_id)
    on conflict do nothing;
end;
$$;
grant execute on function public.block_user(uuid) to authenticated;

create or replace function public.unblock_user(target_profile_id uuid)
  returns void
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  me uuid;
begin
  me := public.my_profile_id();
  if me is null then return; end if;
  delete from public.user_blocks where blocker_id = me and blocked_id = target_profile_id;
end;
$$;
grant execute on function public.unblock_user(uuid) to authenticated;

-- ── 4. report_user RPC ──────────────────────────────────────────────────────
create or replace function public.report_user(
  reported_profile_id uuid,
  reason              text,
  details             text default ''
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
  if me = reported_profile_id then raise exception 'Cannot report yourself'; end if;
  if coalesce(reason, '') = '' then raise exception 'Reason is required'; end if;

  insert into public.reports (reporter_id, reported_user_id, reason, details, status)
    values (me, reported_profile_id, reason, coalesce(details, ''), 'pending')
    returning id into new_id;

  return new_id;
end;
$$;
grant execute on function public.report_user(uuid, text, text) to authenticated;

-- ── 5. Realtime publication for blocks (so client can react instantly) ─────
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'user_blocks'
  ) then
    execute 'alter publication supabase_realtime add table public.user_blocks';
  end if;
end $$;

-- ── 6. Harden find_or_create_dm: refuse blocked targets ────────────────────
-- A user cannot start a new conversation with someone they've blocked or
-- who has blocked them. Existing conversations are already hidden by the
-- updated is_conversation_participant policy.
create or replace function public.find_or_create_dm(
  other_profile_id uuid,
  conv_mode        text default 'date'
) returns uuid
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  me uuid;
  existing_conv uuid;
  new_conv uuid;
begin
  me := public.my_profile_id();

  if me is null then
    raise exception 'Not authenticated';
  end if;

  if other_profile_id = me then
    raise exception 'Cannot start a conversation with yourself';
  end if;

  -- Block check (either direction).
  if exists (
    select 1 from public.user_blocks
     where (blocker_id = me and blocked_id = other_profile_id)
        or (blocker_id = other_profile_id and blocked_id = me)
  ) then
    raise exception 'Cannot start a conversation with a blocked user';
  end if;

  -- Look for an existing 1-1 conversation containing exactly me + other.
  select c.id into existing_conv
  from public.conversations c
  where exists (
          select 1 from public.conversation_participants cp1
          where cp1.conversation_id = c.id and cp1.profile_id = me
        )
    and exists (
          select 1 from public.conversation_participants cp2
          where cp2.conversation_id = c.id and cp2.profile_id = other_profile_id
        )
    and (
          select count(*) from public.conversation_participants cpx
          where cpx.conversation_id = c.id
        ) = 2
  limit 1;

  if existing_conv is not null then
    return existing_conv;
  end if;

  insert into public.conversations (created_by, mode, is_request)
    values (me, coalesce(conv_mode, 'date'), false)
    returning id into new_conv;

  insert into public.conversation_participants (conversation_id, profile_id)
    values (new_conv, me), (new_conv, other_profile_id);

  return new_conv;
end;
$$;
