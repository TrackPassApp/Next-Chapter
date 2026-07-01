-- =============================================================================
-- 017 — Release Candidate 1: notification prefs, stories, quotes, moderation,
--        announcements, events stub, room enhancements
-- =============================================================================
-- Everything RC1 needs on the data side, additive + idempotent.
-- Safe to re-run. No destructive change to existing tables.
-- =============================================================================


-- ── 1. notification_preferences ─────────────────────────────────────────
create table if not exists public.notification_preferences (
  user_id                 uuid primary key references auth.users(id) on delete cascade,
  private_message         boolean not null default true,
  room_reply              boolean not null default true,
  mention                 boolean not null default true,
  verification_approved   boolean not null default true,
  verification_denied     boolean not null default true,
  moderator_warning       boolean not null default true,
  admin_announcement      boolean not null default true,
  match_new               boolean not null default true,
  updated_at              timestamptz not null default now()
);

alter table public.notification_preferences enable row level security;

drop policy if exists "notif_prefs_select_own" on public.notification_preferences;
create policy "notif_prefs_select_own"
  on public.notification_preferences for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "notif_prefs_upsert_own" on public.notification_preferences;
create policy "notif_prefs_upsert_own"
  on public.notification_preferences for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists "notif_prefs_update_own" on public.notification_preferences;
create policy "notif_prefs_update_own"
  on public.notification_preferences for update to authenticated
  using (user_id = auth.uid());

-- Backfill preference rows for existing users; new signups get one on demand
-- from the client on first read.
insert into public.notification_preferences (user_id)
  select id from auth.users
  on conflict (user_id) do nothing;


-- ── 2. Extend moderation_log.target_kind for new kinds ──────────────────
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
    check (target_kind in (
      'user','report','message','photo','conversation','room_message',
      'room','announcement','success_story','event'
    ));
end$$;


-- ── 3. chat_rooms enhancements ──────────────────────────────────────────
alter table public.chat_rooms
  add column if not exists rules       text,
  add column if not exists is_locked   boolean not null default false,
  add column if not exists created_by  uuid references public.profiles(id);

-- Sensible default rules for the seeded rooms if empty.
update public.chat_rooms
  set rules = 'Be kind. No spam. No hate. Report anything that feels off.'
  where rules is null;

-- Any authenticated user can UPDATE chat_rooms via the admin RPCs only —
-- add UPDATE policy for moderator+ so RPCs (which run SECURITY DEFINER
-- anyway) don't rely on service_role.
drop policy if exists "chat_rooms_update_mods" on public.chat_rooms;
create policy "chat_rooms_update_mods"
  on public.chat_rooms for update to authenticated
  using (public.is_moderator_or_above());


-- ── 4. Pinned messages ──────────────────────────────────────────────────
create table if not exists public.room_pinned_messages (
  room_id     uuid not null references public.chat_rooms(id) on delete cascade,
  message_id  uuid not null references public.room_messages(id) on delete cascade,
  pinned_at   timestamptz not null default now(),
  pinned_by   uuid not null references public.profiles(id),
  primary key (room_id, message_id)
);

alter table public.room_pinned_messages enable row level security;

drop policy if exists "room_pins_select_all" on public.room_pinned_messages;
create policy "room_pins_select_all"
  on public.room_pinned_messages for select to authenticated using (true);

-- writes only via RPC (SECURITY DEFINER)


-- ── 5. Announcements (admin-broadcast) ──────────────────────────────────
create table if not exists public.announcements (
  id           uuid primary key default gen_random_uuid(),
  title        text not null,
  body         text not null,
  created_by   uuid not null references public.profiles(id),
  created_at   timestamptz not null default now(),
  published_at timestamptz not null default now(),
  is_active    boolean not null default true
);

alter table public.announcements enable row level security;

drop policy if exists "announcements_select_all" on public.announcements;
create policy "announcements_select_all"
  on public.announcements for select to authenticated using (is_active = true);


-- ── 6. Success stories ──────────────────────────────────────────────────
create table if not exists public.success_stories (
  id          uuid primary key default gen_random_uuid(),
  author_id   uuid not null references public.profiles(id) on delete cascade,
  title       text not null check (length(title) between 3 and 120),
  body        text not null check (length(body) between 10 and 2000),
  status      text not null default 'pending'
              check (status in ('pending', 'approved', 'rejected')),
  approved_at timestamptz,
  approved_by uuid references public.profiles(id),
  admin_notes text,
  created_at  timestamptz not null default now()
);

create index if not exists success_stories_status_idx
  on public.success_stories (status, created_at desc);

alter table public.success_stories enable row level security;

drop policy if exists "stories_select_approved" on public.success_stories;
create policy "stories_select_approved"
  on public.success_stories for select to authenticated
  using (
    status = 'approved'
    or author_id in (select id from public.profiles where user_id = auth.uid())
    or public.is_moderator_or_above()
  );

