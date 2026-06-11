# Leyne — App Store Optimization (ASO) playbook

Synthesized from the 2026-06-09 growth review. ASO is the only growth lever
that compounds on every *future* organic install, costs nothing ongoing, and is
a one-afternoon job for a solo dev. Do this before/alongside the widget builds.

Target search intent (SG): people typing **"bus arrival", "bus timing", "sg
bus", "singapore bus", "bus eta"** — high intent, lower competition than generic
"transit/transport".

---

## App Store (iOS)

- **Title (≤30 chars):** `Leyne: SG Bus Arrivals`
- **Subtitle (≤30 chars):** `Live Singapore bus timings`
- **Keywords field (≤100 chars, comma-sep, no spaces, don't repeat title/subtitle words):**
  `arrival,timing,eta,lta,datamall,mrt,tracker,commute,when,next,stop,service,transport,singapore`
- **Promotional text (≤170, editable without review):** lead with the freshest
  feature, e.g. *"New: long-press any nearby stop for instant alerts, and
  support Leyne with Buy me a coffee."*
- **Screenshots (in order, each with a 3–5 word headline overlay):**
  1. Lock Screen widget showing a live ETA — *"Your bus, one glance away"* (ship Lock-Screen widget first — see iOS plan)
  2. Live Activity / Dynamic Island counting down — *"Never miss it"*
  3. Home pinned-stop hero with live arrivals — *"Your stops. Right now."*
  4. Arrival notification on the Lock Screen — *"A nudge before it pulls in"*
  5. Nearby stops with walk distances — *"Find any stop, instantly"*
- **What's New copy:** lead with the user benefit, not the feature name
  ("Lock Screen widget — check your bus without unlocking" > "added
  accessoryRectangular family"). This field is indexed by Search.
- **Ratings:** now wired (`ReviewPrompt` in `LeyneApp.swift`) — fires after the
  2nd useful-notification tap, once per install.

## Google Play (Android)

- **Title (≤30):** `Leyne: SG Bus Arrival Times`
- **Short description (≤80):** `Live bus arrival times & alerts for Singapore — LTA data, no sign-up needed.`
- **Long description (first 2 lines matter most — front-load keywords naturally):**
  > Leyne shows live bus arrival times for every stop in Singapore, straight
  > from LTA DataMall. Pin your stops, get an alert before your bus arrives, and
  > see the next buses, crowding and route at a glance — no account, no clutter.
  > Then list features as bullets (live ETAs, arrival & alight alerts, nearby
  > stops, route progress, saved stops/services, dark mode).
- **Screenshots:** once Android widgets ship, make the **widget screenshot the
  first asset** (Play surfaces these prominently for utility apps). Use a device
  frame + real data.
- **Store Listing Experiments:** A/B test (a) the icon and (b) the first
  screenshot — the two highest-leverage conversion levers.
- **Ratings:** now wired (`ReviewPrompt` in `review_prompt.dart`, In-App Review
  API) — same trigger as iOS.
- **Android Vitals:** keep ANR < 0.47% and crash rate low — both are Play
  ranking signals. (Crashlytics, once added, will surface these.)

---

## Sequencing
1. Ship the ratings prompt (done — in the next builds).
2. Update Play title + short description today (no build needed).
3. Update App Store subtitle + keywords on the next iOS submission.
4. Re-shoot screenshots once the Lock-Screen widget (iOS) / home widget
   (Android) lands — the widget shot is the single best converting asset.
