# ConnectUp

## Overview
ConnectUp is a free social connection platform for adults 18+ — friendship, dating, activity partners, travel companions — with zero messaging paywalls. The MVP is Flutter Web backed by Supabase (Auth, PostgreSQL, Storage, Realtime).

## Tech Stack & Key Decisions
- **Supabase** for Auth, DB, Storage, and future Realtime messaging — chosen for RLS, generous free tier, and Flutter SDK quality.
- **`supabase_flutter ^2.8.4`** and **`image_picker ^1.1.2`** added via PRIMIO_ADDITIONS anchor in pubspec.yaml.
- **`go_router`** for all navigation with auth-gate redirects; session-restore loading guard prevents flash-to-login on refresh.
- **`provider`** for state; `AuthProvider`, `ProfileProvider`, and `MessagesProvider` live globally in `main.dart`; `BrowseProvider` is route-scoped.
- **No silent mock mode**: `SupabaseService` now captures and exposes `initError` and `configurationError`; any save/load attempt with no client hard-fails with a visible error — never silently falls back to mock data.
- **`image_picker`** used for both web (file input) and mobile (gallery/camera) — same API, different underlying implementation.

## Architecture
- UI layer (`screens/`, `widgets/`) → providers → repositories → `SupabaseService` singleton.
- Repositories (`lib/repositories/`) own all Supabase SQL; providers own state and business rules; screens are thin orchestrators.
- `ProfileRepository` assembles a full `UserProfile` by parallel-fetching 5 child tables (photos, interests, looking_for, life_situation, verification_status).
- `PhotoRepository` manages Supabase Storage bucket `profile-photos`; storage path convention is `{user_id}/{uuid}.ext` enabling user-scoped RLS.
- `main.dart` wires an `AuthProvider` listener that calls `ProfileProvider.loadProfile(userId)` on login/session-restore and `ProfileProvider.clear()` on logout.
- `ProfileProvider.saveProfile()` does a single `upsert` on `profiles` then runs 4 parallel child-table replaces (delete-then-insert pattern for lists).
- Account deletion: photos deleted from Storage first, then the profile row is deleted — ON DELETE CASCADE removes all child rows automatically.

## Conventions
- All Supabase queries go through `lib/repositories/` — never directly in widgets or providers.
- `SupabaseService.client` returns `null` when not configured (mock mode check); `SupabaseService.db` throws — use `.client` with null-guard in repos.
- New routes added to `lib/router/app_router.dart`; screen-specific providers are route-scoped there, not in `main.dart`.
- `/edit-profile` is a top-level GoRouter route (not inside the shell), so it has its own full-screen AppBar with Save action.
- Theme tokens only — no `Colors.*` or hardcoded values in widget files; all custom colors via `AppColorsExtension`.

## Key Patterns & Gotchas
- `ProfileRepository._assembleProfile()` awaits 5 sequential futures (converted from parallel after type-inference issues with `Future.wait`); keep this in mind for performance — add caching if needed.
- The `profiles` table uses `user_id` (auth UUID) as a unique key; `id` (profile UUID) is used as the FK in all child tables. Don't confuse the two.
- Storage RLS requires the upload path to start with `auth.uid()` — the `{user_id}/` prefix in `PhotoRepository` is not cosmetic.
- Delete account flow: `ProfileProvider.deleteAccount()` deletes storage then DB; `AuthProvider.logout()` is called after — order matters (need auth.uid() for cleanup).
- Browse still uses `MockDataService` until Step 3 (real profiles from Supabase browse).

## Design System
- Warm, trustworthy, inclusive palette: primary `#5B6ABF` (soft indigo), secondary `#E8785E` (warm coral), tertiary `#4CA6A8` (teal).
- Intentionally avoids "hookup app" aesthetics — generous spacing, readable typography, muted card borders.
- All spacing via `AppTheme.spacing*`, radii via `AppTheme.radius*`, icon sizes via `AppTheme.icon*`.
- Google Fonts Inter throughout; all text styles defined in `_buildTextTheme()` — never inline `TextStyle`.
