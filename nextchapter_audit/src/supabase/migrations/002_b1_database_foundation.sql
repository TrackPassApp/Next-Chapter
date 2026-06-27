-- ============================================================================
-- Next Chapter — Build Batch B1: Database foundation
-- ============================================================================
-- Additive migration. Idempotent. Safe to re-run.
-- Touches NO existing tables destructively.
-- After this file, the schema is complete enough for B2-B11 to build against.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. Profile field additions: modes, completeness
-- ----------------------------------------------------------------------------

alter table public.profiles
  add column if not exists modes              text[] not null default array['date']::text[],
  add column if not exists is_complete        boolean not null default false,
  add column if not exists completeness_score smallint not null default 0;

-- Multi-mode integrity: at least one mode, only known kinds.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'profiles_modes_nonempty'
  ) then
    alter table public.profiles
      add constraint profiles_modes_nonempty check (cardinality(modes) > 0);
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'profiles_modes_valid'
  ) then
    alter table public.profiles
      add constraint profiles_modes_valid
      check (modes <@ array['date','friend','activity']);
  end if;
end$$;

create index if not exists profiles_modes_gin
  on public.profiles using gin (modes);


-- ----------------------------------------------------------------------------
-- 2. 18+ enforcement at the database level
-- ----------------------------------------------------------------------------
-- Soft NOT VALID so existing rows (some have null DoB) won't be blocked.
-- Future inserts/updates are checked.

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'profiles_dob_adult'
  ) then
    alter table public.profiles
      add constraint profiles_dob_adult
      check (
        date_of_birth is null
        or date_of_birth <= (current_date - interval '18 years')
      ) not valid;
  end if;
end$$;


-- ----------------------------------------------------------------------------
-- 3. Hinge-style prompts
-- ----------------------------------------------------------------------------

create table if not exists public.profile_prompts (
  id           uuid primary key default gen_random_uuid(),
  profile_id   uuid not null references public.profiles(id) on delete cascade,
  prompt_key   text not null,
  answer       text not null check (length(answer) between 1 and 150),
  position     smallint not null default 0,
  is_voice     boolean not null default false,  -- reserved for voice intros later
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (profile_id, position)
);

create index if not exists profile_prompts_profile_idx
  on public.profile_prompts (profile_id);

alter table public.profile_prompts enable row level security;

drop policy if exists "prompts_select_all" on public.profile_prompts;
create policy "prompts_select_all"
  on public.profile_prompts for select to authenticated using (true);

drop policy if exists "prompts_owner_write" on public.profile_prompts;
create policy "prompts_owner_write"
  on public.profile_prompts for all to authenticated
  using (
    profile_id in (select id from public.profiles where user_id = auth.uid())
  )
  with check (
    profile_id in (select id from public.profiles where user_id = auth.uid())
  );


-- ----------------------------------------------------------------------------
-- 4. Messaging: conversations, participants, messages, reads
-- ----------------------------------------------------------------------------

create table if not exists public.conversations (
  id              uuid primary key default gen_random_uuid(),
  mode            text not null default 'date'
                  check (mode in ('date','friend','activity')),
  is_request      boolean not null default true,
  accepted_at     timestamptz,
  archived_at     timestamptz,
  last_message_at timestamptz not null default now(),
  created_at      timestamptz not null default now(),
  created_by      uuid not null references public.profiles(id) on delete cascade
);

create index if not exists conversations_last_message_idx
  on public.conversations (last_message_at desc);

create table if not exists public.conversation_participants (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  profile_id      uuid not null references public.profiles(id) on delete cascade,
  joined_at       timestamptz not null default now(),
  muted_until     timestamptz,
  last_read_at    timestamptz not null default now(),
  primary key (conversation_id, profile_id)
);

create index if not exists conv_participants_profile_idx
  on public.conversation_participants (profile_id);

create table if not exists public.messages (
  id                 uuid primary key default gen_random_uuid(),
  conversation_id    uuid not null references public.conversations(id) on delete cascade,
  sender_id          uuid not null references public.profiles(id),
  client_message_id  uuid not null,
  body               text not null check (length(body) between 1 and 2000),
  kind               text not null default 'text'
                     check (kind in ('text','system')),
  created_at         timestamptz not null default now(),
  edited_at          timestamptz,
  deleted_at         timestamptz,
  unique (conversation_id, client_message_id)
);

create index if not exists messages_conv_created_idx
  on public.messages (conversation_id, created_at desc);

create table if not exists public.message_reads (
  message_id uuid not null references public.messages(id) on delete cascade,
  reader_id  uuid not null references public.profiles(id) on delete cascade,
  read_at    timestamptz not null default now(),
  primary key (message_id, reader_id)
);

-- Helper used by RLS: "is auth.uid() a participant in this conversation"
create or replace function public.is_conversation_participant(c_id uuid)
  returns boolean
  language sql stable security definer set search_path = public
