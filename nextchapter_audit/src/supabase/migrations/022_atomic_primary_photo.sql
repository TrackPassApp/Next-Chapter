-- 022 — Promote a profile photo atomically.
-- Replaces multiple client-side UPDATE requests that produced cycling and
-- off-by-one results. Ownership is checked before any row is changed.

begin;

create or replace function public.set_primary_profile_photo(
  target_photo_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile_id uuid;
  v_target_order integer;
  v_updated_rows integer;
begin
  select pp.profile_id, pp.display_order
    into v_profile_id, v_target_order
    from public.profile_photos pp
    join public.profiles p on p.id = pp.profile_id
   where pp.id = target_photo_id
     and p.user_id = auth.uid();

  if v_profile_id is null then
    raise exception 'Photo not found or not owned by the signed-in user.'
      using errcode = '42501';
  end if;

  update public.profile_photos
     set display_order =
       case
         when id = target_photo_id then 0
         when display_order < v_target_order then display_order + 1
         else display_order
       end
   where profile_id = v_profile_id;

  get diagnostics v_updated_rows = row_count;
  if v_updated_rows = 0 then
    raise exception 'No profile photos were updated.';
  end if;

  return target_photo_id;
end;
$$;

revoke all on function public.set_primary_profile_photo(uuid)
  from public, anon;
grant execute on function public.set_primary_profile_photo(uuid)
  to authenticated;

commit;
