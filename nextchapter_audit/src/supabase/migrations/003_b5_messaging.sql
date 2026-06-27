-- ============================================================================
-- Batch B5 — Messaging foundation (real Supabase messaging)
-- ============================================================================
-- The conversations / conversation_participants / messages / message_reads
-- tables already exist from migration 002. This migration adds:
--
--   1. find_or_create_dm(other_profile_id, conv_mode)  →  uuid
--      Atomically returns the conversation id for a 1-1 DM between the
--      caller and other_profile_id. Creates the conversation + both
--      participant rows if no DM exists yet.
--
--   2. mark_conversation_read(conv_id)  →  void
--      Bumps conversation_participants.last_read_at to now() for the caller.
--
--   3. update_conversation_last_message_at trigger
--      Keeps conversations.last_message_at in sync with the newest message.
--
--   4. Realtime publication: messages + conversations + participants
--      (so subscribe() works on the client).
--
-- Run this in Supabase SQL editor once.
-- ============================================================================

-- ── 1. Helper: my profile id for the current auth user ──────────────────────
create or replace function public.my_profile_id()
  returns uuid
  language sql stable security definer set search_path = public
as $$
  select id from public.profiles where user_id = auth.uid() limit 1;
$$;

-- ── 2. find_or_create_dm ────────────────────────────────────────────────────
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

  -- Create the new conversation.
  insert into public.conversations (created_by, mode, is_request)
    values (me, coalesce(conv_mode, 'date'), false)
    returning id into new_conv;

  insert into public.conversation_participants (conversation_id, profile_id)
    values (new_conv, me), (new_conv, other_profile_id);

  return new_conv;
end;
$$;

grant execute on function public.find_or_create_dm(uuid, text) to authenticated;

-- ── 3. mark_conversation_read ───────────────────────────────────────────────
create or replace function public.mark_conversation_read(conv_id uuid)
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

  update public.conversation_participants
     set last_read_at = now()
   where conversation_id = conv_id
     and profile_id      = me;
end;
$$;

grant execute on function public.mark_conversation_read(uuid) to authenticated;

-- ── 4. Keep conversations.last_message_at fresh ─────────────────────────────
create or replace function public.touch_conversation_last_message()
  returns trigger
  language plpgsql
as $$
begin
  update public.conversations
     set last_message_at = new.created_at
   where id = new.conversation_id;
  return new;
end;
$$;

drop trigger if exists trg_touch_conversation_last_message on public.messages;
create trigger trg_touch_conversation_last_message
  after insert on public.messages
  for each row execute function public.touch_conversation_last_message();

-- ── 5. Enable Realtime publication ──────────────────────────────────────────
-- (idempotent — alter publication ADD TABLE errors if already added, so use
-- a DO block.)
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'messages'
  ) then
    execute 'alter publication supabase_realtime add table public.messages';
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'conversations'
  ) then
    execute 'alter publication supabase_realtime add table public.conversations';
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'conversation_participants'
  ) then
    execute 'alter publication supabase_realtime add table public.conversation_participants';
  end if;
end $$;