as $$
  select exists(
    select 1
      from public.conversation_participants cp
      join public.profiles p on p.id = cp.profile_id
     where cp.conversation_id = c_id
       and p.user_id = auth.uid()
  );
$$;

alter table public.conversations enable row level security;
alter table public.conversation_participants enable row level security;
alter table public.messages enable row level security;
alter table public.message_reads enable row level security;

drop policy if exists "conv_select_participants" on public.conversations;
create policy "conv_select_participants"
  on public.conversations for select to authenticated
  using (public.is_conversation_participant(id));

drop policy if exists "conv_update_participants" on public.conversations;
create policy "conv_update_participants"
  on public.conversations for update to authenticated
  using (public.is_conversation_participant(id));

drop policy if exists "conv_insert_self" on public.conversations;
create policy "conv_insert_self"
  on public.conversations for insert to authenticated
  with check (
    created_by in (select id from public.profiles where user_id = auth.uid())
  );

drop policy if exists "cp_select_participants" on public.conversation_participants;
create policy "cp_select_participants"
  on public.conversation_participants for select to authenticated
  using (public.is_conversation_participant(conversation_id));

drop policy if exists "cp_insert_participants" on public.conversation_participants;
create policy "cp_insert_participants"
  on public.conversation_participants for insert to authenticated
  with check (
    -- either you're the creator adding any participant, or you're adding yourself
    conversation_id in (
      select id from public.conversations
       where created_by in (select id from public.profiles where user_id = auth.uid())
    )
    or profile_id in (select id from public.profiles where user_id = auth.uid())
  );

drop policy if exists "msg_select_participants" on public.messages;
create policy "msg_select_participants"
  on public.messages for select to authenticated
  using (public.is_conversation_participant(conversation_id));

drop policy if exists "msg_insert_participants" on public.messages;
create policy "msg_insert_participants"
  on public.messages for insert to authenticated
  with check (
    public.is_conversation_participant(conversation_id)
    and sender_id in (select id from public.profiles where user_id = auth.uid())
  );

drop policy if exists "msg_update_own" on public.messages;
create policy "msg_update_own"
  on public.messages for update to authenticated
  using (sender_id in (select id from public.profiles where user_id = auth.uid()));

drop policy if exists "reads_insert_self" on public.message_reads;
create policy "reads_insert_self"
  on public.message_reads for insert to authenticated
  with check (reader_id in (select id from public.profiles where user_id = auth.uid()));

drop policy if exists "reads_select_participants" on public.message_reads;
create policy "reads_select_participants"
  on public.message_reads for select to authenticated
  using (
    message_id in (
      select id from public.messages
       where public.is_conversation_participant(conversation_id)
    )
  );

-- Conversation auto-promote and last_message_at maintenance.
create or replace function public.on_message_inserted()
  returns trigger
  language plpgsql
  security definer
  set search_path = public
as $$
begin
  update public.conversations
     set last_message_at = new.created_at,
         is_request = case
           when is_request and new.sender_id <> created_by then false
           else is_request
         end,
         accepted_at = case
           when accepted_at is null and new.sender_id <> created_by then new.created_at
           else accepted_at
         end
   where id = new.conversation_id;
  return new;
end$$;

drop trigger if exists trg_on_message_inserted on public.messages;
create trigger trg_on_message_inserted
  after insert on public.messages
  for each row execute function public.on_message_inserted();

-- Enable realtime on messages + conversations (idempotent).
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      execute 'alter publication supabase_realtime add table public.messages';
    exception when duplicate_object then null;
    end;
    begin
      execute 'alter publication supabase_realtime add table public.conversations';
    exception when duplicate_object then null;
    end;
  end if;
end$$;


-- ----------------------------------------------------------------------------
-- 5. Moderation log (admin audit trail)
-- ----------------------------------------------------------------------------

create table if not exists public.moderation_log (
  id              uuid primary key default gen_random_uuid(),
  actor_id        uuid references auth.users(id),
  target_user_id  uuid references auth.users(id),
  target_kind     text not null check (target_kind in ('user','report','message','photo')),
  action          text not null,
  reason          text,
  metadata        jsonb default '{}'::jsonb,
  created_at      timestamptz not null default now()
);

create index if not exists moderation_log_target_user_idx
  on public.moderation_log (target_user_id);
create index if not exists moderation_log_created_idx
  on public.moderation_log (created_at desc);

alter table public.moderation_log enable row level security;

drop policy if exists "modlog_admin_select" on public.moderation_log;
create policy "modlog_admin_select"
  on public.moderation_log for select to authenticated
  using (
    coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')
      in ('admin','super_admin','moderator')
  );

-- No INSERT/UPDATE/DELETE policies — service role only.


-- ----------------------------------------------------------------------------
-- 6. Reports: add admin-required columns + admin policies
-- ----------------------------------------------------------------------------

