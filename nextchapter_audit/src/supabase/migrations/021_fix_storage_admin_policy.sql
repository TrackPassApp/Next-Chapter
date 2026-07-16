-- 021 — Remove obsolete Storage policy that calls the revoked legacy
-- public.is_admin() helper during unrelated Storage operations.
--
-- Migration 020 intentionally revoked authenticated execution of the legacy
-- is_admin(uuid) helper. The older verif_docs_select_admin policy remained on
-- storage.objects, so PostgreSQL could evaluate it while uploading a profile
-- photo and return: permission denied for function is_admin.
--
-- vdoc_select_mods already grants verification-document reads to moderators,
-- admins, and super-admins through is_moderator_or_above(), so removing this
-- duplicate policy does not reduce intended access.

begin;

drop policy if exists "verif_docs_select_admin"
  on storage.objects;

commit;
