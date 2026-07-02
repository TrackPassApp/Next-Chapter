-- =============================================================================
-- 019 — RC1 Stabilization Batch C: success_stories categorisation
-- =============================================================================
-- Idempotent + additive.
--   • success_stories.kind         — story category
--   • success_stories.tagged_profile_id — optional other-member reference
--   • submit_success_story now accepts kind + tagged_profile_id
--     (old 2-arg call site remains valid — default kind='other', tag=null)
-- =============================================================================

alter table public.success_stories
  add column if not exists kind text,
  add column if not exists tagged_profile_id uuid references public.profiles(id);

-- Constrain the category values.
do $$
declare cons text;
begin
  select conname into cons
    from pg_constraint
   where conrelid = 'public.success_stories'::regclass
     and contype = 'c'
     and pg_get_constraintdef(oid) ilike '%kind%';
  if cons is not null then
    execute format('alter table public.success_stories drop constraint %I', cons);
  end if;
  alter table public.success_stories
    add constraint success_stories_kind_check
    check (kind is null or kind in (
      'dating','friendship','activity_partner','community','marriage','other'
    ));
end$$;

-- Fill legacy rows so future NOT NULL is trivial.
update public.success_stories set kind = 'other' where kind is null;

-- Extend submit_success_story to accept the new fields. Overload cleanly.
create or replace function public.submit_success_story(
  p_title text,
  p_body  text,
  p_kind  text default 'other',
  p_tagged_profile_id uuid default null
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

  insert into public.success_stories
    (author_id, title, body, status, kind, tagged_profile_id)
    values (my_profile, p_title, p_body, 'pending', coalesce(p_kind,'other'), p_tagged_profile_id)
    returning id into new_id;
  return new_id;
end;
$$;
grant execute on function public.submit_success_story(text, text, text, uuid) to authenticated;
