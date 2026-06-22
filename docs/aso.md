# Leyne — App Store Optimization (ASO) playbook

Synthesized from the 2026-06-09 growth review. ASO is the only growth lever
that compounds on every *future* organic install, costs nothing ongoing, and is
a one-afternoon job for a solo dev. Do this before/alongside the widget builds.

Target search intent (SG): people typing **"bus arrival", "bus timing", "sg
bus", "singapore bus", "bus eta"** — high intent, lower competition than generic
"transit/transport".

---

## App Store (iOS)

FINAL — paste-ready (char counts verified):

- **Title (27/30):** `Leyne: SG Bus Arrival Times`
- **Subtitle (29/30):** `Live MRT, train & ETA tracker`
- **Keywords field (98/100, comma-sep, no spaces, no words repeated from title/subtitle):**
  `singapore,timing,sbs,smrt,lta,commute,next,stop,service,transport,nearby,route,alert,schedule,when`
  - Note: includes operator brand terms `sbs,smrt` (real, low-competition SG
    searches). Apple auto-combines tokens across all three fields, so don't add
    "sgbus" etc. Singular forms only; Apple stems plurals.
- **Promotional text (≤170, editable anytime WITHOUT review):**
  `Live arrivals for every SG bus stop & MRT line. Pin your stops, get a nudge before your bus pulls in. Free, no sign-up, no account.`
  - If the Buy-me-a-coffee channel is live in prod, you can append:
    ` Support Leyne with Buy me a coffee.`
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

FINAL — paste-ready:

- **Title (27/30):** `Leyne: SG Bus Arrival Times`
- **Short description (74/80, keyword-indexed, plain text):**
  `Live bus and MRT arrival times for Singapore. LTA data, alerts, no sign up.`
  - Leads with the two exact-match queries ("bus ... arrival times",
    "Singapore"). Keep "Singapore" in full; the title only carries "SG".
- **Long description (keyword-indexed, plain text, refreshed 2026-06-22 to match
  the live feature set; no dashes or bullet symbols per owner request):**

  > Leyne shows live bus arrival times for every bus stop in Singapore, straight from LTA DataMall, plus MRT and LRT lines, all in one clean and fast app. No account, no clutter, no sign up.
  >
  > Pin the stops you use, see the next buses at a glance, and get a heads up before your bus pulls in so you never run for it again.
  >
  > Live bus arrival times for every Singapore bus stop.
  > MRT and LRT lines with live service status and station crowd levels.
  > Nearby stops, sorted by walking distance.
  > Pin your favourite stops, services and stations.
  > Arrival alerts before your bus pulls in.
  > Follow your bus stop by stop along its route.
  > Seat availability and crowd levels for each bus.
  > Lift maintenance and service advisories at a glance.
  > Dark mode, loads in seconds.
  > Free to use, no account needed.
  >
  > Whether you are catching a feeder bus, changing at an interchange, or timing the next train, Leyne keeps Singapore buses and MRT one glance away.
  >
  > Bus and train data from LTA DataMall.
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
