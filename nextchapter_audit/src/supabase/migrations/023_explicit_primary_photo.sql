-- 023 — Make the primary profile photo an explicit database identity.
-- display_order remains gallery presentation only; it is no longer the
-- source of truth for which photo is primary.

begin;

alter table public.profiles
  add column if not exists primary_photo_id uuid;

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conrelid = 'public.profiles'::regclass
       and conname = 'profiles_primary_photo_id_fkey'
  ) then
    alter table public.profiles
      add constraint profiles_primary_photo_id_fkey
      foreign key (primary_photo_id)
      references public.profile_photos(id)
      on delete set null;
  end if;
end;
$$;

-- Preserve every existing profile's current order-0 choice.
with first_photos as (
  select distinct on (pp.profile_id)
    pp.profile_id,
    pp.id
  from public.profile_photos pp
  order by pp.profile_id, pp.display_order, pp.created_at, pp.id
)
update public.profiles p
   set primary_photo_id = fp.id
  from first_photos fp
 where fp.profile_id = p.id
   and p.primary_photo_id is null;

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

  -- This is the authoritative primary-photo write.
  update public.profiles
     set primary_photo_id = target_photo_id
   where id = v_profile_id;

  -- Keep gallery order intuitive, but primary identity no longer depends on it.
  update public.profile_photos
     set display_order =
       case
         when id = target_photo_id then 0
         when display_order < v_target_order then display_order + 1
         else display_order
       end
   where profile_id = v_profile_id;

  return target_photo_id;
end;
$$;

revoke all on function public.set_primary_profile_photo(uuid)
  from public, anon;
grant execute on function public.set_primary_profile_photo(uuid)
  to authenticated;

-- Give the first uploaded photo primary status automatically, and choose a
-- deterministic replacement if the current primary photo is deleted.
create or replace function public.maintain_primary_profile_photo()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  replacement_id uuid;
begin
  if tg_op = 'INSERT' then
    update public.profiles
       set primary_photo_id = new.id
     where id = new.profile_id
       and primary_photo_id is null;
    return new;
  end if;

  select pp.id
    into replacement_id
    from public.profile_photos pp
   where pp.profile_id = old.profile_id
     and pp.id <> old.id
   order by pp.display_order, pp.created_at, pp.id
   limit 1;

  update public.profiles
     set primary_photo_id = replacement_id
   where id = old.profile_id
     and primary_photo_id = old.id;

  return old;
end;
$$;

drop trigger if exists maintain_primary_profile_photo_insert
  on public.profile_photos;
create trigger maintain_primary_profile_photo_insert
after insert on public.profile_photos
for each row execute function public.maintain_primary_profile_photo();

drop trigger if exists maintain_primary_profile_photo_delete
  on public.profile_photos;
create trigger maintain_primary_profile_photo_delete
before delete on public.profile_photos
for each row execute function public.maintain_primary_profile_photo();

commit;
