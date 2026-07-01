-- =============================================================================
-- 013 — Fix admin_review_verification_request 42725 (leftover bare is_admin)
-- =============================================================================
-- The stabilization audit found one remaining callable that still guards on
-- the ambiguous bare `public.is_admin()`:
--
--   006_b8_verification.sql:137  → admin_review_verification_request(...)
--
-- Every OTHER 006 bare-is_admin site is either:
--   • a policy USING clause bound at CREATE POLICY time to a specific OID
--     (vreq_admin_select, vreq_admin_update, verif_docs_select_admin —
--     resolved to is_admin(uuid) which is why the user cannot drop it), or
--   • an RPC also redefined by 012 (admin_dashboard_metrics, admin_user_summary).
--
-- admin_review_verification_request is what the Admin → Verification tab
-- calls when a moderator/admin approves or rejects a submitted verification
-- request. If a user has already run 011 (which recreates the 0-arg is_admin)
-- and then presses "Approve" or "Reject" in that tab, Postgres raises:
--     42725 function public.is_admin() is not unique
-- This migration swaps the guard to the uniquely-named helper.
--
-- Signature and body are byte-identical to 006 apart from the guard line.
-- Idempotent — safe to re-run.
-- =============================================================================

create or replace function public.admin_review_verification_request(
  request_id uuid,
  approve    boolean,
  notes      text default null
) returns void
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  req record;
begin
  if not public.is_moderator_or_above() then
    raise exception 'Admin only';
  end if;

  select * into req from public.verification_requests where id = request_id;
  if req.id is null then raise exception 'Request not found'; end if;

  update public.verification_requests
     set status      = case when approve then 'approved' else 'rejected' end,
         reviewed_at = now(),
         reviewed_by = auth.uid(),
         admin_notes = notes
   where id = request_id;

  if approve then
    perform public.admin_set_verification(req.profile_id, req.kind, true, notes);
  end if;

  perform public.admin_log(
    (select user_id from public.profiles where id = req.profile_id),
    'user',
    case when approve then 'verify_' || req.kind else 'reject_' || req.kind end,
    notes,
    jsonb_build_object('request_id', request_id, 'profile_id', req.profile_id, 'kind', req.kind)
  );
end;
$$;

grant execute on function public.admin_review_verification_request(uuid, boolean, text) to authenticated;

-- =============================================================================
-- End of migration 013. Idempotent. No policies touched.
-- =============================================================================
