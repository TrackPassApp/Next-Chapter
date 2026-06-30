-- ============================================================================
-- Batch B9 — Demo community seed
-- ============================================================================
-- Creates 6 fully-fleshed demo users (3 men, 3 women) plus a one-click RPC
-- the real user can call to populate sample conversations with all six.
--
-- Re-running this migration is safe: every insert is guarded with ON CONFLICT
-- DO NOTHING so the seed is idempotent. Photo URLs use Unsplash hosted
-- assets (no storage bucket needed for demo browsing).
--
-- IMPORTANT: This migration writes directly into auth.users. That's only
-- possible when the SQL is executed by the Supabase service_role (the
-- dashboard SQL Editor uses service_role by default).
-- ============================================================================

-- ── Deterministic uuids so we can reference rows later ─────────────────────
-- Auth user ids (auth.users.id)
--   sarah   00000000-0000-4000-8000-000000000001
--   lisa    00000000-0000-4000-8000-000000000002
--   maria   00000000-0000-4000-8000-000000000003
--   james   00000000-0000-4000-8000-000000000004
--   david   00000000-0000-4000-8000-000000000005
--   michael 00000000-0000-4000-8000-000000000006

-- Helper: insert one auth.users row + return the (existing or new) profile id.
create or replace function public._seed_demo_user(
  in_user_id  uuid,
  in_email    text,
  in_first    text,
  in_dob      date,
  in_city     text,
  in_state    text,
  in_gender   text,
  in_status   text,
  in_about    text,
  in_modes    text[],
  in_score    int
) returns uuid
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  new_profile_id uuid;
begin
  -- Insert into auth.users only if not already present.
  insert into auth.users (
    id, instance_id, aud, role,
    email, encrypted_password,
    email_confirmed_at,
    raw_user_meta_data, raw_app_meta_data,
    created_at, updated_at,
    confirmation_token, email_change, email_change_token_new, recovery_token
  )
  values (
    in_user_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    in_email,
    -- Demo accounts have no usable password. The 60-char placeholder is
    -- bcrypt-shaped so the column constraint is satisfied, but it doesn't
    -- correspond to any real plaintext. Avoids depending on pgcrypto's
    -- crypt()/gen_salt() (which lives in the `extensions` schema on Supabase
    -- and isn't always on the search_path).
    '$2a$10$DemoAccountNoLoginXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX',
    now(),
    jsonb_build_object('demo', true),
    jsonb_build_object('demo', true),
    now(), now(),
    '', '', '', ''
  )
  on conflict (id) do nothing;

  -- The bootstrap trigger may have created a profile already. If so, update
  -- it; otherwise insert a fresh one.
  select id into new_profile_id from public.profiles where user_id = in_user_id;
  if new_profile_id is null then
    insert into public.profiles (
      user_id, first_name, date_of_birth, city, state, gender, relationship_status,
      about_me, modes, is_complete, completeness_score, is_online, last_active
    ) values (
      in_user_id, in_first, in_dob, in_city, in_state, in_gender, in_status,
      in_about, in_modes, true, in_score, true, now()
    )
    returning id into new_profile_id;
  else
    update public.profiles set
      first_name          = in_first,
      date_of_birth       = in_dob,
      city                = in_city,
      state               = in_state,
      gender              = in_gender,
      relationship_status = in_status,
      about_me            = in_about,
      modes               = in_modes,
      is_complete         = true,
      completeness_score  = in_score,
      is_online           = true,
      last_active         = now()
    where id = new_profile_id;
  end if;

  -- Verification row already created by bootstrap trigger; ensure it exists.
  insert into public.verification_status (profile_id) values (new_profile_id)
    on conflict (profile_id) do nothing;

  return new_profile_id;
end;
$$;

-- ── 1. Create the six demo users ────────────────────────────────────────────
do $$
declare
  sarah_id   uuid;
  lisa_id    uuid;
  maria_id   uuid;
  james_id   uuid;
  david_id   uuid;
  michael_id uuid;
begin
  sarah_id := public._seed_demo_user(
    '00000000-0000-4000-8000-000000000001', 'sarah.demo@nextchapter.app', 'Sarah',
    date '1972-04-12', 'Austin', 'Texas', 'Female', 'Divorced',
    'Empty-nester rediscovering Texas. Sunday hikes, weekday yoga, late-night vinyl. Looking for someone who laughs easily and reads on weekends.',
    array['date','activity']::text[], 95);

  lisa_id := public._seed_demo_user(
    '00000000-0000-4000-8000-000000000002', 'lisa.demo@nextchapter.app', 'Lisa',
    date '1966-09-21', 'Portland', 'Oregon', 'Female', 'Widowed',
    'Book club host, garden tender, grandmother of two. Found my second wind after losing my husband — open to deep conversation and small adventures.',
    array['date','friend']::text[], 88);

  maria_id := public._seed_demo_user(
    '00000000-0000-4000-8000-000000000003', 'maria.demo@nextchapter.app', 'Maria',
    date '1977-12-03', 'Miami', 'Florida', 'Female', 'Single',
    'Chef by day, salsa dancer by night. Family-first, fluent in Spanish, never says no to fresh ceviche. Hoping to meet someone who can keep up.',
    array['date','activity']::text[], 82);

  james_id := public._seed_demo_user(
    '00000000-0000-4000-8000-000000000004', 'james.demo@nextchapter.app', 'James',
    date '1969-06-18', 'Denver', 'Colorado', 'Male', 'Divorced',
    'Retired engineer, current guitarist (poorly). Two grown kids, one rescue dog. Looking for someone to share Front Range trails and slow Sunday breakfasts.',
    array['date','friend']::text[], 92);

  david_id := public._seed_demo_user(
    '00000000-0000-4000-8000-000000000005', 'david.demo@nextchapter.app', 'David',
    date '1963-02-27', 'Phoenix', 'Arizona', 'Male', 'Widowed',
    'Lost my wife three years ago. Still figuring out who I am alone — but I''m ready to try. Lifelong traveler, terrible at golf, decent at conversation.',
    array['date','activity']::text[], 78);

  michael_id := public._seed_demo_user(
    '00000000-0000-4000-8000-000000000006', 'michael.demo@nextchapter.app', 'Michael',
    date '1975-08-09', 'Seattle', 'Washington', 'Male', 'Single',
    'Photographer who never got married because work always came first. Recalibrating in my 40s. Coffee snob, ferry-ride lover, looking for a partner in slow living.',
    array['date','friend','activity']::text[], 85);

  -- ── 2. Photos ────────────────────────────────────────────────────────────
  insert into public.profile_photos (profile_id, storage_path, display_url, display_order) values
    (sarah_id,   'demo/sarah-1.jpg',   'https://images.unsplash.com/photo-1551836022-d5d88e9218df?w=900&q=80', 0),
    (sarah_id,   'demo/sarah-2.jpg',   'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=900&q=80', 1),
    (sarah_id,   'demo/sarah-3.jpg',   'https://images.unsplash.com/photo-1546961342-1e3c5f6f7b8a?w=900&q=80', 2),
    (lisa_id,    'demo/lisa-1.jpg',    'https://images.unsplash.com/photo-1554151228-14d9def656e4?w=900&q=80', 0),
    (lisa_id,    'demo/lisa-2.jpg',    'https://images.unsplash.com/photo-1488426862026-3ee34a7d66df?w=900&q=80', 1),
    (maria_id,   'demo/maria-1.jpg',   'https://images.unsplash.com/photo-1531123897727-8f129e1688ce?w=900&q=80', 0),
    (maria_id,   'demo/maria-2.jpg',   'https://images.unsplash.com/photo-1502323777036-f29e3972d82f?w=900&q=80', 1),
    (maria_id,   'demo/maria-3.jpg',   'https://images.unsplash.com/photo-1487412720507-e7ab37603c6f?w=900&q=80', 2),
    (james_id,   'demo/james-1.jpg',   'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=900&q=80', 0),
    (james_id,   'demo/james-2.jpg',   'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=900&q=80', 1),
    (james_id,   'demo/james-3.jpg',   'https://images.unsplash.com/photo-1463453091185-61582044d556?w=900&q=80', 2),
    (david_id,   'demo/david-1.jpg',   'https://images.unsplash.com/photo-1552058544-f2b08422138a?w=900&q=80', 0),
    (david_id,   'demo/david-2.jpg',   'https://images.unsplash.com/photo-1547425260-76bcadfb4f2c?w=900&q=80', 1),
    (michael_id, 'demo/michael-1.jpg', 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=900&q=80', 0),
    (michael_id, 'demo/michael-2.jpg', 'https://images.unsplash.com/photo-1492562080023-ab3db95bfbce?w=900&q=80', 1),
    (michael_id, 'demo/michael-3.jpg', 'https://images.unsplash.com/photo-1488161628813-04466f872be2?w=900&q=80', 2)
  on conflict do nothing;

  -- ── 3. Hinge-style prompts ───────────────────────────────────────────────
  insert into public.profile_prompts (profile_id, prompt_key, answer, position) values
    (sarah_id, 'A perfect Sunday looks like…',           'Trail head at sunrise, brunch with friends, a long bath, and reading till midnight.', 0),
    (sarah_id, 'My most controversial opinion is…',      'Pumpkin spice is a personality flaw.', 1),
    (sarah_id, 'I''m looking for…',                       'Someone who texts back and finishes books.', 2),
    (lisa_id,  'A perfect Sunday looks like…',           'Farmer''s market, gardening, then a phone call with my grandkids.', 0),
    (lisa_id,  'Two truths and a lie…',                  'I''ve climbed Kilimanjaro, I hate cilantro, I taught myself piano at 50.', 1),
    (maria_id, 'I''m looking for…',                       'A partner in everything — cooking, dancing, paying off the boat I impulse-bought.', 0),
    (maria_id, 'A perfect Sunday looks like…',           'Beach at dawn, cafecito with mom, salsa class at night.', 1),
    (maria_id, 'My most controversial opinion is…',      'There is no such thing as too much garlic.', 2),
    (james_id, 'A perfect Sunday looks like…',           'Coffee, the paper, a 12-mile bike ride, then guitar with my kids over video.', 0),
    (james_id, 'Two truths and a lie…',                  'I designed a satellite, I''ve never owned a TV, I''ve run two marathons.', 1),
    (james_id, 'I''m looking for…',                       'Someone curious. Bonus if you know your way around a kitchen.', 2),
    (david_id, 'A perfect Sunday looks like…',           'Quiet morning, long drive, somewhere I''ve never been by sunset.', 0),
    (david_id, 'I''m looking for…',                       'A second chapter. Slow, honest, no games.', 1),
    (michael_id,'A perfect Sunday looks like…',          'Ferry to Bainbridge, oysters, taking the long way home with the camera.', 0),
    (michael_id,'My most controversial opinion is…',     'Film is better than digital. I will die on this hill.', 1),
    (michael_id,'Two truths and a lie…',                 'I''ve photographed three Olympics, I make my own bread, I''m fluent in Italian.', 2)
  on conflict do nothing;

  -- ── 4. Interests, looking_for, life_situation ────────────────────────────
  insert into public.profile_interests (profile_id, interest) values
    (sarah_id, 'Hiking'), (sarah_id, 'Yoga'), (sarah_id, 'Reading'), (sarah_id, 'Live Music'), (sarah_id, 'Cooking'),
    (lisa_id, 'Reading'), (lisa_id, 'Gardening'), (lisa_id, 'Cooking'), (lisa_id, 'Travel'),
    (maria_id, 'Dancing'), (maria_id, 'Cooking'), (maria_id, 'Beach'), (maria_id, 'Family Time'), (maria_id, 'Music'),
    (james_id, 'Cycling'), (james_id, 'Music'), (james_id, 'Hiking'), (james_id, 'Cooking'),
    (david_id, 'Travel'), (david_id, 'Golf'), (david_id, 'Wine Tasting'), (david_id, 'Reading'),
    (michael_id, 'Photography'), (michael_id, 'Coffee'), (michael_id, 'Hiking'), (michael_id, 'Film')
  on conflict do nothing;

  insert into public.profile_looking_for (profile_id, looking_for) values
    (sarah_id, 'Long-term Relationship'), (sarah_id, 'Companionship'),
    (lisa_id, 'Friendship'), (lisa_id, 'Long-term Relationship'),
    (maria_id, 'Long-term Relationship'), (maria_id, 'Marriage'),
    (james_id, 'Long-term Relationship'), (james_id, 'Friendship'),
    (david_id, 'Long-term Relationship'), (david_id, 'Companionship'),
    (michael_id, 'Long-term Relationship')
  on conflict do nothing;

  insert into public.profile_life_situation (profile_id, life_situation) values
    (sarah_id, 'Empty Nester'), (sarah_id, 'Career-focused'),
    (lisa_id, 'Widowed'), (lisa_id, 'Has Grandchildren'),
    (maria_id, 'Has Children'),
    (james_id, 'Retired'), (james_id, 'Has Children'),
    (david_id, 'Widowed'), (david_id, 'Retired'),
    (michael_id, 'Career-focused')
  on conflict do nothing;

  -- ── 5. Verification flags (variety: some fully verified, some partial) ──
  update public.verification_status set email_verified=true, phone_verified=true,  selfie_verified=true,  id_verified=true  where profile_id = sarah_id;
  update public.verification_status set email_verified=true, phone_verified=true,  selfie_verified=true,  id_verified=false where profile_id = lisa_id;
  update public.verification_status set email_verified=true, phone_verified=true,  selfie_verified=false, id_verified=false where profile_id = maria_id;
  update public.verification_status set email_verified=true, phone_verified=true,  selfie_verified=true,  id_verified=true  where profile_id = james_id;
  update public.verification_status set email_verified=true, phone_verified=false, selfie_verified=false, id_verified=false where profile_id = david_id;
  update public.verification_status set email_verified=true, phone_verified=true,  selfie_verified=true,  id_verified=false where profile_id = michael_id;
end$$;

-- ── 6. One-click "populate my inbox with demo conversations" RPC ───────────
-- The caller (the signed-in real user) gets six DM conversations with seed
-- opening messages from each demo so they can evaluate the messaging UI
-- without registering multiple accounts.
create or replace function public.seed_demo_conversations_for_me()
  returns int
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  me uuid;
  demo record;
  conv_id uuid;
  created_count int := 0;
begin
  me := public.my_profile_id();
  if me is null then raise exception 'Not authenticated'; end if;

  for demo in
    select id, first_name from public.profiles
    where user_id in (
      '00000000-0000-4000-8000-000000000001',
      '00000000-0000-4000-8000-000000000002',
      '00000000-0000-4000-8000-000000000003',
      '00000000-0000-4000-8000-000000000004',
      '00000000-0000-4000-8000-000000000005',
      '00000000-0000-4000-8000-000000000006'
    )
  loop
    if demo.id = me then continue; end if;

    -- Use the existing helper to find/create the DM.
    conv_id := public.find_or_create_dm(demo.id, 'date');

    -- Only seed messages if the conversation has none yet.
    if not exists (select 1 from public.messages where conversation_id = conv_id) then
      insert into public.messages (conversation_id, sender_id, body, kind, client_message_id)
      values
        (conv_id, demo.id, 'Hey — your profile caught my eye. Whereabouts in the country are you?', 'text', gen_random_uuid()),
        (conv_id, demo.id, 'I see we both like ' ||
            (select interest from public.profile_interests where profile_id = demo.id order by random() limit 1) ||
            ' — coincidence?', 'text', gen_random_uuid());
      created_count := created_count + 1;
    end if;
  end loop;

  return created_count;
end;
$$;
grant execute on function public.seed_demo_conversations_for_me() to authenticated;
