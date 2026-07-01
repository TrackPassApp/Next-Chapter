# Next Chapter — Product Requirements Document

## Original Problem Statement
Initial: Perform a full architectural audit of the Next Chapter (formerly ConnectUp) Flutter project — security, DB design, Supabase integration, and feature parity vs. major dating platforms.

Pivot 1: Build the app in **12 feature batches**. NO step-by-step testing.
Pivot 2 (Msg 414): Stop feature work; execute a **5-Batch Stabilization Plan** to fix B1–B8.
Pivot 3 (Msg ~430): Stop all batches; perform a **full code-level repair audit** that fixes Profile Detail, My Profile, Admin and Demo Profiles, then deploys with a visible build label.

## Product Goals (Beta 1.0)
- 100% free messaging, privacy-first dating + friendship platform (ages 18–100)
- Stack: Flutter + Supabase Free tier (no Drift, no OneSignal, no Sightengine)
- Core flows: Email Auth, Onboarding Wizard, Real Browse/Search, Real Messaging, Block/Report, Hidden Admin route, Verification UI, Account deletion, Monetization placeholders

## Architecture
- Flutter Web/Mobile frontend (`/app/nextchapter_audit/src/lib/`)
- Deployed static bundle (`/app/frontend/`) is served by `serve.js` behind Nginx → preview URL.
- Supabase: Auth, Postgres, Storage (`profile-photos` bucket), Realtime
- State: Provider
- Routing: GoRouter (hash strategy)
- Secrets via `--dart-define` (SUPABASE_URL, SUPABASE_ANON_KEY, APP_URL)

## Build Checklist (12 Batches)
- [x] **B1** Security + DB foundation
- [x] **B2** Onboarding Wizard
- [x] **B3** Profiles & Photos
- [x] **B4** Browse + filters
- [x] **B5** Messaging
- [x] **B6** Block & report
- [x] **B7** Admin Dashboard
- [x] **B8** Verification UI
- [x] **B9** Demo community + 5-tab navigation
- [x] **B10** Privacy, safety, account deletion pipeline (2026-07-01, awaits user-run migration 014 + live smoke test)
- [ ] **B11** Monetization placeholders (ad slot, donation tile)
- [ ] **B12** End-to-end smoke test + polish

## Stabilization / Repair Log
- 2026-07-01 — **B10 Account Deletion Pipeline** (`014_account_deletion.sql`, `settings_screen.dart`, released as build `B10-20260701163651`):
  - New user-callable RPC `public.request_account_deletion(reason text default null)` (SECURITY DEFINER):
    flips `profiles.is_deleted=true`, sets `deleted_at=now()`, `is_complete=false`; redacts PII (`first_name → 'Deleted User'`, `about_me/city/state` cleared); purges child rows on `profile_photos/prompts/interests/looking_for/life_situation`; writes `moderation_log` row with `action='self_delete'` + optional reason. Messages, conversations, reports, moderation_log are all preserved for admin history.
  - New index `profiles_deleted_at_idx` scoped to `is_deleted=true` — feeds a future 30-day hard-delete cron. Cron NOT built per user directive.
  - New RLS policy `profiles_select_admins` — `is_moderator_or_above()` bypass so soft-deleted users remain visible to admins/moderators in AdminUsersTab (which filters `deleted=true`) even though the regular `profiles_select_self_or_public` policy from 010 hides them from everyone else.
  - Hardened `msg_insert_participants` — sender row now must have `coalesce(is_deleted,false)=false`, so a soft-deleted account cannot post new messages even if it still holds a valid session.
  - `SettingsScreen._DeleteAccountDialog`: replaces the placeholder delete tile with a two-step dialog (Immediately / Kept for safety / After 30 days copy sections, optional reason, `I understand` checkbox + typed `DELETE` confirmation). Calls `request_account_deletion(reason)`, then `AuthProvider.logout()`, then `context.go('/')`.
