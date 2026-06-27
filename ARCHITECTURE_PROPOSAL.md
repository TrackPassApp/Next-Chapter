# Next Chapter — Clean-Slate Architectural Proposal
*A from-scratch design exercise. No code in this document. No files in the existing project have been modified.*

Author: E1 (acting as Lead Architect / CTO for this exercise)
Date: 2026-01
Scope: Full architecture of an ideal Next Chapter, with subsystem-by-subsystem comparison against the current implementation.
Posture: I am not preserving the current stack. I am proposing what I would build with a clean garage, then telling you which parts of your existing build are worth keeping anyway.

---

## 0. How to read this document

1. **§1 Product principles** — the constraints that drive every architectural choice below.
2. **§2 The proposed stack at a glance** — one diagram, one paragraph.
3. **§3–§22 Subsystem-by-subsystem deep dives**, each using the exact comparison template you asked for:
   - Current implementation
   - Proposed implementation
   - Advantages
   - Disadvantages
   - Migration difficulty (1 = trivial, 5 = full rewrite)
   - Recommendation: **Keep current / Iterate / Replace**
4. **§23 What to remove before launch**
5. **§24 What to add before launch**
6. **§25 Recommended modern Flutter packages and other technologies**
7. **§26 Long-term architectural patterns**
8. **§27 Cost & operations model**
9. **§28 Migration map (if you choose to evolve the existing app vs rebuild)**
10. **§29 Closing & decision points awaiting your call**

Severity / recommendation legend used throughout:
- 🟢 **Keep** — current implementation is fit for purpose; do not waste energy.
- 🟡 **Iterate** — current is salvageable; specific fixes named.
- 🔴 **Replace** — the right architectural answer is materially different; iterating it costs more long-term than replacing it.

Migration difficulty (1 = trivial, 5 = full rewrite) is rated against the *current 6,000-LOC Flutter+Supabase codebase*.

---

## 1. Product principles (these are the constraints)

Every design choice below honors all eight:

1. **Free messaging, forever, with no asterisk.** No "first message free", no "read receipts only for paid", no "5 messages a day on free". Architectural implication: messaging is a *cost center*, not a profit center, so it must be ruthlessly cost-engineered.
2. **Dating and friendship co-equal.** Architecture must support a user being in date-mode for one person and friend-mode for another simultaneously. Not a toggle. Not a sub-app.
3. **Ages 18–100.** Implies: aggressive accessibility, large hit targets, no swipe-stack mechanic, plain-language copy, support for non-tech-native users, age-spread match logic that doesn't collapse to "young people only".
4. **Privacy-first.** "We can prove what we don't see." Specifically: minimum data collection, server-side encryption + zero-staff-read policy, full audit log of all admin reads, no third-party tracking SDKs.
5. **No selling user information.** Implies: no Mixpanel, no Segment, no Facebook SDK, no Google Analytics 4 (privacy-hostile), no ad networks that retarget. First-party analytics only.
6. **Account deletion permanently removes user data.** Hard delete with 30-day reversible grace period, then irreversible. Includes auth user, photos, messages, log mentions, embeddings, derived features.
7. **Modern, clean interface.** Material 3 expressive baseline + custom expressive identity, motion budget, type scale tuned for older eyes, dark mode at parity.
8. **Long-term scalability.** Architectural decisions must work at 1M MAU, not just 1K. No knowingly-disposable code paths.

If a decision below seems unusual, it is downstream of one of these eight.

---

## 2. The proposed stack at a glance

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                          CLIENTS (one codebase)                              │
│   Flutter 3.27+ (Material 3 + WASM web)                                      │
│   Riverpod 2 · GoRouter · freezed · drift · dio · sentry · posthog-self     │
└──────────────────────────────────────────────────────────────────────────────┘
                  │  HTTPS+JWT  │  WSS realtime  │  signed image URLs
                  ▼             ▼                ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                       EDGE  (Cloudflare)                                     │
│   • CDN + WAF + bot mgmt + rate limit                                        │
│   • Cloudflare Images (resize, transform, $5/100k)                           │
│   • R2 for cold object storage (zero egress)                                 │
└──────────────────────────────────────────────────────────────────────────────┘
                  │
                  ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                       APPLICATION TIER                                       │
│   ┌────────────────────────┐  ┌────────────────────────┐                     │
│   │ Phoenix (Elixir) API    │  │ Phoenix LiveView Admin │                     │
│   │ • Channels (chat WSS)   │  │ • Internal only        │                     │
│   │ • REST/JSON for CRUD    │  │ • Moderation queue     │                     │
│   │ • Background jobs (Oban)│  │ • All actions audited  │                     │
│   └────────────────────────┘  └────────────────────────┘                     │
└──────────────────────────────────────────────────────────────────────────────┘
                  │           │            │
                  ▼           ▼            ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                       DATA TIER                                              │
│   PostgreSQL 16 (primary)   Redis 7        Meilisearch       pgvector       │
│   • PostGIS for geo         • sessions     • bio FTS         • bio sim      │
│   • row-level security      • rate limit                                     │
│   • declarative partitions  • presence                                       │
└──────────────────────────────────────────────────────────────────────────────┘
                  │
                  ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                       3RD-PARTY (privacy-vetted)                             │
