---
name: ios-modern-design
description: >
  Modern iOS design reference for building or reviewing iOS UI in this repo:
  iOS 26 Liquid Glass APIs (glassEffect, GlassEffectContainer, glass button
  styles, floating tab bar, toolbar spacers, search tab), PLUS HIG design
  fundamentals — type scale, spacing/8pt grid, touch targets, semantic colour,
  animation timing and haptics — and performance/accessibility constraints.
  Use whenever designing, restyling, or reviewing SwiftUI screens/components,
  choosing fonts/padding/colours/animations, adopting Liquid Glass, or deciding
  how a new iOS surface should look and behave. The owner is not a UI designer:
  this skill does the design lifting.
---

# Modern iOS design (iOS 26 Liquid Glass)

The iOS app (`ios-native/Leyne/`, active UI in `WhereSia/`) targets the iOS 26
design language: **Liquid Glass**. Glass is a *material system for the
navigation layer* — floating bars, buttons, sheets — never a skin for content.
Colour stays semantic per the app's design language (colour = data; blue =
interaction). Requires Xcode 26 / iOS 26 SDK; older OSes fall back to
`.ultraThinMaterial`.

Researched 2026-07-18 from Apple docs + community references (verify against
current SDK if something doesn't compile):
- https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views
- https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass
- https://github.com/conorluddy/LiquidGlassReference

## Core API surface

### Glass effect

```swift
.glassEffect()                                            // .regular in a Capsule
.glassEffect(_ glass: Glass = .regular, in shape: some Shape, isEnabled: Bool = true)

Glass.regular          // default adaptive variant — use for controls/nav
Glass.clear            // high transparency — over media only
Glass.identity         // no-op — conditional disable without layout churn
.tint(_ color:)        // semantic tint only (primary action / state), chainable
.interactive()         // touch scale/bounce/shimmer — put on tappable glass

.glassEffect(.regular.tint(.blue).interactive(), in: .capsule)
```

Shapes: `.capsule`, `.circle`, `.ellipse`, `RoundedRectangle(cornerRadius:)`,
`.rect(cornerRadius: .containerConcentric)` (matches parent corner — prefer for
nested cards), or any custom `Shape`.

### Grouping & morphing

Glass cannot sample other glass — multiple glass elements MUST share a
`GlassEffectContainer` (also merges GPU sampling → cheaper):

```swift
GlassEffectContainer(spacing: 20) {           // spacing = morph threshold
    ...views with .glassEffect()...
}
.glassEffectID(id, in: namespace)             // pair states for morph transitions
.glassEffectUnion(id:namespace:)              // fuse adjacent glass into one shape
.glassEffectTransition(.matchedGeometry)      // or .materialize / .identity
```

### Buttons

```swift
.buttonStyle(.glass)              // secondary
.buttonStyle(.glassProminent)     // primary (opaque)
.buttonBorderShape(.capsule | .circle | .roundedRectangle(radius:))
.controlSize(.mini ... .extraLarge)
```

Known issue: `.glassProminent` + `.circle` renders artifacts → add
`.clipShape(Circle())`.

### Toolbars

Toolbar items get glass automatically. `ToolbarItemPlacement` now drives style:
`.confirmationAction` → glassProminent, `.cancellationAction` → glass.

```swift
ToolbarSpacer(.fixed, spacing: 12)   // split items into separate glass pods
ToolbarSpacer(.flexible)
.sharedBackgroundVisibility(.hidden) // detach an item from the shared glass pod
```

Prefer symbol-only toolbar buttons; group related actions, split unrelated ones
with `ToolbarSpacer`.

### Tab bar (floating)

The tab bar floats over content and can minimize on scroll:

```swift
TabView {
    Tab("Home", systemImage: "house", value: 0) { ... }
    Tab("Search", systemImage: "magnifyingglass", role: .search) {
        NavigationStack { ... .searchable(text: $q) }   // NavigationStack required
    }
}
.tabBarMinimizeBehavior(.onScrollDown)   // or .automatic / .never
.tabViewBottomAccessory { ... }          // persistent shelf above tabs — global
                                         // controls only (e.g. live trip strip)
@Environment(\.tabViewBottomAccessoryPlacement)  // .expanded / .collapsed
.searchToolbarBehavior(.minimized)
```

The blur/scroll-edge effect under bars is automatic — don't hand-roll it.

### Content & navigation niceties

```swift
.backgroundExtensionEffect()                     // extend hero content under bars
.scrollContentBackground(.hidden)                // let glass show through lists
.navigationTransition(.zoom(sourceID:in:)) + .matchedTransitionSource(id:in:)
.presentationDetents([.medium, .large])          // sheets get glass automatically
```

## Design fundamentals (Apple HIG — the owner is not a designer; apply these for him)

### Typography

System type scale (SF Pro; use `Font.TextStyle`, never raw sizes, so Dynamic
Type works):

| Style | pt | Use |
|---|---|---|
| `.largeTitle` | 34 | Screen hero title only |
| `.title` / `.title2` / `.title3` | 28 / 22 / 20 | Section heroes, big numbers (ETAs) |
| `.headline` | 17 semibold | Card titles, row primaries |
| `.body` | 17 | Default reading text |
| `.callout` / `.subheadline` | 16 / 15 | Secondary row text |
| `.footnote` | 13 | Metadata, timestamps |
| `.caption` / `.caption2` | 12 / 11 | Badges, tertiary labels — never below 11 |

Rules: max ~2 weights per screen (regular + semibold/bold); numbers that update
live get `.monospacedDigit()` so they don't jiggle; WhereSia's custom
Inter/Plex fonts must be wrapped in `ScaledMetric`/`relativeTo:` so Dynamic
Type still scales them. Never more than 3 font sizes in one component.

### Spacing & layout

- **8pt grid**: paddings/gaps are 4, 8, 12, 16, 20, 24, 32. Screen edge margin
  16 (20 on plus-size). Never odd one-off values like 13, 17.
- **Touch targets ≥ 44×44pt** — pad small icons with `.frame` +
  `.contentShape`, never rely on the glyph's own size.
- Related items sit closer than unrelated ones (e.g. 4–8 inside a card,
  12–16 between cards, 24–32 between sections).
- One primary element per screen zone; align everything to a single leading
  edge — mixed alignments read as clutter.

### Colour

- Use **semantic system colours** (`.primary`, `.secondary`, `Color(.systemBackground)`,
  `.separator`) or the app theme's tokens — never ad-hoc hex in views. They
  adapt to dark mode and Increased Contrast for free.
- Hierarchy by opacity, not new hues: primary text full, secondary ~60%,
  tertiary ~30%.
- Contrast: body text ≥ 4.5:1 against its background, large text ≥ 3:1.
- This app's law: **colour = data** (line colours, crowd green/amber/red,
  "arriving" green), **blue = interaction**. Everything else neutral. If a
  screen has more than those colour jobs, it's wrong.

