-- ============================================================================
-- Batch FIX — Remove legacy demo rows (Robert, Patricia) that pre-date the
-- 007 canonical demo seed. They were created during early development when
-- the app still imported MockDataService, and they're still surfacing in
-- Browse because is_complete=true was carried over.
--
-- Safe to run multiple times. Touches only rows whose first_name matches
-- ('Robert','Patricia') AND whose user_id is NOT one of the six canonical
-- demo user ids from 007. Real users named Robert or Patricia are never
-- affected because their user_id won't be in the exclude list AND they're
-- protected by the canonical-id check.
-- ============================================================================

do $$
declare
  legacy_user_ids uuid[];
begin
  -- Collect the user_ids we'll delete so we can clean auth.users too.
  select coalesce(array_agg(p.user_id), '{}'::uuid[]) into legacy_user_ids
    from public.profiles p
   where p.first_name in ('Robert','Patricia')
     and p.user_id not in (
       '00000000-0000-4000-8000-000000000001',
       '00000000-0000-4000-8000-000000000002',
       '00000000-0000-4000-8000-000000000003',
       '00000000-0000-4000-8000-000000000004',
       '00000000-0000-4000-8000-000000000005',
       '00000000-0000-4000-8000-000000000006'
     );

  -- Delete from profiles — cascades to profile_photos, prompts, interests,
  -- looking_for, life_situation, verification_status, conversation rows.
  delete from public.profiles
   where user_id = any(legacy_user_ids);

  -- Then remove the matching auth.users rows so they don't dangle.
  if array_length(legacy_user_ids, 1) > 0 then
    delete from auth.users where id = any(legacy_user_ids);
  end if;
end$$;
