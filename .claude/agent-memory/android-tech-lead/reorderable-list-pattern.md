---
name: reorderable-list-pattern
description: This Flutter SDK's ReorderableListView.onReorderItem semantics, and the codebase's established id-list reorder convention
metadata:
  type: project
---

## SDK gotcha: `onReorderItem` vs `onReorder`

Project pins Flutter 3.44.0. `ReorderableListView` in this SDK exposes BOTH
`onReorder` (deprecated, `ReorderCallback`) and `onReorderItem` (its
replacement). The two differ in `newIndex` semantics:

- `onReorder`: raw indices — caller must manually do
  `if (newIndex > oldIndex) newIndex -= 1` before `removeAt`/`insert`
  (the classic Flutter reorder gotcha most blog posts warn about).
- `onReorderItem`: the framework does that adjustment internally before
  invoking the callback (`_handleReorderItem` in
  `packages/flutter/lib/src/widgets/reorderable_list.dart`). Callback body
  can do a plain `removeAt(oldIndex)` / `insert(newIndex, item)` with no
  extra math.

All reorder UI in this repo uses `onReorderItem` (confirmed by grep —
`onReorder` doesn't appear as a call site anywhere in `lib/`). If asked to
add "index adjustment" logic for a new `onReorderItem` handler, don't — it's
already double-adjusted and reorders will be off-by-one.

## Established reorder convention

Four precedents, all the same shape — [[architecture-patterns]] AppModel
owns persistence, the widget owns index math:

- `AppModel.reorderPins(List<String> newCodes)` — `app_model.dart:1315`
- `AppModel.reorderFavServices(List<String> newIds)` — `app_model.dart:1331`
- `AppModel.reorderSavedMrt(List<String> newIds)` — `app_model.dart:535`
- `AppModel.reorderAlerts(List<String> newIds)` — added 2026-07-03 for the
  alert pause/resume + reorder port (ManageAlertsScreen)

Shape: the AppModel method takes the **full desired id order** (not raw
oldIndex/newIndex), rebuilds the list by looking up each id in a `byId` map,
then appends anything not mentioned (`byId.values`) so items outside the
reordered subset keep their relative order. The widget-side
`onReorderItem` callback builds that full ordered list locally
(`removeAt(oldIndex)` → `insert(newIndex, item)` on a copy) and passes the
mapped ids down — see `soft_favourites_screen.dart` `_stopsArea` /
`_servicesSection` / `_stationsSection` for the canonical widget-side
pattern (shrinkWrap + `NeverScrollableScrollPhysics` nested inside an outer
`ListView`, `proxyDecorator` strips the Material elevation, explicit
`Icons.drag_handle_rounded` + `ReorderableDragStartListener` as the handle).

When a task asks for a raw `moveItem(int oldIndex, int newIndex)` signature
instead, prefer this id-list convention unless there's a concrete reason not
to (e.g. it's the only shape that survives a sectioned/filtered UI — see
ManageAlertsScreen's Active/Other split — where "index into what's on
screen" isn't a stable identity). Flag the deviation explicitly rather than
silently picking one.

`buildDefaultDragHandles` defaults to `true` but is a no-op on mobile
platforms (only adds a visible handle on desktop) — mobile always drags via
long-press-anywhere unless you set it `false` and supply an explicit handle.
Existing favourites precedent leaves it at the default (rows have no other
interactive elements); set it `false` when a row contains its own tappable
controls (e.g. a Switch) so long-press-anywhere doesn't fight them.
