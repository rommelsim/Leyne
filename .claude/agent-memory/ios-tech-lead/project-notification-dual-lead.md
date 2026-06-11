---
name: project-notification-dual-lead
description: Arrival alerts now fire TWO notifications (3 min + 1 min) via AlertTiming.arrivalLeads; no user-picked lead for arrivals
metadata:
  type: project
---

Arrival alerts schedule two notifications — 3 min and 1 min before the bus — using `AlertTiming.arrivalLeads = [3, 1]`. The user-facing lead picker was removed from `NotifyWhenSheet` and `StopAlertSheet` for arrival alerts. Destination alerts keep their lead picker unchanged.

Notification identifiers follow `arrival.<stopCode>.<busNo>.<lead>` pattern. `cancelAlert` sweeps both leads plus legacy single-lead and headsup identifiers from older builds. `scheduleArrivalAlerts` in `NotificationsManager` loops over `arrivalLeads` per alert, skipping any lead whose fire time is already past.

**Why:** Product decision (2026-06-10) — fixed dual-lead matches Android parity; removes a decision point the user never needed.

**How to apply:** When touching notification scheduling or the alert sheet UI, remember arrival alerts have no configurable lead. Only destination alerts use `AlertTiming.leadOptions(.destination)` and a picker. `AlertTiming.arrivalRowSubtitle` is the canonical subtitle string for ManageAlertsView rows and the inline active-alert card in SoftStopView.
