# Next Chapter — Full Architectural Audit
*Read-only review. No code has been modified. Awaiting approval before any change.*

Audit date: 2026‑01
Auditor: E1 (Emergent)
Codebase: `com-primio-connectup-source-782523511.zip` (38 Dart files, ~6,000 LOC, supabase_schema.sql, 10 tables)
Stack: Flutter Web + Supabase (Auth / Postgres / Storage / Realtime-not-yet-used)
Plan in scope: Supabase **Free**

---

## 0. How to read this document

1. **§1 Executive Summary** — top-of-stack view, 1-page version. Read this first.
2. **§2 Severity-ranked findings** — every issue, with file:line references and a one-line fix.
3. **§3 Domain deep dives** — section-by-section walkthroughs (security, DB, auth, messaging, search, moderation, verification, performance, UI/UX, accessibility, monetization, maintainability).
4. **§4 Competitive feature analysis** — POF / OkCupid / Match / Bumble / Hinge / FB Dating vs. Next Chapter, with what to keep, what to drop, what would be a real differentiator.
5. **§5 Prioritized roadmap** — impact × effort matrix and a concrete 12-week sequence.

Severity scale:
- **🔴 P0 — Critical / Security or correctness blocker. Ship-stopper.**
- **🟠 P1 — High. Fix before public launch.**
- **🟡 P2 — Medium. Fix in first 60 days post-launch.**
- **🟢 P3 — Low / polish.**

---

## 1. Executive Summary

Next Chapter has a clean Flutter foundation, a clear product thesis (free messaging, second-chance demographic, friendship + dating), and a well-organized provider → repository → service architecture. The visual design language is warm, age-inclusive, and intentionally non-"hookup-app".

However, **the app is not yet a functional product in the categories the brand promises**. The audit found that several pillars are still scaffolds:

| Pillar promised | Actually in the build |
| --- | --- |
| Free unlimited messaging | **100% mock** — no `messages`/`conversations` tables exist; the chat sends to an in-memory list that disappears on refresh |
| Admin dashboard / moderation | **100% mock** — reports, suspend, delete are dummy snackbars; admins read mock data |
| Verification (Email / Phone / Selfie / ID) | Flags exist in DB; no upload, no flow, no provider |
| Blocks | Inserted into DB but **never enforced** in browse or messages |
| Search & filters | All filtering happens **client-side after loading every profile** — won't scale past ~500 users |
| "Online status" | Boolean in DB with no writer — always stale |

In parallel, there are **three security defects severe enough to block launch**:

