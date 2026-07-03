---
name: android-settings-unreachable
description: Android SoftSettingsScreen has zero entry point as of 2026-07-03 punch-list item 9 — owner must pick a new home
metadata:
  type: project
---

As of 2026-07-03 (owner punch list, Section E, item 9), the Android app has
NO way to reach `lib/screens/v2/soft_settings_screen.dart` from anywhere in
the UI. The header gear on `soft_alerts_screen.dart` was the only call site
that ever instantiated `SoftSettingsScreen(...)` (grep-verified across
`lib/`) — it was removed to match iOS `WSAlertsView`, which has no settings
entry at all on its Alerts screen (or anywhere else, per the native rewrite's
"Settings is no longer a tab" direction).

Settings currently hosts (verified by reading the file directly, not
assumed): **Appearance** (theme mode picker), **Hidden stops** (nav to
`hidden_stops_screen.dart` — only shown once the user has hidden a stop, and
is now the ONLY way to un-hide one), **Buy me a coffee** (live Stripe
donation link), and **Haptics** toggle. Note: contrary to an earlier
assumption, this screen does NOT currently contain any UMP/consent UI or a
clock-format toggle — UMP consent is gathered automatically at launch via
`lib/services/ad_consent.dart` (`AdConsent.gatherThenStart()`), with no
in-app "manage privacy choices" reopen row anywhere in the codebase; the
12-hour clock has no format toggle by design (see the file's own header
comment).

**Why this matters:** the donation row is a live revenue channel and hidden
stops has no other undo path, so this isn't cosmetic — it's a real feature
regression until the owner decides where Settings' entry point should live
now that both the tab bar and the Alerts-screen gear are gone.

**How to apply:** don't relocate these rows yourself if asked to touch
Settings-adjacent screens again — flag the gap and let the owner pick the
new home (a Home/Saved screen affordance, a long-press menu, etc.), per
[[feedback_platform_design]]-style owner-driven decisions on this project.
Re-verify this memory before acting on it — a new entry point may have been
added since 2026-07-03.
