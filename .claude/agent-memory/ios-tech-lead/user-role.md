---
name: user-role
description: "Who the user is and their platform expertise context — informs how to frame iOS vs Android trade-offs"
metadata:
  type: user
---

The user owns and ships the Leyne app on both iOS (SwiftUI native rewrite) and Android (Flutter). They are hands-on with both codebases — writing Swift, Dart, and reviewing diffs directly. They are technically sophisticated enough to evaluate code-level recommendations without hand-holding.

The iOS native app is the quality reference they use to judge Android. They are currently **disappointed with the Android Flutter app** and want concrete parity analysis, not general advice.

**How to apply:** When comparing iOS and Android, be concrete and file-specific. The user doesn't need "consider using X" — they need "line 104 in `soft_search_screen.dart` routes all chips to `searchStops`, while iOS does postal geocode in `SoftSearchView.maybeGeocode()`. Fix is: split on `_filter` exactly as iOS does." Lead with what's broken or missing; the user does the fixing.
