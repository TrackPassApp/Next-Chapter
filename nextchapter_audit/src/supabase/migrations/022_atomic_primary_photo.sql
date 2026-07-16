-- 022 — Promote a profile photo atomically.
-- Replaces multiple client-side UPDATE requests that could leave transient
-- duplicate order values and produce cycling/off-by-one results.

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
  target_profile_id uuid;
begin
  select pp.profile_id
    into target_profile_id
    from public.profile_photos pp
    join public.profiles p on p.id = pp.profile_id
   where pp.id = target_photo_id
     and p.user_id = auth.uid();

  if target_profile_id is null then
    raise exception 'Photo not found or not owned by the signed-in user.'
      using errcode = '42501';
  end if;

  with ranked as (
    select
      pp.id,
      (row_number() over (
        order by
          case when pp.id = target_photo_id then 0 else 1 end,
          pp.display_order,
          pp.created_at,
          pp.id
      ) - 1)::integer as new_order
    from public.profile_photos pp
    where pp.profile_id = target_profile_id
  )
  update public.profile_photos pp
     set display_order = ranked.new_order
    from ranked
   where pp.id = ranked.id;

  return target_photo_id;
end;
$$;

revoke all on function public.set_primary_profile_photo(uuid)
  from public, anon;
grant execute on function public.set_primary_profile_photo(uuid)
  to authenticated;

commit;