drop policy if exists "stories_insert_self" on public.success_stories;
create policy "stories_insert_self"
  on public.success_stories for insert to authenticated
  with check (
    author_id in (select id from public.profiles where user_id = auth.uid()
                    and coalesce(is_deleted, false) = false)
  );


-- ── 7. Daily quotes ─────────────────────────────────────────────────────
create table if not exists public.daily_quotes (
  id         uuid primary key default gen_random_uuid(),
  quote      text not null,
  author     text,
  sort_order int  not null default 100,
  is_active  boolean not null default true
);

alter table public.daily_quotes enable row level security;

drop policy if exists "daily_quotes_select_all" on public.daily_quotes;
create policy "daily_quotes_select_all"
  on public.daily_quotes for select to authenticated using (is_active = true);

-- Seed a rotation. `on conflict do nothing` on quote text uniqueness proxy.
insert into public.daily_quotes (quote, sort_order) values
  ('Today is a good day to start a new friendship.',            10),
  ('Sometimes one conversation changes everything.',            20),
  ('Someone out there is hoping to meet someone just like you.',30),
  ('Small connections turn into stories worth telling.',        40),
  ('You do not have to have it all figured out to reach out.',  50),
  ('A kind word today can be the start of something lasting.',  60),
  ('Say hi. That is the whole first step.',                     70),
  ('The best time to make a new friend was yesterday. The second-best time is now.', 80),
  ('Loneliness is not who you are. It is a moment you can move through.', 90),
  ('Every profile here is a real person hoping someone notices.', 100),
  ('Show up as yourself — the right people are looking for exactly that.', 110),
  ('You are allowed to want a real friendship too.', 120),
  ('One coffee. One walk. One message. That is how communities begin.', 130),
  ('Be the person you needed to meet a year ago.', 140),
  ('The next chapter starts the moment you decide to write it.', 150)
on conflict do nothing;


-- ── 8. Events foundation (STUB — no UI for Beta) ────────────────────────
create table if not exists public.events (
  id          uuid primary key default gen_random_uuid(),
  kind        text not null default 'meetup'
              check (kind in (
                'coffee_meetup', 'walking_group', 'volunteer',
                'game_night', 'concert', 'travel_group',
                'cruise', 'local_gathering', 'meetup'
              )),
  title       text not null,
  description text,
  location    text,
  start_time  timestamptz,
  end_time    timestamptz,
  capacity    int,
  created_by  uuid references public.profiles(id),
  status      text not null default 'draft'
              check (status in ('draft', 'published', 'cancelled', 'ended')),
  created_at  timestamptz not null default now()
);

alter table public.events enable row level security;

drop policy if exists "events_select_published" on public.events;
create policy "events_select_published"
  on public.events for select to authenticated
  using (
    status = 'published'
    or created_by in (select id from public.profiles where user_id = auth.uid())
    or public.is_moderator_or_above()
  );


-- ── 9. Realtime publications ────────────────────────────────────────────
do $$
declare tbl text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    for tbl in select unnest(array[
      'room_pinned_messages', 'success_stories', 'announcements'
    ]) loop
      begin
        execute format('alter publication supabase_realtime add table public.%I', tbl);
      exception when duplicate_object then null;
      end;
    end loop;
  end if;
end$$;


-- ── 10. RPCs ────────────────────────────────────────────────────────────

