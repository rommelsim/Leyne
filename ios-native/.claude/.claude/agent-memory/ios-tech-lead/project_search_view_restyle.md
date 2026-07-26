---
name: project-search-view-restyle
description: SoftSearchView 2.4.0 restyle — large Search title, vertical recents list, 2x2 Browse grid replacing horizontal chip row
metadata:
  type: project
---

SoftSearchView was restyled from a "Find" eyebrow + horizontal chip row to a first-class Search tab with a large bold title, vertical recent-searches list, and a 2x2 Browse shortcut grid.

**Why:** Search is now a dedicated tab, not a modal overlay; the design needed to match the SoftHomeView/SoftStopView card language and give recents more prominence.

**How to apply:** When reviewing or extending this screen, the empty state is composed as: `emptyState` → `recentsSection` (conditional on `!m.recents.isEmpty`) + `browseSection`. The horizontal chip scroll and `exampleChips` computed var are gone. The `examples` tuple array is still present and used by Browse tile actions to seed example queries.

Key decisions:
- Mic icon is a plain `Image` (not Button) — visual affordance only, no dead tap target.
- Cancel button is conditional on `focused` (animated show/hide), and still calls `onClose()` so modal callers are not broken.
- Browse tiles: Nearby → `onClose()`, Stops → seeds "17179", Services → seeds "96", Places → seeds "Clementi". No invented features.
- `detectQueryKind` used in `recentRow` to pick icon: bus.fill / mappin / location / clock.arrow.circlepath.
- `m.removeRecent` / `m.clearRecents` / `m.recents` all confirmed on AppModel (line 373, 478, 486, 490).