│   Stytch B2C        Stripe Identity    Persona Lite    Sightengine          │
│   (auth)            (ID verify)        (selfie liveness) (image moderation) │
│   Resend            Twilio Verify      OneSignal       PostHog (self-host)  │
│   (email)           (phone OTP)        (push)          (analytics)          │
└──────────────────────────────────────────────────────────────────────────────┘
```

**One-paragraph rationale.** Flutter wins client because it is the cheapest path to a *single* premium codebase across iOS, Android, and Web — critical for a startup serving an 18-100 demographic where some users will browse on a 9-year-old Android, some on a desktop browser, some on an iPad. Elixir/Phoenix wins server because messaging is the headline feature and Phoenix Channels solves "free unlimited chat for 1M concurrent users" with off-the-shelf primitives the rest of the industry doesn't have — that single technical choice is the moat that lets you keep messaging free forever. Postgres + pgvector + PostGIS + Meilisearch covers DB, geo, similarity, and text search without three separate vendor relationships. Cloudflare (R2 + Images + CDN + WAF) makes image bandwidth ~10× cheaper than AWS at this scale, which directly subsidizes free messaging. Privacy-first vendors only (Stytch, Persona, Resend, PostHog) because the brand is built on "we don't sell you".

---

## 3. Application architecture

### Current implementation
Flutter 3.7 client → `provider` state → repositories → Supabase JS SDK (anon key in source) → Postgres + Storage + Auth. No backend service of our own. All business logic lives client-side. Two state-management patterns mixed (`ChangeNotifier` providers, some scoped, some global). Three branded names (`primio_app`, `ConnectUp`, `Next Chapter`).

### Proposed implementation
**Three-layer architecture:**

1. **Thin clients.** Flutter for mobile + web. State via **Riverpod 2** with `riverpod_generator` for type-safe, testable, codegen-backed providers. Routing via **GoRouter** with declarative auth-gated routes. Offline cache via **drift** (SQLite). Models via **freezed** + `json_serializable`. Crash reporting via **Sentry**. First-party analytics via **PostHog self-hosted**.
2. **Application tier (the missing layer in the current build).** A single **Elixir/Phoenix** app exposing both REST (CRUD, profile, search) and WebSockets (chat, presence, notifications via Phoenix Channels). Background work via **Oban** (Postgres-backed job queue — no Redis needed for jobs). Admin app is a separate Phoenix release with **LiveView** (so admin tools live inside the same Elixir codebase but never ship to end users).
3. **Data tier.** Postgres 16 + PostGIS + pgvector (one DB, three superpowers). Redis 7 for ephemeral state (rate limits, presence, sessions). Meilisearch for FTS. R2 for object storage. Cloudflare CDN+Images for delivery.

Communication patterns:
- **Reads** (browse, profile detail) → REST over HTTPS, edge-cached for 60 s where safe.
- **Writes** → REST, transactional, idempotent on `request_id`.
- **Realtime** (messages, typing, presence, notifications) → Phoenix Channels over WSS.
- **Background** (push fan-out, moderation scans, embedding refresh, account deletion) → Oban jobs.

### Advantages
- A real backend layer means client never sees the DB anon key — entire class of credential exposures disappears.
- One language (Elixir) covers chat, REST, admin, background jobs, presence — no microservice sprawl until you actually need it.
- Phoenix Channels handles ~2M concurrent WSS on a single beefy VM (this is well-documented production reality at Bleacher Report, Discord's legacy stack, etc.).
- Oban + Postgres means no separate Redis-cluster-for-jobs operations burden.
- LiveView admin app means moderation tools render server-side, audit-log automatically, never get bundled with the user app, can be deployed independently.
- Riverpod (vs `provider`) gives compile-time dependency graph, easy mocking, no `context.read` footguns, declarative invalidation.
- Drift offline cache means messaging works on a subway / on a plane — crucial for the older "I'm flying to see my grandkids" use case.

### Disadvantages
- Elixir is harder to hire than Node/Go/Python. Mitigation: small team (1-2 backend) where you trade hiring breadth for per-engineer productivity. Phoenix's gentle on-ramp from Ruby helps.
- Adds an operational tier the current architecture doesn't have: you must run Postgres + Phoenix + Meilisearch + Redis. Mitigation: Fly.io or Render handles all four with minimal ops.
- Riverpod is a bigger learning curve than `provider`. Mitigation: it pays for itself in tests by week two.

### Migration difficulty
**4/5** if you keep the Flutter shell and rewrite the data layer behind it; **5/5** if you also rewrite Flutter screens against Riverpod. The Flutter UI layer is largely reusable — what changes is what sits behind the repositories.

### Recommendation
🔴 **Replace** the architecture. The current "Flutter → Supabase direct" pattern is fine for a prototype but it has put 100 % of business logic, auth gating, and moderation surface area inside the client — which is the wrong side of the trust boundary for a privacy-first dating app. A real backend tier is non-optional.

If full replacement is too expensive: 🟡 **Iterate** by introducing Supabase Edge Functions (Deno) as the missing tier and forbidding the client from doing anything except calling those functions. This is the cheap, 80-percent-of-the-value path. Long-term the Phoenix path is still better, but the Edge Functions path lets you ship faster.

---

## 4. Frontend framework

### Current implementation
Flutter 3.7.2 SDK. Material 2 mixed with some Material 3 widgets. Provider for state. GoRouter for nav. No code generation. ~40 packages in `pubspec.yaml`, ~15 unused.

### Proposed implementation
- Flutter 3.27+ (Material 3 Expressive + impeller everywhere + WASM web build).
- State: **Riverpod 2 + riverpod_generator + riverpod_lint** (kills 90 % of `provider` boilerplate, gives type-safe families, builds dependency graph at compile time).
- Routing: **GoRouter 14** (keep — same as today, modern enough).
- Models: **freezed + json_serializable** for immutable, JSON-roundtrippable data.
- Async: **dio** with retry interceptor (keep — already in pubspec).
- Local DB: **drift** (SQLite) for offline conversation cache + outbox pattern.
- Forms: **flutter_form_builder** + **form_builder_validators** (huge boilerplate killer for the 6-step onboarding).
- Animation: **flutter_animate** (keep — already in pubspec).
- Errors: **sentry_flutter**.
- Analytics: **posthog_flutter** pointed at self-hosted PostHog.
- Lints: **very_good_analysis** with strict rules.

### Advantages
- Single codebase still covers iOS / Android / Web — non-negotiable for a startup at this audience breadth.
- Riverpod fixes the testability gap. Today the auth/profile/messages providers cannot be unit-tested without spinning Supabase.
- freezed makes models immutable, which fixes a long tail of "I changed `_profile` and the UI didn't update" bugs.
- Drift unlocks **optimistic-send messaging**: the user types and sees their message immediately; the network is decoupled. Critical for free messaging UX over flaky mobile data.
- WASM web target gives the 50+ desktop audience a sub-2-second TTI even on Comcast residential.

### Disadvantages
- Riverpod's mental model is harder than `provider`'s. Two-week ramp.
- WASM web build has slightly worse first-load size today (~2.5 MB vs JS 1.5 MB). Mitigation: PWA + service worker + asset prefetch.
- drift adds a build_runner step.

### Migration difficulty
**3/5.** Screens can be ported off `provider` to `riverpod` 1 file at a time — they coexist fine. freezed + json_serializable replace hand-written models gradually. Drift is additive.

### Recommendation
🟡 **Iterate.** Keep Flutter, upgrade the SDK, adopt Riverpod + freezed + drift incrementally, throw away the unused packages. Don't switch frameworks; do switch state management.

---

## 5. Backend / API service

### Current implementation
None. The Flutter client talks directly to Supabase Postgres via PostgREST using the anon key. All authorization is RLS-only. There is no place to put business logic, server-side moderation, push fan-out, or webhooks.

### Proposed implementation
**Elixir/Phoenix 1.7+** monolith with three runtime surfaces:
- **JSON REST API** (`/api/v1/...`) for profile CRUD, search, settings, moderation reports, verification requests.
- **Phoenix Channels** (`/socket`) for messages, presence, typing indicators, notification fan-in.
- **LiveView Admin app** at `admin.nextchapter.app`, separate release, restricted by IP allowlist + admin role.
- **Oban** background workers in the same app: push-notification fan-out, moderation pipelines, embedding refresh, GDPR exports/deletions, abandoned-account reaping.

Why Elixir specifically:
- Phoenix Channels: best-in-class WebSocket primitives. Discord, Bleacher Report, Pinterest's notification system, and the Brazilian government's PIX payment messaging all run on Phoenix.
- BEAM VM gives soft-realtime guarantees + fault-isolation per connection (a misbehaving client cannot crash the box).
- The `Phoenix.PubSub` primitive makes "notify all conversation participants when a message arrives" a one-liner that scales to millions.
- Oban + Postgres means no Sidekiq/Redis-for-jobs operational burden.

Why not the obvious alternatives:
- **Node.js / Express:** great DX, but managing a million WebSockets across a Node cluster requires Redis pub/sub plumbing that Phoenix gives for free. Also single-threaded event loop bites at the wrong moment.
- **Go (chi/gin):** excellent performance, easiest hiring, but the WebSocket-fan-out story is "build it yourself with NATS or Centrifugo". Adds operational surface.
- **Django/FastAPI Python:** great for CRUD; for realtime chat at scale you end up bolting Channels (different Channels — Django's), Daphne, and Redis. More moving parts than Phoenix's one.
- **Supabase Edge Functions (Deno) only:** great for v1; hits limits when you need long-lived WebSockets, request-coalescing, or coordinated state.
- **Stream.io / Sendbird managed chat:** $$$ and "no selling user info" is in tension with their analytics; both are giving up the most differentiating piece to a third party.

### Advantages
- Removes the entire class of "client has too much trust" bugs (the privilege escalation in your current admin check disappears at the architecture level).
- One Elixir codebase covers chat + REST + admin + jobs.
- Free messaging cost stays manageable: ~1 cent per million messages on a single Hetzner box vs ~$1+ on Stream.io / Sendbird.
- Background-jobs-in-Postgres (Oban) means transactional consistency — when an Edge Function says "the user is deleted", their pending jobs are deleted in the same transaction. Sidekiq cannot.

### Disadvantages
- Hiring Elixir is slower than hiring Node/Go.
- Two deployable units (user-facing API and admin LiveView) versus one Supabase project — slightly more ops.
- LiveView's first-paint requires JS bundle; some accessibility tools don't love it. Mitigation: admin app is internal-only, accessibility burden is much lower there.

### Migration difficulty
**5/5** as a from-scratch rewrite. **3/5** if you do the "thin Phoenix gateway in front of existing Supabase" pattern: Phoenix proxies authenticated calls to Supabase short-term, you migrate tables off Supabase one at a time, then turn off direct Supabase access.

### Recommendation
🔴 **Replace.** A direct-to-DB architecture is the single biggest constraint on Next Chapter ever becoming production-grade. The Phoenix path is the highest-leverage architectural decision in this entire document.

---

## 6. Database

### Current implementation
- Supabase managed Postgres (Free tier — 500 MB DB, 1 GB Storage, 2 GB egress/month).
- 9 tables: `profiles`, `profile_photos`, `profile_interests`, `profile_looking_for`, `profile_life_situation`, `verification_status`, `user_settings`, `blocks`, `reports`.
- Three near-identical child tables for tag categories.
- RLS on everything, but admin policies missing.
- No `messages`, `conversations`, `matches`, `notifications`, `moderation_log`, `audit_log`, `verification_documents`, `meet_ups`.
- No indexes beyond PKs/uniques.
- No FTS, no geo, no vectors.

### Proposed implementation
PostgreSQL 16 (managed: Supabase Pro to start, migratable to Neon or self-host on Hetzner later).

**Schema sketch (about 22 tables):**

Core:
- `users` (auth identity, immutable DoB, locale, role enum, deletion_scheduled_at)
- `profiles` (visible profile, including verified flags as columns — not a separate table)
- `profile_tags` (polymorphic: kind ∈ {interest, looking_for, life_situation, prompt_answer, language, dealbreaker})
- `profile_photos` (with `is_primary`, `nsfw_score`, `face_count`, `moderation_status`)
- `profile_prompts` (Hinge-style: prompt_key + free-text answer, max 5)
- `profile_voice_intros` (15-30 s audio, with transcript for accessibility)

Discovery:
- `profile_geo` (PostGIS `geography(point,4326)` with city-level fuzzing precomputed; never stores exact GPS)
- `profile_embeddings` (pgvector(768) for bio + prompts)
- `profile_likes` (one-way: like, super_like, pass — for ranking only, never gates messaging)

Messaging:
- `conversations` (id, created_at, last_message_at, mode ∈ {date, friend, activity}, is_request, accepted_at, archived_by_users uuid[])
- `conversation_participants` (conversation_id, profile_id, joined_at, muted_until, last_read_at)
- `messages` (id, conversation_id, sender_id, body, kind ∈ {text, voice, image}, media_id, created_at, edited_at, deleted_at, moderation_status)
- `message_reactions` (message_id, profile_id, emoji)

Safety / trust:
- `blocks` (blocker, blocked, created_at, reason_optional)
- `reports` (with severity, evidence_message_id, evidence_photo_id, status, resolved_by, resolved_at, action_taken)
- `moderation_log` (actor, target, action, reason, created_at) — immutable; admin actions audited
- `audit_log` (actor, action, target_kind, target_id, ip, user_agent, created_at) — admin reads of PII recorded here
- `verification_documents` (kind, storage_path, status, submitted_at, reviewer_id, reviewed_at) — separate from profile, stricter RLS
- `trust_scores` (precomputed by background job; never user-visible)

Community:
- `meet_ups` (host, kind, location_geo, starts_at, capacity, mode ∈ {public, invite_only})
- `meet_up_rsvps` (meet_up, profile, status)

Notifications:
- `notifications` (recipient, kind, payload jsonb, read_at, delivered_at, channel ∈ {push, email, in_app})
- `notification_preferences` (per recipient, per kind)

GDPR/CCPA:
- `data_export_requests` (status, file_path, expires_at)
- `deletion_requests` (status, scheduled_for, completed_at) — drives the hard-delete pipeline

**Indexing strategy:**
- Partial indexes on the always-filtered combos: `WHERE is_suspended=false AND is_deleted=false` everywhere relevant.
- GIN on `profile_tags(value)` for tag-based filters.
- GIST on `profile_geo.location` for radius queries.
- HNSW (pgvector 0.5+) on `profile_embeddings.embedding`.
- `tsvector` generated column on `profiles(first_name, about_me)` + GIN.
- BRIN on `messages.created_at` (huge table, append-only).
- Declarative partitioning on `messages` by month once table > 50 M rows.

**RLS posture:**
- Every table has RLS enabled.
- Policies expressed via Postgres roles + a `current_profile_id()` SECURITY DEFINER function. No more "raw user_id = auth.uid()" boilerplate.
- Admin policies via `current_user_has_role('admin')` — backed by `app_metadata`, not `user_metadata`.
- All admin SELECT operations on PII tables write to `audit_log` via trigger.

### Advantages
- One database engine covers OLTP + geo + FTS + vector similarity. No Elasticsearch, no Cassandra, no separate Pinecone.
- Schema can answer "show me 20 verified-veteran profiles within 50 mi who match my looking_for and recently active" in one query under 50 ms with the proper indexes.
- The `profile_tags` polymorphic collapse removes three near-identical tables and lets you add `dealbreaker` / `language` / `dietary` categories without DDL.
- Hard-delete is straightforward: one `deletion_requests` row + cascading FK + Oban worker.
- Audit log + moderation log give you a real defensibility story when a journalist asks "how do you catch abusers".

### Disadvantages
- pgvector + PostGIS + Meilisearch is a meaningful schema complexity bump vs. the current 9 tables.
- Declarative partitioning is operationally non-trivial; can be deferred to the 10 M-messages mark.
- Postgres alone won't store all messages forever cheaply; at ~100 M messages plan a cold-storage tier (S3 + Parquet, queried via DuckDB).

### Migration difficulty
**4/5** as a clean cutover. **3/5** as an additive migration on top of the current Supabase project (add new tables, leave the old ones, dual-write during transition, drop old tables once traffic is shifted).

### Recommendation
🔴 **Replace.** The current 9-table schema misses too many production-required entities (`messages`, `notifications`, `audit_log`, `verification_documents`, `meet_ups`, `moderation_log`). And the three tag tables should be one. This is too central to iterate on; rebuild properly.

---

## 7. Authentication & identity

### Current implementation
- Supabase Auth, email/password only.
- Password min 6 chars.
- `is_admin` read from user-writable `user_metadata` (privilege escalation hole).
- DoB stored in `user_metadata` + `profiles` (drift risk + user-writable).
- No social, no phone, no passkeys.
- Anon key shipped in source.

### Proposed implementation
**Auth provider: Stytch B2C** (preferred) or **Hanko self-hosted** (if budget is tight or self-host purity matters).

Why Stytch:
- Native passkeys + magic links + passwordless + social out of the box.
- Privacy posture acceptable (HIPAA + SOC 2; not in the data-broker business).
- Pricing fits early-stage and is predictable: ~$0.05/MAU at consumer scale.

Auth modes offered to users, in this order:
1. **Passkey (WebAuthn)** — the *default*. Older users actually love it once you label the button "Sign in with your phone".
2. **Magic link (email)** — secondary. No password to forget.
3. **Phone OTP** — for users who don't email.
4. **Sign in with Apple** + **Sign in with Google** — frictionless, but the brand stance is "we minimize third-party tracking", so Apple is preferred to Google.
5. **Email + password** — last-resort, behind a "I prefer a password" link. Enforced 12 chars + breached-password check (Pwned Passwords API).

Roles & claims:
- Roles live on a `users.role` enum: `user`, `moderator`, `admin`, `super_admin`.
- The JWT issued to the client carries `role` and `profile_id` as immutable claims signed by the server.
- The client never writes `role` anywhere.

Session policy:
- Access token TTL: 30 minutes.
- Refresh token TTL: 30 days; rotated on every use; invalidated on password change.
- Forced re-auth before "delete account" and "change email".
- Concurrent session limit: 5 devices, with a session list UI.

CAPTCHA: **hCaptcha** on signup and on >3 failed login attempts.

### Advantages
- Privilege-escalation class of bugs vanishes (role is server-issued, signed, never client-set).
- Passkeys + magic link cuts password-reset volume by ~80 % at this demographic — confirmed in older-audience product data.
- Single auth vendor with audit-quality logs.

### Disadvantages
- Stytch is a paid SaaS. ~$0.05/MAU. At 100 K MAU = $5 K/mo. Not nothing; cheap vs the engineering cost of rolling your own.
- Adds an external dependency for login. Mitigation: cache JWT validation keys; the app survives a brief Stytch outage for already-signed-in users.

### Migration difficulty
**4/5.** Migrating live Supabase Auth users to Stytch requires a bulk import + forced password reset on first login. Stytch supports this flow but it is a coordinated cutover.

### Recommendation
🔴 **Replace.** The current auth model has one critical bug (privilege escalation) and three serious gaps (no passkeys, no phone, no breached-password check). All three are vendor-product-shaped problems. Better to use the right vendor.

If budget is tight: 🟡 **Iterate** — stay on Supabase Auth, fix the role bug, enable hCaptcha, add Sign in with Apple/Google. This is a 1-week project rather than a 4-week project. The roadmap allows for moving to Stytch later.

---

## 8. Profile system

### Current implementation
First name, DoB, city, state, gender, relationship status, about_me (500 chars), photo URLs, tags across three tables, verification flags in a separate table. Photos go to a private bucket with 10-year signed URLs.

### Proposed implementation
**Profile = 4 layers, building from least private to most:**

1. **Public surface** — first name (or chosen display name), age (with optional ±2 fuzzing toggle), city *or* region (user picks granularity), pronouns, primary photo. Visible to logged-in users in browse.
2. **Profile detail** — about_me, prompts (Hinge-style, pick 3 from ~40 curated questions), voice intro, all photos, life chapter tags, looking_for tags, languages spoken. Visible only after profile is opened.
3. **Verification surface** — badges (email/phone/selfie/ID + earned ones: veteran, retiree, widowed-opt-in). Visible to others but the underlying documents are not.
4. **Private (only visible to self)** — exact DoB, exact location, full contact details, settings.

**Prompts** are the most underappreciated UX upgrade for an older audience:
- Curated set of ~40, each tonally appropriate ("My next chapter is about…", "Something I've finally let go of…", "Saturday at 10 a.m. I'm probably…", "A song that makes me cry-laugh…").
- Pick 3, answer in ≤150 chars each. Visible on profile.
- One prompt is a **voice prompt** (15-30 s audio with auto-transcript for accessibility).

**Photos:**
- 1–6 photos.
- Primary photo must pass face detection (one face, eyes open) — eliminates car-mirror selfies and sunset-only profiles that drive low reply rates.
- All photos run through Sightengine (NSFW + face + watermark detect) on upload before they are visible.
- Photos served via Cloudflare Images: URL has signed transforms (`/w=480,q=80`) and is rotatable.

**Profile completeness score** (server-side, 0–100):
- +20 primary photo passes face check
- +15 about_me ≥ 50 chars
- +10 each prompt answered (×3 = 30)
- +10 ≥ 3 interests
- +10 voice intro
- +15 phone verified
- Display the score to user; do *not* gate the score on payment.
- Hide profiles below 40 from default browse (configurable).

**Privacy controls per field:**
- Each field has a visibility setting (`everyone | matches_only | nobody`) with a sensible default.
- "Last active" precision adjustable: exact / today / this week / hidden.
- City precision adjustable: exact / metro / state / hidden.
- Age precision: exact / decade / hidden (with rule: dating-mode requires at least decade).

### Advantages
- Privacy-by-design defaults — users see exactly what is shared, can dial it down per field.
- Voice intros are a 10× signal for trust at this demographic; cheap to implement.
- Prompts dramatically improve reply rates (Hinge's primary moat) and are easier for older users than "fill 500 chars of biography".
- Photo face-check eliminates the most common bot/fake pattern automatically.

### Disadvantages
- Per-field privacy UI is more complex than today's flat "share all on" model.
- Voice intros and face-detection require background processing — needs Oban workers.

### Migration difficulty
**3/5.** Tables are additive; UI is mostly new screens. Existing profiles map cleanly.

### Recommendation
🔴 **Replace** the profile model. Today's flat profile is the same shape as POF circa 2003. The proposed model is the same shape as Hinge, but with privacy controls that Hinge doesn't have. This is the single biggest UX differentiator.

---

## 9. Messaging

### Current implementation
100 % mock. No `messages` table. In-memory list per chat screen. "Free unlimited messaging" is currently aspirational copy.

### Proposed implementation
**Phoenix Channels over WebSockets + Postgres for durable storage + Oban for fan-out.**

Conversation states:
- `request` — only one message sent, recipient hasn't replied yet. Sits in the "Requests" tab.
- `active` — recipient has replied at least once; promotes to "Messages" tab.
- `archived` — either party archived (still queryable via "Archived"); fully hideable.
- `blocked` — between two parties, one has blocked the other; messages disabled both ways but history retained for safety review.

Message kinds:
- `text` (max 2,000 chars)
- `voice` (≤ 90 s, auto-transcribed for accessibility; transcript stored alongside audio)
- `image` (≤ 10 MB, passed through Sightengine before delivery, NSFW blocked at server)
- `system` (e.g., "Sarah accepted your message request", "Date safety check-in suggested")

Wire protocol (Phoenix Channels):
- Client joins `conversation:{id}` with JWT.
- Server validates participation via `conversation_participants`.
- Send/receive over the same channel.
- Typing indicators ephemeral via Phoenix.Presence.
- Read receipts: optional, default ON, can be disabled globally by either user (no paywall).

Reliability:
- Client maintains an outbox in drift (SQLite) — messages "sent" optimistically appear instantly even offline; sync when the WSS reconnects.
- Server assigns a monotonic `created_at` on insert; clients reconcile by server ID.
- Idempotency: client supplies `client_message_id` (UUID); duplicate inserts return the existing row.

Safety in messaging:
- Pre-send moderation: text scanned client-side for catfish-scam keyword regexes (free, fast, hint warning), then server scans via OpenAI Moderation or self-hosted Detoxify (defer hard block; flag for review).
- Images scanned synchronously via Sightengine before delivery.
- "Safety check-in" system message can be scheduled by either party: "I'm meeting @Sarah at 7pm. Ping me at 9pm." Phoenix scheduler triggers an OK/SOS at the set time; SOS auto-emails the user's pre-set emergency contact (opt-in feature).
- "First message of the day from a verified user" priority delivery — never silenced by Do Not Disturb.

Free messaging at scale — cost reality:
- 1 message ≈ 200 bytes Postgres write + 1 WSS broadcast + 1 push notification.
- 100 M messages/month ≈ 20 GB DB write, 100M push fan-outs.
- Cost on Postgres Pro: ~$50/mo extra. Push: free via FCM/APNs. Storage: ~$0.50.
- This is why Phoenix is the right choice: same workload on Sendbird is ~$3,500/mo.

Retention:
- Active conversation messages: retained indefinitely (default).
- User can set per-conversation auto-delete after 30/90/365 days.
- On account deletion: all messages sent by that user are scrubbed of body text and replaced with "[message removed — user deleted]" within 30 days. Counter-party's view preserves chronology but not content.

### Advantages
- Free messaging is actually free to operate, sustainably.
- Realtime + offline + reliable in one design.
- Safety check-in is a brand-aligned safety feature no competitor offers.
- Voice messages dramatically improve communication for older users.

### Disadvantages
- WebSocket plumbing is more complex than polling. Mitigation: Phoenix abstracts most of it.
- Server-side moderation introduces ~50-150 ms per message — perceptible. Mitigation: optimistic delivery to sender, lazy moderation on recipient side.

### Migration difficulty
**5/5** — replacing mock with this is a from-scratch build of the most important feature, but it's a build you have to do anyway.

### Recommendation
🔴 **Replace** (the mock). Build messaging as described. The Phoenix Channels approach is the linchpin that makes free messaging economically possible long-term.

---

## 10. Search & discovery

### Current implementation
`BrowseProvider.loadProfiles()` fetches all profiles into memory then filters client-side. State-only and city-substring filters. Verified-only toggle. No distance, no FTS, no ranking.

### Proposed implementation
**Three feeds, one ranking function, server-side throughout.**

Feeds (tabs on Browse):
1. **For You** — ranked by `match_score(viewer, candidate)` (described below). Cursor-paginated 20-at-a-time, infinite scroll.
2. **New** — last 14 days of signups in viewer's region. Sorted by activity, then completeness.
3. **Has things in common** — explicitly surfaces shared interest/life-situation count. Sorted by overlap × distance.

Mode selector (sits above the tabs): **Date / Friend / Activity Partner**. Independent feeds per mode; user can be in date-mode for one person and friend-mode for another simultaneously.

Filters (sheet, applies to current feed):
- Distance (5 / 10 / 25 / 50 / 100 / 250 mi / Anywhere). Uses PostGIS `ST_DWithin`.
- Age range (with default ±15 from viewer's age; one-tap "Anywhere 18+").
- Looking-for (multi-select).
- Interests / Life situation (multi-select).
- Verification tier (one or more of Phone / Selfie / ID).
- Has voice intro? (toggle — major reply-rate signal).
- Activity within (1 day / week / month).

Match score function (computed in Postgres):
```
score = 0.35 * lookingFor_jaccard
      + 0.20 * lifeSituation_jaccard
      + 0.15 * interests_jaccard
      + 0.10 * geo_proximity_decay(distance_km)
      + 0.10 * age_compat(viewer, candidate)
      + 0.05 * verification_strength
      + 0.05 * recency_bonus(last_active)