-- Submit a success story (author = current user's profile).
create or replace function public.submit_success_story(
  p_title text,
  p_body  text
) returns uuid
  language plpgsql security definer set search_path = public
as $$
declare
  my_profile uuid;
  new_id     uuid;
begin
  if auth.uid() is null then raise exception 'Not authenticated.'; end if;
  select id into my_profile from public.profiles where user_id = auth.uid();
  if my_profile is null then raise exception 'No profile.'; end if;
  insert into public.success_stories (author_id, title, body, status)
    values (my_profile, p_title, p_body, 'pending')
    returning id into new_id;
  return new_id;
end;
$$;
grant execute on function public.submit_success_story(text, text) to authenticated;

-- Admin/moderator: approve or reject a success story.
create or replace function public.admin_moderate_story(
  p_story_id uuid,
  p_status   text,
  p_notes    text default null
) returns void
  language plpgsql security definer set search_path = public
as $$
declare
  my_profile uuid;
  target_author uuid;
begin
  if not public.is_moderator_or_above() then raise exception 'Moderator only.'; end if;
  if p_status not in ('approved','rejected','pending') then
    raise exception 'Invalid status: %', p_status;
  end if;
  select id into my_profile from public.profiles where user_id = auth.uid();

  update public.success_stories
     set status = p_status,
         approved_at = case when p_status = 'approved' then now() else approved_at end,
         approved_by = case when p_status = 'approved' then my_profile else approved_by end,
         admin_notes = coalesce(p_notes, admin_notes)
   where id = p_story_id
   returning author_id into target_author;

  insert into public.moderation_log
    (actor_id, target_user_id, target_kind, action, reason, metadata)
  values
    (auth.uid(),
     (select user_id from public.profiles where id = target_author),
     'success_story', 'moderate_story', p_notes,
     jsonb_build_object('story_id', p_story_id, 'status', p_status));
end;
$$;
grant execute on function public.admin_moderate_story(uuid, text, text) to authenticated;


-- Pin / unpin a room message (moderator+).
create or replace function public.admin_pin_room_message(
  p_message_id uuid
) returns void
  language plpgsql security definer set search_path = public
as $$
declare
  my_profile uuid;
  target_room uuid;
begin
  if not public.is_moderator_or_above() then raise exception 'Moderator only.'; end if;
  select id into my_profile from public.profiles where user_id = auth.uid();
  select room_id into target_room from public.room_messages where id = p_message_id;
  if target_room is null then raise exception 'Message not found.'; end if;

  insert into public.room_pinned_messages (room_id, message_id, pinned_by)
  values (target_room, p_message_id, my_profile)
  on conflict do nothing;

  insert into public.moderation_log
    (actor_id, target_user_id, target_kind, action, metadata)
  values
    (auth.uid(), null, 'room_message', 'pin',
     jsonb_build_object('room_id', target_room, 'message_id', p_message_id));
end;
$$;
grant execute on function public.admin_pin_room_message(uuid) to authenticated;

create or replace function public.admin_unpin_room_message(
  p_message_id uuid
) returns void
  language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_moderator_or_above() then raise exception 'Moderator only.'; end if;
  delete from public.room_pinned_messages where message_id = p_message_id;
  insert into public.moderation_log
    (actor_id, target_user_id, target_kind, action, metadata)
  values
    (auth.uid(), null, 'room_message', 'unpin',
     jsonb_build_object('message_id', p_message_id));
end;
$$;
grant execute on function public.admin_unpin_room_message(uuid) to authenticated;


-- Warn a user (moderator+). Sends them a notification + logs.
create or replace function public.admin_warn_user(
  target_profile_id uuid,
  reason            text
) returns void
  language plpgsql security definer set search_path = public
as $$
declare target_user uuid;
begin
  if not public.is_moderator_or_above() then raise exception 'Moderator only.'; end if;
  select user_id into target_user from public.profiles where id = target_profile_id;
  if target_user is null then raise exception 'Profile not found.'; end if;

  insert into public.notifications (user_id, kind, title, body, link, payload)
  values (target_user, 'moderator_warning',
          'Moderator warning',
          coalesce(reason, 'A moderator has issued a warning on your account.'),
          '/settings',
          jsonb_build_object('reason', reason));

  insert into public.moderation_log
    (actor_id, target_user_id, target_kind, action, reason, metadata)
  values
    (auth.uid(), target_user, 'user', 'warn', reason,
     jsonb_build_object('profile_id', target_profile_id));
end;
$$;
grant execute on function public.admin_warn_user(uuid, text) to authenticated;


-- Lock / unlock a room (admin+ per spec).
create or replace function public.admin_lock_room(
  p_room_id uuid,
  p_locked  boolean,
  p_reason  text default null
) returns void
  language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin_or_above() then raise exception 'Admins only.'; end if;
  update public.chat_rooms set is_locked = p_locked where id = p_room_id;
  insert into public.moderation_log
    (actor_id, target_user_id, target_kind, action, reason, metadata)
  values
    (auth.uid(), null, 'room',
     case when p_locked then 'lock_room' else 'unlock_room' end,
     p_reason, jsonb_build_object('room_id', p_room_id));
end;
$$;
grant execute on function public.admin_lock_room(uuid, boolean, text) to authenticated;

-- Create / rename / soft-delete rooms (admin+).
create or replace function public.admin_create_room(
  p_slug        text,
  p_name        text,
  p_description text default null,
  p_category    text default 'general',
  p_rules       text default null
) returns uuid
  language plpgsql security definer set search_path = public
as $$
declare
  my_profile uuid; new_id uuid;
begin
  if not public.is_admin_or_above() then raise exception 'Admins only.'; end if;
  select id into my_profile from public.profiles where user_id = auth.uid();
  insert into public.chat_rooms (slug, name, description, category, rules, created_by)
  values (p_slug, p_name, p_description, p_category, p_rules, my_profile)
  returning id into new_id;
  insert into public.moderation_log
    (actor_id, target_user_id, target_kind, action, metadata)
  values (auth.uid(), null, 'room', 'create_room',
          jsonb_build_object('room_id', new_id, 'slug', p_slug));
  return new_id;
end;
$$;
grant execute on function public.admin_create_room(text, text, text, text, text) to authenticated;

create or replace function public.admin_rename_room(
  p_room_id uuid,
  p_name    text,
  p_description text default null,
  p_rules   text default null
) returns void
  language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin_or_above() then raise exception 'Admins only.'; end if;
  update public.chat_rooms
     set name        = coalesce(p_name, name),
         description = coalesce(p_description, description),
         rules       = coalesce(p_rules, rules)
   where id = p_room_id;
  insert into public.moderation_log
    (actor_id, target_user_id, target_kind, action, metadata)
  values (auth.uid(), null, 'room', 'rename_room',
          jsonb_build_object('room_id', p_room_id, 'name', p_name));
end;
$$;
grant execute on function public.admin_rename_room(uuid, text, text, text) to authenticated;

create or replace function public.admin_delete_room(
  p_room_id uuid,
  p_reason  text default null
) returns void
  language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin_or_above() then raise exception 'Admins only.'; end if;
  update public.chat_rooms set is_active = false where id = p_room_id;
  insert into public.moderation_log
    (actor_id, target_user_id, target_kind, action, reason, metadata)
  values (auth.uid(), null, 'room', 'delete_room', p_reason,
          jsonb_build_object('room_id', p_room_id));
end;
$$;
grant execute on function public.admin_delete_room(uuid, text) to authenticated;


-- Global announcement (admin+): stores a row and fans out to every user
-- as a notification (respecting their preferences).
create or replace function public.admin_broadcast_announcement(
  p_title text,
  p_body  text
) returns uuid
  language plpgsql security definer set search_path = public
as $$
declare
  my_profile uuid;
  new_id     uuid;
begin
  if not public.is_admin_or_above() then raise exception 'Admins only.'; end if;
  select id into my_profile from public.profiles where user_id = auth.uid();
  insert into public.announcements (title, body, created_by)
    values (p_title, p_body, my_profile)
    returning id into new_id;

  -- Fan out — respect notification_preferences.admin_announcement.
  insert into public.notifications (user_id, kind, title, body, link, payload)
    select np.user_id, 'admin_announcement', p_title, p_body, '/', jsonb_build_object('announcement_id', new_id)
      from public.notification_preferences np
     where np.admin_announcement = true;

  insert into public.moderation_log
    (actor_id, target_user_id, target_kind, action, metadata)
  values (auth.uid(), null, 'announcement', 'broadcast',
          jsonb_build_object('announcement_id', new_id));
  return new_id;
end;
$$;
grant execute on function public.admin_broadcast_announcement(text, text) to authenticated;


-- Profile completion helper — returns 0..100.
create or replace function public.profile_completion(target_profile_id uuid)
  returns int
  language plpgsql stable security definer set search_path = public
as $$
declare
  photos_cnt int;
  prompts_cnt int;
  interests_cnt int;
  about_ok boolean;
  vs record;
  score int := 0;
begin
  select count(*) into photos_cnt   from public.profile_photos    where profile_id = target_profile_id;
  select count(*) into prompts_cnt  from public.profile_prompts   where profile_id = target_profile_id;
  select count(*) into interests_cnt from public.profile_interests where profile_id = target_profile_id;
  select (about_me is not null and length(about_me) > 20) into about_ok
    from public.profiles where id = target_profile_id;
  select * into vs from public.verification_status where profile_id = target_profile_id;

  if photos_cnt   >= 1 then score := score + 15; end if;
  if photos_cnt   >= 3 then score := score + 10; end if;
  if prompts_cnt  >= 1 then score := score + 10; end if;
  if prompts_cnt  >= 3 then score := score + 10; end if;
  if interests_cnt >= 3 then score := score + 15; end if;
  if about_ok then score := score + 10; end if;
  if vs.email_verified  then score := score + 10; end if;
  if vs.phone_verified  then score := score + 10; end if;
  if vs.id_verified     then score := score + 10; end if;
  if score > 100 then score := 100; end if;
  return score;
end;
$$;
grant execute on function public.profile_completion(uuid) to authenticated;


-- Room member count (distinct posters in last 90 days).
create or replace function public.room_member_count(target_room_id uuid)
  returns int
  language sql stable security definer set search_path = public
as $$
  select count(distinct sender_id)::int
    from public.room_messages
   where room_id = target_room_id
     and created_at > now() - interval '90 days'
     and deleted_at is null;
$$;
grant execute on function public.room_member_count(uuid) to authenticated;


-- ── 11. reports.kind — extend to include new kinds (idempotent) ─────────
alter table public.reports
  add column if not exists kind       text not null default 'user',
  add column if not exists subject_id uuid;


-- =============================================================================
-- End of migration 017
-- =============================================================================
