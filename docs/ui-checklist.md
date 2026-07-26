# Departly UI checklist

**Read this before writing UI code, and check the finished work against it before
saying a feature or fix is done.** Every line here is an owner decision, most of
them made after seeing the mistake on a real device. They are not preferences to
re-litigate — if a new design needs to break one, say so explicitly and ask.

Scope: iOS (`ios-native/Leyne/WhereSia/`) is the source of truth. Android
(`lib/`) mirrors features, not chrome — see "Platform" below.

---

## 1. Native iOS chrome — no hand-drawn substitutes

The single most repeated correction in this project. If the system has a
control for it, use the system's control.

- [ ] Tab bar is a real `TabView` + `Tab(value:)`. **Never** a custom floating
      pill. (A custom bar as a `safeAreaInset` outside the NavigationStack also
      breaks scrolling — see §5.)
- [ ] Screen titles are `.navigationTitle` in a real nav bar. No hand-built
      title rows, no in-content header bars on root tabs.
- [ ] Title display mode is `.inline` app-wide. `.large` reserved a tall empty
      band the owner rejected.
- [ ] Bar actions are `ToolbarItem` + `Button(_:systemImage:)`. No custom
      circular white tiles for back / star / search / map / Edit.
- [ ] Back is the SYSTEM back button. Don't hide it and redraw it; hiding the
      whole bar is what forced the `enableSwipeBack()` workaround.
- [ ] Search is `.searchable` (+ `.searchFocused`, `.cancellationAction`), not a
      custom text field with a custom clear dot and a text "Cancel".
- [ ] Map controls are MapKit's (`MapUserLocationButton`, `MapCompass`). If the
      map ignores a safe area, host them via `@Namespace` + `.mapScope` so they
      don't land on the status bar.
- [ ] Edit/Done, alerts, sheets, context menus: system components.

Still custom by exception: `wsHeaderBar` (MRT station, Service Info) draws a
WSIcon back button inside the real nav bar. Not yet flagged by the owner.

## 2. Information hierarchy

- [ ] **Place first, then departures.** A stop card's title is the STOP NAME.
      The bus is never the biggest text on a card about a stop.
- [ ] Stop metadata format, everywhere: **`Stop 41101 · 2 min walk · 189m away`**
      — built by `wsStopCodeLabel(_:suffix:)`. Never a bare 5-digit number: it's
      ambiguous next to bus numbers and line codes.
- [ ] Metadata that matters is readable — 13pt+, not an 11.5pt grey sentence
      stranded in whitespace.
- [ ] Facts that describe ONE thing live in ONE card, divided by hairlines.
      Loose capsules floating on the ground read as unrelated objects — and a
      value needs its label ("68m" alone doesn't say what it measures).
- [ ] A chevron means "this navigates". Don't put one on a chip that's really
      a full-width row's job.
- [ ] Every ETA carries a unit. `Arr` is banned in board/slot contexts; print
      **"Now"**.
- [ ] Labels are sequence words (`NEXT / THEN / LATER`), not ordinals
      (`2ND / 3RD`) — ordinals next to numerals read as part of the number.
- [ ] Crowd is a chip (gauge + word), never a bare word stacked under a time.
      No occupancy from LTA prints "No data", never a bare dash.
- [ ] Lists of services show DISTINCT services (a feed repeat of the same bus is
      noise when the question is "which bus can I take").
- [ ] MRT rows/alerts show the STATION pill code (`EW23`), not the bare line
      code.

## 3. Alignment and empty space

- [ ] Columns in a board share one type size so labels, times and chips each sit
      on a single line across slots. Emphasise the primary slot with weight or
      opacity, **never** with a larger size — that breaks every row's alignment.
- [ ] Fixed-width segments where a column must align down a list
      (`SoftBusTimePill(noWidth:timeWidth:)`).
- [ ] `.frame(minHeight:)` without an `alignment:` CENTRES short content. In a
      row of columns of unequal height that silently sinks the short ones — pass
      `alignment: .top` whenever columns must share a top edge.
- [ ] Don't add padding on top of a shared component's own inset
      (`SoftSectionHead` already carries the 4pt heading indent) — the extra
      pushes that one heading out of line with every other section.
- [ ] A mark and its label live in ONE column, not in two parallel stacks with
      different width rules — that's what drifted the MRT strip's station names
      out from under their nodes. Draw connecting rails as a background inset by
      half a column.
- [ ] Prefer encoding information in the diagram over repeating it as text: the
      route strip carries its own directions (terminus at each end) and the
      station's crowd on its own node.
- [ ] Missing data gets a sentence, not blank columns ("No later bus timed yet").
- [ ] ONE empty state per screen, and it's a composed card (icon + headline +
      detail + what to do), never a bare sentence floating in the layout. If a
      section and its placeholder can both fire, gate the section so only one
      renders — two copies of the same sentence with different padding is what
      reads as "items randomly placed".