```
Then re-ranked by **pgvector bio-similarity** as a tiebreaker. All weights tunable per-user via a "what matters most to you" slider trio (intentions, geography, interests). No black-box ML required; later, replace with a learned ranker once you have labels.

Search bar (text): fuzzy across first name, city, prompt answers (where visibility allows). Backed by Meilisearch with a 1-minute index refresh job.

### Advantages
- Server-side throughout; scales to millions.
- Three feeds + three modes lets the brand thesis (dating + friendship) live in the architecture, not just the marketing.
- All weights explainable to users ("we showed you Sarah because she's also a recent retiree in Austin and her bio mentions hiking"). No black-box ML.

### Disadvantages
- Three feeds × three modes × filters = 9 result sets per user — non-trivial caching strategy. Mitigation: 60 s edge cache per (user, feed, mode, filter-hash); a write to anyone in the slice invalidates only their slice.
- Re-rank by embedding adds ~10 ms per query.

### Migration difficulty
**4/5.** Schema needs profile_tags (already adding), geo column (new), embeddings (new), the match score function (new SQL). Front-end is a redesign.

### Recommendation
🔴 **Replace.** Today's browse is the single largest scalability risk in the current build. The new model is the actual feature.

---

## 11. Matching / connection model

### Current implementation
None. No likes, no matches, no "interested in" signals. Anyone can message anyone via the (mock) chat.

### Proposed implementation
Free messaging is sacred, so we do **not** gate messages behind matches. But we still want explicit "interested" signals because they:
- Power ranking.
- Drive a healthy "Who's interested in you" tab.
- Allow consent gating for opt-in higher-trust modes.

Three signals, all free:
- **Like** — quiet positive signal. Recipient sees in "Interested in you" tab.
- **Send a "Hi"** — single-message intro. Goes to recipient's Requests tab; recipient must accept (one tap, or just reply) to promote to Messages.
- **Pass** — quietly suppresses re-appearance in feeds for 60 days. Reversible.

Optional consent gating:
- Each user has a per-mode "First contact" setting: `Anyone` (default) / `Verified-only` / `Mutually liked first`.
- The "Mutually liked first" setting gives users who want it a Bumble-style gate, while leaving free messaging as the default.

"Super signals" (rare, time-boxed, all free):
- One free **highlighted message** per week (sender's photo is slightly larger in recipient's request list).
- One free **boost** per month (your card appears in 50 more feeds in your area for an hour).

Optional paid super-signals (monetization, never gating regular messaging):
- Extra boosts ($1.99 each).
- "Travel mode" — fake your location for a city you're visiting next month.
- See "who liked you" (free shows count, paid shows names) — POF's best monetization, brand-acceptable.

### Advantages
- Free messaging fully preserved.
- Users who *want* tighter consent gating can opt in.
- "Like" gives the ranker a strong implicit signal without forcing matching mechanics on people who hate them.

### Disadvantages
- Slightly more concepts to teach in onboarding ("send a hi" vs "send a like" vs "pass").
- Anti-spam pressure now lives in the request-acceptance flow rather than at message-send.

### Migration difficulty
**3/5.** Two new tables (`profile_likes`, `profile_passes`), one new tab, one new privacy preference.

### Recommendation
🔴 **Add** (this didn't exist before). Definitively yes — without "interested" signals you have no ranking input and no re-engagement loop.

---

## 12. Friendship & multi-mode

### Current implementation
Looking-for tags include "Friendship", "Local Friends", "Travel Partner", "Activity Partner" — but they are filter chips only. There is no first-class friendship mode. A user is one user, one profile, one inbox.

### Proposed implementation
**A single profile, three independent visibility modes**:
- **Date** — visible in date-mode browse; mutual likes count for matching; date-safety check-ins.
- **Friend** — visible in friend-mode browse; no romantic framing copy; matches show "shared interests" rather than compatibility %.
- **Activity** — visible in activity-mode browse; surfaces local meet-ups; focuses on "what do you want to do" rather than "who do you want to be with".

Per-mode controls:
- Toggle each mode on/off independently.
- Per-mode bio (optional override).
- Per-mode visible age range / distance.
- Per-mode photo selection (e.g., dating photo + activity photo with hiking buddies).

Inbox is one inbox, but each conversation is tagged with the mode it began in. Friend-mode conversations don't show date-safety prompts. Date-mode conversations don't show "join my hiking meetup" suggestions.

### Advantages
- Genuine architectural support for the brand's "dating + friendship" thesis. Bumble (BFF / Bizz) and Match (Stir Events) have tried this; nobody has nailed it because they bolted it on as a sub-app. We bake it in.
- Older users who feel uncomfortable openly dating can start in friendship mode without re-onboarding.
- Significantly expands TAM: the "I just want hiking buddies" market is larger than the "I want to date" market in many demographics.

### Disadvantages
- Triples the onboarding decision space — needs careful copy and progressive disclosure.
- Ranker has to be aware of mode (already accounted for in §10).

### Migration difficulty
**3/5.** Mostly UI and a per-mode preferences table.

### Recommendation
🔴 **Add.** This is the single biggest brand-product alignment opportunity.

---

## 13. Verification

### Current implementation
4 boolean columns (email, phone, selfie, ID). Email is set by Supabase. The other three are user-writable via RLS — i.e., today a user can set themselves to ID-verified.

### Proposed implementation
**Tiered, earned, partially monetized:**

| Tier | Method | Provider | Cost | Visible badge |
|---|---|---|---|---|
| 1 | Email | Stytch | free | "Email ✓" (faint) |
| 2 | Phone | Twilio Verify | $0.05 once | "Phone ✓" |
| 3 | Selfie liveness | Persona Lite | $0.10–0.30 once | "Real Person ✓" |
| 4 | Government ID match | Stripe Identity | $1.50 once | "ID Verified ✓" |
| 5a | Veteran badge | VA.gov OAuth | free | "Veteran ✓" |
| 5b | Retiree badge | manual review of document | ~$0.50 human-min | "Retired ✓" |
| 5c | Widowed badge | manual, opt-in, sensitive | ~$0.50 human-min | "Widowed ✓" |
| 5d | Local check-in | geocoded photo at landmark | free | "Local ✓" |
| 5e | Background check (US only) | Garbo/BeenVerified API | $14.99 | "BG Cleared ✓" |

Tier 3 (Selfie) is the trust inflection point. Once 40 % of the userbase has Tier 3+, the platform's reply rate compounds.

Architecture:
- All verification flows are server-side. Tokens issued by the provider go to a webhook (Phoenix endpoint) that updates `verification_documents` and the corresponding profile flag in a transaction.
- The flag columns on `profiles` are **never** user-writable. RLS denies. Only the webhook (running as a service role) can set them.
- Documents (selfie images, ID images) are stored encrypted at rest in R2 with per-row keys derived from a KMS master. Admins viewing them generates an audit_log entry.
- Tier 5b/c (manual) flow into a moderation queue with redacted document preview; reviewers can't download originals.

Pricing model:
- Tiers 1, 2, 5a, 5d → free.
- Tiers 3, 4 → paid one-time ($4.99 selfie+ID bundle is the recommended SKU).
- Tier 5e → $14.99 one-time.

The badges are visible in browse cards and on profile detail. Filters can require a tier.

### Advantages
- Trust is *earned* (not declared). Eliminates the current self-write vulnerability.
- The earned-badge tier (Veteran/Retired/Widowed/Local) is the brand's actual moat — no major competitor verifies these, and your demographic deeply cares about them.
- Free messaging stays free; verification is the natural monetization lane.

### Disadvantages
- Manual review tier costs human-minutes; needs an SLA (24 h).
- ID providers add a new compliance surface (GDPR special-category data).

### Migration difficulty
**4/5.** Schema is doable. The flows are 4 separate integrations.

### Recommendation
🔴 **Replace.** The current model is structurally insecure (P0 in the audit). Build it right or skip the feature.

---

## 14. Moderation & safety

### Current implementation
Admin screen reads from `MockDataService`; suspend/delete/resolve are dummy snackbars. Reports table has no admin RLS policy. No keyword scan. No image moderation. No moderation log. No appeals flow.

### Proposed implementation
**Three layers: prevent, detect, respond.**

**Prevent** (before bad content exists):
- Photo upload runs through Sightengine: NSFW, child-safety match, face detect, watermark detect, "stock photo" detect. Block at upload, fail with explanation.
- Message send runs through OpenAI Moderation (or self-host Detoxify). Decision: deliver, deliver+flag, hold.
- Signup runs through hCaptcha + disposable-email block + IP reputation check.

**Detect** (after content exists):
- Crowd reports surfaced in a moderation queue with severity.
- Trust score: composite of (account age × verifications × reply ratio × report ratio × block ratio). Low-trust profiles get extra scrutiny.
- Pattern detection: 5+ reports against one user in 24 h auto-suspends pending review.
- Periodic re-scan of older photos as the moderation provider's models improve.

**Respond** (when something is flagged):
- Moderation queue in the Phoenix LiveView admin app.
- One-tap actions: dismiss, warn, suspend 24 h / 7 d / forever, full ban (auth user deleted, messages scrubbed).
- Every action writes `moderation_log` + `audit_log` entries.
- User receives a clear notice with reason, with appeal link.
- Appeals open a second queue.
- For severe categories (CSAM, threats of violence, doxxing): mandatory NCMEC report (US legal requirement), auto-preserved evidence in cold-storage bucket with retention.

**Safety features (user-facing):**
- "Date safety check-in" (see §9).
- "I felt unsafe" report kind — auto-blocks the reported user during review.
- Optional **safety nudges**: if a user is messaging someone they haven't liked back, soft prompt "have you both shown interest?" — reduces unwanted attention without paywalling.
- **Safety contacts**: user can pre-register up to 3 emergency contacts (email or phone) for SOS escalation.
- **Quiet mode**: hide your profile from search for 7/30/90 days without deleting.

### Advantages
- Real moderation > theater moderation. Legal exposure drops dramatically.
- Audit log + moderation log = real defensibility in court / press.
- Safety nudges + check-ins are brand-aligned, free, and competitively differentiated.

### Disadvantages
- Sightengine costs ~$0.001/image. At 1 M images/month = $1,000.
- OpenAI moderation has rate limits; need self-host fallback.
- Manual moderator headcount is real ops cost (~1 mod per 10K MAU initially).

### Migration difficulty
**4/5.** Net-new system.

### Recommendation
🔴 **Replace.** The current "mock admin" is a launch blocker.

---

## 15. Administration

### Current implementation
Admin screen in the user-facing Flutter app, reads from `MockDataService`. No separate URL. No audit. No role-gating server-side (gated only by client `isAdmin` getter).

### Proposed implementation
**Separate web app — `admin.nextchapter.app` — Phoenix LiveView.**

Why separate:
- Different security posture (IP allowlist, hardware-key MFA required).
- Different bundle (doesn't ship admin code to end users).
- Different release cadence (admins are 10 people, users are 1 M people).
- Different audience (no need for Material 3 polish; LiveView's "looks like a respectable internal tool" is ideal).

Surfaces:
- **Moderation queue** (sorted by severity, SLA, age).
- **Reports list** (filter by reason, status, severity, target).
- **Users list** (search by email/phone/profile-name).
- **User detail** — full profile, recent messages (with audit log entry on view), reports against, verifications, trust score, action buttons (suspend/ban/restore/refund).
- **Verification queue** (Tier 5b/5c manual reviews).
- **Live metrics dashboard** — DAU/WAU/MAU, signups/day, reports/day, ban rate, message volume, push success rate.
- **Audit log explorer** — search by actor / action / target. Read-only.
- **System settings** — feature flags, weights for ranker, content moderation thresholds.

Roles:
- `read_only` — view but no actions (analysts).
- `support` — view + warn + restore.
- `moderator` — view + warn + suspend + resolve reports.
- `admin` — moderator + ban + refund + verification overrides.
- `super_admin` — admin + role assignment + settings + audit log purge (rare).

All admin authentication via Stytch with mandatory hardware key.

### Advantages
- Cleanly separates the trust boundary.
- LiveView is exceptionally fast to build internal tools in (sometimes 10× faster than React-Admin).
- Audit log built in via Plug middleware.

### Disadvantages
- Two deploys instead of one.
- LiveView has a learning curve for engineers new to Elixir.

### Migration difficulty
**5/5** as net-new.

### Recommendation
🔴 **Replace.** Admin tooling inside the user app is an architectural anti-pattern. Separate it.

---

## 16. Notifications

### Current implementation
`awesome_notifications` is in `pubspec.yaml`; never used. No push backend. No email backend. No SMS. No in-app preferences.

### Proposed implementation
- **Push**: Firebase Cloud Messaging (FCM) for both iOS (via APNs proxy) and Android. Free.
- **Email**: **Resend** (privacy-first, developer-first). Templated via MJML.
- **SMS**: **Twilio**, *only* for verification and SOS — never marketing.
- **In-app**: persistent feed in the app, real-time via Phoenix Channels.

Pipeline:
1. Domain event happens (`message_inserted`, `like_received`, `safety_check_due`, `report_action_taken`).
2. Phoenix broadcasts on the appropriate Pub/Sub topic.
3. Oban worker enqueues outbound notifications across channels per user preferences.
4. Delivery results are logged; failures retried with exponential backoff.

Per-user preferences (granular):
- Notification kinds: messages, likes, profile views, safety reminders, verification updates, weekly digest.
- Channels per kind: push, email, in-app, none.
- Quiet hours.
- Digest mode ("daily summary instead of per-event").

Anti-overnotification:
- Coalesce: 5 likes in 10 minutes = one notification, not five.
- Throttle: never more than one push per user per 15 minutes (configurable).
- No marketing growth-hack pushes ("Sarah just joined!"). Brand-defining.

### Advantages
- Modern privacy-respecting stack (Resend, not SendGrid).
- Quiet hours + digest mode = older-user-friendly.
- Coalescing avoids notification fatigue.

### Disadvantages
- Resend pricing scales linearly; at 1 M MAU it's ~$1,000/mo. Acceptable.
- FCM token management is fiddly on web (use service workers).

### Migration difficulty
**4/5** — net-new system.

### Recommendation
🔴 **Add.** Today there is nothing. Without push, free messaging cannot compete.

---

## 17. Performance & scalability

### Current implementation
- All-rows browse fetch.
- N+1 in `_assembleProfile`.
- No indexes beyond PKs.
- No caching.
- No CDN for images.
- Free Supabase plan caps out around 100 users with photos.

### Proposed implementation
**Per-tier targets and architectural moves:**

| Scale | Strategy |
|---|---|
| 0 – 10 K MAU | Single Phoenix instance + Postgres Pro + Cloudflare in front. No replicas needed. |
| 10 K – 100 K | Two Phoenix nodes behind LB + Postgres + 1 read replica + Redis presence cluster. Edge cache on browse. |
| 100 K – 1 M | Phoenix horizontally scaled via libcluster + Postgres primary + 2 read replicas + connection pooling (Supavisor or PgBouncer) + Meilisearch HA + R2 + Cloudflare Images + push fan-out via dedicated Oban node. |
| 1 M – 10 M | Declarative partition `messages` by month, BRIN indexes. Move cold messages (>365 d) to S3+Parquet, queried via DuckDB. Separate the messaging Phoenix node-class from the REST one. |
| 10 M+ | Per-region Phoenix clusters (multi-region Postgres via Patroni or move to CockroachDB). Bring up Scylla for chat if Postgres saturates writes. |

**Always-on optimizations:**
- Edge cache browse cards for 60 s; invalidate on profile update via `Cache-Tag` headers.
- Cloudflare Images for resize + WebP + AVIF; 1 source photo serves all device sizes.
- All list endpoints cursor-paginated (no offset).
- Connection pooling tuned to ~10× CPU count.
- N+1 forbidden by code review; repo functions explicitly load assemblies in one query.
- Background recomputation of ranker scores (so first-paint hits a precomputed table).
- Drift (client-side SQLite) caches browse cards for instant resume.

### Advantages
- Linear scaling. No "rewrite needed at 100 K users" moment.
- Cost per user stays low because the image tier (the heavy bandwidth user) lives on Cloudflare ($0 egress) not S3.

### Disadvantages
- Multiple moving parts (Phoenix + Postgres + Redis + Meilisearch + R2). Mitigation: Fly.io / Render reduce ops to dashboards.

### Migration difficulty
**4/5** — backed-in across the new architecture.

### Recommendation
🔴 **Replace** (the current performance posture). Today the app cannot survive 1 K real users. The new design comfortably reaches 1 M.

---

## 18. Security

### Current implementation
Anon key in source, privilege escalation via `user_metadata`, no admin RLS for reports, user-writable verification flags, no CSP, public diagnostics route, no rate limiting at app level, no CAPTCHA, no breached-password check, 6-char passwords, no audit log, 10-year-signed photo URLs.

### Proposed implementation
**Defense in depth, starting from a STRIDE pass on every endpoint.**

- **Auth** — Stytch with passkeys; JWT issued server-side; role in `app_metadata` only.
- **AuthZ** — Postgres RLS as the floor; Phoenix Pundit-style policies as the ceiling; admin actions double-check both.
- **Secrets** — `.env` per environment, encrypted via `sops` + age. No secrets in source.
- **Transport** — TLS 1.3, HSTS, certificate pinning on mobile.
- **CSP** — strict CSP on web build: `default-src 'self'; img-src 'self' https://images.nextchapter.app data:;` etc.
- **Rate limiting** — Cloudflare WAF + per-route in Phoenix via `hammer` (token bucket). Login: 5/15 min/IP. Signup: 3/h/IP. Message send: 60/min/user.
- **Bot defense** — hCaptcha on signup; Cloudflare bot management.
- **PII at rest** — DB encrypted by managed provider; sensitive columns (DoB, last 4 of phone) field-level encrypted via libsodium with KMS-managed keys.
- **Verification documents** — separate encrypted bucket; per-row keys; viewable only by admins; every view logged.
- **Signed URLs** — short-lived (10 min) for media; Cloudflare Images transform URLs preferred where possible (no signing needed).
- **CSRF** — irrelevant for JWT API; for LiveView admin app, the framework handles it.
- **Headers** — security headers via Cloudflare workers (HSTS, X-Content-Type-Options, Referrer-Policy: strict-origin-when-cross-origin, Permissions-Policy).
- **Audit log** — every admin action and PII view → `audit_log`. Immutable. Append-only.
- **Bug bounty** — public program (HackerOne or self-host); $50 minimum, $5,000 max.
- **SOC 2 path** — start with Drata or Vanta from day one; cheap when small, painful retro.

