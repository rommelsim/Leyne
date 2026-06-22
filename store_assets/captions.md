# Leyne — App Store screenshot captions

Format: bold **title** (≤4 words) + one-line subtitle, set above a device frame
on a brand background. Frame + caption with AppLaunchpad / Previewed / fastlane
frameit. Target size: **1320 × 2868** (iPhone 6.9").

Captured 2026-06-12 from device build (Debug, `-screenshots` flag → no ad banner).
Note: device build was v2.6.0; the MRT-public + paywall-removed changes ship in
**2.7.0** (bump version before archiving so the What's New screen fires).

## Recommended store order

App Store shows ~3 before the user scrolls — lead with the strongest.

| # | Screen | Title | Subtitle |
|---|--------|-------|----------|
| 1 | Nearby / "Stops near you" | Your stops, the moment you open | Live arrivals near you, always |
| 2 | Bus + live map tracking | See exactly where it is | Track your bus on the map in real time |
| 3 | Stop arrivals board | Never miss your bus | Live times the moment they change |
| 4 | Bus full-route timeline | Know every stop ahead | Glance at the route before you board |
| 5 | MRT — all lines running | Live MRT status, free | Every line at a glance, plus disruption alerts |
| 6 | Search | Find any stop, bus or place | Search the whole network |
| 7 | Saved | Your commute, one tap away | Pin the stops and buses you ride |

## Not for the store
- **Settings** — verification shot only; doesn't sell anything.

## Optional add (re-capture needed)
- **Alight Reminder** — strongest "magical" feature (wake-me-before-my-stop).
  Start a journey, capture the "Alight at…" tracking screen. Slot at position 3.
  Suggested caption: **Doze off, we'll wake you** — Get nudged just before your stop.

## Notes
- Status bars show 91% charging + 5G — fine for the App Store. Re-shoot on full
  battery only if you want them pristine.
- Keep titles short so they stay legible as search-result thumbnails.
- Soft timeliness language ("real time", not "to the second") — matches how the
  app presents arrivals.

---

## Android (Google Play) — regenerated 2026-06-22

Dark-mode, ads-free captures (`--dart-define=LYNE_SCREENSHOT_MODE=true`) framed in
a **Samsung S24 Ultra** body on a light pale-blue gradient (matches the iOS App
Store set: dark navy headline, gray subcaption). Output: 1080×2100 (under
Play's 2:1 cap). Framed PNGs in `store_assets/screenshots/android/`; raws in
`screenshots/android/`. Renderer: `scripts/android_store_frames.py` (re-run to tweak).

Play shows ~3 before scroll — strongest first.

| # | Screen | Headline | Subcaption |
|---|--------|----------|------------|
| 1 | Nearby | Your stops. Right now. | Live arrivals at every stop near you |
| 2 | Stop arrivals board | Every bus, live to the minute | All arrivals at your stop, one tap away |
| 3 | Bus arriving + seats | Know before it arrives | Live timing, seats and crowd as it nears |
| 4 | Bus full-route timeline | Follow it, stop by stop | See exactly where your bus is on the route |
| 5 | MRT | Trains too — every line, live | MRT status across the whole network |
| 6 | Alerts | Always know what's running | Disruptions, advisories and lift maintenance |

Voice matches the iOS set + `aso.md`: benefit-first, sentence case, soft
timeliness ("live", not "to the second"), no hype words.
