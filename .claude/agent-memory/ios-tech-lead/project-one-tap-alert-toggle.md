---
name: project-one-tap-alert-toggle
description: One-tap arrival alert toggle pattern replacing the old NotifyWhenSheet + NotifyConfirmView sheet flow (landed 2026-06-10)
metadata:
  type: project
---

Arrival alerts now use a one-tap toggle + Undo toast pattern (no sheet, no confirmation). The old `NotifyWhenSheet.swift` and `NotifyConfirmView.swift` have been deleted — they are gone.

**Key pieces:**
- `AppModel.toggleArrivalAlert(busNo:stopCode:stopName:dest:)` — returns `ArrivalAlertToggleResult` (`.armed` / `.removed`).
- `AppModel.toggleArrivalAlertWithToast(...)` — convenience that calls `toggleArrivalAlert` and returns a pre-built `ArrivalAlertToastState`.
- `ArrivalAlertToast.swift` in `V2/` — the actionable top overlay toast with Undo button. Uses `.task(id:)` for auto-dismiss (3 s). View extension `.arrivalAlertToastOverlay(state:t:)` for clean call-site.
- `SoftStopView` — per-bus button now shows bell + "Notify"/"On" caption (labelled VStack, rounded rect background). State: `@State var alertToast: ArrivalAlertToastState?`. Sheets for NotifyWhenSheet + NotifyConfirmView removed; `notifySvc` and `confirmAlert` state vars removed.
- `SoftBusView` — `toggleBoardingAlert()` now calls `toggleArrivalAlertWithToast`. `@State var alertToast: ArrivalAlertToastState?` added. Both toasts (save-confirm + alert) as two independent `.overlay(alignment: .top)` chains.
- `StopAlertSheet.swift` — untouched; still wired from `SoftHomeView` long-press context menu ("Arrival Alerts"). That is a stop-first (not per-bus) path with a Done button and is NOT part of the one-tap flow.
- `NotifyWhenSheet` destination-alert branch — `NotifyWhenSheet` supported both `.arrival` and `.destination` kinds but was only ever presented from `SoftStopView` for arrival. The destination alert flow lives in `SoftBusView` / `DetailView` (separate, not touched).

**Why:** Product feedback: bare bell icon unclear, full-screen sheet for "you'll be reminded twice" was wasted UX, and undoing required navigating to ManageAlerts. Android already uses the same single-tap toggle pattern.

**How to apply:** Any future per-bus arrival-alert entry point should call `toggleArrivalAlertWithToast` and bind `ArrivalAlertToastState` to an overlay — not present `NotifyWhenSheet`.