### Advantages
- Production-grade. Will survive a press incident.
- Every privilege escalation surface from the current build is closed at the architecture level.

### Disadvantages
- More moving parts. Mitigation: pick managed Cloudflare; everything else is config not infra.

### Migration difficulty
**3/5** — most of this is configuration, not code.

### Recommendation
🔴 **Replace.** Multiple P0 security issues in the current build need to be fixed regardless; doing them as part of a coherent posture is cheaper than as scattered patches.

---

## 19. Privacy posture (the brand promise)

### Current implementation
Privacy is asserted in marketing copy ("we will never sell your data") and partially enforced via RLS. No data-flow diagram. No DSAR (data-subject access request) flow. No granular per-field privacy controls. No third-party tracking but also no policy enforcing this.

### Proposed implementation
A **named, enforced, audited privacy posture**.

Data minimization:
- DoB is the only legally-required PII. We collect nothing else mandatorily.
- City/state default to "metro" precision; user can opt up or down.
- We **do not** collect phone unless verifying, and we store only the hash + last 4 after verification.
- We **do not** collect ID document images beyond verification; document is destroyed within 30 days of successful verification, only the result + last 4 of ID number retained.

Third-party policy:
- No Facebook SDK, no Google Analytics, no Mixpanel, no Segment, no Adjust, no Branch, no AppsFlyer.
- Analytics: **PostHog, self-hosted**, with anonymized IPs.
- Crash reporting: **Sentry self-hosted** or **Glitchtip**, with PII scrubbing.
- Performance: **Grafana + Tempo + Loki** self-hosted.
- The list of third parties is published on `nextchapter.app/privacy/subprocessors` and updated on any addition.

