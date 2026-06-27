# Next Chapter — Product Requirements Document

## Original Problem Statement
Initial: Perform a full architectural audit of the Next Chapter (formerly ConnectUp) Flutter project — security, DB design, Supabase integration, and feature parity vs. major dating platforms.

Pivot: Build the app in **12 feature batches**. NO step-by-step testing. Run **one** complete end-to-end test after Batch B12.

## Product Goals (Beta 1.0)
- 100% free messaging, privacy-first dating + friendship platform (ages 18–100)
- Stack: Flutter + Supabase Free tier (no Drift, no OneSignal, no Sightengine)
- Core flows: Email Auth, Onboarding Wizard, Real Browse/Search, Real Messaging, Block/Report, Hidden Admin route, Verification UI, Account deletion, Monetization placeholders

## Architecture
- Flutter Web/Mobile frontend (`/app/nextchapter_audit/src/lib/`)
- Supabase: Auth, Postgres, Storage (`profile-photos` bucket), Realtime
- State: Provider (Riverpod migration deferred to post-Beta)
- Routing: GoRouter
- Secrets via `--dart-define` (SUPABASE_URL, SUPABASE_ANON_KEY, APP_URL)

## Build Checklist (12 Batches)
- [x] **B1** Security + DB foundation — admin role hardening, RLS, 002 migration ✅
- [x] **B2** Onboarding Wizard — 9-step `/welcome` flow ✅
- [x] **B3** Profiles & Photos — photo upload/delete, prompts, modes, completeness ring, real Profile Detail ✅ (2026-02)
- [x] **B4** Browse + filters — real Supabase queries, modes filter, hide incomplete/suspended/deleted, server-side state/age/modes filtering ✅ (2026-02)
- [ ] **B5** Messaging (conversations, threads, Supabase realtime)
- [ ] **B6** Block & report enforcement
- [ ] **B7** Admin (real users list, suspend/delete, reports queue, metrics)
- [ ] **B8** Verification UI (status + placeholder screens)
- [ ] **B9** Demo community seed (6 SQL profiles + sample photos)
- [ ] **B10** Privacy, safety, account deletion pipeline
- [ ] **B11** Monetization placeholders (ad slot, donation tile)
- [ ] **B12** End-to-end smoke test + polish

## Key Files
- `lib/models/user_profile.dart` — UserProfile + completeness calculator
- `lib/providers/profile_provider.dart` — Save, photo upload/delete, prompts
- `lib/repositories/profile_repository.dart` — Supabase data access
- `lib/repositories/photo_repository.dart` — Storage `profile-photos` bucket
- `lib/screens/edit_profile_screen.dart` — Edit form with modes, prompts, completeness
- `lib/screens/profile_detail_screen.dart` — Real profile view (photos carousel, modes, prompts)
- `lib/widgets/common/completeness_ring.dart`
- `lib/data/prompts_catalog.dart` — 40 Hinge-style prompts
- `supabase/migrations/001_admin_role.sql` (executed)
- `supabase/migrations/002_b1_database_foundation.sql` (executed)

## DB Schema Highlights
- `profiles` (id, user_id, modes text[], is_complete, completeness_score, 18+ check)
- `profile_prompts` (profile_id, prompt_key, answer, position)
- `profile_photos` (profile_id, storage_path, display_url, display_order)
- `conversations`, `messages`, `moderation_log`
- Admin via `auth.users.raw_app_meta_data->>'role'`

## Carry-Over (Non-Blocking)
- 56 deprecation `info` notices from `flutter analyze` — user opted to ignore
- `resetPasswordForEmail()` still uses deep-link redirect (revisit if web URL needed)

## Critical Operating Rule
**Do NOT stop for testing/approval between batches except after each batch is complete.** User wants approval only between batches; one E2E test at B12.
