# Next Chapter — Evolutionary Implementation Plan
## Beta 1.0 MVP · Supabase + Flutter · First 5 Batches

Decisions confirmed:
- **A. Evolve, do not rebuild.** Keep Supabase + Flutter foundation.
- **B. Yes:** Riverpod/freezed gradually, multi-mode (Date/Friend/Activity), Hinge prompts. **Later:** voice intros, Cloudflare, Sentry. **Not now:** Phoenix, Stytch, Persona, Stripe Identity, VA.gov, self-host PostHog.
- **C. Name: Next Chapter.** Retire ConnectUp / primio_app references.
- **D. Phased.** 12-week Beta 1.0 first; deeper architecture revisited months 4–9.

**Ground rules for every batch below:**
- No code or file edits until you approve the batch.
- Every DB migration written as additive SQL in a new file under `supabase/migrations/NNN_description.sql`; never edit existing migrations.
- Every batch ends with a hard **STOP** — I deliver the batch, you verify, you approve the next one.
- Tests live in `test/` (Flutter) and `supabase/tests/` (pgTAP for SQL). No batch is "done" until tests pass.
- Each batch is sized for **1–2 sprints** of one engineer (you, or me as your hands).

Risk legend: 🟢 Low · 🟡 Medium · 🔴 High

---

## Batch 1 — Security foundation & brand cleanup
*1 sprint · 🔴 High risk if skipped, 🟡 Medium risk to execute*

### Goal
Close the three P0 security holes from the audit, rotate exposed credentials, retire the dead/conflicting brand names, and put in place the safety nets every later batch depends on. Nothing user-facing changes visually except a logo/title rename. This is the batch where Next Chapter goes from "demo with privilege escalation" to "safe to test with real users".

### Specific outcomes
1. Anon key rotated; old key revoked in Supabase dashboard.
2. Credentials no longer in any committed file; loaded via `--dart-define` at build time.
3. Admin check moved from user-writable `user_metadata` to server-controlled `app_metadata` + a dedicated `admin_users` table with RLS.
4. `reports` and `profiles.is_suspended` RLS policies allow admin SELECT/UPDATE; admin actions write to a new `moderation_log`.
5. `verification_status.id_verified` / `selfie_verified` / `phone_verified` no longer user-writable (only service-role can flip them).
6. CAPTCHA enabled in Supabase Auth (hCaptcha, free).
7. Password minimum raised to 10 chars; Supabase project setting + client-side validator.
8. `app_config.dart` removed from working tree and from git history (`git filter-repo`); replaced by `--dart-define` build flags.
9. Diagnostics route (`/diagnostics`) gated behind `kDebugMode || isAdmin`.
10. App display name changed from `ConnectUp` / `primio_app` to `Next Chapter` in `pubspec.yaml`, `web/index.html`, `web/manifest.json`, `MaterialApp.title`, iOS/Android bundle (if mobile builds matter now).
11. Lockfile-of-truth: `analysis_options.yaml` added with `very_good_analysis` so the next batches are linted from day one.

### Files likely affected
- `lib/config/app_config.dart` — **deleted**.
- `lib/services/supabase_service.dart` — read from `String.fromEnvironment('SUPABASE_URL')` and `…ANON_KEY`; remove the file dependency.
- `lib/providers/auth_provider.dart` — `isAdmin` getter reads from `app_metadata` only; remove the hardcoded email check.
- `lib/main.dart` — title constant → 'Next Chapter'.
- `lib/router/app_router.dart` — restrict `/diagnostics` to debug or admin.
- `lib/screens/admin_screen.dart` — wire a real admin-check guard (still mock data this batch; that comes in Batch 3 of post-MVP roadmap).
- `lib/screens/auth_screen.dart` — password validator min length 10 + breached-password warning hint.
- `pubspec.yaml` — change `name:` to `next_chapter`; bump version to `1.0.0-beta.1+1`; add `analysis_options` setup; add `very_good_analysis` dev dep.
- `web/index.html`, `web/manifest.json` — title, short_name, theme color.
- `android/app/build.gradle` + `android/app/src/main/AndroidManifest.xml` — applicationId `app.nextchapter.android`, label `Next Chapter` (only if you intend to build Android in this batch; skip if web-only for now).
- `ios/Runner/Info.plist` — `CFBundleDisplayName` = Next Chapter (skip if iOS not built yet).
- `.gitignore` — keep `lib/config/app_config.dart` listed (defensive; file is deleted).
- New: `analysis_options.yaml`.
- New: `supabase/migrations/001_security_baseline.sql`.
- New: `docs/runbooks/key_rotation.md`.

### Database changes required
Single migration file `001_security_baseline.sql`:

1. Create `admin_users(user_id uuid PK references auth.users, role text check (role in ('moderator','admin','super_admin')), created_at, created_by)`.
2. Create a SECURITY DEFINER function `public.is_admin(uid uuid) returns boolean` that reads `admin_users`.
3. Replace `reports` policies: keep "users can insert reports" but add "admins can SELECT all reports" and "admins can UPDATE reports".
4. Add policy on `profiles`: "admins can UPDATE is_suspended".
5. Tighten `verification_status` policies: remove the user-writable `for all to authenticated`; replace with `for select to authenticated using (true)` and *no* user UPDATE/INSERT. Add `for all to service_role`.
6. Add table `moderation_log(id, actor_id, target_user_id, action text, reason text, created_at)` with RLS allowing admins SELECT, service_role INSERT.
7. Add CHECK constraint on `profiles.date_of_birth`: `date_of_birth <= now() - interval '18 years'`. (Existing rows: backfill or fail — schema allows nulls today so the check only bites when set.)
8. Add CHECK constraint `reports.reporter_id <> reports.reported_user_id`.
9. Add the storage bucket policies as actual SQL (today they live as comments in `supabase_schema.sql`). Ensures reproducible env setup.
10. (Optional but recommended) Seed the first row in `admin_users` for your own user with role `super_admin`.

