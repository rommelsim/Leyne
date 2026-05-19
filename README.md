# Leyne — iOS app

Native SwiftUI implementation of the **Lyne** Singapore bus-transit prototype
(from the Claude Design handoff bundle). Lyne's thesis: *let the phone tell you
when your bus is close, so you stop staring at it.*

## Run it

This Mac has Xcode installed but the active developer dir is the Command Line
Tools. Either point at Xcode once:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

…then open `Lyne.xcodeproj` in Xcode and run on an iOS 18+ simulator or device
(iOS 26 for the full Liquid Glass tab bar + detached search pill).
Or build from the CLI without changing the global setting:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Lyne.xcodeproj -scheme Lyne \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Run tests (unit + live LTA integration):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -project Lyne.xcodeproj -scheme Lyne \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Verified building, testing (15/15 green) & running clean on Xcode 26.4.1 /
iOS 18 simulator with **live LTA DataMall data**.

## Live data (LTA DataMall)

No mock data. Everything is pulled from LTA DataMall (`LTAService` /
`DataStore`):

- **Bus Arrival v3** — live ETA / load / type / WAB / position, per stop,
  refreshed ~every 25 s; ETA derived from `EstimatedArrival` (rounded down,
  `<1 min` → "Arr", per the guide).
- **Bus Stops** — full SG dataset (disk-cached weekly); powers Nearby
  (device GPS + haversine) and Stop search.
- **Bus Services** — service search.
- **Bus Routes** — ordered route stops for the Detail map (lazy, disk-cached).
- API key + base URL live in `LTAConfig.swift`. Reference datasets cache to
  `Caches/LTA/`.

## What's implemented (full app)

- **Launch animation** — strokes draw on, wordmark + caption, fade out.
- **Onboarding** — 5 steps with the real UI mocks. Shows on first run only
  (persisted); replayable from Settings.
- **Home** — user-pinned stops (persisted, start empty), long-press to
  reorder, tap the ✎ label to rename, 3-service cap with "+N more",
  arriving-bus highlight, live countdown, pull-to-refresh, empty/loading/error
  states, Add-a-stop sheet (live search → pick buses).
- **Nearby** — live nearest stops via device GPS + LTA Bus Stops; sortable
  (Distance / Arrival / Service), expandable (live arrivals on demand),
  Pin / Open, location-permission prompt.
- **Detail** — stop overview → drill into a bus → **real Apple MapKit map**
  (route polyline + stop pins + live bus position), real route progress with
  tap-to-set alight stop, notify card, **Start Live Activity**.
- **Live Activity** — full lock-screen takeover, real countdown from the
  live `EstimatedArrival` (in-app simulation, matching the prototype).
- **Search** — Conservative & Ambitious variants (live Buses + Stops;
  persisted recents). Places/postal omitted (LTA has no geocoding — needs
  OneMap, out of scope).
- **Settings** — theme, sound/haptics/motion feedback, search style, replays.
- **Light & dark themes**, and the sensory feedback system (synthesised audio,
  Core Haptics, device-shake on success/arrival).

## Implementation notes

- **Fonts:** the prototype used *JetBrains Mono* for mono accents. To avoid
  bundling font binaries, the app uses the system monospaced face (SF Mono).
  Drop a `JetBrains Mono` font file into the target and swap `Theme.mono(_:)`
  to use it for an exact match.
- **No device chrome:** the prototype rendered a fake iPhone frame; on a real
  device iOS provides the status bar / Dynamic Island / home indicator, so that
  chrome is intentionally omitted.
- **Live Activity** is an in-app lock-screen *simulation* (as the prototype
  does). A true ActivityKit widget extension is a separate, larger build.
- **Detail map** is real MapKit. The route polyline needs the LTA Bus Routes
  dataset, fetched lazily on first map open and disk-cached (first open shows
  a brief "Loading route…").
- **Launch-argument seam:** `-lyne.onboarded 1`, `-lyne.startTab nearby`,
  `-lyne.theme dark` via the standard NSArgumentDomain — handy for
  UI verification and deep-linking.
- **Tests:** `LyneTests` target — unit (parsing, ETA rules, haversine,
  detection, pin logic) + live LTA integration. Run via the command above.