alter table public.reports
  add column if not exists resolved_at  timestamptz,
  add column if not exists resolved_by  uuid references auth.users(id),
  add column if not exists action_taken text,
  add column if not exists severity     text default 'medium'
                          check (severity in ('low','medium','high','critical'));

-- Prevent self-reports (idempotent CHECK).
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'reports_not_self'
  ) then
    alter table public.reports
      add constraint reports_not_self
      check (reporter_id <> reported_user_id);
  end if;
end$$;

-- Admin can SELECT/UPDATE all reports.
drop policy if exists "reports_admin_select" on public.reports;
create policy "reports_admin_select"
  on public.reports for select to authenticated
  using (
    coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')
      in ('admin','super_admin','moderator')
  );

drop policy if exists "reports_admin_update" on public.reports;
create policy "reports_admin_update"
  on public.reports for update to authenticated
  using (
    coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')
      in ('admin','super_admin','moderator')
  );


-- ----------------------------------------------------------------------------
-- 7. Profiles: admin can suspend/delete
-- ----------------------------------------------------------------------------

drop policy if exists "profiles_admin_update" on public.profiles;
create policy "profiles_admin_update"
  on public.profiles for update to authenticated
  using (
    coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')
      in ('admin','super_admin')
  );


-- ----------------------------------------------------------------------------
-- 8. Verification status: lock down user writes
-- ----------------------------------------------------------------------------
-- Users may READ their own verification status (and any visible one).
-- Users may NOT write any verification flag — only service_role / admin can.
-- This closes the audit's P1-17 finding.

drop policy if exists "verification_status_user_all" on public.verification_status;
drop policy if exists "verification_status_owner_all" on public.verification_status;

drop policy if exists "vs_select_all" on public.verification_status;
create policy "vs_select_all"
  on public.verification_status for select to authenticated using (true);

-- No INSERT/UPDATE/DELETE policies for authenticated. Service role only.


-- ----------------------------------------------------------------------------
-- 9. Bootstrap trigger: new auth user → profile + user_settings + verification_status
-- ----------------------------------------------------------------------------

create or replace function public.bootstrap_profile_on_signup()
  returns trigger
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  new_profile_id uuid;
  dob_text       text;
  dob_value      date;
begin
  -- If a profile already exists for this user, do nothing.
  if exists (select 1 from public.profiles where user_id = new.id) then
    return new;
  end if;

  -- Try to read date_of_birth from user_metadata (legacy clients passed it there).
  -- The new flow passes it through the onboarding wizard instead, so this is optional.
  dob_text := nullif(new.raw_user_meta_data ->> 'date_of_birth', '');
  if dob_text is not null then
    begin
      dob_value := dob_text::date;
    exception when others then
      dob_value := null;
    end;
  end if;

  insert into public.profiles (user_id, date_of_birth, modes)
  values (new.id, dob_value, array['date']::text[])
  returning id into new_profile_id;

  insert into public.user_settings (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  insert into public.verification_status (profile_id)
  values (new_profile_id)
  on conflict (profile_id) do nothing;

  return new;
end$$;

drop trigger if exists trg_bootstrap_profile_on_signup on auth.users;
create trigger trg_bootstrap_profile_on_signup
  after insert on auth.users
  for each row execute function public.bootstrap_profile_on_signup();


-- ----------------------------------------------------------------------------
-- 10. Backfill: ensure every existing auth.users has profile + settings + verification
-- ----------------------------------------------------------------------------

do $$
declare
  u record;
  new_profile_id uuid;
begin
  for u in select id from auth.users loop
    if not exists (select 1 from public.profiles where user_id = u.id) then
      insert into public.profiles (user_id, modes)
      values (u.id, array['date']::text[])
      returning id into new_profile_id;

      insert into public.user_settings (user_id)
      values (u.id)
      on conflict (user_id) do nothing;

      insert into public.verification_status (profile_id)
      values (new_profile_id)
      on conflict (profile_id) do nothing;
    end if;
  end loop;
end$$;


-- ----------------------------------------------------------------------------
-- 11. Storage bucket policies for profile-photos
-- ----------------------------------------------------------------------------
-- These were originally documented only as SQL comments. Now codified so the
-- bucket is reproducible.

do $$
begin
  if not exists (
    select 1 from storage.buckets where id = 'profile-photos'
  ) then
    insert into storage.buckets (id, name, public)
    values ('profile-photos', 'profile-photos', false);
  end if;
end$$;

drop policy if exists "photos_read_all_authenticated" on storage.objects;
create policy "photos_read_all_authenticated"
  on storage.objects for select to authenticated
  using (bucket_id = 'profile-photos');

drop policy if exists "photos_insert_own_folder" on storage.objects;
create policy "photos_insert_own_folder"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "photos_update_own_folder" on storage.objects;
create policy "photos_update_own_folder"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "photos_delete_own_folder" on storage.objects;
create policy "photos_delete_own_folder"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );


-- ============================================================================
-- End of migration. Re-running is safe.
-- ============================================================================
