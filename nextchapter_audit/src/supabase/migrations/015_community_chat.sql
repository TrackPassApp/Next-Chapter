-- =============================================================================
-- 015 — Community Chat Rooms (B11)
-- =============================================================================
-- Public, real-time chat rooms so members can talk in the open around shared
-- interests. Fights loneliness; free forever; no paywalls; no ads inside the
-- message stream itself.
--
-- Objects created:
--   • chat_rooms                — 15 seeded rooms, slug-keyed, public-read
--   • room_messages             — text messages, real-time, RLS-guarded
--   • RPC report_room_message   — any user can flag a message
--   • RPC admin_delete_room_message — mod+ soft-deletes a message
--   • RPC admin_mute_user       — admin+ mutes a user across all rooms
--   • profiles.muted_until      — new column consulted by the room-post policy
--
-- All additive + idempotent. Safe to re-run.
-- =============================================================================


-- ── 1. Rooms table ───────────────────────────────────────────────────────
create table if not exists public.chat_rooms (
  id           uuid primary key default gen_random_uuid(),
  slug         text not null unique,
  name         text not null,
  description  text,
  category     text not null default 'general',
  sort_order   int  not null default 100,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now()
);

alter table public.chat_rooms enable row level security;

drop policy if exists "chat_rooms_select_all" on public.chat_rooms;
create policy "chat_rooms_select_all"
  on public.chat_rooms for select to authenticated using (is_active = true);


-- ── 2. Messages table ────────────────────────────────────────────────────
create table if not exists public.room_messages (
  id          uuid primary key default gen_random_uuid(),
  room_id     uuid not null references public.chat_rooms(id) on delete cascade,
  sender_id   uuid not null references public.profiles(id),
  body        text not null check (length(body) between 1 and 2000),
  created_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  deleted_by  uuid references public.profiles(id),
  delete_reason text
);

create index if not exists room_messages_room_created_idx
  on public.room_messages (room_id, created_at desc);

create index if not exists room_messages_sender_idx
  on public.room_messages (sender_id);

alter table public.room_messages enable row level security;

-- Anyone signed in can read non-deleted messages (or their own deleted ones).
-- Moderators can read all messages.
drop policy if exists "room_messages_select_public" on public.room_messages;
create policy "room_messages_select_public"
  on public.room_messages for select to authenticated
  using (
    deleted_at is null
    or sender_id in (select id from public.profiles where user_id = auth.uid())
    or public.is_moderator_or_above()
  );


-- ── 3. Muted-user column on profiles ─────────────────────────────────────
alter table public.profiles
  add column if not exists muted_until timestamptz;

-- Extend moderation_log.target_kind to accept 'room_message' (existing check
-- constraint limits it to user/report/message/photo).
do $$
declare cons text;
begin
  select conname into cons
    from pg_constraint
   where conrelid = 'public.moderation_log'::regclass
     and contype = 'c'
     and pg_get_constraintdef(oid) ilike '%target_kind%';
  if cons is not null then
    execute format('alter table public.moderation_log drop constraint %I', cons);
  end if;
  alter table public.moderation_log
    add constraint moderation_log_target_kind_check
    check (target_kind in ('user', 'report', 'message', 'photo', 'room_message', 'conversation'));
end$$;


-- ── 4. Insert policy — only your own row, not deleted, not suspended, not muted
drop policy if exists "room_messages_insert_self" on public.room_messages;
create policy "room_messages_insert_self"
  on public.room_messages for insert to authenticated
  with check (
    sender_id in (
      select id from public.profiles
        where user_id = auth.uid()
          and coalesce(is_deleted,   false) = false
          and coalesce(is_suspended, false) = false
          and (muted_until is null or muted_until < now())
    )
  );

-- Users can soft-delete their own messages.
drop policy if exists "room_messages_delete_own" on public.room_messages;
create policy "room_messages_delete_own"
  on public.room_messages for update to authenticated
  using (sender_id in (select id from public.profiles where user_id = auth.uid()));


-- ── 5. Publish room_messages via Realtime ────────────────────────────────
-- Supabase Realtime listens on the `supabase_realtime` publication.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      alter publication supabase_realtime add table public.room_messages;
    exception
      when duplicate_object then null;  -- already added
    end;
  end if;
end$$;


-- ── 6. RPC: report_room_message — any authenticated user ────────────────
-- Add optional `kind` + `subject_id` columns to reports so a report can point
-- at a specific room message. These are additive & idempotent.
alter table public.reports
  add column if not exists kind        text not null default 'user',
  add column if not exists subject_id  uuid;

create or replace function public.report_room_message(
  target_message_id uuid,
  reason            text default null
) returns void
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  reporter_profile uuid;
  target_sender    uuid;
