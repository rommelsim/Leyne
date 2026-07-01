# WhereSia — build brief

## Concept
Real-time public-transit tracker for Singapore. Crowd-first: the headline value is showing **how full** the next buses/trains are, so riders choose the emptier one. Grounded entirely in the government **LTA DataMall** open API.

## Audience & job
Everyday SG commuters standing at (or heading to) a stop who want one thing fast: *when's the next one, and will I get a seat?* The app opens straight to nearby live arrivals.

## Scope
**In scope**
- Live bus arrivals (next 3 per service) with per-bus crowd + bus type + wheelchair access + live-vs-scheduled flag.
- MRT/LRT station crowd (now) and same-day crowd forecast.
- Service info (first/last bus, frequency bands) — *not* a minute timetable (none exists).
- Live single-bus tracking along its route, with MRT-interchange stops flagged.
- Alerts: train service disruptions, station facility (lift) outages, and user-set reminders.
- Search, Saved places, and a Me/settings area.

**Out of scope (deliberately cut — do not add)**
- Trip planning / routing / directions.
- Any map view.

## Platform
The design is **iOS-first** (notch/Dynamic Island, squircle icon, Live Activity, iOS tab bar). Two live-ops features — **Lock Screen Live Activity** and **Dynamic Island** — are iOS-native only (ActivityKit / WidgetKit). Stack is the implementer's call; if cross-platform (React Native / Flutter) is chosen, those two features degrade to a normal push notification on non-iOS. Everything else is platform-neutral.

## The 10 screens
Ordered as they appear in `reference/mockup.html` (and the PNG sheets), left-to-right, top-to-bottom.

1. **Home · Nearby** — brand + "Nearby" header, search bar, filter chips (All / Bus / MRT / Saved), then a list of nearby stops. Each stop row: name, code · road · distance, route-number tiles (capped with a `+N` overflow chip), and the soonest arrival with an inline crowd gauge + word. Bottom tab bar (Home / Saved / Alerts / Me).
2. **Search · tap state** — appears when the search bar is tapped. Active input with blinking caret, "Search near me" (use current location), and a "Recent" list of mixed results (bus stop / service / MRT station, each with a distinct leading glyph).
3. **Search · results** — while typing. Results grouped by type (MRT stations / Bus stops), query term bolded in each hit, type filter chips.
4. **Bus stop** — big stop name, code · road · updated time. If the stop is itself an MRT station, an **interchange card** (train glyph + "AT THIS STOP" + line bullets + station crowd chip). Then one block per service: route tile, destination, operator, bus-type icon, wheelchair icon, live icon; and a row of up to 3 **arrival pills** (minutes + crowd gauge + word; first pill highlighted; scheduled buses shown dimmed with an empty gauge). A footer **key** legend + a "Live from LTA DataMall · refreshes every 20s" status line.
5. **MRT station** — station name + line bullets + service state. Cards: crowd now (wide gauge + word), by-platform crowd, and a same-day **crowd forecast** as a small vertical bar chart with a plain-language "busiest around…" note.
6. **Service info** — route tile + destination + operator/type, a direction segmented control, then first/last bus (weekday/Sat/Sun-PH) and frequency bands (AM peak / midday / PM peak / evening). Note that there is no fixed minute timetable.
7. **Track bus** — a live card (route, destination, "reaching your stop in N min", crowd) over a vertical **route timeline**. Long routes are collapsed with "N earlier/more stops" chips so the user never scrolls endlessly. The moving bus is a pulsing node between stops; MRT-interchange stops are flagged; the user's stop is highlighted. CTA: "Alert me 1 stop before".
8. **Alerts** — grouped: Train service (line bullet + disruption text + time), Stations (facility/lift outages), and Your alerts (user reminders with toggles).
9. **Saved** — saved Stops (each with a HOME/WORK/GYM tag) and saved Lines, showing live next-arrival + crowd inline. Uses the bookmark icon consistently.
10. **Me** — profile (name, generic placeholder email), Preferences (notifications, open-on, appearance), Accessibility (flag wheelchair buses, larger text), About (data source = LTA DataMall, version).

## Navigation model
- **Tab bar** (persistent): Home · Saved · Alerts · Me.
- **Push** into detail screens: Bus stop, MRT station, Service info, Track bus (from list rows / search results).
- **Search** presents modally from the Home search bar (tap → search state → results).
- **Bottom sheet** for a single service's detail over the bus-stop list (see `reference/wheresia-system-views.png`).
- **Live Activity / Dynamic Island** while actively tracking a bus (iOS).

## Interaction & motion notes
- Live data auto-refreshes (~20s for bus arrivals); show the last-updated time and a subtle live indicator.
- Motion is restrained and meaningful: crowd gauges fill on appear, live glyphs pulse, the tracked bus node pulses. **All animation must be gated behind `prefers-reduced-motion`** (the mockup already does this).
- Quality floor: responsive to mobile widths, visible keyboard focus, VoiceOver labels (esp. crowd = give the word, never rely on the gauge alone), Dynamic Type support (there's a "Larger text" setting).

## Copy voice
Plain, active, sentence case. Name things by what the rider controls ("Alert me 1 stop before", "Notify when seats available"). Crowd is always spoken as a **word** (Seats / Standing / Limited for buses; Low / Moderate / High for stations) alongside the gauge — see DESIGN-SYSTEM.md.