User-facing privacy controls:
- **Privacy ledger** — single screen in Settings showing exactly which fields are visible to whom, with toggles. Includes "last viewed" log for own profile.
- **Quiet mode** — hide from search for 7/30/90 days.
- **Cone of silence** — disappear entirely without deleting (account dormant; no profile shown; messages still receivable but not surfaced).
- **DSAR exports** — one-click export of all your data as a structured JSON (Oban worker, link emailed when ready).
- **Right to delete** — see §22.

Internal access controls:
- Engineers cannot read user PII in production. Period.
- Production DB queries require a ticketed request that auto-logs the query and target.
- Customer-support staff see only redacted fields by default; "reveal" requires a justification text and writes audit_log.

Legal:
- GDPR-compliant data processing agreement.
- CCPA-compliant disclosures.
- Children's safety: hard 18+ gate (DB CHECK), automatic NCMEC report pipeline for CSAM.
- Data retention policy published and enforced via Oban: deleted accounts purged at 30 days; logs purged at 90 days; verification documents purged at 30 days; analytics rolled up and PII-stripped at 13 months.

### Advantages
- "We don't sell you" becomes provable, not just claimed.
- Privacy posture is the brand's strongest differentiator vs. POF/Match (which absolutely *do* sell behavioral data).

### Disadvantages
- Self-hosting analytics + crash reporting + observability is real ops work.
- Some integrations (Apple Sign-In) bring third-party trackers — must be carefully gated.

