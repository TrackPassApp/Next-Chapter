# Donation / Support Provider Setup

Next Chapter's monetization is **donation-driven and voluntary**. Messaging is
free. Donors get no communication advantage. There is no paywall.

To turn the "Support Next Chapter" surfaces in the app from a placeholder into
a live donation flow, you need **one** external donation provider. Any of the
following works — pick whichever is easiest for you.

---

## Option A — PayPal Business (recommended for US individuals/LLCs)

1. Create a **PayPal Business** account at <https://www.paypal.com/business>.
2. Verify your email + bank.
3. Once approved, go to **PayPal.me** and claim a handle, e.g.
   `paypal.me/nextchapterapp`.
4. Optional: create a fixed "Donate" button
   (Products & Services → Donations) for a nicer landing page.
5. Use the resulting URL (`https://paypal.me/nextchapterapp` or the
   generated donate URL) as the `DONATE_URL` build define below.

Pros: instant, works globally, low fees. Cons: not tax-deductible unless you
set up a registered nonprofit.

---

## Option B — Stripe Payment Link (recommended if you already use Stripe)

1. Sign in to <https://dashboard.stripe.com>.
2. **Products → Add product** → "Next Chapter — Support" (any name).
3. Add a one-time or preset amount(s). **Do not** create a recurring product —
   B11 explicitly excludes subscriptions.
4. From the product page, **Payment links → Create payment link**.
5. Copy the payment-link URL and use it as `DONATE_URL`.

Pros: hosted checkout, receipts, refunds, currency support.

---

## Option C — Buy Me a Coffee / Ko-fi / Liberapay

Fastest of all three. Sign up at any of:

- <https://www.buymeacoffee.com>
- <https://ko-fi.com>
- <https://liberapay.com>

Turn OFF monthly memberships during setup (Beta 1.0 is one-time only). Grab
the profile URL (e.g. `https://buymeacoffee.com/nextchapter`) and use it as
`DONATE_URL`.

---

## Wiring the URL into the app

Do **not** hard-code your personal payment URL anywhere in `/lib`. It is read
from a compile-time define so it can be rotated per environment / re-deployed
without a code change:

```bash
flutter build web --release \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=... \
  --dart-define=APP_URL=... \
  --dart-define=DONATE_URL=https://buymeacoffee.com/nextchapter
```

Behaviour:

- **Empty (default):** the Support buttons show a friendly "Donation link
  coming soon" snackbar. No broken links.
- **Set:** every Support button opens the URL in a new tab.

## Where the Support surfaces live

| Location | Variant | File |
|---|---|---|
| Settings → Support Next Chapter | dialog | `lib/screens/settings_screen.dart` |
| My Profile (top banner) | banner | `lib/screens/my_profile_screen.dart` |
| Messages (top banner)   | banner | `lib/screens/messages_screen.dart` |
| Community (card)        | card   | `lib/screens/community_screen.dart` |
| Activity (sponsored)    | sponsored | `lib/screens/activity_screen.dart` |

All five reuse the same widget (`lib/widgets/support/support_next_chapter_card.dart`)
so copy stays consistent: "Next Chapter will always keep messaging free…".

---

## What NOT to do

- **Do not** put a personal PayPal link inline in Dart code.
- **Do not** add a subscription tier — B11 is explicit: one-time donations
  only.
- **Do not** give donors profile boosts, ad-free flags, or messaging
  advantages. Donation must never affect functionality.
- **Do not** advertise donation inside an active chat thread.

If you switch providers later, update `DONATE_URL` at build time — no code
change required.