- [ ] No dead bands: don't stack manual bottom spacers on top of a
      `safeAreaInset`; the system already insets scroll content.

## 4. Colour semantics

- [ ] Accent is sky blue (`SoftBlue.blue`). Mint is banned.
- [ ] Attention order red > amber > green > blue. Amber/red are reserved for
      real disruptions. Green stays rare. Always pair colour with a word.
- [ ] Line colour = identity; traffic-light colour = status. Don't mix.
- [ ] **On the map, blue means the user.** Bus-stop dots are ink. Two marks in
      the same blue is the ambiguity bug.
- [ ] Uncertainty is a whisper (a "~"), never a banner. The product's promise is
      timely updates delivered confidently.

## 5. Scrolling, insets, gestures

- [ ] Scroll content must reach the end of the list. The "can't scroll to the
      MRT stations" bug was a custom tab bar applied as a `safeAreaInset`
      OUTSIDE each tab's NavigationStack — inner scroll views never got the
      inset.
- [ ] Swipeable rows use `WSHorizontalPan` (UIKit, horizontal-dominant), never a
      SwiftUI `DragGesture` — the latter eats vertical scrolls.
- [ ] Detail screens hide the tab bar on push (`.toolbar(.hidden, for: .tabBar)`).
- [ ] Tap targets ≥44pt, even when the visual is smaller.

## 6. Motion

- [ ] One vocabulary: `SoftMotion.flow` (interactions), `.drift` (entrances),
      `.settle` (one-shot), `.breathe` (live tells). No `.snappy`.
- [ ] Tab switches animate — the system TabView has no transition of its own, so
      tab content uses `wsTabEntrance()` (replays on every appear).
- [ ] PUSHED screens delay their entrance ~0.28s (`pushSettle`). An entrance
      that starts on `onAppear` plays underneath the navigation slide and is
      never seen — which reads as "this screen has no animation".
- [ ] Don't put a screen-level `.wsEntrance()` above a per-card stagger; the
      outer fade swallows the stagger.
- [ ] Every animation is gated behind Reduce Motion.
- [ ] Live data announces itself by dipping the data (`dataPulse`), not by a
      spinner or an "updated Ns ago" caption.

## 7. Interaction completeness

- [ ] A card that represents a destination is tappable as a whole, not only via
      its button.
- [ ] A second tap on an already-selected map pin opens the thing.
- [ ] Give the user the platform escape hatch: bus stops offer **Directions** in
      Apple Maps (walking).
- [ ] Actions that arm something (alerts) take ONE tap — no confirm sheet.

## 8. Ads, changelog, release hygiene

- [ ] Root tabs: native ad cards inline only. Anchored banners belong on
      high-dwell detail screens (`wsDetailAdBanner`).
- [ ] The exit interstitial hangs off the navigation POP (`onChange(of: path)`
      in `WSRoot`), not off a back button. Don't re-add ad calls to buttons.
- [ ] Every AAB / Archive updates `CHANGELOG.md` at the repo root. There is no
      in-app What's New on either platform.

## 9. Platform

- [ ] Features reach parity across iOS and Android; DESIGN does not. iOS follows
      iOS 26 conventions, Android follows Material You. No idiom bleed.
- [ ] Android has no map (removed deliberately). Don't re-add without an ask.
- [ ] Don't launch the simulator. Build to confirm it compiles, then stop — the
      owner verifies UI on device.

---

### Working rule

When a fix is requested, don't fix only the instance that was reported: run the
same check across every screen that shares the pattern, and say which screens
you checked. Most items on this list started as "just this one card".