### Animation & motion

- Default to springs: `.snappy` (small state flips), `.spring(response:
  0.3–0.4, dampingFraction: 0.8)` (movement), `.bouncy` only for playful
  confirmations. Ease-in-out only for opacity/camera.
- Durations 0.2–0.35s; anything longer must be interruptible.
- Animate only what changed (`withAnimation` around the state write, or
  `.animation(_:value:)` scoped to one value — never unscoped).
- Every animation needs a **Reduce Motion fallback**: check
  `accessibilityReduceMotion` → crossfade or no-op instead of moving/zooming.
- Prefer system transitions (`.navigationTransition(.zoom)`, matched geometry)
  over hand-rolled offsets.
- Haptics pair with meaning, not motion: `.sensoryFeedback(.selection,…)` for
  pickers/tabs, `.impact` for commits, `.success/.warning` for outcomes.

### Component defaults (when unsure, pick these)

- Cards: `RoundedRectangle(cornerRadius: 16–20, style: .continuous)`; nested
  radii concentric (child = parent − inset, or `.containerConcentric` on 26).
- Lists of settings: `List` with `.insetGrouped` look, not hand-built stacks.
- Destructive actions: confirmation dialog + `role: .destructive`, red only there.
- Empty states: one SF Symbol + one sentence + one action — `ContentUnavailableView`.
- Loading: skeleton/redacted (`.redacted(reason: .placeholder)`) over spinners.

## Rules for this app

- **Glass = navigation layer only.** Bars, floating buttons, sheets, the
  Nearest-Stop-style overlays. Never on departure rows, cards of data, or maps'
  content itself.
- **One container per cluster.** Floating controls that sit near each other go
  in a single `GlassEffectContainer`; never stack glass on glass.
- **Tint is semantic.** Blue for interaction/primary, line colours stay on data
  pills — no decorative tinting of glass.
- **Interactive glass must be `.interactive()`**, otherwise it reads as static
  chrome.
- **Concentricity:** nested rounded corners use `.containerConcentric`, don't
  eyeball radii.
- **Timely-over-honest** still applies: uncertainty is a faint `~`, never a
  glass banner.
- **Accessibility is automatic — don't fight it.** Reduce Transparency /
  Increase Contrast / Reduce Motion adapt glass by themselves; never hard-code
  opacities that bypass this. Test all three, plus Dynamic Type.
- **Performance:** glass is GPU-costly on iPhone 11–13 — no continuous
  animations on glass, profile with Instruments if a screen has many pods.
  To disable glass conditionally use the `isEnabled:` parameter (keeps layout
  stable) rather than swapping the variant to `.identity`.
- **Verify by building only** (owner checks UI himself — no simulator runs).

## Existing in-repo references

- `ios-native/Leyne/WhereSia/` — the live Liquid Glass implementation (hero,
  board, tab bar, context menus). Match its idioms before inventing new ones.
- Android counterpart is Material You — never mirror glass there (see
  `parity-audit` skip-list).

## Boundaries

- This is the *design/API* reference. To copy a finished iOS design onto
  Android, use `port-ios-feature`; to check both platforms match, `parity-audit`.
- For architecture calls (state, data flow), delegate to `ios-tech-lead`.