begin
  if auth.uid() is null then raise exception 'Not authenticated.'; end if;

  select id into reporter_profile
    from public.profiles where user_id = auth.uid();
  if reporter_profile is null then raise exception 'No profile.'; end if;

  select sender_id into target_sender
    from public.room_messages where id = target_message_id;
  if target_sender is null then raise exception 'Message not found.'; end if;

  insert into public.reports
    (reporter_id, reported_user_id, reason, details, status, severity,
     kind, subject_id)
  values
    (reporter_profile,
     target_sender,
     coalesce(reason, 'room_message'),
     coalesce(reason, ''),
     'pending',
     'medium',
     'room_message',
     target_message_id);

  insert into public.moderation_log
    (actor_id, target_user_id, target_kind, action, reason, metadata)
  values
    (auth.uid(),
     (select user_id from public.profiles where id = target_sender),
     'room_message', 'report', reason,
     jsonb_build_object('message_id', target_message_id));
end;
$$;

grant execute on function public.report_room_message(uuid, text) to authenticated;


-- ── 7. RPC: admin_delete_room_message — moderator+ soft-delete ───────────
create or replace function public.admin_delete_room_message(
  target_message_id uuid,
  reason            text default null
) returns void
  language plpgsql
  security definer
  set search_path = public
as $$
declare mod_profile uuid; target_sender uuid;
begin
  if not public.is_moderator_or_above() then
    raise exception 'Moderator only.';
  end if;
  select id into mod_profile from public.profiles where user_id = auth.uid();

  select sender_id into target_sender
    from public.room_messages where id = target_message_id;
  if target_sender is null then raise exception 'Message not found.'; end if;

  update public.room_messages
     set deleted_at = now(),
         deleted_by = mod_profile,
         delete_reason = reason
   where id = target_message_id and deleted_at is null;

  insert into public.moderation_log
    (actor_id, target_user_id, target_kind, action, reason, metadata)
  values
    (auth.uid(),
     (select user_id from public.profiles where id = target_sender),
     'room_message', 'delete_room_message', reason,
     jsonb_build_object('message_id', target_message_id));
end;
$$;

grant execute on function public.admin_delete_room_message(uuid, text) to authenticated;


-- ── 8. RPC: admin_mute_user — admin+ time-boxed mute ─────────────────────
create or replace function public.admin_mute_user(
  target_profile_id uuid,
  hours             int  default 24,
  reason            text default null
) returns void
  language plpgsql
  security definer
  set search_path = public
as $$
declare target_user uuid;
begin
  if not public.is_admin_or_above() then
    raise exception 'Admins only: moderators cannot mute users.';
  end if;
  update public.profiles
     set muted_until = now() + make_interval(hours => hours)
   where id = target_profile_id
   returning user_id into target_user;
  if target_user is null then raise exception 'Profile not found'; end if;

  insert into public.moderation_log
    (actor_id, target_user_id, target_kind, action, reason, metadata)
  values
    (auth.uid(), target_user, 'user', 'mute', reason,
     jsonb_build_object('profile_id', target_profile_id, 'hours', hours));
end;
$$;

grant execute on function public.admin_mute_user(uuid, int, text) to authenticated;


-- ── 9. Seed the 15 launch rooms ──────────────────────────────────────────
insert into public.chat_rooms (slug, name, description, category, sort_order) values
  ('general',           'General Chat',       'Anything goes — say hi.',                    'general',   10),
  ('new-members',       'New Members',        'Just joined? Introduce yourself here.',      'general',   20),
  ('dating-advice',     'Dating Advice',      'Ask, share, and support each other.',        'advice',    30),
  ('friendship',        'Friendship',         'Find friends — no romance required.',        'connect',   40),
  ('music',             'Music',              'What are you listening to?',                 'interest',  50),
  ('movies-tv',         'Movies & TV',        'Recent watches, recs, hot takes.',           'interest',  60),
  ('pets',              'Pets',               'Show us your good boys and girls.',          'interest',  70),
  ('cooking',           'Cooking',            'Recipes, kitchen wins and disasters.',       'interest',  80),
  ('sports',            'Sports',             'Teams, games, workouts.',                    'interest',  90),
  ('cars-motorcycles',  'Cars & Motorcycles', 'Wheels, roads, projects.',                   'interest', 100),
  ('travel',            'Travel',             'Trips, tips, wishlists.',                    'interest', 110),
  ('coffee-talk',       'Coffee Talk',        'Slow chats over a cup.',                     'general',  120),
  ('florida',           'Florida',            'Locals and visitors — the Sunshine State.',  'region',   130),
  ('pennsylvania',      'Pennsylvania',       'Keystone State neighbours.',                 'region',   140),
  ('daily-positivity',  'Daily Positivity',   'One good thing per day.',                    'general',  150)
on conflict (slug) do update
  set name = excluded.name,
      description = excluded.description,
      category = excluded.category,
      sort_order = excluded.sort_order,
      is_active = true;


-- ── 10. Add 'room_message' to reports.kind if constrained ────────────────
-- If your reports.kind column has a check constraint, extend it. We do this
-- defensively: drop-and-recreate the constraint only if one is present.
do $$
declare
  cons text;
begin
  select conname into cons
    from pg_constraint
    where conrelid = 'public.reports'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%kind%';
  if cons is not null then
    execute format('alter table public.reports drop constraint %I', cons);
    alter table public.reports
      add constraint reports_kind_check
      check (kind in ('user', 'message', 'conversation', 'photo', 'room_message', 'other'));
  end if;
end$$;

-- =============================================================================
-- End of migration 015
-- =============================================================================