### Risk level
🟡 **Medium.**
- Risk: a misconfigured RLS policy locks legitimate users out of their own data. Mitigation: every new policy is tested via pgTAP before merging; manual smoke test of every CRUD path in staging before production.
- Risk: key rotation breaks live sessions (none today since no users, but the muscle memory matters). Mitigation: run during a documented maintenance window; old key invalidated only after the new build is verified working.
- Risk: scrubbing `app_config.dart` from git history rewrites SHAs — anyone who has cloned the repo needs to re-clone. Mitigation: announce + force-push during the same window.

### Test plan
**SQL (pgTAP, lives in `supabase/tests/`):**
- A non-admin user CANNOT update another user's `profiles.is_suspended`. ✓ expected: 403.
- A non-admin user CANNOT update their own `verification_status.id_verified` from false to true. ✓ expected: 0 rows affected.
- An admin user CAN update `profiles.is_suspended`. ✓ expected: 1 row, audit row in `moderation_log`.
- A regular user CANNOT see another user's report. ✓ expected: 0 rows.
- An admin CAN see all reports. ✓ expected: N rows.
- A user CANNOT insert a report against themselves. ✓ expected: CHECK violation.
- A user with DoB < 18 years ago CANNOT be inserted into `profiles`. ✓ expected: CHECK violation.

**Flutter (widget + integration):**
- `auth_provider_test.dart`: `isAdmin` returns false when no `app_metadata.role`; true when set; **false even if `user_metadata.is_admin == true`**. (The killer test.)
- App boot test: when `SUPABASE_URL` not provided via `--dart-define`, the app shows the diagnostics error state (not silently uses mock).
- Login flow: 10-char password passes; 9-char password rejected with inline error.
- `/diagnostics` route: returns 404 / redirects in release build; accessible in debug build.

**Manual smoke (5-minute checklist, written into `docs/runbooks/batch_1_smoke.md`):**
- Build web with `--dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…` → loads.
- Sign up new user → email arrives → click confirm → can log in.
- Old key on Supabase dashboard → "Revoked" badge shown.
- App display name on browser tab is "Next Chapter".

### Stop point
**STOP after Batch 1.**
I will deliver:
- Migration file (review-ready).
- PR-shaped diff for the Flutter files (still no commit until you green-light).
- pgTAP test results.
- Updated `docs/runbooks/key_rotation.md`.
- A 5-minute video / GIF of the smoke test passing in staging.

**Your approval to look for:**
- Old anon key revoked? ✓
- `is_admin` cannot be self-set? ✓
- Display name is Next Chapter? ✓
- All pgTAP + Flutter tests green? ✓

Only after you say "Batch 1 approved" do I touch Batch 2.

---

## Batch 2 — Real onboarding, profile bootstrap, age & email gating
*1 sprint · 🟡 Medium risk*

### Goal
A new signup today lands on `/browse` with no profile, no photo, and an unverified email — they look like a bot to every other user. This batch turns signup into the actual product entry point: a guided 60–90 second wizard, with a DB trigger that materialises the user's `profiles` / `user_settings` / `verification_status` rows in one transaction at signup, and route-gating that prevents browsing until email is verified and the profile is minimally complete.

This is also where the **Date / Friend / Activity multi-mode toggle** is introduced as a first-class profile field — *cheap to add now, expensive to add later once messaging and matching depend on it*.

### Specific outcomes
1. Postgres trigger on `auth.users` insert auto-creates a `profiles` row, a `user_settings` row, and a `verification_status` row in one transaction.
2. Email confirmation **required** before `/browse` is reachable (currently the redirect just sends to `/browse`).
3. New onboarding flow at `/welcome` with 6 steps:
   1. Email confirmation reminder (skippable once confirmed).
   2. Name + DoB (DB CHECK age ≥ 18 hard-enforces).
   3. **Mode selection** — multi-select chips: Date, Friend, Activity Partner. At least one required.
   4. First photo upload (face-detection deferred to Batch 5; for now just "must be an image, ≤5 MB").
   5. Pick ≥1 looking_for, ≥3 interests, ≥1 life_situation.
   6. Review + "Go to Browse".
4. `/browse` redirect rule extended: if `isLoggedIn && !isEmailVerified` → `/verify-email`; if `…&& profile.completeness < 40` → `/welcome`.
5. **Profile completeness score** computed server-side and surfaced in a small ring icon on the user's avatar in the bottom nav.
6. Date-of-birth dropped from `auth.user_metadata` (it was duplicated there + writable by the user). Only the immutable `profiles.date_of_birth` survives.
7. Mode preference visible in profile detail; filterable in browse (browse server-side filtering is Batch 4, but the *field* must exist now).
8. The current `EditProfileScreen` becomes the post-onboarding edit surface (smaller, no wizard).

