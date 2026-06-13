---
name: ui-behavior-test
description: >
  Write and run tests that verify buttons and views behave as intended on Android
  (Flutter) and iOS (SwiftUI). Use when the user asks to test a screen/button/view,
  add UI or widget tests, check that a control does what it should (tap, toggle,
  navigate, enable/disable, show/hide), write a regression test for a UI bug, or
  verify behavior after a change. Matches each platform's existing test idiom.
---

# UI / behavior testing (Android + iOS)

Goal: prove a control or view does what it's supposed to — a tap fires the right
action, a toggle flips state, a view shows/hides, navigation lands on the right
screen, disabled stays disabled. Each platform has an established idiom; **follow
it, don't invent a new harness.**

## Android (Flutter) — real widget tests

Tooling: `flutter_test` (`testWidgets`). Tests live in `test/` as `*_test.dart`.
Existing examples to mirror: `test/screens_test.dart`, `test/pinned_card_test.dart`,
`test/onboarding_test.dart`, `test/eta_pill_test.dart`, `test/settings_features_test.dart`.

This can drive the UI directly — actually tap and assert:

```dart
testWidgets('tapping a nearby card opens the stop', (tester) async {
  await tester.pumpWidget(/* wrap the widget with its Providers + LyneTheme */);
  await tester.pumpAndSettle();

  expect(find.text('Stops near you'), findsOneWidget);     // view renders
  await tester.tap(find.byIcon(Icons.search_rounded));      // press the control
  await tester.pumpAndSettle();
  expect(find.byType(SoftSearchScreen), findsOneWidget);    // intended outcome
});
```

Checklist of "performs as intended" assertions:
- **Renders:** expected text/widgets present (`findsOneWidget` / `findsNothing`).
- **Tap fires action:** `tester.tap(find.byKey/byIcon/byType/text)` → state or
  navigation changes. Add `Key`s to controls that are hard to find.
- **Toggle/switch:** tap flips the bound model value and the visual state.
- **Show/hide & empty/loading states:** pump the relevant state, assert
  visibility.
- **Disabled:** assert the action does NOT fire / control is non-interactive.
- **Navigation:** assert the destination widget appears (or use a mock
  `NavigatorObserver`).

Notes:
- Most V2 screens depend on `AppModel` / stores via Provider — wrap the widget
  under test in the same providers (see how existing screen tests set up the
  model) and stub data so it's deterministic. Don't hit the network.
- Run: `flutter test` (all) or `flutter test test/<file>_test.dart`. Keep tests
  isolated; never depend on real LTA calls.

## iOS (SwiftUI) — behavior-of-the-button tests

Tooling: XCTest unit target `ios-native/LeyneTests/`, `@MainActor`,
`@testable import Leyne`. There is **no XCUITest target**. Existing examples:
`LeyneTests/NearbyActionTests.swift`, `BusAlertTests.swift`, `AlertTimingTests.swift`.

Project idiom (from `NearbyActionTests.swift`): **SwiftUI buttons are thin
wrappers over `AppModel` / `DataStore` state mutations, so test those effects
directly** rather than pixel-tapping. Example mapping:
- "Add to Saved" / "Remove" button → assert `AppModel.togglePin` changes `pins`
- a toggle → assert the bound published property flips and persists
- "Open Stop" → assert `addRecent` records the visit
- list/sort order → assert the ordering contract

```swift
@MainActor final class StopActionTests: XCTestCase {
    func testSaveTogglesPin() {
        let m = AppModel(/* test init */)
        let code = "TEST123"
        XCTAssertFalse(m.pins.contains(code))
        m.togglePin(code)                       // the button's action
        XCTAssertTrue(m.pins.contains(code))    // intended effect
        m.togglePin(code)                       // cleanup + toggle-off path
        XCTAssertFalse(m.pins.contains(code))
    }
}
```

Rules from the existing tests:
- `AppModel` persists to `UserDefaults` — use obviously-fake stop codes and clean
  up so tests stay isolated from real user data.
- Navigation closures, UIKit handoffs (Open on Map, Share), and sheet
  presentation are integration concerns — assert the state/flag they set, not the
  OS-level presentation.
- Run: `xcodebuild test -scheme Leyne -destination 'platform=iOS Simulator,name=iPhone 16'`
  (pick an available simulator).

**If true tap-driven end-to-end UI testing is explicitly wanted on iOS:** it needs
a new XCUITest target (none exists today). Flag this to the user and offer to
scaffold it — don't silently assume it.

## Procedure

1. Identify the control/view and its **intended behavior** (what should change).
2. Pick the idiom: Flutter widget test (can tap directly) / iOS XCTest on the
   model effect.
3. Write deterministic tests (stub data, no network), including the negative case
   (disabled / no-op) and any regression for a reported bug.
4. Run the suite; report pass/fail with output. If something fails, say so with
   the failing assertion — don't paper over it.

## Boundaries

- Keep tests hermetic — never depend on live LTA/network or real user data.
- For broader test strategy / edge-case enumeration, delegate to the
  `qa-test-engineer` agent.
- This skill is about *verifying behavior in tests*. To manually launch the app
  and watch a change, use the built-in `run` / `verify` skills instead.
