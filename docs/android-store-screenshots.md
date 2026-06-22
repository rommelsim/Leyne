# Leyne — Android (Play Store) screenshot capture

Guide for regenerating the Android phone screenshots. Raw captures go in
`screenshots/android/`; framed/captioned store-ready output is produced from
them afterwards (see `store_assets/`).

Set produced: 2026-06-22. Supersedes the 20 May set (UI has changed since).

## 1. Build an ads-free build

The store shots must NOT show the test ad banner / app-open / interstitial /
Stop-screen MREC. The app has a built-in switch that collapses every ad surface
to zero (the tab bar sits flush, no 50pt reservation):

```sh
flutter run --release --dart-define=LYNE_SCREENSHOT_MODE=true -d <android-device-id>
```

- Use `--release` so there's no debug banner in the corner.
- `flutter devices` to get the device id once the phone is plugged in (USB
  debugging on).
- Verify: there should be **no ad anywhere** — Home, Stop screen (no MREC),
  between-screen interstitials, and no app-open ad on launch.

## 2. Capture (6 shots)

Target the same real device that produced the originals → **1440 × 3120**
(Play Store phone: 2–8 shots, 9:16, up to 3840px — this is ideal). Capture with
the phone's screenshot combo, or via `adb exec-out screencap -p > shot.png` over
USB if you prefer pixel-clean grabs.

Capture each screen with **real, live data** mid-day so times look healthy.

| # | File                  | Screen          | What to show / set up |
|---|-----------------------|-----------------|------------------------|
| 1 | `01-nearby.png`       | Nearby          | "Stops near you" with several stops + live arrivals and walk times. |
| 2 | `02-home.png`         | Home            | Home / greeting state, clean and populated. |
| 3 | `03-detail.png`       | Stop detail     | A busy stop's live arrivals board, multiple services, real "Arr"/min times. **No MREC** (screenshot mode hides it). |
| 4 | `04-search.png`       | Search          | Search with a query showing stops + services + stations matches. |
| 5 | `05-mrt.png`          | MRT             | MRT tab — lines running + live crowd; ideally a non-all-"Low" moment so crowd levels show range. |
| 6 | `06-saved.png`        | Saved           | A few pinned stops/services so it looks lived-in (pin some before shooting). |

Notes:
- Status bar: full battery + clean (no clutter notifications) reads best, but
  not mandatory.
- Light mode for all six (consistency); one dark-mode alt is optional.
- Android has no bus-view map overlay (by design) — do not try to shoot a map.

## 3. Drop + next steps

Save the six PNGs into `screenshots/android/` using the filenames above
(overwrite the old set). Then I will:
1. Frame + add headline/subcaption overlays (Android/Play voice).
2. Order them (strongest first — Play shows ~3 before scroll).
3. Export store-ready sizes into `store_assets/screenshots/` and update
   `store_assets/captions.md` for Android.
