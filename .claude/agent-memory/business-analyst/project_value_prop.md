---
name: project-value-prop
description: Leyne's core value proposition and target user — grounding for feature prioritization and copy decisions
metadata:
  type: project
---

## Value Proposition

Leyne's proposition is **commuter calm at the stop level**: instead of the Singapore transit ecosystem's overcrowded super-apps (Citymapper, Google Maps, MyTransport.SG), Leyne does one thing — tells you exactly when your specific buses are arriving, with zero noise from route planning, bookings, or news.

The three-layer thesis, from onboarding copy:
1. **Pin your stops, not a generic map.** Stop-level personalization means the app opens to the one or two stops the user actually uses, with only the buses they ride.
2. **Know when to leave, not just when the bus arrives.** Arrival alerts ("buzz 2 min before") + alight alerts ("tell me 2 stops out") close the gap between looking at a screen and catching a bus.
3. **Trust the number.** Live/Scheduled provenance chip is explicit: users know which ETAs are GPS-tracked vs. scheduled estimates — a transparency differentiator in a market where rival apps blend them without disclosure.

## Target User

Primary: **daily Singapore bus commuter**, likely age 20–40, rides the same 2–5 stops and 4–8 service numbers every week. Already installed MyTransport or Citymapper but finds them too cluttered for a quick "is Bus 88 coming?" check.

Secondary: **transit-aware occasional commuter** — knows a handful of stops near home/office, wants a zero-friction lookup without typing every time.

**Platform split (inferred):** iOS is the primary revenue and iteration target. Android is a parity port — keeps the app discoverable on Play and serves users who don't own an iPhone.

**Geography:** Singapore only. LTA DataMall is the sole data source; there is no multi-city or multi-country scope.

## Monetization Model

- Free download, ad-supported (AdMob banner).
- No IAP, no premium tier, no subscription.
- Revenue ceiling is therefore a function of: daily active users x sessions per day x banner fill rate x eCPM.
- The monetization model is very low friction (no paywall) but also very low ceiling per user. Growth in DAU is the only revenue lever.

Related: [[project-leyne-overview]], [[project-accounts]]
