# Departly — App Store Optimization (ASO) playbook

*(App renamed from Leyne to **Departly** on 2026-07-04 — this doc was
re-baselined the same day. Repo/bundle IDs keep the Leyne name; only
user-facing metadata changed.)*

Synthesized from the 2026-06-09 growth review. ASO is the only growth lever
that compounds on every *future* organic install, costs nothing ongoing, and is
a one-afternoon job for a solo dev.

Target search intent (SG): people typing **"bus arrival", "bus timing", "sg
bus", "singapore bus", "bus eta"** — high intent, lower competition than generic
"transit/transport".

---

## App Store (iOS)

FINAL — paste-ready (char counts verified 2026-07-04):

- **Name (8/30):** `Departly`
  - Staged in App Store Connect (owner decision with the rename). A bare name
    leaves ~22 indexed characters unused; if search traffic dips post-rename,
    the keyword-carrying variant is `Departly: SG Bus Arrivals` (25/30).
- **Subtitle (26/30):** `Live SG bus & MRT arrivals`
  - Staged with the rename; ships with the next iOS submission.
- **Keywords field (99/100, comma-sep, no spaces, no words repeated from name/subtitle):**
  `singapore,timing,train,eta,sbs,smrt,lta,commute,next,stop,service,transport,nearby,route,alert,when`
  - Re-cut for the new subtitle: the old subtitle spent "train/ETA/tracker",
    the new one doesn't, so `train` and `eta` moved INTO the keywords (they
    are top SG queries); `schedule` was dropped to fit. Operator brand terms
    `sbs,smrt` stay (real, low-competition searches). Singular forms only;
    Apple stems plurals.
- **Promotional text (150/170, editable anytime WITHOUT review, ASCII-only per owner request):**
  `Live arrivals for every SG bus stop and MRT station - plus live crowd levels. Save your stops, get a nudge before your bus pulls in. Free, no sign-up.`
  - If the Buy-me-a-coffee channel is live in prod, you can append:
    ` Support Departly with Buy me a coffee.`
- **Description (1343/4000, not keyword-indexed — pure conversion copy,
  ASCII-only per owner request; set live 2026-07-04):**

  > Departly gets you to your bus before it gets to your stop.
  >
  > Live arrival times for every bus stop in Singapore, and live crowd levels for every MRT station - presented so one glance answers the only question that matters: when do I leave?
  >
  > TRACK YOUR BUS
  > - Live arrivals for every SG bus stop, straight from LTA DataMall
  > - Watch your bus move along its route, with minutes to YOUR stop
  > - "Alert me 1 stop before" - a nudge so you never miss your alight
  > - ARRIVING flags the bus that's pulling in now
  >
  > KNOW THE MRT
  > - Live station crowd levels: Low, Moderate, High
  > - Today's crowd forecast in half-hour steps, so you can beat the crush
  > - Train line status and station lift outages, in one Alerts tab
  >
  > BUILT FOR THE DAILY RIDE
  > - Nearby stops and stations with walk distances
  > - Save your stops; reorder them your way
  > - Search by stop name, bus number, MRT station, or postal code
  > - Home Screen widgets: Pinned Stop, Nearby, Favourite Service
  > - Live Activity counts down on your Lock Screen and in the Dynamic Island
  > - Dark mode throughout
  >
  > NO ACCOUNT. NO SETUP.
  > Departly works the moment you open it. Your saved stops and settings stay on your device - no sign-up, no profile, nothing to manage.
  >
  > Departly was previously called Leyne - same app, new name.
  >
  > Arrival data is provided live by LTA DataMall.
  >
  > Questions or feedback: leyne0000@gmail.com

- **Screenshots — current live set (framed + captioned 2026-07-04, 1284×2778):**
  1. Bus route tracking — *"Watch your bus roll in"*
  2. Home / Nearby — *"Every stop near you, live"*
  3. MRT station crowd — *"Know the crowd first"*
  4. Alerts — *"Know before you go"*