- 2026-07-01 — **Stabilization audit** (`013_fix_admin_review_verification_request.sql`): grep-based audit surfaced one bug — `admin_review_verification_request()` in 006 still guarded on bare `is_admin()`, which 42725s when an admin approves/rejects. 013 redefines it with `is_moderator_or_above()`.
- 2026-07-01 — **AdminFix-2026-07-01** (build stamp latest)
  - Migration 011 introduces the role hierarchy: `super_admin > admin > moderator`.
  - New Postgres helpers: `jwt_role()`, `is_moderator_or_above()`, `is_admin_or_above()`, `is_super_admin()`. Suspend / unsuspend / soft_delete / restore RPCs now require `is_admin_or_above()`; moderators can only view + resolve reports + moderate verification.
  - New RPCs: `admin_list_admins()`, `admin_grant_role()`, `admin_revoke_role()`, `admin_my_role()`. All role writes are super_admin-only server-side.
  - AuthProvider exposes `role`, `canModerate`, `canAdmin`, `isSuperAdmin`.
  - AdminScreen: new **Roles** tab (super_admin can grant/revoke moderators/admins); tabs now scroll horizontally when there are 6.
  - AdminUserDetailDialog: destructive user buttons disabled with tooltip for moderators.
  - Settings gains a "Moderation" section that only appears for admins/moderators, containing "Admin Dashboard (<ROLE>)" and "Diagnostics" links.
  - `/diagnostics` route removed from the public router; replaced with admin-only `/admin/diagnostics`.
  - Public build-label overlay removed from `index.html`. Debug pill removed from ProfileDetail header. `AppConfig.buildLabel` remains only as an internal string on the diagnostics page.
- 2026-07-01 — **ScaffoldFix-2026-07-01**: nested-Scaffold layout bug fixed; ProfileDetailScreen returns a Material→SafeArea→Column layout that lives inside the AppShell's single Scaffold. Confirmed working by user.
- 2026-06-30 — see prior entries.
  - Profile Detail rewritten (Scaffold + ListView; UUID guard; always-render sections with empty-state hints; new `_NoPhotoPlaceholder`; build pill in app bar).
  - My Profile reuses ProfileDetailScreen — never blank, even for sparse data.
  - Router: legacy `/profile/:id` redirects to canonical `/browse/profile/:id`; non-UUID ids bounce to `/browse`.
  - Admin: role check reads `app_metadata.role` from JWT only; web-only guard.
  - Deployment: Cache-busted filenames (`main.<stamp>.dart.js`, `flutter_bootstrap.<stamp>.js`); self-uninstalling service worker; `no-store` headers for HTML/JS/JSON; permanent build badge overlay in `index.html`; Settings → Run Diagnostics tile.
  - Diagnostics screen (`/#/diagnostics`) now reports: build label, Supabase config, init status, mock-mode, login state, JWT admin role, email verified, own profile data, Browse fetch count, single-profile round-trip, demo seed presence — fully exportable to clipboard.
  - Sarah's broken Unsplash URL replaced (migrations/009).

## Key Files
- `lib/config/app_config.dart` — `buildLabel` constant
- `lib/router/app_router.dart` — all routes, redirect logic
- `lib/screens/profile_detail_screen.dart` — full profile view
- `lib/screens/my_profile_screen.dart` — own-profile gate
- `lib/screens/admin_screen.dart` — web-only admin dashboard
- `lib/screens/diagnostics_screen.dart` — runtime diagnostics
- `lib/screens/settings_screen.dart` — build chip + Diagnostics tile
- `lib/repositories/profile_repository.dart` — Supabase data access
- `frontend/index.html` + `frontend/flutter_bootstrap.<stamp>.js` + `frontend/main.<stamp>.dart.js`
- `frontend/serve.js` — no-store headers
- `supabase/migrations/001`..`009` — applied incrementally; 009 fixes one demo photo URL

## DB Schema Highlights
- `profiles` (id, user_id, modes text[], is_complete, completeness_score, is_suspended, is_deleted, 18+ check)
- `profile_prompts`, `profile_photos`, `profile_interests`, `profile_looking_for`, `profile_life_situation`
- `conversations`, `messages`, `moderation_log`, `reports`, `verification_status`, `admin_users`
- Admin via `auth.users.raw_app_meta_data->>'role'` (JWT-checked)

## Carry-Over (Non-Blocking)
- 75+ deprecation `info` notices from `flutter analyze` — explicitly ignored per user
- `resetPasswordForEmail()` still uses deep-link redirect

## Required Migrations (in order)
001_admin_role.sql · 002_b1_database_foundation.sql · 003_b5_messaging.sql · 004_b6_block_report.sql · 005_b7_admin.sql · 006_b8_verification.sql · 007_b9_demo_seed.sql · 008_cleanup_legacy_demos.sql · 009_fix_demo_photo_urls.sql · 010_fix_profile_rls.sql · 011_admin_role_hierarchy.sql · 012_fix_duplicate_is_admin.sql · 013_fix_admin_review_verification_request.sql · 014_account_deletion.sql

## Critical Operating Rule (current)
**No new feature batches** until the user confirms Profile Detail, My Profile, and Admin all render correctly on the FullRepair-2026-06-30 build.
