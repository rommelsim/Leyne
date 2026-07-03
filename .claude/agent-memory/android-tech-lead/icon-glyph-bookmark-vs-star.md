---
name: icon-glyph-bookmark-vs-star
description: iOS WhereSia uses TWO distinct icon families for "save" — bookmark for stop/station/service-info pin, literal star for per-bus context-menu favourite — Android must mirror which one per affordance, not blanket-replace
metadata:
  type: project
---

iOS WhereSia (`ios-native/Leyne/WhereSia/`) has two genuinely different "save"
affordances that both read as "starring" something, but use different glyphs:

1. **Bookmark family** (`WSIcons.swift` `WSGlyph.bookmark` / `.bookmarkFilled`,
   SF Symbol `bookmark`/`bookmark.fill`, rendered via `WSIcon` at `.light`
   weight) — used for saving/pinning a whole **stop or MRT station**, and for
   the per-service "favourite" header button on `WSServiceInfoView`. Call
   sites: `WSBusStopView.swift:67` (header togglePin), `WSMrtStationView.swift:74`,
   `WSServiceInfoView.swift:51`.
2. **Literal star** (SF Symbol `"star"`/`"star.slash"`, NOT part of the WSIcon
   glyph enum — a bare `Label(systemImage:)` in a SwiftUI `.contextMenu`) —
   used ONLY for the long-press "Favourite bus N at this stop" action inside
   `WSBusStopView.swift`'s per-row context menu (line ~254, `isFavService`).
   This is intentional: iOS context menus conventionally use a star for
   "favourite" (Apple HIG idiom), distinct from the app's own bookmark
   iconography used everywhere else.

**Why this matters:** on 2026-07-03 (owner punch list, Section B item 3) the
Android bus-stop header star (`lib/screens/v2/soft_stop_screen.dart`,
formerly `_starMenu`/`Icons.star_rounded`) was corrected to
`Icons.bookmark_rounded` / `Icons.bookmark_outline_rounded` to match #1 above.
The per-bus swipe-action star in the same file (`_swipeNotify`,
`Icons.star_rounded`/`star_outline_rounded`, "Save"/"Saved" label) was
correctly LEFT AS A STAR — it mirrors #2, not a parity gap.

**How to apply:** when auditing/porting any other Android screen that uses
`Icons.star_rounded`/`Icons.star_outline_rounded`, check which iOS affordance
it actually mirrors before swapping to bookmark. As of 2026-07-03 these
Android files still use star icons and have NOT been audited against this
distinction — treat as open parity-audit items:
- `lib/screens/v2/soft_service_info_screen.dart:212` — likely should be
  bookmark (mirrors `WSServiceInfoView.swift:51`, which uses `.bookmark`/
  `.bookmarkFilled`, not context-menu star).
- `lib/screens/v2/soft_bus_screen.dart:479`

`lib/screens/v2/soft_home_screen.dart` was AUDITED AND FIXED 2026-07-03 (owner
punch list, Section A item 2 pass, prompted by a Section-B-agent addendum
mid-task): both were save affordances mirroring #1, not #2 —
`_showMrtStationMenu`'s "Save station" row (station save, was ~line 1275) and
`_StopPeekSheet`'s "Add to Saved" pin row (stop save, was ~line 1482) — both
now `Icons.bookmark_rounded`/`Icons.bookmark_outline_rounded`, matching
`soft_mrt_station_screen.dart` / `soft_stop_screen.dart`'s existing pair.
Remove this file from the open list; it's fully audited now.

See also [[project-structure]].
