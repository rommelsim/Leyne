---
name: project-slide-to-unpin-spec
description: Design spec and verdict for slide-to-unpin gesture on Home pinned cards (iOS + Android), including button-removal verdict, discoverability, accessibility, and edit-mode interplay — 2026-05-30
metadata:
  type: project
---

## Context established from code audit (2026-05-30)

**Existing iOS (V1 HomeView — PinnedCardView):**
- `PinnedCardView` has an explicit `PinButton` (bookmark icon) in the card header, top-right, visible at all times
- Edit mode via "Edit/Done" button in `savedRoutesHeader` — toggles `editing` state, replaces bookmark with drag handle
- Long-press on service row → context menu for "Make primary" / "Clear primary"
- Long-press on card → NOT implemented (no `.contextMenu` on card root, coachmark via `PinTag` overlay instead)
- `handlePin()` triggers exit animation before calling `onPin()` — confirms unpin is already animated on V1

**Existing iOS V2 (SoftHomeView — SoftPinCard):**
- `SoftPinCard` is a pure `Button(action: onTap)` with `PressScaleButtonStyle` — NO bookmark/pin button, NO edit mode, NO swipe actions
- Unpin is NOT surfaced anywhere on V2 Home card — this is a confirmed gap (from [[project-parity-map]])
- SoftStopView has pin toggle via GlassPillButton (bell/track all)
- SoftBusView has GlassPillButton (pin/pinned) — this IS the only pin-add surface on bus view

**Existing Android V2 (soft_home_screen.dart — _PinCard):**
- `_PinCard` is a simple `InkWell(onTap: ...)` with NO pin button, NO Dismissible, NO long-press
- `PinnedCard` (legacy widget) has `onLongPress: _showRenameSheet` — rename sheet via bottom sheet
- No unpin affordance on the home card at all

**Pin/unpin entry points (both platforms):**
- PIN (add): Search results, Nearby stop list, SoftStopView (bell/track-all pill), SoftBusView (pin pill)
- UNPIN (remove): V1 iOS: PinButton in card header. V2 iOS: NOT exposed on Home. V2 Android: NOT exposed on Home.
- RENAME: V1 iOS: PinTag tap. V2 iOS: no card-level rename. Android: long-press bottom sheet on legacy PinnedCard; not on _PinCard.

## Verdict and spec

See full design recommendation delivered 2026-05-30 in conversation context.

**Key decisions:**
1. Add swipe-to-unpin on both platforms (iOS swipeActions trailing, Android Dismissible)
2. REMOVE the explicit unpin control from V2 Home cards on both platforms (swipe replaces it)
3. KEEP all pin-ADD controls in Stop and Bus views — they serve a different entry point and must stay
4. Undo is mandatory: Android SnackBar with Undo action (M3 standard); iOS native `.destructive` swipe action with undo via `.contextMenu` or long-press menu
5. Accessibility non-gesture fallback required on both platforms (VoiceOver custom action iOS, TalkBack long-press menu Android)
6. Edit mode interplay: swipe-to-unpin is disabled during Edit mode (iOS); Android has no edit mode yet so no conflict
