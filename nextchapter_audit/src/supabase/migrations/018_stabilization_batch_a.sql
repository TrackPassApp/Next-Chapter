-- =============================================================================
-- 018 — RC1 Stabilization Batch A (functional fixes only)
-- =============================================================================
-- Idempotent + additive. Fixes:
--   A2: create the verification-docs storage bucket + policies
--   A4: allow users to DELETE their own notifications
--   A5: moderators must be able to mute users (per spec)
-- =============================================================================


-- ── A2. verification-docs storage bucket + policies ─────────────────────
insert into storage.buckets (id, name, public)
  values ('verification-docs', 'verification-docs', false)
  on conflict (id) do nothing;

-- Owner can upload into their own {uid}/... folder
drop policy if exists "vdoc_insert_own_folder" on storage.objects;
create policy "vdoc_insert_own_folder"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'verification-docs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Owner can read their own docs (short-lived signed URL from client)
drop policy if exists "vdoc_select_own" on storage.objects;
create policy "vdoc_select_own"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'verification-docs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Moderators+ can read every verification doc (admin dashboard signed URLs)
drop policy if exists "vdoc_select_mods" on storage.objects;
create policy "vdoc_select_mods"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'verification-docs'
    and public.is_moderator_or_above()
  );

-- Owner may replace their own doc (upsert)
drop policy if exists "vdoc_update_own_folder" on storage.objects;
create policy "vdoc_update_own_folder"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'verification-docs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Owner may delete their own doc if they cancel/replace
drop policy if exists "vdoc_delete_own_folder" on storage.objects;
create policy "vdoc_delete_own_folder"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'verification-docs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );


-- ── A4. Users may DELETE their own notifications ────────────────────────
drop policy if exists "notifications_delete_self" on public.notifications;
create policy "notifications_delete_self"
  on public.notifications for delete to authenticated
  using (user_id = auth.uid());


-- ── A5. Moderators may mute users (per RC1 spec) ────────────────────────
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
  if not public.is_moderator_or_above() then
    raise exception 'Moderator+ required to mute users.';
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


-- =============================================================================
-- End of migration 018
-- =============================================================================