### Migration difficulty
**4/5** — touches every layer.

### Recommendation
🔴 **Replace** (the current "we promise but don't prove it" posture). Make the promise auditable.

---

## 20. User experience

### Current implementation
Material 3 with custom warm palette. Three-tab bottom nav (Browse / Messages / Settings). Card grid on Browse. Profile detail with sliver app bar and bottom CTA. Forms heavy in onboarding. Some accessibility gaps (small hit targets, color-only signals).

### Proposed implementation
**Material 3 Expressive baseline + an identity layer that's *quietly distinctive*** (not loud, not "AI-design-slop"):

- **Type system**: a humanist serif for headings (e.g., Söhne or Tiempos as a paid choice; **Newsreader** or **Fraunces** as free alternatives) over a clean grotesque for body (e.g., **Inter** — but use only weights 400, 500, 700; trim the family). Why a serif: differentiates instantly from POF/Match/Bumble (all sans-serif); reads as "newspaper / story" not "tech app".
- **Color**: warm primary; high-contrast pairing in dark mode by default; semantic color tokens.
- **Motion**: opinionated but restrained. Spring physics for page transitions; reduced-motion variant respects system pref.
- **Layout**: left-aligned editorial, generous whitespace (think Substack/Stratechery, not Tinder).
- **Iconography**: line-icon set (e.g., Phosphor Icons free tier), not Material's stock; the heart icon retired in favor of a "next page" or "open book" mark.
- **Empty states**: written like a friend ("No messages yet. Want to say hi to Sarah? She's into hiking too."), not like a SaaS dashboard.
- **Microcopy**: warm, plain. "Hi" not "Match". "Say hi" not "Send DM". "I felt unsafe" not "Report".

