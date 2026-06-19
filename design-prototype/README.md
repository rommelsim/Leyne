# Leyne — design sandbox (localhost replica of the iOS app)

A zero-build HTML/CSS/JS replica of the iOS app, for iterating a design overhaul
fast in the browser instead of rebuilding in Xcode. Faithful to the current
SwiftUI app (`ios-native/Leyne`) as a starting point — then restyle freely.

## Run

```bash
cd design-prototype
python3 -m http.server 4321
# open http://localhost:4321
```

(Any static server works — `npx serve`, etc.) Edit a file → refresh. No build.

## How to redesign

- **All visual tokens live in `styles.css` `:root`** — colours (light + dark),
  typography, radii, spacing, the device size. Change a token, refresh, every
  screen updates. Dark-mode tokens are under `:root[data-theme="dark"]`.
- **Components** are plain CSS classes in `styles.css` (`.card`, `.badge`,
  `.arow`, `.crowd`, `.tabbar`, …) — restyle these to reshape the UI.
- **Screens + data + the reusable component HTML** are in `app.js`
  (`screenHome`, `screenStop`, `screenBus`, `screenSearch`, `screenSaved`,
  `screenMrt`, `screenAlerts`, `screenSettings`; helpers `badge` / `stopCard` /
  `arrivalRow` / `crowd` / `etaCol`). Sample SG data is at the top of `app.js`.

## In-app controls (desktop)

- **◐ Theme** — toggle light / dark.
- **A+ Text** — bump the Dynamic-Type multiplier (`--dyna`) to check large text.
- Tap the **tab bar** (Bus · MRT · Saved · Search · Alerts), tap stop cards and
  arrival rows to drill into Stop / Bus detail, the gear on Home → Settings.

## Fidelity notes / what's stubbed

- **Design DNA preserved:** monochrome-first (the accent is black/white, not a
  hue); confidence shown via opacity, weight, and the quiet `~` prefix; MRT line
  colours are the only hues. Matches `ios-native/Leyne/Theme.swift`.
- Icons are lightweight inline SVGs approximating SF Symbols (not pixel-exact).
- The Bus-detail map, live route position, and real data are stubbed with
  believable SG sample content — this is a design canvas, not a working client.
- Liquid Glass is approximated with `backdrop-filter` on the tab bar.

Source of truth for the real screens: `ios-native/Leyne/V2/Soft*.swift`.