### Files likely affected
- New: `lib/screens/welcome/welcome_screen.dart` (host + progress bar).
- New: `lib/screens/welcome/step_*.dart` (one widget per step; lifts logic out of `edit_profile_screen.dart`).
- New: `lib/screens/verify_email_screen.dart` (inert "check your inbox; tap to refresh status" page).
- `lib/router/app_router.dart` — add `/welcome`, `/verify-email`; tighten redirect logic.
- `lib/providers/auth_provider.dart` — emit a stream/notifier for `isEmailVerified` so router auto-redirects on state change.
- `lib/providers/profile_provider.dart` — add `completenessScore` (computed locally for now; backend function in Batch 5).
- `lib/repositories/profile_repository.dart` — add a `fetchOrCreateProfile()` for the trigger-or-fallback path; do not duplicate inserts (idempotent).
- `lib/models/user_profile.dart` — add `modes: Set<ProfileMode>` enum field.
- `lib/screens/edit_profile_screen.dart` — slim down; mode toggle added; DoB no longer collected here (set in welcome only, immutable thereafter).
- `lib/screens/browse_screen.dart` — show "edit your modes" banner if zero modes selected.
- `lib/widgets/welcome/mode_picker.dart` — new shared widget (used in welcome and edit).
- New: `supabase/migrations/002_profile_bootstrap_and_modes.sql`.

### Database changes required
Single migration file `002_profile_bootstrap_and_modes.sql`:

1. Add column `profiles.modes text[] not null default array['date']::text[]` with CHECK `cardinality(modes) > 0` and CHECK `modes <@ array['date','friend','activity']`.
2. Add column `profiles.is_complete boolean not null default false` (set true by trigger when minimal fields populated).
3. Add column `profiles.completeness_score smallint not null default 0`.
4. Create trigger function `public.on_auth_user_created()`:
   - INSERT INTO `profiles` (user_id) with sensible defaults.
   - INSERT INTO `user_settings` (user_id).
   - INSERT INTO `verification_status` (profile_id) using the new profile's id.
   - Use SECURITY DEFINER so it bypasses RLS during creation.
5. CREATE TRIGGER `on_auth_user_created_trigger AFTER INSERT ON auth.users FOR EACH ROW EXECUTE PROCEDURE on_auth_user_created()`.
6. Create function `public.compute_profile_completeness(profile_id uuid) returns smallint` — runs the rubric (1 photo +20, about_me ≥ 50 +15, etc.). Called by Batch 5 properly; this batch just defines it.
7. Backfill: insert `profiles` / `user_settings` / `verification_status` for any existing `auth.users` rows that don't have them (idempotent `ON CONFLICT DO NOTHING`).
8. Index: `CREATE INDEX profiles_modes_gin ON profiles USING GIN (modes);` — Batch 4 will need it.

### Risk level
🟡 **Medium.**
- Risk: trigger throws on weird auth users (e.g., SSO without email metadata) → signup breaks silently. Mitigation: trigger is `SECURITY DEFINER` with explicit DEFAULTs for every column; exhaustive error handling that logs to a side table rather than aborting.
- Risk: router redirect loop if `isEmailVerified` flips slowly. Mitigation: only one redirect per navigation; rely on Supabase's `onAuthStateChange` to push, not on polling.
- Risk: DoB-removal-from-`user_metadata` invalidates older sessions that still cache it. Mitigation: `user_metadata.date_of_birth` is left in place for one batch; only the *write path* stops; cleanup is Batch 4.

### Test plan
**SQL (pgTAP):**
- INSERT into `auth.users` → `profiles`, `user_settings`, `verification_status` rows exist for that user_id, in 1 transaction. ✓
- INSERT into `profiles` with `modes = '{}'` → CHECK violation. ✓
- INSERT with `modes = '{date,foo}'` → CHECK violation. ✓
- `compute_profile_completeness` returns 0 for a fresh profile, 20 after 1 photo, etc. ✓
- Re-running migration is idempotent (no duplicate rows). ✓

**Flutter (widget + integration):**
- `welcome_flow_test.dart`: full 6-step happy path → profile saved → router lands on `/browse`. ✓
- `welcome_flow_test.dart`: under-18 DoB → step 2 inline error, cannot proceed. ✓
- `welcome_flow_test.dart`: unverified email → `/verify-email`, cannot bypass via direct URL. ✓
- `mode_picker_test.dart`: can't proceed with zero modes; can with any subset. ✓
- `router_redirect_test.dart`: logged-in + verified + incomplete profile → `/welcome`. ✓
- `router_redirect_test.dart`: logged-in + verified + complete profile → `/browse`. ✓

**Manual smoke (`docs/runbooks/batch_2_smoke.md`):**
- Fresh signup → email → confirm → wizard → arrive on Browse with profile visible.
- Refresh during wizard at step 4 → return to step 4 (state preserved).
- Try `/browse` directly while unconfirmed → bounced to `/verify-email`.

### Stop point
**STOP after Batch 2.**
Delivered: migration file, all new screens, updated router, all tests passing, video of the full onboarding flow.

**Your approval to look for:**
- Onboarding feels under 90 s on a real device? ✓
- Mode picker copy reads warm + plain (not "select your verticals")? ✓
- Email verification truly blocks bypass? ✓
- No flicker on router redirects? ✓

Only after "Batch 2 approved" do I touch Batch 3.

---

## Batch 3 — Real messaging (the headline feature)
*2 sprints · 🔴 High risk (largest single batch)*

### Goal
Replace the 100 %-mock messaging with real, durable, realtime, free messaging backed by Supabase Postgres and Supabase Realtime. This is the riskiest batch — it touches the schema, the realtime subsystem, the UI, the safety surface, and the push pipeline. We deliberately do *not* take on encrypted-at-rest or moderation pipelines in this batch; those are Batch 6 / Batch 8. We do enforce participant-level RLS, block enforcement, and basic spam guards.