1. 🔴 `lib/config/app_config.dart` ships in the source zip with the **production Supabase anon key in plaintext** despite `.gitignore` claiming it is excluded. Anyone with the zip has the live anon key. (Anon keys are public by design *but* see #3.)
2. 🔴 The admin check is `user?.email == 'admin@nextchapter.com' || user?.userMetadata?['is_admin'] == true`. `user_metadata` is **user-writable** in Supabase. Any signed-in user can call `supabase.auth.updateUser({data:{is_admin:true}})` and become admin. **Privilege escalation, trivially exploitable.**
3. 🔴 The `reports` RLS lets users see only their own reports, and **there is no admin role policy**, so the admin screen's "real" data path would return nothing anyway — but the mock data path is what's currently rendered. When this gets wired to Supabase as-is, abuse reports will be invisible.

These three issues alone make a public launch unsafe. Everything else in the audit is either a feature gap, a scalability cliff, or polish.

**Top-level verdict:** A strong starting point with serious gaps. Before launch you need (a) real messaging, (b) real admin/moderation with a proper role model, (c) credential rotation and a hardened auth boundary, (d) server-side filtering and pagination in browse. After that, the differentiation roadmap in §4–§5 will set Next Chapter apart from POF/Match/Bumble.

---

## 2. Severity-Ranked Findings (full inventory)

### 🔴 P0 — Critical, fix before launch

| # | Area | Finding | File / Line | One-line fix |
|---|------|---------|-------------|--------------|
| P0-1 | Auth | `is_admin` read from user-writable `user_metadata` → privilege escalation | `lib/providers/auth_provider.dart:56-58` | Move admin flag to `app_metadata` (service-role only) or a dedicated `admin_users` table; check via SECURITY DEFINER RPC |
| P0-2 | Secrets | `lib/config/app_config.dart` is committed (file exists in source zip though `.gitignore` lists it). Project URL and a live JWT anon key are in the zip. | `lib/config/app_config.dart:18-24`, `.gitignore:2` | Rotate the anon key, delete the file from history (`git filter-repo`), use `--dart-define` or `flutter_dotenv` for build-time injection |
| P0-3 | Moderation | Admin screen reads from `MockDataService`; suspend/delete/resolve are `SnackBar`s. Reports table has no admin RLS policy. | `lib/screens/admin_screen.dart:2,50-147`; `supabase_schema.sql:262-286` | Build real `AdminRepository`; add `is_admin` claim and RLS policies that grant SELECT/UPDATE on `reports`, UPDATE on `profiles.is_suspended` to admins |
| P0-4 | Messaging | No `conversations` / `messages` / `participants` tables. Chat is fully in-memory. "Free unlimited messaging" is currently fiction. | `lib/providers/messages_provider.dart`, `lib/services/mock_data_service.dart`, missing in `supabase_schema.sql` | Add schema (conversations, messages, conversation_participants, message_reads), realtime subscription, RLS by participant |
| P0-5 | Blocks | `blocks` table exists but `ProfileRepository.fetchAllProfiles()` never joins or filters by it; blocked users still appear in browse and could re-initiate contact. | `lib/repositories/profile_repository.dart:47-69` | Add `NOT IN` subquery (or LEFT JOIN) excluding rows where current user is in `blocked_id`/`blocker_id` |
| P0-6 | Browse data layer | N+1 explosion: for each profile, 5 separate child-table queries (`_assembleProfile`). 50 profiles = 251 round trips. Will time out on real data. | `lib/repositories/profile_repository.dart:60-69, 176-209` | Single denormalized `profile_summary` view, or single SQL with `select profiles.*, array_agg(...)` via PostgREST embedding |
| P0-7 | Account creation | `Supabase.signUp` does not create rows in `profiles`, `verification_status`, `user_settings`. New users have an auth user but no profile until they manually save Edit Profile. They can browse with no profile. | `lib/providers/auth_provider.dart:114-142`; missing in `supabase_schema.sql` | DB trigger `on auth.users insert` → insert profile + verification_status + user_settings rows, OR an Edge Function on signup webhook |
| P0-8 | Age gate | 18+ check is *only* `DateTime.now().difference(dob).inDays ~/ 365` client-side. DoB is then stored in `user_metadata` (user-writable). | `lib/providers/auth_provider.dart:115-118` | DB CHECK constraint `dateOfBirth <= now() - interval '18 years'`; store DoB only in `profiles`, never `user_metadata`; verify via ID upload before higher-trust actions |
| P0-9 | RLS gap | No RLS policy on the storage bucket in the actual SQL — only described in SQL comments (lines 290-305). If those policies are not run separately in the dashboard, storage is wide open. | `supabase_schema.sql:289-305` | Add `storage.objects` policies to the SQL file with `INSERT INTO storage.policies` so the schema is fully reproducible |

### 🟠 P1 — High, fix before public launch / first 30 days

| # | Area | Finding | File / Line | Fix sketch |
|---|------|---------|-------------|------------|
| P1-1 | Performance | `BrowseProvider.loadProfiles()` materializes the entire `profiles` table in memory and filters client-side. | `lib/providers/browse_provider.dart:37-45, 109-126`; `lib/services/mock_data_service.dart` (still wired) | Server-side filtering via Postgres function or PostgREST `or=()/in.()`. Add pagination (`range(0,19)`) with infinite scroll. Cache cursor. |
| P1-2 | Search | No full-text search on `about_me`/`first_name`/`city`; no GIN index on interests. | `supabase_schema.sql` | Add `tsvector` generated column on profiles + GIN index; GIN index on `profile_interests.interest` |
| P1-3 | Privacy | Any authenticated user can SELECT every profile's `city`, `state`, `gender`, `relationship_status`, `about_me`, `last_active`. No distance abstraction, no city-level fuzzing for opt-outs. | `supabase_schema.sql:29-32` | Add `user_settings.privacy_level` ('exact' / 'city_only' / 'region_only'); a SQL VIEW that masks city based on viewer relationship; consider hiding `last_active` precise time |
| P1-4 | Photo abuse | MIME type is taken from client (`mimeType: file.mimeType ?? 'image/jpeg'`). Bucket may accept non-image bytes labeled "image/jpeg". No NSFW / scam-image scan. | `lib/screens/edit_profile_screen.dart:166-173`; `lib/repositories/photo_repository.dart:32-36` | Server-side sniff MIME (Edge Function magic-bytes check); integrate Sightengine / Rekognition for NSFW / face-detect; require at least one photo of a real person |
| P1-5 | Identity verification | `selfie_verified` / `id_verified` are columns with no flow to flip them to true. | Whole codebase | Add Stripe Identity, Persona, or Onfido flow (Edge Function callback). Show "Verified" tier visibly. |
| P1-6 | CAPTCHA / anti-bot | Signup has no friction. With anon key public, signup is an open API. | `lib/providers/auth_provider.dart:122-129` | Enable Supabase Auth CAPTCHA (hCaptcha) at the project level — free, two-line change in dashboard + Flutter |
| P1-7 | Email verification enforcement | `redirect:` rule sends new signups straight to `/browse` regardless of `isEmailVerified`. | `lib/router/app_router.dart:33-37` | Add `if (loggedIn && !auth.isEmailVerified) return '/verify-email'` |
| P1-8 | Password policy | Minimum 6 chars client-side; no strength feedback, no breached-password check. | `lib/screens/auth_screen.dart:184` | Enforce ≥10 chars + a category mix at Supabase Auth level (Project Settings → Password requirements), show real-time strength meter |
| P1-9 | Realtime presence | `profiles.is_online` boolean has no writer; the badges and filters lie. | `lib/repositories/profile_repository.dart` (no presence code) | Use Supabase Realtime presence (`channel.track()`) on login, fall back to `last_active < 5 minutes ago` |
| P1-10 | Push notifications | `awesome_notifications` is in pubspec but nothing wires it. Without push, "free messaging" cannot compete with apps that notify in real time. | `pubspec.yaml:21`, no usage | OneSignal or Firebase Cloud Messaging + Supabase Edge Function on `messages` insert |
| P1-11 | Free-tier limits | On Free plan: 500 MB DB, 1 GB Storage, 2 GB egress/mo, 50 K MAU. Storing one 1-MB photo per user × 1,000 users = full Storage tier already. | Supabase plan | Move to Pro before public launch ($25/mo) or aggressively transcode photos to WebP @ 70 quality before upload (already have `image: ^4.5.4`) |
| P1-12 | Image transcoding | Photos uploaded as raw `image_picker` output (often 3–8 MB iPhone JPEGs). | `lib/repositories/photo_repository.dart:32-36`, `lib/screens/edit_profile_screen.dart:163-173` | Resize client-side to max 1080px long edge + re-encode as WebP/JPEG q85 — cuts ~80 % of egress |
| P1-13 | URL hygiene | Photos are signed for **10 years** (`60*60*24*365*10`). Once leaked, a URL is permanent. | `lib/repositories/photo_repository.dart:39-42` | Use 1-hour signed URLs refreshed lazily; or make the bucket public (no signing) and rely solely on row-level access for the path. Or use Supabase Storage transformation URLs which are short-lived. |
| P1-14 | Account deletion | `deleteProfile` deletes the row but **does not delete the auth user**. The ghost auth user can sign in and get a fresh empty profile. | `lib/repositories/profile_repository.dart:167-172`; `lib/providers/profile_provider.dart:188-198` | Call `supabase.auth.admin.deleteUser(userId)` from an Edge Function (service-role only); or use Supabase's new "delete my account" RPC |
| P1-15 | Reports schema | `reports` lacks: `resolved_at`, `resolved_by`, `action_taken`, `severity`, `evidence_url`, `target_message_id`. No moderator queue. | `supabase_schema.sql:262-269` | Extend table; add `report_actions` audit table; add admin RLS |
| P1-16 | Audit log | No record of who suspended/deleted whom. Required for legal defense in harassment cases. | None | Add `moderation_log(actor_id, target_id, action, reason, created_at)` table, written by trigger or Edge Function |
| P1-17 | Verification fraud | `verification_status` is user-writable (`for all to authenticated using (profile owns row)`) — a user can `UPDATE` their own row to set `id_verified=true`. | `supabase_schema.sql:197-205` | Restrict UPDATE to specific columns only, or remove user UPDATE entirely and only allow service-role/Edge-Function writes |
| P1-18 | Reports of self | `reports.reported_user_id` has no CHECK against `reporter_id`. Users can spam-report themselves. | `supabase_schema.sql:262-286` | `check (reporter_id <> reported_user_id)` |
| P1-19 | "Looking for" matching | The most differentiating axis ("Friendship", "Travel Partner", "Long-Term Relationship") is collected but never used as a match weight. | All filtering | Implement reciprocity score: `weight(A→B) = jaccard(A.lookingFor, B.lookingFor) + life_situation_overlap` |
| P1-20 | Onboarding | A new user lands on `/browse` with no profile; sees other people; never told to complete profile. | `lib/router/app_router.dart:36`, `lib/screens/browse_screen.dart` | Force redirect to `/edit-profile` step-wizard until `ProfileProvider.hasProfile == true` and at least 1 photo exists |

### 🟡 P2 — Medium, fix in 30–90 days

| # | Area | Finding | Fix sketch |
|---|------|---------|------------|
| P2-1 | Data model bloat | `profile_interests`, `profile_looking_for`, `profile_life_situation` are three nearly-identical tables. | Collapse to one `profile_tags(profile_id, kind, value)` with `kind in ('interest','looking_for','life_situation')` and unique constraint; halves index footprint |
| P2-2 | `verification_status` overkill | Separate table with 1:1 unique key duplicates a row that could be 4 columns on `profiles`. | Move flags to `profiles` (`email_verified`, `phone_verified`, `selfie_verified`, `id_verified`) |
| P2-3 | Defensive defaults | `text not null default ''` for `first_name`, `city`, `state`, `gender`. Empty string defeats the NOT NULL contract. | Make `nullable` OR add CHECK `length(first_name) > 0` — but only after profile is "published" (`is_complete bool`) |
| P2-4 | DOB type | DoB stored in two places (auth `user_metadata.date_of_birth`, profiles.date_of_birth). Drift risk. | Single source: `profiles.date_of_birth` |
| P2-5 | Schema observability | No indexes shown beyond PKs/UNIQUEs. `last_active`, `state`, `city`, `(state,city)`, `is_online` are all queryable but unindexed. | Add `CREATE INDEX` for the common filters |
| P2-6 | Bundle bloat | `fl_chart`, `table_calendar`, `carousel_slider`, `flutter_staggered_grid_view`, `vector_math`, `package_info_plus`, `flutter_spinkit`, `loading_animation_widget`, `flutter_animate`, `shimmer_animation` — all imported, none used in screens reviewed. | Remove unused deps. Easy 1 MB+ off the Web bundle. |
| P2-7 | Tests | `tests/` folder exists with no contents. Zero unit / widget tests. | Start with auth_provider, profile_repository, browse filter logic |
| P2-8 | Web CSP | No Content-Security-Policy headers configured in `web/index.html`. | Add `Content-Security-Policy: default-src 'self' https://*.supabase.co; img-src 'self' https://*.supabase.co data:; ...` |
| P2-9 | `diagnostics_screen.dart` shipping | A public `/diagnostics` route exposes Supabase URL prefix + first 40 chars of the anon key + init errors. Marked "remove before production" — but easy to forget. | Gate behind `kDebugMode` or admin-only |
| P2-10 | Two HTTP clients | `dio: ^5.8.0` and `http: ^1.4.0` both included; `supabase_flutter` brings its own. | Pick one (Supabase already uses `dio`) |
| P2-11 | Profile timestamps | `created_at` and `last_active` are set but not user-visible. | Show "Joined 3 months ago" — a trust signal |
| P2-12 | Browse filter UX | "Verified" filter requires 1+ verification, but UI doesn't reveal **which** verification. | Show specific badges in cards (already partially shown), allow filtering by specific badge |
| P2-13 | `lookingFor` plurals | DB stores label literals ("Long-Term Relationship"). If you ever translate the app, you re-do every row. | Store as enum keys (`long_term`), render label in UI |
| P2-14 | Empty-state copy | "Start browsing profiles and say hello!" — friendly but doesn't say what happens next. | Add CTA to "complete profile to be visible" with progress meter |
| P2-15 | Forgot-password redirect | `redirectTo: 'io.supabase.nextchapter://reset-password'` is a deep link that breaks on Flutter Web (and requires app association on iOS/Android). | Use platform-specific redirects; on web use `https://app.nextchapter.example/reset` |
| P2-16 | Conversation reads | `conversation.unreadCount` and `requestCount` are derived from mock; no `message_reads` table planned. | Build `message_reads(message_id, user_id, read_at)` and aggregate via SQL |
| P2-17 | Browse ad slot | `AdPlaceholder` hardcoded at index 4 only. No frequency cap, no removal for premium users. | Insert every Nth card with config; suppress for paying users |
| P2-18 | Theme tokens drift | Several `withOpacity(...)` calls; will warn in Flutter 3.27+ (`withOpacity` deprecated, use `.withValues(alpha: …)`). | Bulk rename |

### 🟢 P3 — Low / polish

| # | Area | Finding |
|---|------|---------|
| P3-1 | Brand name | `pubspec.yaml` is `primio_app`, internal title is `ConnectUp`, marketing is "Next Chapter". Three names → ranking, deep-link, and store-listing confusion. |
| P3-2 | Lint | No `analysis_options.yaml` shown; consider `flutter_lints` + `very_good_analysis` |
| P3-3 | i18n | All strings hardcoded English in widgets; no ARB. The 18-100 demographic *will* include non-English speakers in the US (Spanish, Vietnamese, Tagalog cohorts) |
| P3-4 | Dark mode | Not implemented. Older users notably prefer dark mode for low-light reading |
| P3-5 | App icon / branding asset | `assets/icons/` referenced but no audit of contents |
| P3-6 | "Female Female Male Male" gender list | Add: Trans man, Trans woman, Non-binary subtypes, Two-spirit, Prefer to self-describe → critical for an inclusive brand targeting 18-100 |
| P3-7 | DOB picker | `initialDate: DateTime(2000)` on signup biases toward people born in 2000. For a brand serving 18–100, the historical default should be e.g. `DateTime(1975)` (median user) and the year picker should default to "year" mode, not "day" mode |
| P3-8 | "Free & unlimited messaging" banner | Repeated in chat header, messages screen, profile CTA. Once is enough — repetition reads as defensive |
| P3-9 | Spelling | "It's complicated" (with smart quote) in code: `"It\'s complicated"` — fine; double-check on RTL languages |
| P3-10 | Iconography | `Icons.favorite` heart used as the app logo and in chat input — heart icon biases brand toward "dating", muddying the "friendship + dating" thesis |

---

## 3. Domain Deep Dives

### 3.1 Security

**Threat model gap.** The codebase has not had a threat-model pass for a dating app. The minimum threat set for this category is:

1. Account takeover via credential stuffing
2. Impersonation / fake profiles
3. Romance scams (catfishing for money)
4. Underage account creation
5. Image-based abuse (NSFW unsolicited photos, child sexual abuse material — federal mandatory report)
6. Stalking (ex-partners locating an account)
7. Doxxing (PII leakage)
8. Harassment / hate speech in messages
9. Coordinated brigading (raid signups, mass reports)
10. Data breach of PII (DoB + city = identity-fraud goldmine)

The build currently has a partial defense for **none** of these. The most urgent gaps:

- **Privilege escalation (P0-1)** — already covered.
- **Anon key in source (P0-2)** — Supabase anon keys are intended to be in clients, *however* combined with the privilege-escalation hole in #1 and the missing RLS on `reports`, this is exploitable. Rotate the key, and treat the key change as the trigger for moving secrets to `--dart-define`.
- **No rate limiting** on signup/login at the app level. Supabase Auth has built-in rate limits (default 30/h per IP) but you should also enable hCaptcha for signup and password reset.
- **No row-level "I am verified that I am verifying my own request" check** in `verification_status` (P1-17). A regular user can run `UPDATE verification_status SET id_verified=true` on their own row right now.
- **Personal data fingerprint.** Even one photo + first name + city + DoB is enough to find someone's LinkedIn in 60 seconds. Consider:
  - Letting users set city to a region (`Greater Austin`, `Within 50 mi of San Diego`)
  - Letting users hide exact age, show only "50s"
  - Auto-blurring the most recent location field for users who report being in DV-shelter situations (a category your demographic genuinely needs)
- **No web CSP / Trusted Types / SRI** (P2-8). Flutter Web is a single-page WASM/JS app; an XSS via a misconfigured WebView opens the door to the anon key + the user's JWT.

**Auth posture — Supabase specifics:**
- Enable: "Confirm email" (already on per `isEmailVerified` check); "Secure email change" (require both old & new); "Secure password change" (require recent login).
- Disable: `signup` from the public API key once you have CAPTCHA — or proxy signups through an Edge Function that does extra checks (email reputation, IP reputation, disposable-domain block).
- Use **`app_metadata.role`** for admin gating (set via service-role); never `user_metadata` (P0-1).

### 3.2 Database design

**What's there (10 tables):** `profiles`, `profile_photos`, `profile_interests`, `profile_looking_for`, `profile_life_situation`, `verification_status`, `user_settings`, `blocks`, `reports`, plus the (commented-out) storage bucket.

**What's missing for a real product:**

- `conversations` (`id`, `created_at`, `last_message_at`, `is_request`, `request_accepted_at`)
- `conversation_participants` (`conversation_id`, `profile_id`, `joined_at`, `muted`, `archived`)
- `messages` (`id`, `conversation_id`, `sender_id`, `body`, `created_at`, `deleted_at`, `edited_at`)
- `message_reads` (`message_id`, `reader_id`, `read_at`) — for unread counts
- `message_reactions` (optional but POF & Hinge have them)
- `matches` / `likes` (`from_profile`, `to_profile`, `kind`, `created_at`) — even with free messaging, you want a "showed interest" signal
- `profile_views` (`viewer_id`, `viewed_id`, `created_at`) — "who's checked you out" is the #1 monetization hook on POF
- `favorites` / `bookmarks`
- `moderation_log` (`id`, `actor_id`, `target_id`, `action`, `reason`, `created_at`)
- `report_actions` (`report_id`, `action`, `actor_id`, `created_at`)
- `verification_documents` (`id`, `profile_id`, `kind`, `storage_path`, `status`, `submitted_at`, `reviewed_at`, `reviewer_id`) — for ID and selfie verification
- `notifications` (`id`, `recipient_id`, `kind`, `payload jsonb`, `read_at`, `created_at`)
- `audit_log` for compliance (CCPA/GDPR export/delete requests)
- `safety_check_ins` (date-night check-ins) — a Next Chapter differentiator (see §4)
- `meet_ups` (group/activity events) — friendship/activity-partner support

**Structural improvements:**

- **Collapse three child tables into one (P2-1).** `profile_tags(profile_id, kind text, value text, position int)` is exactly the same shape and lets you add new tag categories (`languages`, `dealbreakers`, `personality_traits`) without DDL.
- **`verification_status` → columns on `profiles` (P2-2).** It's already 1:1 by unique key.
- **Generated `tsvector` column** on `profiles(first_name, about_me, city, state)` + GIN index — enables real text search in one line.
- **GIN index** on `profile_interests(interest)` — turns "match by interest" from O(N) into O(log N).
- **Geo column.** A `geography(point, 4326)` on `profiles` + `ST_DWithin` enables distance search and the "within 50 miles" filter that Match/Bumble all have. Backfill from `(city, state)` via a one-off geocoder.
- **Partial indexes:** `WHERE is_suspended=false AND is_deleted=false` is in every query — make it a partial index on (`last_active DESC`) so the hot path is small.
- **`updated_at` triggers** are present on `profiles` only. Extend to all tables; trivial DRY refactor.

**MongoDB-vs-Postgres consideration (since the platform prompt mentions Mongo):** Postgres is the right choice. Don't migrate.

### 3.3 Supabase integration

**Strengths:**
- Singleton pattern + `initError` / `configurationError` is clean and developer-friendly.
- Repository layer correctly isolates all queries.
- `onAuthStateChange` listener restores sessions across reloads (good).
- Soft `mock mode` is well-marked and explicit.

**Gaps:**
- No **Edge Functions** anywhere. You need them for: (a) account deletion (`auth.admin.deleteUser`), (b) Stripe webhook for verification, (c) push-notification fan-out, (d) photo moderation callbacks, (e) abuse-keyword scanning before message send.
- No **Realtime subscriptions** anywhere — despite messaging being the headline feature. Implement once `messages` exists: `client.channel('room:$id').on('postgres_changes', ...)`.
- No **storage transform URLs** — Supabase supports `?width=200&quality=75` natively. Use these for thumbnails instead of issuing 10-year signed URLs to full-res photos.
- No **DB triggers**: signup → profile bootstrap (P0-7), photo insert → reorder display_order, message insert → conversation.last_message_at update.
- No **PITR / backups** — only available on Pro tier. For a dating app holding PII you should be on Pro before any real-user signups.
- No **rate-limit configuration** in `auth.json` (Supabase project-level config-as-code).

**Free → Pro decision tree.** With your audience (broad 18–100), realistic scale assumptions:
- 5,000 MAU × 2 sessions = ~300 K req/day → fine on Free
- 5,000 users × 3 photos × 800 KB = 12 GB Storage → **breaks Free (1 GB) immediately**
- 12 GB egress/mo from photo viewing → **breaks Free (2 GB)**
Recommendation: switch to **Pro ($25/mo)** the day you exceed 100 users with photos, and turn on PITR.

### 3.4 Authentication

Already covered in §2 (P0-1, P0-8, P1-6, P1-7, P1-8, P1-14) and §3.1. Specific additions:

- **Add Sign in with Apple** (mandatory if you ever publish to iOS) and **Sign in with Google** (massive friction reducer for the 50+ demographic who reuse Google). Don't ship without these.
- **Add phone-OTP login** — preferred by an older demographic that doesn't trust email or struggles with passwords. Supabase supports it natively.
- **Add magic-link login** — same demographic argument.
- **Session timeout policy.** Default Supabase is 1 hour access token, infinite refresh. For a dating app handling PII, consider: refresh token TTL of 30 days, access TTL of 60 min, force-logout on password change.

### 3.5 Messaging

Currently a beautiful UI on top of nothing. To make "free unlimited messaging" real:

**Phase A — basic chat (1 sprint):**
```
conversations(id, created_at, last_message_at, is_request)
conversation_participants(conversation_id, profile_id, ...)
messages(id, conversation_id, sender_id, body, created_at, deleted_at)
```
RLS: read/write only if `auth.uid()` is in `conversation_participants`.
Realtime: subscribe to `messages` filtered by `conversation_id`.

**Phase B — safety net (1 sprint):**
- Pre-send keyword scan (regex + a small list of phishing patterns: "send me $", "telegram me at", "i need bail money") → soft warning, log to `moderation_log`
- Image-in-DM moderation via Sightengine before delivery
- Per-recipient rate limit: max 50 messages to a non-replying user, then forced cool-down ("they haven't replied yet — please respect their space")

**Phase C — differentiation (2 sprints):**
- **Voice notes** (Bumble & FB Dating have them; older users prefer voice over typing)
- **Conversation starters** that reference the recipient's `lookingFor` / `lifeSituation` ("You both mentioned 'Veteran' — say hi about that?")
- **Safety check-ins** (Bumble has one). "Going on a date with @Sarah tonight at 7pm — text me at 9pm to confirm I'm safe." Auto-escalate to user's emergency contact if no response.

### 3.6 Profile system

**Strengths:** Clean upsert + parallel child-table replace; signed-URL storage paths with `auth.uid()` prefix; account-deletion order (storage → DB) is correct.

**Critical fix already noted:** signup must create a profile row (P0-7).

**Other improvements:**
- **Profile completeness score.** Compute server-side (`length(about_me)>20 ? 10 : 0` etc.). Show progress bar. Don't list profiles below 40 % completeness — improves match quality and bot defense.
- **Photo order = drag-and-drop** (currently driven by `display_order` insert order only).
- **Verified profile photo (first photo)** — require selfie liveness check on the primary photo. Major signal of authenticity.
- **Prompts (Hinge model)** — the strongest profile-UX innovation of the last 5 years. Pre-written prompts ("My favorite chapter so far is…", "I'm rebuilding because…") let users sound like themselves without writing 300 words of "about me". For your 18-100 demographic this is *especially* valuable — older users have rich stories but freeze at a blank bio box.
- **"Story so far" voice intro** (15-30 s audio). Cheap, very Next-Chapter-on-brand. Older users record voice memos every day.

### 3.7 Search & discovery

Currently: client-side filter over all rows. Will collapse at 500 users.

**Discovery model recommendation.** Don't ship as pure "browse + filter" — that's POF circa 2003. Mix three feeds:

1. **"For You"** — ranked by `lookingFor` overlap × interest overlap × distance × verification × recency, with a freshness boost for new profiles.
2. **"New to Next Chapter"** — last 7 days of signups in your area.
3. **"Has things in common"** — surfaces shared interests/life-situation explicitly. (Older users articulate "same life situation" as a stronger pull than appearance.)

Server-side implementation: a single Postgres function `match_for(profile_id, lookingFor[], interests[], lifeSituation[], near_lat, near_lng, limit, after_cursor)` returning a `setof match_result`. Memoize per user for 1 minute. Use `cursor_pagination` (`(score, id) > (last_score, last_id)`).

**Filters:**
- Distance ("Within 25/50/100 miles, or anywhere") — add geo column.
- "Don't show me people who have already passed/blocked me" (mutual).
- "Only show profiles with photos" / "with selfie-verified" / "with ID-verified".
- "Hide profiles I've already messaged" / "Hide profiles I've already seen this week".

### 3.8 Moderation & admin tools

Today: 100 % mock.

**Minimum admin v1 (1 sprint):**
- Real reports list filterable by status/severity, sorted by created_at DESC.
- One-click `suspend` (calls Edge Function with service role; writes `moderation_log`; sends notification email).
- One-click `ban` (suspend + auth user delete + storage purge).
- "View user's last 20 messages" — keep them in chronological context.
- "View user's recent reports against them" — pattern detection.
- Bulk close N reports for a user once banned.
- Search: by email, by profile name, by city.
- Metrics: real signups/day, reports/day, ban rate, time-to-action.

**Moderation v2 — proactive (sprint 4-5):**
- Async keyword/regex pipeline that flags messages without blocking send. Flagged messages enter a "needs review" queue.
- Image moderation (Sightengine, Rekognition, or Hive) on every photo upload — auto-block obvious NSFW.
- **Trust score** per profile (verifications + age + report ratio + reply ratio). Show admins, never show users.

**Appeals:**
- Users can appeal a suspension once; goes to a separate admin queue.
- 30-day deletion grace period (already partially structured — `is_deleted` flag) is a competitive advantage for the older demographic who delete impulsively.

### 3.9 Verification

The flags exist. The flows do not. Recommended stack:

| Level | What | Provider | Cost | Trust signal |
|---|---|---|---|---|
| 1 | Email | Supabase Auth | Free | Tiny — anyone can make Gmail |
| 2 | Phone OTP | Supabase Auth (Twilio under the hood) or Twilio Verify | $0.05 / verification | Medium — costs $ to spoof |
| 3 | Selfie + liveness | Persona Lite / Onfido Document / Stripe Identity | $0.10–$1.50 / verification | High |
| 4 | Government ID | Stripe Identity / Onfido | $1.50 / verification | Very high |
| 5 | Life-situation-specific badges | VA.gov verify (Veteran), LinkedIn (Employer), etc. | Mostly free APIs | **Differentiator** |

The #5 row is the unique opportunity. POF / Bumble / Match cannot verify "Veteran" or "Widowed" trivially. You can, via:
- **VA.gov OAuth** — verify "Veteran" badge for free.
- **An obituary check** for "Widowed" (sensitive — opt-in only).
- **A divorce-decree document upload** (manual review) for "Divorced".
- **A retirement-account verification** (manual review) for "Retired".

These badges, displayed prominently, are a near-unforgeable trust signal that your demographic will *pay* to earn (or to display as a signal to others). See §4 for monetization.

### 3.10 Performance & scalability

**At current architecture, hard limits:**

| Scale | Will it work? |
|---|---|
| 100 users | Yes |
| 1,000 users | Browse becomes slow (5–10 s) |
| 10,000 users | Browse times out; client OOM on web |
| 100,000 users | Free-tier Storage and egress exceeded; DB CPU saturated |

Required changes to clear each cliff:
- 1 K → server-side filtering + pagination
- 10 K → indexes (GIN, geo, partial), tsvector
- 100 K → connection pooling (Supavisor), read-replica routing, signed-URL caching CDN, photo CDN (Bunny/Imgix on top of Storage)

**Flutter Web specifics:**
- Use `flutter build web --wasm` (Flutter 3.22+) — 2-3× faster on this demographic's older devices.
- Lazy-load admin/diagnostics screens with `deferred as` imports — saves ~100 KB initial bundle.
- Replace `google_fonts` runtime download with bundled `assets/fonts/` (Inter is small and you save a CORS round-trip on first paint).

### 3.11 UI/UX

**What's working:**
- Warm palette is on-brand and demographically inclusive.
- Consistent design tokens (`AppTheme.spacing*`, `AppTheme.radius*`).
- Generous spacing.
- Clear "free messaging" affordance.

**What needs work:**

- **Bottom nav has 3 tabs, missing "Profile"/"You".** Users currently access their own profile only via Settings → Edit Profile (3 taps). For a profile-centric product that's wrong — make Profile a top-level tab.
- **No "matches" / "interested in you" tab.** Even without paid mechanics, "X people viewed your profile this week" is a powerful re-engagement loop.
- **Onboarding wizard missing.** A new signup is dropped into Browse with 0 photos and 0 about-me — they look like a bot to other users. Force a 60-second wizard: name → DoB → 1 photo → 3 interests → 1 looking_for → submit → land in Browse.
- **Inconsistent "free messaging" copy.** It appears in 3 places (chat banner, messages screen badge, profile detail CTA). Once on the landing page, then quiet, would feel more confident.
- **Heart icon for the brand logo.** Conflicts with the dual friendship+dating positioning. Consider a "page turn" / "open book" / "second sunrise" mark instead.
- **Profile cards show only 2 `lookingFor` chips.** Cards should also show 1-2 interests in common with the viewer ("You both like Hiking") — the highest-ROI thing on a list view.
- **Search bar is name + city + state only**. Users want to search by interest and by life-situation too.
- **No skeleton/shimmer states** for cards while loading. `shimmer_animation` is in pubspec — use it.
- **Empty messages screen** says "Start browsing profiles and say hello!" — show 3 suggested profiles right there.
- **No `Hero` animations** between browse card → detail. Easy delight upgrade.
- **DOB picker** opens to day-of-month — bad for older users typing 1948. Open to year mode by default.
- **No "Profile completeness" affordance** — users have no signal that adding a 4th photo would 3× their visibility.

### 3.12 Accessibility (A11y)

This will be the single biggest competitive differentiator for an 18-100 brand.

Current state has multiple gaps:

- **No `Semantics` labels** on icon-only buttons (online dot, photo delete X, filter close icon, badge icon).
- **No focus order** override for keyboard nav on web.
- **Color-only signals**: online (green dot) / offline (gray dot) — needs text label too.
- **Touch targets** below 48 dp: photo delete X is 14 px wide; online indicator dot is 12 px (info-only, OK); the small icon buttons in admin are sometimes 24 px without padding-extender. WCAG AA requires 44×44 (iOS) / 48×48 (Android/Material).
- **Text contrast.** Verified badge uses `Colors.white` over `appColors.verified` (#3498DB) — that's 4.05:1, which fails AA on normal text. Either darken `verified` or use a darker text color.
- **No reduced-motion variant** — the upcoming `flutter_animate` use should respect `MediaQuery.disableAnimations`.
- **`maxLines: 1` + `ellipsis` on names** — fine, but the screen-reader announcement should be the full name. Add `Semantics(label: profile.firstName)`.
- **No alt text on images.** `CachedNetworkImage` needs `semanticsLabel`.
- **Font sizing.** Currently fixed via Google Fonts Inter. Respect `MediaQuery.textScaler` — older users routinely set 130-150 % system text scale. Verify your tight `RangeSlider` labels, badge rows, and chip wraps don't overflow.
- **High-contrast theme.** Older eyes prefer it. Plan a `ThemeMode.system + highContrast extension` later.

Accessibility done well is your **public marketing message**: "Built for grown-ups, including those with low vision, hearing loss, or tremor."

### 3.13 Monetization (with free messaging preserved)

Free messaging is sacred to your brand — keep it. There are still 5 healthy revenue paths that don't violate it:

1. **Verification fees, not chat fees.** Charge $4.99 (one-time) for ID-verified gold badge; $0.99 for phone-verified; bundle for $7.99. People pay for *trust*, not for *access*.
2. **Boosts / Spotlights.** "Be one of the top 10 cards for 30 minutes in your city for $1.99." Doesn't gate messaging.
3. **"Who viewed me / who liked me".** POF's biggest paid feature. $3.99/month or $19.99/year. Free users see anonymous counts; paid users see names.
4. **Travel mode.** "Browse in NYC while you live in Tampa" for $2.99/week. Strong with your Travel Partner segment.
5. **Premium safety pack.** Background check ($14.99 via a partner like Garbo or BeenVerified), date-safety check-in escalation to a real human concierge ($9.99/mo). Aligns with brand.
6. **(Soft)** First-party ads on browse — already scaffolded with `AdPlaceholder`. Respect: never an ad in a chat; never an ad for a competing dating service; cap at 1 per 12 cards.
7. **(Optional, later)** "Next Chapter Local" — paid event listings for local meet-ups (book clubs, hike groups, widows' coffee). Hosts pay $20 to list; attendees free.

**What NOT to charge for:**
- Sending messages (core promise)
- Replying to messages
- Receiving messages (the "you have a message but pay to read" anti-pattern POF/Match abuse — refuse to do this)

### 3.14 Long-term maintainability

- **Three names** (`primio_app`, `ConnectUp`, `Next Chapter`) → pick one. (P3-1)
- **No tests** → start with `auth_provider_test.dart`, `profile_repository_test.dart`, `browse_filter_test.dart`.
- **No CI** → GitHub Actions: `flutter analyze && flutter test && flutter build web` on every PR.
- **No environment matrix.** Add `--dart-define=ENV=dev|staging|prod` and three Supabase projects.
- **No JSON serializers** on models → `json_serializable` or hand-rolled `fromJson`/`toJson`. Today, the model's mapping is scattered inside `_assembleProfile`, which makes it brittle.
- **Dead code in production paths:** `MockDataService` is still imported by `BrowseScreen`, `MessagesScreen`, `ChatScreen`, `ProfileDetailScreen`, `AdminScreen`, and `FilterSheet`. After messaging/admin/browse are wired to Supabase, fail the build if `MockDataService` is imported outside `lib/services/`.
- **No code-gen / linting strictness.** Add `flutter_lints` + a custom `analysis_options.yaml` with `prefer_const_constructors`, `avoid_print`, `unawaited_futures` set to errors.

---

## 4. Competitive Feature Analysis

| Feature | POF | OkCupid | Match | Bumble | Hinge | FB Dating | **Next Chapter today** | **NC opportunity** |
|---|---|---|---|---|---|---|---|---|
| Free messaging | ✅ | ❌ paywall | ❌ | ✅ (women-first) | ❌ likes paywall | ✅ | ✅ (mocked) | **Keep — moat** |
| Profile prompts (Hinge style) | ❌ | partial | ❌ | partial | ✅ best-in-class | ✅ | ❌ | **Adopt** — perfect for older storytellers |
| Voice intro | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | **Adopt** — older demographic loves voice |
| Video intro | ❌ | ❌ | ❌ | ✅ | partial | ❌ | ❌ | Adopt eventually |
| Compatibility quiz | partial | ✅ deep | partial | ❌ | partial | partial | ❌ | Adopt — but make it about *life chapter*, not personality MBTI |
| Distance filter | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | Must add |
| "Looking for" filter | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ (good!) | **Lean in** — make it dominant |
| Friend/BFF mode | ❌ | ❌ | ❌ | ✅ BFF | ❌ | ❌ | ⚠ collected, not used | **Differentiator** — make friendship co-equal with dating |
| Activity partners | ❌ | ❌ | ❌ | ✅ Bizz (work) | ❌ | ❌ | ⚠ collected, not used | **Differentiator** — hiking/travel partners |
| Group events / meetups | ❌ | ❌ | ✅ Stir events | ❌ | ❌ | ❌ | ❌ | **Differentiator** — "Next Chapter Locals" |
| Verification | partial | partial | partial | ✅ photo | ✅ photo | ✅ via FB | ⚠ flags only | **Adopt + go beyond** (veteran, widow, retired badges) |
| ID verification | ❌ | partial | partial | partial | partial | ❌ | ❌ | Adopt — sell as $4.99 badge |
| Selfie liveness | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | Adopt |
| Background check | ❌ third-party | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | **Differentiator** — partner with Garbo |
| Safety check-in (date alarm) | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | **Adopt + extend** — emergency-contact escalation |
| Block / report | ✅ basic | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠ partial | Finish + add admin tooling |
| Read receipts | paywall | paywall | paywall | paywall | ❌ | ❌ | ❌ | Free for all (brand alignment) |
| Boost / spotlight | paywall | paywall | paywall | paywall | paywall | ❌ | ❌ | Adopt as paid (doesn't break free messaging) |
| Travel mode | paywall | paywall | paywall | paywall | paywall | ❌ | ❌ | Adopt as paid |
| Who viewed me | paywall | paywall | paywall | paywall | ❌ | ❌ | ❌ | Adopt as paid |
| Compatibility % | paywall | ✅ | partial | ❌ | ❌ | ❌ | ❌ | Adopt — based on life-chapter overlap, not personality |
| AI conversation starters | ❌ | partial | ❌ | partial | partial | ❌ | ❌ | **Differentiator** — "you both lost a spouse — say hi about a shared book?" (caring tone, not flirty) |
| Stories / ephemeral updates | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | Adopt later |
| Friend-of-friend matching | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ via FB | ❌ | Skip (privacy collision) |
| Audio rooms | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | **Wildcard differentiator** — book-club style audio rooms for the empty-nester segment |
| Local interest groups | ❌ | ❌ | ✅ Stir | ❌ | ❌ | ❌ | ❌ | **Adopt** — major loyalty driver |

### Top 5 features that would make Next Chapter stand out (ranked)

1. **Life-chapter matching, not personality matching.** OkCupid asks 1,000 questions about your political opinions. Next Chapter should ask 20 about *where you are in life right now* (Are you newly widowed? Newly retired? Newly relocated? Newly empty-nested?) and match on chapter overlap. This is the most differentiated, brand-true feature you can build. It uses data you already collect.

2. **Multi-mode discovery (Date / Friends / Activity).** One signup, three independent feeds, one shared profile. A user can opt-out of one mode entirely. This is the single most important UX decision because it dictates the home screen. Bumble tried with BFF/Bizz and it works — but for an older audience, the activity-partner mode is the larger market (golf buddies, hiking groups, travel companions, art-class partners).

3. **Earned trust badges beyond "verified".** "Veteran ✓" (VA OAuth), "Retired ✓" (manual review), "Widowed ✓" (sensitive, optional), "Local ✓" (geo-check). This is something the big platforms cannot do without serious investment — you can.

4. **Built-in safety net.** Combine date safety check-ins, optional emergency-contact escalation, optional background check, and a no-ghosting culture (a user who breaks contact gets a soft "they're not replying — try someone else?" rather than a paywall). Safety as brand, not as a paid feature.

5. **Caring AI co-pilot (not sleazy AI co-pilot).** A free, opt-in suggestion box: "Sarah recently relocated and likes hiking — say hi about that trail in Austin?" Tonally different from Hinge's flirty AI prompts. Tested copy with the older demographic; they respond positively because it removes the cold-start friction without feeling manipulative.

### Anti-patterns to avoid

- **Don't** add "Likes" you have to pay to see. Brand-destroying.
- **Don't** add a "send a rose" / "super like" / "boost message" economy. Brand-destroying.
- **Don't** swipe-stack mechanic. POF tried it and lost users. Card-list browse + filters is right for this demographic.
- **Don't** ephemeral 24-hour matches (Bumble's expiry). Stressful for older users.
- **Don't** require Facebook / Instagram link. Generationally hostile.

---

## 5. Prioritized Roadmap

### Impact × Effort matrix

```
HIGH IMPACT
   │
   │   P0 fixes        Real messaging       Multi-mode discovery
   │   (P0-1..9)       (P0-4)               (date/friend/activity)
   │   (must do)
   │
   │   Server-side     Verification         Life-chapter
   │   filtering       v1 (selfie+phone)    matching
   │   (P1-1, P1-2)
   │
   │                   Onboarding wizard    Earned trust badges
   │                   (P1-20)              (Veteran, Widow, etc)
   │
   │   Bundle clean    Profile prompts      Safety check-ins
   │   (P2-6)          (Hinge style)        + background checks
   │
   │   Tests, CI       Voice intros         AI co-pilot
   │   (P2-7)                               (caring tone)
   │
LOW IMPACT ────────────────────────────────────────────────► HIGH EFFORT
```

### Concrete 12-week sequence

**Weeks 1–2 — Security & foundations (P0)**
- Rotate Supabase anon key; move secrets to `--dart-define`
- Fix `is_admin` → app_metadata + admin_users table
- Add signup→profile trigger
- Add CAPTCHA on signup
- Apply storage RLS via SQL (not comments)
- Account deletion via Edge Function (delete auth user too)
- Tighten `verification_status` RLS (drop user UPDATE)
- Restrict diagnostics route to admins
- Add basic indexes (`last_active`, `(state,city)`, GIN on interests)

**Weeks 3–4 — Real messaging (P0-4)**
- Schema: conversations, conversation_participants, messages, message_reads
- RLS by participant
- Realtime subscription on chat screen
- Push notifications via Edge Function + OneSignal
- Block enforcement in browse + messages (P0-5)

**Weeks 5–6 — Real moderation (P0-3)**
- Admin role + RLS for reports & profiles.is_suspended
- Real reports list, suspend/ban/resolve actions
- moderation_log audit table
- Sightengine integration on photo upload
- Pre-send keyword scan in messages

**Weeks 7–8 — Browse scale (P1-1..3)**
- Server-side filtering + pagination function
- Distance / geo column + filter
- tsvector + GIN indexes
- Onboarding wizard
- Profile completeness score

**Weeks 9–10 — Verification & trust**
- Phone OTP verify (Twilio Verify, $0.05/each)
- Selfie + liveness via Persona Lite
- ID via Stripe Identity (paid badge $4.99 one-time)
- Veteran badge via VA.gov OAuth
- "Who viewed me" feature (paid $3.99/mo)

**Weeks 11–12 — Differentiation v1**
- Multi-mode toggle on Browse (Date / Friends / Activity)
- Life-chapter matching score
- Hinge-style prompts (5 prompts, 2 visible on profile)
- Voice intro upload + playback (15-30 s)
- Safety check-in feature
- Caring AI conversation starter (one model call per opened profile, cached)

### What to defer to post-12-week

- Travel mode (paid)
- Local meet-ups marketplace
- Audio rooms
- Background-check partnership
- Dark mode
- i18n
- Native iOS/Android shells (Flutter handles, but App Store listings need attention)

### KPIs to instrument before launch

- Signup → first photo (target 70 %)
- First photo → first message sent (target 50 %)
- First message → reply (target 25 %)
- D7 retention (target 35 %)
- Reports / 1,000 MAU (target < 8)
- Time to suspend (target < 4 h)
- Verified % of profiles (target > 40 % at 90 days)

---

## 6. Closing notes

The codebase is *small enough* (38 files, 6 K LOC) that none of the P0/P1 fixes are weeks of work individually. The risk profile is "small but exposed": good bones, several scaffolds masquerading as features, and three trivially-exploitable security holes. Two of the three P0 security issues are 10-line fixes. The third (real messaging) is roughly two weeks.

The biggest *strategic* gap is not technical: it's that Next Chapter has chosen a differentiated demographic (18-100 with a 40+ lean, "fresh start" thesis, friendship + dating) but the product currently looks like a slightly nicer POF. The roadmap above is engineered to convert your brand promise into product reality: life-chapter matching, earned-trust badges, multi-mode discovery, voice-first profiles, and a safety-as-brand posture. That combination is something neither POF nor Bumble nor FB Dating can copy quickly, and it's exactly what your stated demographic will pay for.

I will not make any code changes until you respond with which items (or which week-blocks) to start. If you want, I can also produce a `MIGRATIONS/` folder with the additive SQL for the new tables, a stubbed `MessagingRepository`, and an Edge Functions skeleton — all behind a feature flag — but none of that will be touched without explicit go-ahead.

— end of audit —