- **Screenshots — target set** (canonical order; capture the missing shots —
  widgets and Live Activity have SHIPPED, so 1/2/4 are now shootable):
  1. Widget showing a live ETA — *"Your bus, one glance away"*
  2. Live Activity / Dynamic Island counting down — *"Never miss it"*
  3. Home hero with live arrivals — *"Your stops. Right now."*
  4. Arrival notification on the Lock Screen — *"A nudge before it pulls in"*
  5. Nearby stops with walk distances — *"Find any stop, instantly"*
- **What's New copy:** lead with the user benefit, not the feature name
  ("Lock Screen widget — check your bus without unlocking" > "added
  accessoryRectangular family"). This field is indexed by Search.
- **Ratings:** now wired (`ReviewPrompt` in `LeyneApp.swift`) — fires after the
  2nd useful-notification tap, once per install.

## Google Play (Android)

FINAL — paste-ready:

- **Title (30/30):** `Departly: SG Bus Arrival Times`
  - Play titles are keyword-indexed, so the suffix earns its keep. If the
    owner prefers the bare `Departly` for store parity with iOS, the short
    description below still carries the core queries.
- **Short description (75/80, keyword-indexed, plain text):**
  `Live bus and MRT arrival times for Singapore. LTA data, alerts, no sign up.`
  - Leads with the two exact-match queries ("bus ... arrival times",
    "Singapore"). Keep "Singapore" in full; the title only carries "SG".
- **Long description (keyword-indexed, plain text, re-baselined 2026-07-04 for
  the rename + shipped widgets; no dashes or bullet symbols per owner request):**

  > Departly shows live bus arrival times for every bus stop in Singapore, straight from LTA DataMall, plus MRT and LRT lines, all in one clean and fast app. No account, no clutter, no sign up.
  >
  > Save the stops you use, see the next buses at a glance, and get a heads up before your bus pulls in so you never run for it again.
  >
  > Live bus arrival times for every Singapore bus stop.
  > MRT and LRT lines with live service status and station crowd levels.
  > Station crowd forecast for the rest of today.
  > Nearby stops, sorted by walking distance.
  > Save your favourite stops, services and stations.
  > Arrival alerts before your bus pulls in.
  > Follow your bus stop by stop along its route.
  > Seat availability and crowd levels for each bus.
  > Home screen widgets for your stop and nearby stops.
  > Lift maintenance and service advisories at a glance.
  > Dark mode, loads in seconds.
  > Free to use, no account needed.
  >
  > Whether you are catching a feeder bus, changing at an interchange, or timing the next train, Departly keeps Singapore buses and MRT one glance away.
  >
  > Departly is the new name for Leyne. Same app, same data, new name.
  >
  > Bus and train data from LTA DataMall.
- **Screenshots:** interim captioned set exists (2026-07-04, S24 Ultra frames,
  1440×3120) but it frames iOS captures — **re-shoot from the Android build**
  before publishing. Android widgets have shipped: make the **widget screenshot
  the first asset** in that re-shoot (Play surfaces it prominently for utility
  apps). Use a device frame + real data.
- **Store Listing Experiments:** A/B test (a) the icon — the pin-clock replaced
  the blue "D" on 2026-07-04, a natural experiment — and (b) the first
  screenshot. The two highest-leverage conversion levers.
- **Ratings:** now wired (`ReviewPrompt` in `review_prompt.dart`, In-App Review
  API) — same trigger as iOS.
- **Android Vitals:** keep ANR < 0.47% and crash rate low — both are Play
  ranking signals. (Crashlytics, once added, will surface these.)

---

## Sequencing
1. Ship the ratings prompt (done — in the next builds).
2. Play title + short description (update to the Departly values above — no
   build needed).
3. App Store name/subtitle staged with the rename; keywords + promotional
   text + description go live with the next iOS submission (promo text can go
   live immediately, no review).
4. Capture the missing widget / Live Activity / notification screenshots
   (all shipped features now) — the widget shot is the single best
   converting asset — and re-shoot the Play set from the Android build.