### Specific outcomes
1. `conversations`, `conversation_participants`, `messages`, `message_reads` tables exist with strict participant-level RLS.
2. Sending a message persists it to Postgres and broadcasts via Supabase Realtime; recipient sees it ≤ 1 s end-to-end on a typical mobile connection.
3. Unread counts and conversation order are derived from real data, not mock.
4. Conversations have a `mode` enum (`date | friend | activity`) inherited from the first sender's mode at conversation creation.
5. A user can **request** a conversation with a single message; recipient sees it in the **Requests** tab until they reply (auto-promotes to Messages) or decline (auto-archives).
6. Blocking a user immediately tears down all open chat channels between the two, hides their conversations, and prevents new ones.
7. Per-user rate limit: max 60 messages / minute / sender, max 5 unanswered request messages to distinct users / hour (cheap anti-spam, server-enforced via a `messages_today` materialized view + trigger).
8. Push notifications via **OneSignal** (free up to 10 K subs) fire on new messages for offline recipients. Single one-line opt-in in Settings.
9. Offline send via **drift**-backed outbox: typed messages persist locally and replay on reconnect (introducing drift this batch since messaging is the natural home for it).
10. `MockDataService.conversations` and `getMessages` are deleted; build fails if anything imports them.

### Files likely affected
- `lib/providers/messages_provider.dart` — rewritten on top of a new `MessagesRepository` + Realtime subscription; mock paths removed.
- New: `lib/repositories/messages_repository.dart`.
- New: `lib/repositories/realtime_repository.dart` — owns the WSS connection lifecycle and channel registry; single source of truth for Realtime.
- `lib/screens/chat_screen.dart` — render from real data, optimistic insert, read-receipt animation, error pill on send failure.
- `lib/screens/messages_screen.dart` — tabs derive from real data; request acceptance one-tap.
- `lib/models/conversation.dart` — add `mode`, `acceptedAt`, `archivedAt`; introduce `Message` (renamed from `ChatMessage`) with `serverId`, `clientId`, `sentStatus` enum.
- `lib/services/mock_data_service.dart` — remove conversations/messages parts; leave the (also slated for removal) profile mocks for Batch 4 to clean up.
- New: `lib/services/outbox_db.dart` — drift schema for the outbox.
- New: `lib/services/push_service.dart` — thin wrapper over OneSignal Flutter SDK.
- `pubspec.yaml` — add `drift`, `drift_flutter`, `sqlite3_flutter_libs`, `onesignal_flutter`. Add `build_runner` + `drift_dev` to dev_deps.
- `lib/main.dart` — initialize drift before runApp; register `RealtimeRepository` + `PushService` in providers.
- `lib/router/app_router.dart` — deep link `/messages/:id` parses to real conversation id (UUID).
- `lib/screens/profile_detail_screen.dart` — "Message X — Free" CTA now creates a real `conversations` row + initial `messages` row, returns the new id.
- `lib/widgets/chat/message_bubble.dart` — read-state checkmark; show "couldn't send — tap to retry" on failure.
- New: `supabase/migrations/003_messaging_core.sql`.
- New: `supabase/migrations/004_messaging_rls_and_triggers.sql` (split because RLS is fiddly enough to deserve its own diff).
- New: Edge Function `supabase/functions/notify-on-message/index.ts` — receives Postgres webhook from `messages` insert, fans out push to recipients via OneSignal REST.

### Database changes required
**Migration `003_messaging_core.sql`:**
1. `conversations(id uuid pk, mode text check (mode in ('date','friend','activity')), is_request boolean not null default true, accepted_at timestamptz, archived_at timestamptz, last_message_at timestamptz not null default now(), created_at timestamptz not null default now(), created_by uuid not null references profiles(id))`.
2. `conversation_participants(conversation_id uuid references conversations on delete cascade, profile_id uuid references profiles on delete cascade, joined_at timestamptz default now(), muted_until timestamptz, last_read_at timestamptz default now(), primary key (conversation_id, profile_id))`.
3. `messages(id uuid pk default gen_random_uuid(), conversation_id uuid not null references conversations on delete cascade, sender_id uuid not null references profiles, client_message_id uuid not null, body text not null check (length(body) between 1 and 2000), kind text not null default 'text' check (kind in ('text','system')), created_at timestamptz not null default now(), edited_at timestamptz, deleted_at timestamptz, unique(conversation_id, client_message_id))`. Note `client_message_id` for idempotency.
4. `message_reads(message_id uuid references messages on delete cascade, reader_id uuid references profiles on delete cascade, read_at timestamptz not null default now(), primary key (message_id, reader_id))`.
5. Index: `messages(conversation_id, created_at DESC)` for the chat scroll query.
6. BRIN index: `messages(created_at)` — append-only table, BRIN is ~free.
7. Index: `conversations(last_message_at DESC)` for inbox order.
8. Trigger on `messages` insert: bumps `conversations.last_message_at`, promotes conversation from request to active if sender is not the conversation creator.
9. Enable Supabase Realtime publication on `messages` and `conversations` (`alter publication supabase_realtime add table messages, conversations`).

**Migration `004_messaging_rls_and_triggers.sql`:**
1. RLS on `conversations`: SELECT/UPDATE only if `auth.uid()` maps to a participant.
2. RLS on `conversation_participants`: same.
3. RLS on `messages`: SELECT/INSERT only if `auth.uid()` is a participant of the conversation; UPDATE (for `deleted_at`) only by sender; soft-delete only.
4. RLS on `message_reads`: INSERT only by `auth.uid() = reader_id` (via profiles mapping).
5. Trigger before INSERT on `messages`: reject if either participant has blocked the other (`blocks` table lookup) → raises a clean Postgres exception.
6. Trigger before INSERT on `messages`: enforce rate limits via a transactional row in `rate_limit_counters` table (helper table created here).
7. `rate_limit_counters(user_id, kind, minute_bucket, count)` with a function to atomically increment + check.
8. Function `public.conversation_for(other_profile_id uuid, mode text) returns conversations` — idempotent "get or create" used by the profile detail "Message" CTA so we don't create dupes.

