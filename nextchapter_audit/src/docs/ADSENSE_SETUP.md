# Ad Provider Setup

Next Chapter runs a **minimum, tasteful set of ad slots**. No popups, no
full-screen takeovers, no ads inside chat threads. The current placeholders
show a labelled "AD / Sponsored slot / Messaging stays free" tile so you can
lay out the app now and drop a real network into a single file when you're
ready.

---

## Recommended path

1. **Beta 1.0 → Google AdSense.** Easiest to approve for small web projects,
   works out-of-the-box with a single JS snippet + publisher ID, revenue lands
   monthly. Apply at <https://adsense.google.com>.
2. **Once traffic grows or direct sponsors appear → Google Ad Manager.**
   AdSense stays as a fallback fill; AdManager gives you house-ad and direct-
   sponsor line items and better reporting.
3. **Optional side-channels:**
   - Direct sponsor cards (fixed CPM, one advertiser)
   - House ads (Support Next Chapter — already wired)
   - "No ad" mode for anyone using `--dart-define=ADS_ENABLED=false`

## Where the slots live

| Slot | Type | File |
|---|---|---|
| Browse grid (1 card between profiles) | card | `lib/widgets/common/ad_placeholder.dart` |
| Messages list header | banner | `lib/widgets/common/ad_banner.dart` |
| Community rooms list header | banner | `lib/widgets/common/ad_banner.dart` |
| Activity — sponsored card (Support only) | sponsored | `lib/widgets/support/support_next_chapter_card.dart` |

Explicitly **not** wired to ads: private chat threads (`chat_screen.dart`),
community room threads (`room_chat_screen.dart`), onboarding, auth,
verification.

## Enable / disable at build time

```bash
flutter build web --release \
  --dart-define=ADS_ENABLED=true            # default; shows placeholders
flutter build web --release \
  --dart-define=ADS_ENABLED=false           # kills all ad slots app-wide
```

## When AdSense is approved

You will receive a **publisher ID** (`ca-pub-XXXXXXXXXX`) and can create
individual ad units.

For **web**, wiring is a two-step swap:

1. Add the AdSense loader once to `frontend/index.html`:
   ```html
   <script async
     src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=ca-pub-XXXXXXXXXX"
     crossorigin="anonymous"></script>
   ```
2. Replace the placeholder body in `ad_placeholder.dart` (`_placeholderBody`)
   and `ad_banner.dart` (`_body`) with an `HtmlElementView` that renders an
   `<ins class="adsbygoogle" ...>` tag for your specific ad unit. That is the
   only file each slot lives in — no screen code changes.

For **mobile** builds, use `google_mobile_ads` (already compatible with the
current Flutter version). Same replacement point.

## When you switch to Ad Manager

The same widget swap works — Ad Manager uses the same `<ins>` markup with a
different `data-ad-client` + `data-ad-slot`. You can also drop in
`googletag.cmd` for line-item targeting. Because our layout code never
imports an ad SDK directly, screens keep compiling regardless of provider.

## Rules baked into B11 that a future ad provider must not violate

- ⛔ No popups, interstitials, or full-screen ads.
- ⛔ No ads inside private chat threads.
- ⛔ No ads inside community room threads.
- ⛔ No pay-to-message, pay-to-view-profile, or subscription tiers.
- ⛔ No deceptive ad creatives (fake "You have a new message" ads etc.).
- ✅ Ads must be clearly labelled "AD" or "Sponsored".
- ✅ Ads must be replaceable in one file per placement.

Keep the ad footprint small. The mission is fighting loneliness — not
maximising CPMs.