**Navigation:**
- Bottom nav becomes **4 tabs**: Home (For-You feed) / Inbox / Profile / Settings.
  - Profile-as-tab is essential at this demographic — "where do I see how I look to others" is the most asked question.
  - Inbox shows badge for unread + requests.

**Onboarding** (≤90 seconds, 6 steps, exit anywhere with progress preserved):
1. Email/passkey
2. Name + DoB (18+ gate)
3. Mode selection (Date / Friend / Activity — multi-select)
4. 1 photo (face-detected before continue)
5. 3 prompt answers (skippable, but "your profile is 3× more likely to get a reply with prompts" nudge)
6. Looking-for + interests + life situation (multi-select chips)

After step 6 → land on Home with the new-user banner "Your profile is 60% complete — add a voice intro to round it out."

**Microinteractions to invest in:**
- Send-message animation: optimistic insert + slight scale-up + read receipt fade.
- Photo zoom: Hero animation, never opens in a modal.
- Tab change: cross-fade with subtle parallax.

**Dark mode**: ship at parity, not as a postscript.

### Advantages
- Older users feel *seen* (literate type, generous space, plain copy).
- Distinctive visual identity that's not generic Material.
- Information density tuned for actual reading, not glancing.

### Disadvantages
- More design opinions to maintain. A design system + Figma library required.
- Custom motion + serif heading + dark mode = more QA matrix.

### Migration difficulty
**4/5** if a full redesign; **2/5** if iterating from the current palette.

### Recommendation
🟡 **Iterate.** The current design language is on-brand. Don't throw it away — push it further into editorial/literary territory.

---

## 21. Accessibility (separately called out — biggest brand-aligned moat)

### Current implementation
Material 3 widget defaults. No `Semantics` labels on icon-only buttons. Small hit targets (12-14 px close icons). Color-only online/offline indicator. Verified badge fails WCAG AA contrast.

### Proposed implementation
**Targets:**
- WCAG 2.2 AA across all user-facing surfaces; AAA in onboarding and safety flows.
- Minimum hit target 48×48 (Material) — no exceptions in production.
- Contrast ≥ 4.5:1 for all text; ≥ 7:1 for elderly users in "Large text + high contrast" mode (toggle in Settings).
- Respects system `textScaler` up to 200%; layouts reflow, never clip.
- `Semantics` labels on every interactive element; tested with screen reader (TalkBack/VoiceOver) by an actual user with low vision in beta.
- Reduced motion respected; no parallax for users who opt out.
- All voice messages auto-transcribed (Whisper API or self-host). Transcript shown to users with reduced hearing; transcript also indexed for search.
- Color-blind safe palette tested with Sim Daltonism.
- No "color-only" signals — every state has a text and/or icon equivalent.
- Keyboard navigation works fully on web; visible focus rings; skip links.
- A "Read aloud my matches" feature for users with low vision, surfacing bio + prompts via TTS.

### Advantages
- The brand promise ("everyone, 18-100") becomes literal.
- Marketing line "the dating app that actually works at 200% font scale" is sticky and true.
- Reduces support volume from older users.

### Disadvantages
- 10-15% engineering tax on UI work.
- QA matrix grows.

### Migration difficulty
**3/5** — pervasive but additive.

### Recommendation
🔴 **Replace** (the current accessibility posture). For a brand targeting 18-100 with a privacy-first ethos, accessibility is not optional polish — it is the brand.

---

## 22. Account deletion (called out — explicit goal)

### Current implementation
`ProfileProvider.deleteAccount()` deletes the profile row; auth user remains; storage cleared mostly. No grace period. No purge of messages content. No record retained for legal compliance.

### Proposed implementation
**Two-phase hard delete:**

Phase 1 — request:
- User initiates from Settings → "Delete my account".
- Re-auth required.
- Confirmation screen lists exactly what will be deleted.
- Optional reason (anonymous, for product learning).
- `deletion_requests` row created with `scheduled_for = now() + 30 days`.
- Account immediately enters "deleted-pending" state: profile hidden, messages sent show as "[user is leaving]", no notifications received, but user can sign in to undo.

Phase 2 — purge (at scheduled_for):
- Oban worker runs `purge_user(user_id)`:
  1. Delete all `profile_photos` rows + storage objects.
  2. Delete all `verification_documents` + storage objects.
  3. Delete `profile_tags`, `profile_prompts`, `profile_voice_intros`, `profile_embeddings`.
  4. Scrub `messages.body` to NULL for messages sent by this user; replace with system-marker "[deleted user]"; preserve `created_at` + `conversation_id` for the other party's continuity.
  5. Delete `profile_likes`, `profile_views` (both directions).
  6. Delete `notifications`, `notification_preferences`.
  7. Delete `meet_up_rsvps`.
  8. Anonymize `reports.reporter_id` to NULL (preserve for safety pattern detection).
  9. Anonymize `moderation_log` entries against this user (preserve for legal defense).
  10. Delete `audit_log` entries *initiated by* this user (not entries *about* them).
  11. Delete `profile`, `profile_geo`.
  12. Delete `users` (auth identity).
  13. Call Stytch API to delete the auth identity there too.
  14. Write final `audit_log` entry: "user X purged on date Y" (with no PII).

Reversibility: user can sign in during the 30 days to cancel deletion (one-click). After 30 days: irreversible, including legal defense.

Communication: email at request, email at 25 days ("last chance"), email at completion ("we have deleted you; here is your receipt").

DSAR export: parallel flow; user can request a JSON dump of all their data at any time before purge.

### Advantages
- Real "permanently delete" matches the stated goal.
- 30-day grace is industry standard and reduces impulsive deletes (which is the user-pain reason most platforms keep accounts).
- Audit log of "user purged" satisfies regulators without retaining the PII.

### Disadvantages
- More complex than `DELETE FROM users WHERE id = $1`.
- The scrub-but-preserve approach on `messages` is the only one that respects the *other* party's right to their conversation history; defending it is the right ethical call.

### Migration difficulty
**3/5** — additive table + 1 Oban worker.

### Recommendation
🔴 **Replace.** Today's deletion is incomplete and would not survive a CCPA audit.

---

## 23. What I would REMOVE before launch

Each of these is in the current build (or planned) and shouldn't be:

1. **`MockDataService` from production paths.** It is imported by six screens. Either build the real backend or stub at the repository layer, but the mock should not be reachable in a release build.
2. **The standalone `verification_status` table.** Collapse to columns on `profiles`. Saves a join.
3. **The three tag tables** (`profile_interests`, `profile_looking_for`, `profile_life_situation`). Collapse to one polymorphic `profile_tags`.
4. **`mock_mode` in `AuthProvider`.** Either Supabase is up or it isn't. The "silent fallback to mock" pattern hides config bugs in production.
5. **The `is_admin == email == 'admin@nextchapter.com'` check.** Hardcoded admin emails are a launch-blocker class of bug.
6. **The public `/diagnostics` route.** Restrict to debug builds or admin-gated.
7. **`dio` if not used.** `http` or `dio`, pick one; `supabase_flutter` already uses one of them.
8. **Unused packages**: `fl_chart`, `table_calendar`, `carousel_slider`, `flutter_staggered_grid_view`, `vector_math`, `loading_animation_widget`, `flutter_spinkit`, `shimmer_animation`. Each is +50-500 KB to the web bundle.
9. **The 10-year signed URL pattern.** Long-lived signed URLs are essentially permanent leaks if ever shared.
10. **The "Ad management coming soon" placeholder.** Don't announce features you don't have. Either ship ads (first-party only, see §17) or remove the surface.
11. **The "is_request" boolean on `conversations` if you decide to keep matching out of the messaging gate.** With our model, every conversation starts as a request and is promoted on reply — no need for a separate flag.
12. **The "Online" boolean** on profiles. Replace with `last_active < 5min ago` derived from Phoenix.Presence; the boolean lies.
13. **Three product names.** Decide between Next Chapter and ConnectUp and primio_app, then renaming everything (binary name, app id, store listings, pubspec).
14. **The heart icon as the brand mark.** Pulls the brand into dating-only territory. (See §20.)
15. **The "Free & unlimited messaging" repeated banner.** Once on the landing page is confident; in three places it's defensive.

## 24. What I would ADD before launch

In approximate priority order:

1. **Real backend tier** (Phoenix or, as fallback, Edge Functions). Single highest-leverage architectural move.
2. **Real `messages`/`conversations` schema + realtime + push.** The core feature.
3. **Onboarding wizard** with 60-second flow.
4. **Hinge-style prompts.**
5. **Voice intro.**
6. **Multi-mode (Date / Friend / Activity).**
7. **Distance / geo filter.**
8. **Server-side ranked browse + pagination.**
9. **Phone verification + selfie verification flows.**
10. **Real admin app, separate from user app.**
11. **Image moderation (Sightengine) at upload.**
12. **Push + email + in-app notification stack.**
13. **Hard-delete pipeline with 30-day grace.**
14. **DSAR export.**
15. **Privacy ledger UI.**
16. **Safety check-in feature.**
17. **First-party analytics (self-hosted PostHog).**
18. **Bug bounty program.**

