---
name: project-risks
description: "Key risks and dependencies for shipping Leyne V2 — likelihood, impact, and mitigations. Updated 2026-05-30."
metadata:
  type: project
---

## Top risks as of 2026-05-30

### R1 — Large uncommitted cross-cutting work lost (Likelihood: High, Impact: High)
14 modified files span iOS widgets, Flutter stop/bus/home/settings screens, notification service, app model, and data store. A git checkout, Xcode clean, or accidental discard would silently destroy all of it. This is significantly larger than the prior session's 8-file risk.
**Mitigation:** Commit before anything else. Split into logical chunks (iOS widget palette, Android parity pass, Android notifications) rather than one giant commit — reduces blame confusion and makes bisect viable.

### R2 — No version bump before large cross-platform change (Likelihood: High, Impact: Medium)
Both iOS (2.2.3+12) and Flutter (2.2.9+21) versions have not been bumped despite significant new functionality (stop alerts, bus notify, ongoing notification, settings wiring). If an Archive or AAB is cut from uncommitted state without a version bump, either App Store Connect rejects a duplicate build number or the release has no version differentiation.
**Mitigation:** Bump iOS MARKETING_VERSION/CURRENT_PROJECT_VERSION in `project.pbxproj` and Flutter `pubspec.yaml` as part of the commit sequence, before any build.

### R3 — Android ongoing notification is foreground-only (Likelihood: High, Impact: Medium)
The "Live Activity analog" for Android updates the ongoing notification only while the app is in the foreground. A user who pins a stop and backgrounds the app gets a stale or missing notification. This was documented as a known limitation but represents a material gap from the iOS Live Activity (which updates independently).
**Mitigation:** Accepted limitation for now; must be documented in release notes. True fix requires a foreground service (Android `Service` + `startForeground`), which is a substantial engineering task. Do not ship without noting the limitation.

### R4 — Untested new notification logic (Likelihood: Medium, Impact: High)
`lib/services/notifications.dart` has new ongoing notification logic that was not unit-tested in this session (83 existing tests pass, but these cover pre-existing paths). The notification permission state, channel registration, and update-on-foreground paths have no automated coverage.
**Mitigation:** Add at minimum a smoke test for the happy path (notification created, updated, cancelled) via a MockNotificationsPlugin. Run on a real Android device before AAB upload.

### R5 — iOS `ios-native/` has zero CI coverage (Likelihood: High, Impact: Medium)
The CI iOS job builds the Flutter wrapper, not the SwiftUI native app. The newly wired Live Activity CTA and widget palette changes have no automated build validation. A broken `ios-native/` build would only surface at the next manual Archive.
**Mitigation:** Add an `xcodebuild` job (`generic/platform=iOS Simulator`, `CODE_SIGNING_REQUIRED=NO`) to CI. Recs saved in `.claude/agent-memory/devops-engineer/`.

### R6 — Commit scope too large (Likelihood: Medium, Impact: Low)
14 files across iOS and Flutter touching widgets, screens, notifications, and data model in one uncommitted blob makes the commit history unreadable and git bisect unusable if a regression surfaces post-ship.
**Mitigation:** Split into at minimum 3 commits: (1) iOS widget/LA palette + CTA wiring, (2) Android parity pass (stop/home/settings), (3) Android bus notify + ongoing notification.

### R7 — Android exact-alarm permission regression (Likelihood: Low, Impact: High)
Must use `SCHEDULE_EXACT_ALARM` (not `USE_EXACT_ALARM`) in `AndroidManifest.xml`. Play Console rejects the latter for non-alarm/calendar apps.
**Mitigation:** The build script enforces the right flag. Never change without re-reading Play policy.

**Why:** Updated post-session to reflect the larger uncommitted scope and new notification risk.
**How to apply:** Run through R1–R4 at the start of any session that touches a build or flag removal.

Related: [[project-status]], [[next-actions]]
