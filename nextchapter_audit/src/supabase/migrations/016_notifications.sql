-- =============================================================================
-- 016 — Notifications scaffolding (B11)
-- =============================================================================
-- Ground-truth for future notifications (push, email, or in-app bell).
-- This migration is DATA-ONLY: it creates the `notifications` table,
-- adds Supabase Realtime, and installs two simple triggers so the app can
-- start reading real notifications immediately. It does NOT enable browser
-- push notifications — that ships when you decide on FCM / OneSignal.
--
-- Notification kinds seeded here:
--   private_message   — someone messaged you in a 1:1 conversation
--   verification      — an admin approved/rejected your verification
--
-- Future kinds (client just consumes them, no schema change required):
--   room_reply, room_mention, admin_announcement, match_new, block_notice
-- =============================================================================


-- ── 1. Table ─────────────────────────────────────────────────────────────
create table if not exists public.notifications (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  kind         text not null,
  title        text not null,
  body         text,
  link         text,                 -- deep link, e.g. '/messages/<uuid>'
  payload      jsonb not null default '{}'::jsonb,
  read_at      timestamptz,
  created_at   timestamptz not null default now()
);

create index if not exists notifications_user_created_idx
  on public.notifications (user_id, created_at desc);

create index if not exists notifications_user_unread_idx
  on public.notifications (user_id)
  where read_at is null;

alter table public.notifications enable row level security;


-- ── 2. Policies — user sees only their own notifications ────────────────
drop policy if exists "notifications_select_self" on public.notifications;
create policy "notifications_select_self"
  on public.notifications for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "notifications_update_self" on public.notifications;
create policy "notifications_update_self"
  on public.notifications for update to authenticated
  using (user_id = auth.uid());

-- No INSERT policy — writes only happen via SECURITY DEFINER triggers/RPCs.


-- ── 3. Realtime publish so the app can stream new rows to the bell ──────
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      alter publication supabase_realtime add table public.notifications;
    exception when duplicate_object then null; end;
  end if;
end$$;


-- ── 4. RPC: mark_notifications_read ─────────────────────────────────────
create or replace function public.mark_notifications_read(
  ids uuid[] default null
) returns int
  language plpgsql
  security definer
  set search_path = public
as $$
declare n int;
begin
  if auth.uid() is null then raise exception 'Not authenticated.'; end if;
  update public.notifications
     set read_at = now()
   where user_id = auth.uid()
     and read_at is null
     and (ids is null or id = any(ids));
  get diagnostics n = row_count;
  return n;
end;
$$;

grant execute on function public.mark_notifications_read(uuid[]) to authenticated;


-- ── 5. Trigger: notify recipient of a new private message ───────────────
create or replace function public.tg_notify_on_message()
  returns trigger
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  sender_name  text;
  target       uuid;  -- auth.users id of the recipient
begin
  -- Skip system messages entirely.
  if new.kind = 'system' then return new; end if;

  select first_name into sender_name from public.profiles where id = new.sender_id;

  -- Notify every participant except the sender.
  for target in
    select p.user_id
      from public.conversation_participants cp
      join public.profiles p on p.id = cp.profile_id
     where cp.conversation_id = new.conversation_id
       and cp.profile_id <> new.sender_id
  loop
    insert into public.notifications (user_id, kind, title, body, link, payload)
    values (
      target,
      'private_message',
      coalesce(sender_name, 'Someone') || ' sent you a message',
      left(new.body, 140),
      '/messages/' || new.conversation_id,
      jsonb_build_object(
        'conversation_id', new.conversation_id,
        'message_id',       new.id,
        'sender_profile_id', new.sender_id
      )
    );
  end loop;
  return new;
end;
$$;

drop trigger if exists notify_on_message on public.messages;
create trigger notify_on_message
  after insert on public.messages
  for each row execute function public.tg_notify_on_message();


-- ── 6. Trigger: notify user when a verification flag flips ──────────────
-- Fires when any *_verified column changes from false → true or when the
-- verification_notes column is set (admin rejected with a reason).
create or replace function public.tg_notify_on_verification()
  returns trigger
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  target uuid;  -- auth.users id (owner)
  kind_changed text;
  is_approval boolean := false;
begin
  select p.user_id into target
    from public.profiles p where p.id = new.profile_id;
  if target is null then return new; end if;

  if (new.email_verified   is distinct from old.email_verified)   and new.email_verified   = true then
    kind_changed := 'email';   is_approval := true;
  elsif (new.phone_verified is distinct from old.phone_verified)  and new.phone_verified  = true then
    kind_changed := 'phone';   is_approval := true;
  elsif (new.selfie_verified is distinct from old.selfie_verified) and new.selfie_verified = true then
    kind_changed := 'selfie';  is_approval := true;
  elsif (new.id_verified    is distinct from old.id_verified)     and new.id_verified     = true then
    kind_changed := 'id';      is_approval := true;
  end if;

  if is_approval then
    insert into public.notifications (user_id, kind, title, body, link, payload)
    values (
      target,
      'verification',
      'Verification approved: ' || kind_changed,
      'Your ' || kind_changed || ' verification was approved.',
      '/me/verification',
      jsonb_build_object('kind', kind_changed, 'approved', true)
    );
  end if;
  return new;
end;
$$;

drop trigger if exists notify_on_verification on public.verification_status;
create trigger notify_on_verification
  after update on public.verification_status
  for each row execute function public.tg_notify_on_verification();


-- =============================================================================
-- End of migration 016
-- =============================================================================
