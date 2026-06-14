# Leyne — App Store screenshots (captions + order)

Captioned + ordered store-listing set, produced 2026-06-14 via the
`screenshot-captions` skill. Source screenshots live in `~/Downloads/`
(`IMG_4334`–`IMG_4349`). Keep wording consistent with `docs/aso.md`.

**Rendered output:** a bold **headline + a lighter subcaption** are **already
baked** onto each shot, inside an **iPhone 17 Pro Max device frame** (titanium
bezel + Dynamic Island), at **1320 × 2868** (6.9" App Store size). Files:
`~/Downloads/leyne-store/Leyne_NN.png`. Renderer: `/tmp/leyne_caption.py`
(Pillow) — re-run to tweak headline/subcaption/style.

Subcaptions (paired with the headlines in the table below):
`01` A live countdown on your Lock Screen · `02` Tracking stays in your Dynamic
Island · `03` Live arrivals for every stop nearby · `04` Real-time timings,
straight from LTA · `05` See exactly where your bus is · `06` The whole route,
with seats and crowd · `07` Stops, services and stations in one place · `08` Live
MRT status across the network · `09` Search every stop, bus and station · `10` See
how busy before you go · `11` Delays, advisories and lift maintenance.

> Platform: **App Store (iOS)**. **Max 10 shots**; the **first 3 show in search**,
> so they lead with the most differentiated value. NOTE: the list below is 11 —
> once slot 2 is re-shot, drop one (recommended: bench Search, #9) to fit 10.

## Final order (9 shots)

| # | File | Caption (overlay) | Alts | Why this slot |
|---|------|-------------------|------|---------------|
| 1 | `IMG_4340.PNG` — Lock Screen Live Activity | **Your bus, one glance away** | "Live, without unlocking" · "Track it from your Lock Screen" | Strongest differentiator: live ETA you read without opening anything. |
| 2 | `IMG_4347.PNG` — Dynamic Island, cross-app ⚠️ **re-shoot backdrop** | **Follows you across apps** | "Always in your Dynamic Island" · "Tracking, even while you browse" | Cross-app persistence — counts down no matter what you're doing. |
| 3 | `IMG_4334.PNG` — Home "Stops near you" | **Your stops. Right now.** | "Every stop near you, live" · "The buses around you" | The "what is this app" hero — nearby live arrivals + walk times. |
| 4 | `IMG_4335.PNG` — Bus arrivals board | **Every bus, live to the minute** | "All arrivals, one tap" · "Real-time, every service" | Core daily value — the LIVE multi-service board. |
| 5 | `IMG_4338.PNG` — Live bus map | **Watch it approach** | "See exactly where it is" · "Your bus, on the map" | Proof of true real-time tracking (iOS-exclusive map). |
| 6 | `IMG_4337.PNG` — Route timeline | **Follow it, stop by stop** | "See the whole route" · "Right down to your stop" | Depth — full route + "bus here now" + seat availability. |
| 7 | `IMG_4342.PNG` — Saved | **Your daily stops, saved** | "Pin once, check forever" · "Everything you ride, one place" | The habit feature — stops, services *and* stations together. |
| 8 | `IMG_4341.PNG` — MRT | **Trains too — every line, live** | "MRT status at a glance" · "Buses and trains, one app" | Breadth beyond buses; line status + crowd. |
| 9 | `IMG_4343.PNG` — Search | **Find any stop, instantly** | "Search every stop and service" · "Jump to any stop" | Coverage/completeness. Weakest "wow" — first to bench if over 10. |
| 10 | `IMG_4348.PNG` — MRT live crowd | **Live crowd, every station** | "Beat the rush" · "See how busy, before you go" | Differentiator — most bus apps lack train crowding. ⚠️ all-"Low" off-peak; re-capture at peak to show Moderate/High range. |
| 11 | `IMG_4349.PNG` — MRT advisories + lifts | **Service status at a glance** | "Delays and lift outages, covered" · "Always know what's running" | Reliability + accessibility (lift maintenance) angle. |

## Slot 2 — must re-shoot the backdrop

The cross-app Dynamic Island message is a hero shot, but every capture so far has
an unusable background (App Review discourages Apple chrome / competitor apps /
ads, and they're visually noisy):
- `IMG_4344` / `IMG_4345` — shot over Apple's **iPhone 17 Pro** store page.
- `IMG_4346` / `IMG_4347` — shot over the **App Store** (Trip.com **Ad**, Snake
  Clash, Dr. Driving visible).

**Rule: backdrop must have zero Apple chrome, zero competitor apps, zero ads.**
Pick one:
1. **Best/simplest:** crop tight to the Dynamic Island pill (no backdrop) and
   frame on the system-blue background. Caption: *"Follows you across apps."*
2. **Brand-safe:** trigger the Live Activity, then sit on Leyne's own MRT/Saved
   tab so the island floats over *your* app. Caption: *"Always in your Dynamic
   Island."*
3. Neutral Home Screen — clean wallpaper, tidy app layout, no badges. (The real
   Home Screen `IMG_4339` is too cluttered.)

## Not used
- `IMG_4339` — Home-Screen Live Activity: dropped (messy/personal home screen;
  replaced by slot 2).
- `IMG_4336` — inline split-map: near-duplicate of slot 5; keep one.
- `IMG_4344` / `IMG_4346` — compact Dynamic Island over Apple/App-Store: backdrop
  issue; `IMG_4347` is the better content if re-shot.
- Stray `2.PNG` files are byte-identical dupes of `IMG_4334`/`IMG_4335` — ignore.

## Gaps / optional adds
- **Widget shot** — `aso.md` calls the Home/Lock-Screen *widget* the single best
  converting asset; missing here. Re-shoot once it ships and make it shot #1.
- **Seats / crowding** — "Seats available" appears but is never the headline; a
  dedicated *"Know if there's a seat"* shot sells a feature rivals lack.
- **Dark mode** — all shots are light; one dark shot adds visual range.
- **Arrival notification** + **alight alerts** — not shown. (MRT crowd levels +
  advisories/lifts are now covered by shots 10–11.)

## A/B test first
Per `aso.md`, the **first screenshot** + the **icon** are the highest-leverage
conversion levers. Test slot 1 (Lock Screen, *"Your bus, one glance away"*) vs
leading with Home (*"Your stops. Right now."*).

## Art direction
- Device frame + consistent **system-blue** background; caption band in the same
  position on every shot (parallel structure).
- All shots use **real data + LIVE** with consistent ~12:0x times — good.
- Caption style: short, benefit-first, sentence case, no hype words — matches the
  `aso.md` voice.