### Risk level
🔴 **High.**
- Risk: Realtime backpressure under load → messages delivered out of order. Mitigation: client always renders by `created_at`, never by arrival order; server uses `nextval`-monotonic timestamps.
- Risk: an RLS oversight leaks a stranger's conversation. Mitigation: pgTAP covers 9 specific cases; security review checklist in `docs/runbooks/batch_3_security_review.md`.
- Risk: drift schema migration goes wrong on devices that already had a previous schema. Mitigation: drift's schema-version system handled explicitly; first release uses schema version 1.
- Risk: OneSignal-Edge-Function bridge silently fails → people don't get push. Mitigation: every push attempt logged to a `notification_attempts` table; admin sees failure rate; retries via Oban-equivalent (just `pg_cron` for now) on `attempted_at` < 5 min.
- Risk: rate limiter false-positives on bursty real conversations. Mitigation: limits are deliberately loose (60/min); we monitor false-positive ratio before tightening.

### Test plan
**SQL (pgTAP):**
- User A inserts a `messages` row in a conversation she participates in. ✓
- User A inserts a `messages` row in a conversation she does *not* participate in. ✗ (RLS denies).
- User A inserts a `messages` row from a conversation she's in, claiming `sender_id` is User B. ✗ (RLS denies).
- User A blocks User B; both pre-block messages remain visible to A; B trying to insert a new message → trigger exception.
- Duplicate `client_message_id` insert → ON CONFLICT returns the original row (idempotency).
- Rate limit: 61st message within 60 s → trigger exception with `rate_limit_exceeded` error code.
- `conversation_for(other_profile, 'date')` called twice → returns same conversation id (idempotency).

**Flutter:**
- `messages_repository_test.dart`: send → row inserted → realtime callback fires → provider state updated.
- `outbox_test.dart`: airplane-mode send → row in drift → reconnect → row flushed → drift row deleted.
- `chat_screen_widget_test.dart`: send shows checkmark progression (sending → sent → read).
- `block_enforcement_test.dart`: blocking a user removes the conversation from the inbox and chat-screen-bound deep-link returns "this conversation is unavailable".
- `push_service_test.dart`: opting in registers the OneSignal subscription; opting out deregisters.

**Manual smoke (`docs/runbooks/batch_3_smoke.md`):**
- Two browsers, two accounts. A messages B. B sees within 2 s. Read receipt fires within 1 s of B opening.
- A goes airplane → types 3 messages → re-enables network → 3 messages flush in order.
- A blocks B. B's conversation disappears from A's list. B trying to send: in-app error pill "you can't message this user".
- Background push: with the app closed on iOS Safari + Android Chrome, a sent message rings the push.

### Stop point
**STOP after Batch 3.**
Delivered: two migrations, the Edge Function, drift schema v1, all new Flutter files, a short demo video with two browsers chatting end-to-end, and a security review checklist signed off by you.

**Your approval to look for:**
- End-to-end message delivery < 2 s? ✓
- Airplane-mode resilience demonstrated? ✓
- Blocking truly stops new messages? ✓
- pgTAP RLS suite all green? ✓
- Push fires on a real device? ✓

Only after "Batch 3 approved" do I touch Batch 4.

---

## Batch 4 — Server-side browse, multi-mode discovery, geo & block enforcement
*1–2 sprints · 🟡 Medium risk*

### Goal
Stop loading every profile into the client. Move filtering, sorting, and pagination to the server via a Postgres function and PostgREST RPC. Introduce **distance-based browse** (PostGIS) using a coarse city-centroid geocoder. Honour the multi-mode field from Batch 2 so that the user sees Date / Friend / Activity feeds independently. Enforce blocks server-side at the query level (today the table exists but nothing uses it).

This batch also retires the last of `MockDataService` — after it lands, the only thing the file should contain is the `usStates` constant.

### Specific outcomes
1. New Postgres function `browse_feed(viewer_id, mode, filters jsonb, cursor jsonb, limit int)` returning ranked, paginated, block-filtered results.
2. `BrowseProvider` calls the RPC instead of fetching all rows; infinite scroll via cursor.
3. `profile_geo` table holds a city-centroid `geography(point,4326)` per profile (geocoded once via a one-off Edge Function call against a free provider — Nominatim with caching, or a free Mapbox tier).
4. Distance filter chip: 25 / 50 / 100 / 250 mi / Anywhere; default 100 mi.
5. Mode tabs on top of Browse: Date / Friend / Activity — independent feeds, sharing filters.
6. Browse results exclude: self, blocked-either-direction, suspended, deleted, not-yet-completed (`is_complete = false`).
7. The "Has things in common" sort option (audit recommendation): toggle sort between `recommended` (default) and `most_in_common`.
8. `lib/services/mock_data_service.dart` reduced to a single `usStates` constant; all other references removed.
9. New simple **trust score** column on `profiles` (`smallint`, 0–100), computed nightly by a `pg_cron` job — used as a tie-breaker in browse ranking, never user-visible.
10. Edit Profile gets a "Location" panel where user can confirm or correct city / state; geocoder runs on save.

