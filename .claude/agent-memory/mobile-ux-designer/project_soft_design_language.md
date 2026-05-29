---
name: project-soft-design-language
description: The actual cross-platform design strategy in Leyne's code and how it sits against the "no idiom bleed" principle
metadata:
  type: project
---

Leyne's real strategy (from specs + code): **one shared custom visual language ("Soft" — warm dark #15201C / warm light #F4EFE7, mint accent, rounded 16–22pt cards, mono eyebrows, custom pill chips, Inter body font planned) rendered identically on iOS and Android**, with **only the navigation chrome made platform-native**:
- iOS: native iOS 26 `TabView` (Liquid Glass bar, `.search` role tab), `NavigationStack` push/edge-swipe-back.
- Android (Flutter): Material 3 `NavigationBar` + `MaterialPageRoute` fade-through.

So the platform-native layer is THIN (nav container only). Cards, toggles, chips, sort pills, top action bars, settings rows are bespoke and shared.

This is a deliberate brand-led choice (`specs/leyne-2.0-plan.md`, `parity.md`), and it is in tension with the user's stated "no cross-platform idiom bleed" principle. Resolution reached in review: the shared brand surface is legitimate; the bleed risk is in *controls/affordances* that mimic the wrong platform's component (e.g. the custom 38x22 `SoftToggle` instead of native `UISwitch`/Material `Switch`; hand-rolled segmented Appearance picker is OK because iOS uses real `.segmented` Picker; settings rendered as custom cards instead of iOS grouped `List`/Material list).

**Why:** Avoids re-litigating the shared-design decision every review; focuses critique on genuine idiom violations rather than the brand surface itself.
**How to apply:** Don't flag the Soft brand visuals as "bleed." DO flag: non-native interactive controls where a platform component carries free a11y/behavior (switches, lists, search field, context menus, pull-to-refresh), and any place one platform's gesture/affordance assumption is baked in. See [[project-ios-native-gaps]].
