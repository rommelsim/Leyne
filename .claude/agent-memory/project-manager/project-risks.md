---
name: project-risks
description: "Key risks and dependencies for shipping Leyne V2 — likelihood, impact, and mitigations."
metadata:
  type: project
---

## Top risks as of 2026-05-29

### R1 — Uncommitted work lost (Likelihood: Medium, Impact: High)
Eight modified files across iOS and Flutter have never been staged or committed. A git checkout, Xcode clean, or accidental discard would silently destroy the pull-to-refresh wiring, audio session fix, and onboarding parity change.
**Mitigation:** Commit immediately before doing anything else.

### R2 — V2 ships without flag removal (Likelihood: Medium, Impact: Medium)
The V2 Soft UI is behind a `leyne.softUI` `UserDefaults` toggle on iOS and a flag branch in `lib/main.dart`. If an archive is cut before removing the flag, production users get the old V1 UI and reviewers won't see the redesign.
**Mitigation:** Confirm flag removal strategy (flip default-on or delete old paths) before the next Archive/AAB.

### R3 — iOS version mismatch between working tree and App Store Connect (Likelihood: Low, Impact: Medium)
Current `project.pbxproj` is at 2.2.3+12. If a prior build was uploaded at the same version but different code, App Store Connect will reject the duplicate build number.
**Mitigation:** Bump MARKETING_VERSION / CURRENT_PROJECT_VERSION in `project.pbxproj` before each Archive. Check CHANGELOG.md to see what +12 previously uploaded.

### R4 — Flutter `onboarding_screen.dart` onDone removal breaks cold-start launch (Likelihood: Low, Impact: High)
The in-flight Flutter change removes the `onDone` callback from `OnboardingScreen`. The `main.dart` diff removes it from the call site too, which is consistent. But `getNotificationAppLaunchDetails` cold-start path in `main.dart` must still correctly dismiss onboarding via `AppModel.shared.finishOnboarding`. Needs a quick smoke test after commit.
**Mitigation:** Run onboarding flow end-to-end on Android after committing. Confirm the ATT/consent step still dismisses the screen.

### R5 — Dead code / V1 screens inflating binary (Likelihood: High, Impact: Low)
`AddStopSheet.swift` is acknowledged dead code. V1 screens (`HomeView`, `NearbyView`, `DetailView`) remain in the build graph even after V2 is the default. Not a ship-blocker but adds confusion and binary weight.
**Mitigation:** Delete dead V1 screen files after V2 flag is removed and the build verifies clean.

### R6 — Android exact-alarm permission regression (Likelihood: Low, Impact: High)
Must use `SCHEDULE_EXACT_ALARM` (not `USE_EXACT_ALARM`) in `AndroidManifest.xml`. Play Console rejects the latter for non-alarm/calendar apps. If anyone edits the manifest without checking this, a closed-testing upload will be auto-rejected.
**Mitigation:** The build script enforces the right flag. Never change `USE_EXACT_ALARM` → `SCHEDULE_EXACT_ALARM` without re-reading the Play policy.

**Why:** Capturing these now so future sessions don't re-litigate settled decisions or miss a ship-blocking check.
**How to apply:** Run through R1–R4 at the start of any session that touches a build or flag removal.

Related: [[project-status]], [[native-rewrite-status]]