### Files likely affected
- New: `lib/repositories/browse_repository.dart` — single RPC call wrapper.
- `lib/providers/browse_provider.dart` — rewritten around cursor pagination, mode tab, server-driven filters.
- `lib/screens/browse_screen.dart` — mode tab strip above grid; distance chip in filter sheet; infinite scroll via `scroll_to_index` + `provider.loadNext()`.
- `lib/widgets/common/filter_sheet.dart` — distance slider, mode-aware (e.g., "Looking for" chips hide in Activity mode).
- `lib/services/mock_data_service.dart` — trim to `usStates` only.
- `lib/repositories/profile_repository.dart` — remove `fetchAllProfiles` (browse goes through RPC now).
- New: `supabase/migrations/005_geo_and_browse.sql`.
- New: `supabase/functions/geocode-profile/index.ts` (Edge Function called on profile save with city/state).
- New: `supabase/cron/nightly_trust_scores.sql` (runs every 24 h via pg_cron).
- `pubspec.yaml` — no new packages strictly required; consider `infinite_scroll_pagination` for a cleaner pager.

### Database changes required
**Migration `005_geo_and_browse.sql`:**
1. `CREATE EXTENSION IF NOT EXISTS postgis;`
2. `profile_geo(profile_id uuid pk references profiles on delete cascade, location geography(point,4326), city_label text, region_label text, geocoded_at timestamptz)`. Public-readable; user-writable only via service-role through Edge Function.
3. `CREATE INDEX profile_geo_location_gix ON profile_geo USING GIST (location);`
4. `profiles.trust_score smallint not null default 0`.
5. `CREATE INDEX profiles_browse_partial ON profiles (last_active DESC) WHERE is_complete = true AND is_suspended = false AND is_deleted = false;`
6. Function `browse_feed(viewer_id uuid, mode text, filters jsonb, cursor jsonb, lim int)`:
   - Subqueries out: blocked users (either direction), self, suspended, deleted, incomplete.
   - Filter by mode (`profiles.modes @> array[mode]`).
   - Optional filters: age range, looking_for overlap, interests overlap, life_situation overlap, verified-only, max_distance_km.
   - Order by computed `score = 0.35*lookingFor_overlap + 0.20*lifeSituation_overlap + 0.15*interests_overlap + 0.10*geo_decay + 0.05*verification_strength + 0.05*recency + 0.10*trust_score/100`.
   - Cursor: `(score, profile_id)` keyset pagination.
   - Return: page of profile rows + a serializable next-cursor jsonb.
7. Function `most_in_common_feed(...)` with same args but sorted by `overlap_count` descending — implementation calls `browse_feed` internally with a sort flag.
8. Function `nightly_recompute_trust_scores()` — bumps `trust_score` from a transparent formula (verifications, account age in days, report ratio, block-against ratio). Schedule via `pg_cron.schedule`.

### Risk level
🟡 **Medium.**
- Risk: `browse_feed` is slow at scale. Mitigation: explain-analyze on a synthetic 100 K-row dataset before merge; partial indexes already sized for the hot path; query plan reviewed.
- Risk: geocoder API rate limits during initial backfill. Mitigation: queue, exponential backoff, 1 req/s default; backfill via a `pg_cron` job over a week rather than synchronously.
- Risk: `infinite_scroll_pagination` doesn't play well with Riverpod yet. Mitigation: a small custom pager keeps the dependency footprint smaller; revisit if it becomes a maintenance burden.
- Risk: changing browse ranking is an emotional change — early users may feel the feed "got worse". Mitigation: keep a feature flag (`use_server_feed`) on for staff, default off for first 7 days, then ramp.

### Test plan
**SQL (pgTAP):**
- `browse_feed(viewer)` excludes viewer's own profile. ✓
- `browse_feed` excludes profiles where viewer is in `blocks.blocked_id` or `blocks.blocker_id`. ✓
- `browse_feed(viewer, 'date', ...)` returns only profiles where `'date' = ANY(modes)`. ✓
- `browse_feed` returns at most `lim` rows; subsequent call with returned cursor returns the next page non-overlapping.
- Distance filter with `max_distance_km = 50` excludes profiles beyond 50 km (using PostGIS `ST_DWithin`).
- `most_in_common_feed` sort is stable.
- `nightly_recompute_trust_scores` is idempotent.

**Flutter:**
- `browse_repository_test.dart`: RPC returns 20 rows; subsequent call with cursor returns next 20.
- `browse_provider_test.dart`: switching mode tab resets cursor; switching filters resets cursor.
- `browse_screen_widget_test.dart`: scrolling to bottom triggers `loadNext`; no duplicate cards.
- `filter_sheet_widget_test.dart`: setting distance to 25 mi reduces visible count compared to Anywhere.

**Manual smoke (`docs/runbooks/batch_4_smoke.md`):**
- Switch Date → Friend tab → grid reloads with different profile set.
- Block a profile → it disappears from browse on next refresh.
- Distance filter from "Anywhere" to "25 mi" near Austin → only Texas-ish results.
- Scroll 80 cards deep → no jank, no duplicates.

### Stop point
**STOP after Batch 4.**
Delivered: migration, edge function, cron job, all repository + provider rewrites, all tests, video of multi-mode browse with distance filter applied.

**Your approval to look for:**
- Mode tabs feel natural? ✓
- Geocoder backfilled correctly for existing seed accounts? ✓
- Block enforcement works end to end? ✓
- No more `MockDataService` references in user-facing code paths? ✓
- Browse latency P50 < 250 ms on staging? ✓

Only after "Batch 4 approved" do I touch Batch 5.

---

## Batch 5 — Profile system upgrade: prompts, photo moderation, completeness, polymorphic tags
*1–2 sprints · 🟡 Medium risk*

