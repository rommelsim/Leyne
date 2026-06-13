---
name: changelog-update
description: >
  Update or sync Leyne's changelogs without (necessarily) cutting a build. Use
  when the user asks to update the changelog, add a What's New entry, fix/sync the
  changelog across platforms, or when an Android/iOS What's New screen isn't
  showing because its entry is missing. For a full release (version bump + build +
  changelog), use release-build instead.
---

# Changelog update / sync

Leyne keeps **three** changelog locations. Keep them consistent.

1. **`CHANGELOG.md`** (repo root) — canonical engineering log. One section per
   version: version, platform, build number, date, artifact path, bullet summary.
   Every build gets an entry here.
2. **iOS user-facing — `kChangelog` in `ios-native/Leyne/AppModel.swift`** — a
   `[String: WhatsNewEntry]` keyed by marketing version (e.g. `"2.7.0"`). The
   What's New screen reads this.
3. **Android user-facing — `kChangelog` in `lib/data/changelog.dart`** — a
   `Map<String, WhatsNewEntry>` keyed by version. The What's New screen reads
   this.

## Critical rule

**A user-facing release MUST have a matching entry for the running version** in
its platform's user-facing changelog. If the entry for the current version is
missing, the What's New screen **never appears on update**. (This is exactly how
Android's changelog went stale at 2.5.0 while the app shipped 2.7.0.)

## Mirroring across platforms

When a feature ships on both platforms, the iOS and Android entries should say the
same thing. The two trains drift in version number, so match by *content*, not by
version string. When copying an iOS entry to Android, convert SF Symbol icon names
to the nearest Material `IconData`, e.g.:

| SF Symbol | Material `IconData` |
|-----------|---------------------|
| `tram.fill` | `Icons.train_rounded` |
| `star.fill` | `Icons.star_rounded` |
| `bell.badge.fill` | `Icons.notifications_active_rounded` |
| `cloud.sun.fill` | `Icons.wb_sunny_rounded` |
| `circle.lefthalf.filled` | `Icons.circle_outlined` |

(Match the existing entry style in each file; read a neighbouring entry first.)

## Steps

1. Determine the version(s) and the user-facing summary.
2. Add/edit the `CHANGELOG.md` section.
3. Add/edit the `WhatsNewEntry` in `AppModel.swift` (iOS) and/or `changelog.dart`
   (Android), as applicable. Keep wording aligned across platforms.
4. If you touched Dart, run `flutter analyze` to confirm it's clean.
