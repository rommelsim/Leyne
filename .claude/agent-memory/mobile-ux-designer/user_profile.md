---
name: user-profile
description: Who Rommel is and how he prefers to collaborate on Leyne
metadata:
  type: user
---

Rommel (rommelsim@gmail.com) is the solo developer/designer of Leyne, a Singapore transit app he ships on iOS (SwiftUI native, in active rewrite) and Android (Flutter). He originated the app in Flutter and is porting iOS to native SwiftUI ("iOS native leads; Flutter Android ports from iOS").

Design sensibility: strong, opinionated. Cares deeply about platform-native feel and explicitly does not want cross-platform idiom bleed — but in practice runs a shared "Soft" brand visual language with platform-native navigation chrome only (see [[project-soft-design-language]]). Maintains detailed specs (`specs/leyne-2.0-plan.md`, `parity.md`, `design-spec.md`) and writes thorough code comments explaining rationale — he values knowing the *why*.

Works in phases with explicit deferrals (Live Activity, pull-to-refresh tracked as later phases). When reviewing, distinguish "deliberately deferred" from "accidentally broken" — he tracks the former in specs.

**How to apply:** Give specific, code-referenced, prioritized feedback (he keeps a parity matrix, so P0/P1/P2 + file:line lands well). Acknowledge the shared-design decision rather than fighting it. Check specs/parity.md before flagging something as a gap — it may be a known deferral.