## 25. Modern Flutter packages / technologies I recommend

Beyond what's in your current `pubspec.yaml`:

| Package / tech | What it gives | Why it matters |
|---|---|---|
| `flutter_riverpod` + `riverpod_generator` + `riverpod_lint` | Codegen state management | Replaces `provider`; testable; type-safe; compile-time graph |
| `freezed` + `json_serializable` | Immutable models, copyWith, JSON | Eliminates the manual mapping in `_assembleProfile` |
| `drift` | SQLite + reactive queries | Outbox + offline cache for messaging |
| `flutter_form_builder` + `form_builder_validators` | Composable forms | Onboarding wizard becomes trivial |
| `sentry_flutter` | Error tracking | Production telemetry |
| `posthog_flutter` (pointed at self-host) | First-party analytics | Privacy-aligned |
| `flutter_native_splash` | Native splash | First-paint UX |
| `app_links` | Deep linking | Magic link callbacks |
| `local_auth` | Biometric prompts | Re-auth before delete / verify |
| `crypto_keys` + `cryptography` | Client-side field encryption | Optional sensitive-data encryption |
| `very_good_analysis` | Strict lints | Catches bugs at PR time |
| `mocktail` | Test mocks | Better than `mockito` for null-safety |
| `golden_toolkit` | Visual regression tests | Critical for accessibility |
| `feedback` | In-app feedback overlay | Beta signal |
| `flutter_local_notifications` | Local push (replaces `awesome_notifications` for most uses) | Smaller, better maintained |
| `device_preview` (dev only) | Test on simulated devices | Critical for breadth of audience |
| `flutter_lints` + custom rules | Strict lints | Quality |
| Material 3 Expressive theme tokens | New design language | Material 3 / Expressive landed in Flutter 3.27 |
| `flutter build web --wasm` | WASM target | 2-3× faster on older devices |

Non-Flutter:
- **Elixir / Phoenix 1.7** — see §5.
- **Oban Pro** — background jobs.
- **PostgreSQL 16 + PostGIS + pgvector** — see §6.
- **Meilisearch** — search.
- **Cloudflare R2** — object storage (zero egress).
- **Cloudflare Images** — image CDN with transforms.
- **Cloudflare WAF** — bot management.
- **Stytch B2C** — auth.
- **Sightengine** — image moderation.
- **OpenAI Moderation** or **Detoxify** self-host — text moderation.
- **Stripe Identity** — ID verification.
- **Persona Lite** — selfie liveness.
- **Twilio Verify** — phone OTP.
- **Resend** — email.
- **PostHog self-hosted** — analytics.
- **Sentry self-hosted** or **Glitchtip** — error tracking.
- **Grafana + Tempo + Loki** — observability.
- **Fly.io** or **Render** — hosting.
- **Hetzner** dedicated boxes if scale demands cheaper compute.

## 26. Long-term architectural patterns I recommend

1. **Repository pattern (already partially there).** Keep DB access out of UI; expand to expose a stable interface that survives backend swap.
2. **CQRS-lite.** Separate reads from writes at the function level; cache reads aggressively.
3. **Outbox pattern** on the client for messaging — guarantees no message is lost when the network drops.
4. **Event sourcing for moderation actions** — every admin decision is an immutable event in `moderation_log`; current state is a fold. Forensics later: trivial.
5. **Feature flags from day one** (`launchdarkly_lite` or self-host like `unleash`). All risky new features behind a flag, default off, ramped by percentage.
6. **Idempotency keys** on every write API. Client supplies UUID; server stores it; duplicate requests return cached response.
7. **Schema migrations via `ecto_migrate`** (Phoenix) or `prisma-migrate` — never hand-edit prod.
8. **Backward-compatible API versioning** (`/api/v1`, `/api/v2`); never break v1 until 100% of clients have migrated; client carries app-version header so server can do per-version routing.
9. **Type-safe contract layer** (`openapi-generator` or `dart_openapi_client`) between client and backend; no string-typed JSON.
10. **Trunk-based development + feature flags**, not long-lived branches.
11. **CI gates**: lint, test, security scan (`semgrep`), license check, web bundle size (fail if grows >5% per PR).
12. **Observability triad**: logs (Loki), traces (Tempo), metrics (Prometheus). All in one Grafana.
13. **SLOs from day one**: 99.5% uptime; messages delivered in < 1 s P95; sign-in < 3 s P95. Alert when burning the error budget.
14. **Incident runbooks** in the repo, not in someone's head.
15. **Architecture decision records (ADRs)** in `/docs/adr/0001-*.md` — capture *why*, not just *what*.

## 27. Cost & operations model

Rough monthly cost at three scale checkpoints. (USD, conservative.)

| Item | At 1 K MAU | At 100 K MAU | At 1 M MAU |
|---|---|---|---|
| Postgres (managed) | $25 | $400 | $2,500 |
| Phoenix hosting | $20 | $200 | $1,500 |
| Cloudflare R2 + Images + CDN | $5 | $200 | $1,500 |
| Meilisearch | $0 (self-host) | $80 | $400 |
| Redis | $10 | $50 | $200 |
| Stytch B2C | $0 | $4,500 | $40,000 |
| Twilio Verify | $50 | $5,000 | $50,000 |
| Sightengine | $0 (free tier) | $1,000 | $10,000 |
| Stripe Identity | usage | usage | usage |
| Resend | $0 | $200 | $1,500 |
| Sentry/PostHog (self-host) | $20 | $100 | $500 |
| Observability stack | $20 | $200 | $1,000 |
| Domain + TLS | $1 | $1 | $1 |
| Engineering ops | n/a | 1 SRE 0.25-time | 2 SREs |
| Moderation labor | n/a | 1 mod 0.5-time | 6 mods full-time |
| **Approx total infra** | **~$150** | **~$12 K** | **~$110 K** |

Two of these costs are *gross* — Stytch and Twilio Verify, both per-user pricing. At 1 M MAU, alternative paths:
- Stytch → self-host Hanko (saves ~$40 K/mo, costs ~1 FTE 25%).
- Twilio Verify → smart use (only on suspicious logins) + Apple/Google sign-in as primaries (saves 80%).

Per-MAU at 1 M scale ≈ $0.11. With $4.99 verification badges at ~15% conversion + $3.99/mo who-viewed-me at ~3% conversion, ARPU ~ $0.85. Free messaging stays viable.

## 28. Migration map: rebuild vs. evolve

If you decide to evolve the existing app rather than rebuild, the path is:

**Phase A (weeks 1–2):** kill the P0s. Rotate keys, fix role check, build a minimal Supabase Edge Functions tier for sensitive operations (signup, delete, admin actions). Add CAPTCHA, fix verification_status RLS.

**Phase B (weeks 3–6):** real messaging. Build `conversations` / `messages` schema in Supabase; use Supabase Realtime for v1 (200 concurrent on free, 500 on pro — acceptable until 20 K MAU). Push via OneSignal.

**Phase C (weeks 7–10):** real admin app. A separate Next.js app talking to Supabase via service role; not LiveView yet, but structurally separated. Real moderation tools.

**Phase D (weeks 11–14):** server-side browse. Add Postgres functions + indexes + PostGIS + pgvector. Server returns ranked pages.

**Phase E (months 4–6):** the rest of the differentiation (prompts, voice intros, multi-mode, earned trust badges, safety check-ins).

**Phase F (month 7+):** if-and-only-if scale demands it, migrate the backend tier from "Supabase + Edge Functions" to "Phoenix + Postgres-as-a-service". This is the *graceful* path.

If you decide to **rebuild** from scratch with the Phoenix architecture above, plan for 4 engineers × 4 months to reach feature parity + the differentiation. That is the *better*-long-term path; not always the *right* path for a startup that needs to ship.

## 29. Decision points awaiting your call

I have stopped here, with no code changes anywhere. Before I lift a finger I need you to tell me which of the following you want:

**A. Architectural posture** — pick one:
- 1. Evolve the current Supabase + Flutter build using the migration map in §28 (faster ship, technical debt later).
- 2. Rebuild from scratch with Phoenix + Postgres + Flutter (better long-term, 4-month delay).
- 3. Hybrid: Supabase Edge Functions tier first; plan Phoenix migration at the 100 K-MAU mark.

**B. Stack confirmations** — yes/no on each:
- Adopt Riverpod + freezed + drift on the Flutter side?
- Adopt Stytch for auth (replacing Supabase Auth)?
- Adopt Cloudflare (R2 + Images + WAF) for media + edge?
- Self-host PostHog and Sentry?
- Adopt the multi-mode (Date / Friend / Activity) model architecturally?
- Adopt the Hinge-style prompts + voice intro profile model?

**C. Brand & naming**
- Confirm the product name is **Next Chapter** (and we rename `primio_app` and retire `ConnectUp`).
- Confirm the design direction (editorial / serif / quietly literary).

**D. Roadmap shape** — pick one of:
- 1. 12-week MVP roadmap as in the audit document (security + messaging + moderation + browse + verification + differentiation v1).
- 2. 6-month "do it right" roadmap aligned to this proposal.
- 3. Phased — ship the 12-week MVP on the evolutionary path, then absorb the deeper architectural moves over months 4-9.

Once you respond to A, B, C, D, I will produce a concrete sprint plan and only then begin work. As stated: no code, no file edits, until you say go.

— end of clean-slate proposal —