### Goal
Turn the profile from "filled-in form" into a "story you've told". Adopt Hinge-style **prompts** (the single highest-ROI feature for an older audience that has stories but struggles with blank bios). Collapse the three near-identical tag tables into a single polymorphic table — making future tag categories (languages, dealbreakers, dietary, etc.) free. Wire **server-side photo moderation** at upload time via Sightengine's free tier (500 ops/month free; we will not exceed this in beta). Make the **profile completeness score** real and visible — a soft nudge to fill out more.

Voice intros are explicitly **deferred** (per your decision); the schema reserves room for them so we don't have to migrate later.

### Specific outcomes
1. `profile_tags` polymorphic table replaces the three child tables. Old tables left in place this batch (read-only fallback); new code reads/writes only `profile_tags`. Cleanup migration in Batch 6.
2. `profile_prompts` table — 3 prompts per profile, chosen from a curated set of ~40 prompt keys; user provides the answer (≤150 chars each).
3. Edit-profile UI gets a new **Prompts** section. Prompt picker shows 6 suggestions tailored to the user's selected life_situation tags ("If you're newly retired, you might enjoy…").
4. Profile detail screen renders prompts inline (newspaper-style: question in small caps, answer in serif italic). Big visual win for free.
5. Photo upload now hits a Supabase Edge Function `moderate-photo` which calls Sightengine; only photos that pass go to storage. Failures show "this photo couldn't be accepted — please choose another" with a polite reason.
6. `profile_photos.moderation_status` and `nsfw_score` columns added.
7. `profile.completeness_score` (column already exists from Batch 2) is recomputed on every save via the function added in Batch 2; surfaced as a ring on the user's avatar (e.g., 70% full ring around their photo in the nav).
8. A small "+15% if you add a prompt" hint on the Edit Profile page; tappable shortcut.
9. The schema reserves: `profile_voice_intros` table created empty + RLS; column on `profile_prompts.is_voice` reserved. No client UI yet. (Means Batch 11 voice-intro work won't require migration.)

### Files likely affected
- New: `lib/widgets/profile/prompt_picker.dart` — bottom sheet with the curated set.
- New: `lib/widgets/profile/prompt_card.dart` — render of a single prompt+answer on profile detail.
- `lib/screens/edit_profile_screen.dart` — Prompts section added; tag-handling code switched to talk to `profile_tags`.
- `lib/screens/profile_detail_screen.dart` — Prompts section between About Me and Looking For.
- `lib/models/user_profile.dart` — add `prompts: List<PromptAnswer>`; `tags` getter that maps to old field names for compatibility.
- New: `lib/models/prompt.dart` (freezed).
- New: `lib/data/prompts_catalog.dart` — the ~40 curated prompt strings, with metadata (`life_situation_hints: ['Recently Relocated', …]`, `mode_hints: ['date','friend']`).
- `lib/repositories/profile_repository.dart` — read/write `profile_tags` and `profile_prompts`; read fallback also queries the old tag tables for not-yet-migrated profiles (Batch 6 finishes the migration).
- `lib/repositories/photo_repository.dart` — upload now invokes the moderation Edge Function pre-storage-upload; on `accepted=false` returns the human-readable reason.
- New: `supabase/functions/moderate-photo/index.ts` — calls Sightengine, returns verdict.
- New: `supabase/migrations/006_polymorphic_tags_and_prompts.sql`.
- (Optional) `lib/widgets/avatar_with_completeness.dart` — reusable ring widget.

### Database changes required
**Migration `006_polymorphic_tags_and_prompts.sql`:**
1. `profile_tags(id uuid pk, profile_id uuid references profiles on delete cascade, kind text not null check (kind in ('interest','looking_for','life_situation','language','dealbreaker','dietary')), value text not null, position smallint not null default 0, created_at timestamptz default now(), unique(profile_id, kind, value))`.
2. GIN index on `(kind, value)`.
3. `profile_prompts(id uuid pk, profile_id uuid references profiles on delete cascade, prompt_key text not null, answer text not null check (length(answer) between 1 and 150), is_voice boolean not null default false, position smallint not null default 0, created_at timestamptz default now(), unique(profile_id, position))`.
4. RLS: `profile_tags` and `profile_prompts` — SELECT to authenticated true; INSERT/UPDATE/DELETE only by row's profile owner.
5. Add columns to `profile_photos`: `moderation_status text not null default 'pending' check (in ('pending','approved','rejected'))`, `nsfw_score numeric(3,2)`, `face_count smallint default 0`.
6. Add SELECT clause to `profile_photos` RLS: only `moderation_status='approved'` photos visible to non-owners (owners see all of their own).
7. `profile_voice_intros(id uuid pk, profile_id uuid references profiles on delete cascade, storage_path text not null, duration_ms int, transcript text, created_at timestamptz default now())` — empty table, RLS owner-only. Reserved.
8. Backfill: copy existing `profile_interests` → `profile_tags(kind='interest')`, `profile_looking_for` → `profile_tags(kind='looking_for')`, `profile_life_situation` → `profile_tags(kind='life_situation')`. (Old tables remain; Batch 6 cleans them up after we verify zero reads against them.)
9. Re-implement `compute_profile_completeness` to count prompts (+10 each, capped at 30) and verified flags.

### Risk level
🟡 **Medium.**
- Risk: dual-source-of-truth period (old tag tables + new `profile_tags`) creates drift. Mitigation: writes go only to the new table; old tables become read-only as of this batch via revoked INSERT/UPDATE privileges; Batch 6 drops them.
- Risk: Sightengine free tier rate limit (~500/mo) exceeded in beta. Mitigation: cache by image hash; admin alert at 80% consumed; ready-to-flip toggle to paid tier ($30/mo for 5,000 ops).
- Risk: prompt picker analysis-paralysis at the 18-100 audience extremes. Mitigation: catalog uses **everyday language**, no jargon; "skip" always available; tailored suggestions per life_situation; copy A/B-able later.

### Test plan
**SQL (pgTAP):**
- INSERT into `profile_tags` with `kind='foo'` → CHECK violation.
- INSERT 4th prompt for a profile that already has 3 in positions 1-3 → unique-violation if position duplicated.
- A user can SELECT another user's `profile_tags` and `profile_prompts`. ✓
- A user CANNOT INSERT into another user's `profile_tags`. ✗
- A rejected photo (moderation_status='rejected') is NOT visible to non-owners. ✓
- Backfill: every row in `profile_interests` has a corresponding `profile_tags(kind='interest')` row.
- `compute_profile_completeness` for a profile with 3 prompts, 1 photo, 4 interests, no verification = 75 (per the rubric).

**Flutter:**
- `prompt_picker_test.dart`: shows life-situation-tailored prompts above default ones; picking one closes sheet + sets state.
- `edit_profile_test.dart`: saving with 3 prompts persists; reopening shows them.
- `profile_detail_test.dart`: prompt section renders only when prompts exist; hides cleanly otherwise.
- `photo_upload_test.dart`: mock Sightengine accepts → file lands in storage; mock rejects → no file uploaded, error pill shown with reason.
- `completeness_ring_widget_test.dart`: 0% renders empty ring; 50% half; 100% solid with check.

**Manual smoke (`docs/runbooks/batch_5_smoke.md`):**
- Edit profile → add 3 prompts → view own profile → prompts render in serif italic.
- Upload a known-NSFW test image → rejected gracefully.
- Upload a normal photo → accepted; appears in profile.
- Completeness ring updates live as user adds fields.
- Old profile (pre-Batch 6) loads correctly via fallback read of old tag tables.

### Stop point
**STOP after Batch 5.**
Delivered: migration, moderation edge function, prompts catalog, updated profile screens, tests, video of the prompt picker + photo moderation working.

**Your approval to look for:**
- Prompts read warm and on-brand? ✓
- Profile detail visually noticeably better? ✓
- Photo moderation rejects NSFW reliably without false-positives on normal faces? ✓
- Completeness ring is encouraging (not nagging)? ✓
- No regressions on Batches 1–4? ✓

Only after "Batch 5 approved" do I plan Batches 6–10 (cleanup of old tag tables, real admin app, push notifications stack expansion, verification flows, privacy ledger, hard-delete pipeline, safety check-ins, accessibility audit, beta-launch polish).

---

## Summary of where we are after Batch 5

| Subsystem | State |
|---|---|
| Security | All P0s closed. Admin role server-controlled. CAPTCHA on. Audit + moderation log tables in place. |
| Brand | "Next Chapter" everywhere. |
| Auth | Email + password with proper gating; 10-char min; passkeys + social deferred to Batch 8+. |
| Onboarding | Real 6-step wizard. DB trigger bootstraps every new user. Email gate enforced. |
| Profile | Polymorphic tags. Hinge prompts. Photo moderation at upload. Completeness ring visible. Voice intro reserved. |
| Browse | Server-side, paginated, ranked, geo-aware, multi-mode, block-aware. |
| Messaging | Real schema + Realtime + outbox + push. Free unlimited, rate-limited against spam, RLS-secured. |
| Admin | Still mock (Batch 6 makes real). |
| Verification | Flags exist server-controlled; flows are Batch 7. |
| Notifications | Push works; full preference UI is Batch 8. |
| Privacy / hard delete | Schema-ready (audit_log, moderation_log); pipeline is Batch 9. |
| Safety features | Schema-ready; check-ins are Batch 10. |
| Accessibility | Treated as a cross-cutting concern in every batch; full audit + remediation is Batch 11. |
| Monetization | None yet. First paid SKU (verification badge bundle) is Batch 7. |

After Batch 5 you have a real, working, free-messaging dating + friendship product running on Supabase, suitable for invite-only beta with ~500 users. Batches 6–10 add the rest of Beta 1.0.

---

## What I need from you now

A simple yes/no on each:

1. **Approve this 5-batch shape and ordering?** If you want to reorder (e.g., do verification before browse), say which and I'll re-sequence.
2. **OK to introduce drift in Batch 3** as the outbox/offline-cache layer? (Otherwise we lose offline-resilient messaging.)
3. **OK to introduce OneSignal in Batch 3** for push? (Free up to 10 K subs; we can swap for FCM-direct later. Alternative: roll our own Edge Function + APNs/FCM, +2 days of work.)
4. **OK to introduce Sightengine in Batch 5** for photo moderation? (Free tier 500 ops/month is fine for beta. Alternative: defer photo moderation to post-launch and rely on user reports only — risky for an 18-100 brand.)
5. **OK to set aside ~$50/mo** in beta for: Supabase Pro upgrade ($25), OneSignal free, Sightengine free, optional Mapbox geocoder free, optional Resend free? Pro alone is non-negotiable once you have >100 users because Free tier Storage caps at 1 GB.
6. **Engineering hands** — am I doing the actual work, or are you pairing me with another engineer? Affects whether the 5 batches are 8–10 calendar weeks (solo) or 5–6 weeks (paired).

Once you answer those six, I'll move on Batch 1. No code lands until then.

— end of evolutionary plan —
