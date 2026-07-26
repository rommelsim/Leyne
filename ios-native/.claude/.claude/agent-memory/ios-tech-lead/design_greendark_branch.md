---
name: design-greendark-branch
description: State of the "Departly green-dark" WhereSia redesign on branch design-greendark — what's themed, what's not, and the Search/Saved/Alerts rewrite done 2026-07-24
metadata:
  type: project
---

Branch `design-greendark` (repo /Users/rommel/Documents/Leyne, module `ios-native/Leyne/WhereSia/`) carries a full re-skin of the WhereSia module: "Departly green-dark" — near-black blue-grey gradient board, ONE live-data accent (mint #35E0B2 dark / #0E9E7B light), amber reserved for real disruptions, red for packed/destructive, official line colours for rail identity. This supersedes the older "colour = data, blue accent" monochrome rule recorded in [[design_identity_pass]] / [[wheresia_redesign]] — check WSTheme.swift's live header comment before trusting either of those older memories on this branch.

WSTheme.swift and WSComponents.swift already carry the full token set for this pass (as of 2026-07-24): `ws.background()`, `.wsCard(radius:emphasized:)`, `WSGlowEdge`, `WSPulseDot`, `WSServiceTile`, `WSStopCodeChip`, `WSBigETA`, `WSTheme.amber/.amberText/.red/.gold/.mintDeep/.accentInk`, `ws.mintGradient`, `ws.cardFill()`. These were pre-existing when I (ios-tech-lead review agent, tasked as an implementer this session) read them — another agent/session had already landed them. Don't assume they need adding again; verify by reading WSTheme.swift's top comment block first.

2026-07-24: rewrote WSSearchView.swift, WSSavedView.swift, WSAlertsView.swift to this design per an owner-approved distilled spec (multiple parallel agents were working other WhereSia files the same session via `.claude/worktrees/` — check for concurrent edits before assuming these three are the only in-flight changes).

**Interpretation calls made in that pass** (flag for review before assuming they're final):
- WSSearchView: dropped the "All/Bus/MRT/Stops" `WSFilterChips` row entirely (not in the new spec) and flattened the three grouped sections (stations/services/stops) into one ranked card, ordered stations→services→stops. Underlying `store.searchStops`/`searchServices`/`MrtGeo.stations(matching:)` calls unchanged.
- WSSavedView: kept the "Lines" (`favServices`) card group even though the distilled mock only pictured stop + MRT station cards — dropping it would silently un-surface a real saved-line feature. Added a rename context-menu action wired to the pre-existing but previously-unused-in-this-screen `AppModel.rename(code:to:)`.
- WSAlertsView: kept the "Stations" (lift maintenance) card group and the pause/resume toggle (as a compact bell icon) even though the distilled spec's alert card only showed a "Remove" button — both are live, already-wired features not explicitly called out for removal.

None of these three files were built after editing (task explicitly said "Do not build" — visual-only rewrite, scoped review requested no compile verification). If picking this up again, compile-check before shipping.
