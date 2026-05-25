# Leyne — Design Spec

**Status:** Canonical reference, derived from the iOS-native SwiftUI build (`ios-native/`, v2.2.0+9). Flutter Android (`lib/`, v2.1.0+8) is currently behind and should be brought to this spec over time. See `parity.md` for the work queue.

**Source-of-truth rule:** when iOS-native and this doc disagree, iOS-native wins — but update this doc in the same change. When this doc and Flutter disagree, Flutter is behind; treat the gap as a port task, not a spec issue.

---

## 1. Palette

Two themes, warm parchment vs warm near-black. Mint accent in both. Operator stripe palette is shared with the legacy Flutter build.

### Light

| Token | Hex | Use |
|---|---|---|
| `bg` | `#F7F4ED` | Page background |
| `surface` | `#FFFDF7` | Raised surface (cards, sheets) |
| `surfaceHi` | `#F1ECDE` | Hero card surface |
| `contrast` | `#1A1916` | Inverse panel (FAB, dark banners) |
| `contrastFg` | `#F2EFE8` | Foreground on `contrast` |
| `contrastSurface` | `#2A2925` | Raised inside inverse panel |
| `fg` | `#171612` | Primary text |
| `dim` | `#6D6859` | Secondary text (~52% fg) |
| `faint` | `#A8A192` | Tertiary text (~32% fg) |
| `line` | `#E5E0D2` | Hairline borders, dividers |
| `lineHi` | `#D8D3C5` | Stronger border (hero) |
| `accent` / `live` | `#2BAA67` | Primary CTA, "arriving" |
| `liveBg` | `#E3F5EA` | Arriving row background |
| `warn` | `#B58A1F` | "Leave now", "delay" |
| `warnBg` | `#F6EBC9` | Warn row background |
| `crit` | `#C44A3A` | "Last bus", "disrupted" |
| `critBg` | `#F7DAD4` | Crit row background |

### Dark

| Token | Hex | Use |
|---|---|---|
| `bg` | `#0E0E0A` | Page background |
| `surface` | `#161612` | Raised surface |
| `surfaceHi` | `#1D1C18` | Hero card surface |
| `contrast` | `#ECE9E0` | Inverse panel |
| `contrastFg` | `#0B0B08` | Foreground on `contrast` |
| `contrastSurface` | `#2A251F` | Raised inside inverse panel |
| `fg` | `#ECE9E0` | Primary text |
| `dim` | `#ECE9E0 @ 52%` | Secondary text |
| `faint` | `#ECE9E0 @ 32%` | Tertiary text |
| `line` | `white @ 7%` | Hairline |
| `lineHi` | `white @ 14%` | Stronger border |
| `accent` / `live` | `#5EE597` | Primary, "arriving" |
| `liveBg` | `#5EE597 @ 14%` | Arriving row tint |
| `warn` | `#E9B04B` | Warn |
| `warnBg` | `#E9B04B @ 16%` | Warn background |
| `crit` | `#E96A5C` | Crit |
| `critBg` | `#E96A5C @ 16%` | Crit background |

### Operator stripe colors

Applied as a 3pt left edge on non-arriving, non-primary service rows. Quiet identity, never competes with the arriving pill.

| Operator | Color | Notes |
|---|---|---|
| SBST (SBS Transit) | red | |
| SMRT | silver | |
| TTS (Tower Transit) | yellow | |
| GAS (Go-Ahead) | orange-red | |

At 85% opacity on the stripe so it doesn't dominate.

---

## 2. Typography

System face for sans; SF Mono for monospaced. Mono is used for bus numbers, ETAs, stop codes, and uppercase meta labels — anywhere the eye should scan vertically.

### Sans-serif (system default)

| Size | Weight | Use |
|---|---|---|
| 30 | semibold | Onboarding titles |
| 28 | semibold | Page titles ("Home", "Nearby") |
| 26 | semibold | Editable stop names (Detail heading) |
| 20 | semibold | Pinned card title |
| 17 | semibold | Section headers, card titles |
| 16 | semibold | Onboarding body, Continue button |
| 15 | semibold | Nearby row names, search field text |
| 14 | medium | Destination ("→ Place"), service row text |
| 13 | medium | Buttons, chip text |
| 12 | regular | Body, small notes |
| 11 | regular | Captions |

### Monospaced (SF Mono)

| Size | Weight | Tracking | Use |
|---|---|---|---|
| 64 | light | -1.2 | Hero ETA (numeric) |
| 44 | light | — | Hero ETA when "Arr" |
| 28 | medium | — | Pinned card ETA |
| 24 | bold | — | Bus number in Detail hero |
| 22 | medium | — | Pinned card ETA when "Arr" |
| 20 | bold | — | Bus number on pinned card |
| 17 | semibold | — | Bus number in Nearby; distance "NN" in Nearby |
| 15 | semibold | — | Destination prefix, bus number in search |
| 13 | bold | — | Bus chip in search result row |
| 11 | semibold/medium | 1.0–1.2 | "LIVE", "STOP", "SAVED ROUTES" |
| 10 | medium/regular | 0.6–1.2 | Walk time, "then NN", section eyebrows |
| 9 | bold | 0.6 | "ARRIVING" pill |
| 8 | medium | 0.5 | Map "STOP" label |

### Tracking (letterspacing) defaults

- Uppercase mono meta (≥11pt): `1.0–1.4`
- Smaller meta mono: `0.6–0.8`
- Big numeric ETA: `-1.2` (tighter, reads as a countdown)

---

## 3. App structure (RootView)

Native iOS 26 `TabView` with `Tab` items + the iOS 26 Liquid Glass tab bar.

**Tabs (left to right):**

1. **Home** — `house.fill`
2. **Nearby** — `smallcircle.filled.circle`
3. **Settings** — `gearshape.fill`
4. **Search** — `.search` role (renders as detached pill in iOS 26)

The Search tab is interactable but selection never actually moves to `.search`. A custom `Binding` intercepts the change and sets `m.searchOpen = true` to mount `SearchSheetA` as a full-screen overlay.

**Tint:** `accent` (mint).

### Sheet / modal z-index stack (bottom → top)

| zIndex | View | Trigger |
|---|---|---|
| — | Tab bar | always |
| 30 | `DetailView` / `DetailPager` | tap a pin or service |
| 40 | `AddStopSheet` | + button |
| 45 | `SearchSheetA` | search tab tapped |
| 50 | `OnboardingView` | first run only |
| 55 | What's-New changelog | one-time per version |
| 200 | Launch splash | initial mount |

**Transitions:**

- Search / Onboarding / What's New: `.opacity`, `easeInOut(0.3s)`
- Detail open/close: `.move(.trailing) + .opacity`, `easeInOut(0.36s)`

---

## 4. Home

```
DAY DATE          ← mono 11, tracking 1.2
Home          LIVE ← sans 28 semibold ; live chip top-right

SAVED ROUTES · N      EDIT/DONE

[PinnedCard 1 — hero candidate]
[PinnedCard 2]
[PinnedCard 3]
…

LEYNE · BETA · v1.2.3 ← faint footer
```

### Live chip

- Mono 11 semibold, tracking 1.0
- Dot: 7×7pt circle, live color, shadow radius 4 / opacity 0.55 on live state only
- States by data freshness:
  - **Live** (<30s old): green (`live`), with shadow
  - **Stale** (30s–5min): amber (`warn`), no shadow
  - **Offline** (>5min or error): red (`crit`)
- Format: short `"LIVE"` on the sticky bar; expanded `"LIVE · HH:MM"` on the header.

### Sticky compact bar

- Triggers when title scrolls past Y = `-12pt`
- Height: 48pt + safe-area top
- Background: `glassSurface()` with `.ignoresSafeArea(.top)` to frost the status bar
- 1pt `line` bottom hairline shows/hides with the bar
- Transition: `easeInOut(0.22s)`; no hit-testing while hidden

### Pull-to-refresh

- Threshold: 80pt
- Arrow rotates 180° at the trigger; `ProgressView` while active
- Indicator Y is capped at 28pt above safe area; opacity scales `min(1, pullY / 50)`
- Fixed 0.9s active duration

### Empty state

Large bookmark glyph on mint circle (64×64pt, 26pt icon) → "Nothing pinned yet" headline (sans 17 semibold) → body copy (sans 13, line spacing 2) → two CTAs: solid mint "Nearby" capsule + outline "Search" capsule.

### Coachmark (first-run hint)

- Pulses on the first saved card + bookmark button once per install
- `hand.tap` glyph + "Long-press any row to make it your primary" (mono 11)
- Auto-dismisses after 6s
- Entrance: opacity + 14pt Y offset, `easeOut(0.42s)`

### Pinned card entrance

Staggered fade + 14pt → 0pt rise with 60ms per-index delay, capped at 7 cards (~420ms total). `easeOut(0.42s)` per card. Fires once on `onAppear`, stays true across tab switches.

---

## 5. Pinned card (PinnedCardView)

```
Stop Name                                ★|⋮
STOP XXXXX · 5 min walk · ✎ LABEL · 2/4 tracked
─────────────────────────────────────────
✓ 88   → Destination               Arr min
                                   then 9
─────────────────────────────────────────
  156  → Different route               9m
                                   then 18
─────────────────────────────────────────
  410  → Loop service                  4m
                                  then Arr
─────────────────────────────────────────
+ 2 more services                  See all →
```

### Header

- Stop name: sans 20 semibold, foreground `fg`
- Sub-meta: "STOP CODE · walk min · ✎ LABEL · N/M tracked" — all mono 11, `dim`
- Right: bookmark (pinned) or drag handle (in edit mode)
- Pulse dot next to the bookmark if any row is arriving
- First-card coachmark: accent ring pulses, first install only

### Service row anatomy

1. **Bookmark marker** (16pt wide): filled mint bookmark if primary, blank otherwise
2. **Bus badge** (30×30pt min, rounded 8pt cornerRadius)
   - Primary: mint background, white text
   - Non-primary: `contrast` background, `contrastFg` text
   - Mono 15 bold
3. **Destination** (left-aligned): sans 14 medium, `fg`
4. **Load** indicator + step-up badge (if not wheelchair-accessible)
5. **ETA** (right-aligned):
   - Big number: 22pt if `"Arr"`, 28pt otherwise (mono medium)
   - Mint if arriving, else `fg`
   - `.numericText(countsDown: true)` for smooth countdown
   - "then N" below, mono 10, dim
6. **Arriving background**: `liveBg` (mint at 14%)
7. **Left edge**:
   - Arriving → 4pt mint Capsule pill, inset 6pt left + 10pt vertical
   - Else → 3pt operator stripe at 85% opacity

Padding: 14pt horizontal, 12pt vertical.

### Overflow

- "+ N more services" (mono 11)
- "See all" + chevron

### Visual states

| State | Treatment |
|---|---|
| **New card** | Entrance: spring(response 0.5, dampingFraction 0.6), 0.94 scale + -16pt Y, 1.4s fade |
| **Global hero** | 1.6pt `live` border ; shadow radius 14, Y 8, opacity 18% ; primary row gets mint background |
| **Arriving (non-hero)** | 1pt mint border ; shadow radius 14, Y 8, opacity 12% ; **heartbeat** pulse |
| **Edit mode** | drag handle replaces pulse dot + bookmark |

**Heartbeat** = continuous scale 1.0 ↔ 1.012, 1.4s `easeInOut`, repeats forever, while `etaSec ≤ 60`. Fade-out to 1.0 in 0.3s `easeInOut` when ETA exceeds 60s.

### Edit-mode reorder

Native SwiftUI `.draggable` / `.dropDestination`. Drop indicator is a 3pt mint Capsule above the target card. Drop animation: spring(response 0.42, dampingFraction 0.82). Drag handle: `line.3.horizontal`, 14pt semibold.

### Primary selection

Long-press a service row → context menu → "Make primary" / "Clear primary". Primary bus locks: mint bookmark marker + mint bus badge + becomes the hero candidate when this card is the hero.

---

## 6. Stop detail — Variant B Smart Hero (DetailView)

### Top bar (sticky, glass)

- Back: `accent` chevron + label, max width 220pt
- Right: pin toggle (bookmark)
  - Pinned: filled, mint accent, mint background (8%), mint border (25%)
  - Unpinned: outline, `fg`, transparent
- Toggle transition: `easeInOut(0.2s)`

### Heading

```
STOP XXXXX                ← mono 10, tracking 1
[BigTitle editable] ✎     ← sans 26 semibold
Official Stop Name        ← only if different from label
🚶 N min walk             ← only if > 0
```

- `EditableTitle`: tap to rename, TextField on demand, mint underline
- Pencil only when stop is pinned

### Mode A — stop overview (before selecting a service)

**Services list card.** Card is `glassSurface()` with cornerRadius 18 + 1pt `line` stroke.

- "TRACK ALL / UNTRACK ALL" chip at top (with N/M count)
- Divider
- One `ServiceTapRow` per service:

```
[checkbox] [bus#] destination               ETA min
           → Road name           ↓ following
[operator stripe]        [mint left-edge if arriving]
```

- Bus number: mono 20 bold
- Load / wheelchair / deck metadata in the row
- Arriving → mint left pill (4pt) + `liveBg` background
- Non-arriving → 3pt operator stripe
- Untracked rows at 0.55 opacity

Row padding: 16pt horizontal, 14pt vertical.

**Notify card.**

- Bell icon on mint circle (32×32pt, 15pt icon, 13% background)
- Title: "Notify me 2 min before arrival" — or "Pin a bus to enable…"
- Multi-bus + enabled → inline mint-outlined chips (up to 4, then "+N")
- Toggle pill: 44×26 Capsule, white 22pt circle with shadow
  - Enabled: `accent` fill
  - Disabled: `line` fill at 0.6 opacity
- Card: `glassSurface()`, cornerRadius 14, 1pt `line` stroke; 0.55 opacity when disabled.

### Mode B — service drill-in (after tapping a service)

**Hero card.**

```
BUS 88 → Destination
NEXT ARRIVAL
           Arr  or  NN min
           (following mint, lower)
─────────────────────────────────
FOLLOWING       NN min  ·  NN min
```

- Left: bus number (mono 24 bold) + destination (sans 12)
- Right: big ETA — 44pt if `"Arr"`, 64pt if numeric — mono light, `accent` color, `.numericText(countsDown: true)`
- Unit ("min"): mono 16
- Following row: faded 22% opacity per additional bus
- Card: `glassSurfaceHi()`, cornerRadius 22, 1pt `lineHi` stroke
- Padding: 20pt horizontal, 18pt top / 16pt bottom

**Live Activity button.**

- "Start Live Activity" / "Stop Live Activity"
- `lock.rectangle` or `stop.fill` icon, 14pt
- Active: `fg` background, white border + checkmark circle
- Inactive: `bg` background, no border
- Transition: `easeInOut(0.2s)`; disabled opacity 0.55

**Map embed.**

- 240pt height, cornerRadius 18, 1pt `line` stroke
- Markers:
  - Your stop: 26×26pt mint circle, `bus.fill` icon (white, 11pt bold), 2pt white border, "STOP" label (mono 8 tracking 0.5)
  - Live bus: green pill with bus number (mono 11 bold), 1.5pt white border, drop shadow
  - User location: 14pt blue dot + 28pt faded circle
- Legend (top-left): dots + mono 9 labels on semi-transparent pill
- Status (bottom-right): "LIVE · LTA · NO BUS GPS" — mono 9 tracking 0.6, white on black-semi-transparent

**Route progress.**

- Vertical stem with nodes (8pt circles passed/future; 12pt for your stop / bus / alight choice)
- Stem: 2pt (filled = passed, hairline = future)
- Stop name: sans 14 (semibold if it's your stop / where the bus is / alight choice)
- Stop code: mono 10, dim
- Alight: "tap to alight" (mono 9 dim) or filled mint "ALIGHT" pill
- Passing stops: 0.45 opacity

---

## 7. Search sheet (SearchSheet)

```
[Safe Area Top]
┌─ Search field ─────────────── CANCEL ┐
│ 🔍 input                          ✕  │
├──────────────────────────────────────┤
│ DETECTED · TYPE · N matches          │  ← detected kind eyebrow
├─ Content ScrollView ─────────────────┤
│ Recent FlowChips (horizontal scroll) │
│  or:                                 │
│ BUSES (count)                        │
│ [SRRow] [SRRow] …                    │
│ STOPS (count)                        │
│ [SRRow] [SRRow] …                    │
└──────────────────────────────────────┘
```

### Search field

- HStack: magnifying glass (15pt, dim) + TextField + clear ✕ (12pt bold)
- Height: 40pt
- Background: `surface`, cornerRadius 12, 1pt `line` stroke
- Font: sans 15
- Padding: 16pt horizontal, 10pt vertical header

### Detected-kind pill

"DETECTED · BUS · 5 MATCHES" — mono 10, tracking 0.8, dim. No background in empty state.

### Empty state

- "Stops near me" card (icon + text + arrow) — opens Nearby tab
- "RECENT" section with FlowChips

### FlowChips (recent)

- Horizontal `ScrollView` (no indicators), fixed 38pt height
- Each chip: clock icon (10pt medium) + label (sans 12 medium)
- Capsule: `surface` background, 1pt `line` stroke
- Padding: 12pt horizontal, 7pt vertical
- 8pt gap between chips

### Search result row (SRRow)

```
[lead] Title                         →
       Subtitle
```

- Bus lead: mono 13 bold on `live` background, minWidth 48pt, minHeight 32pt, cornerRadius 7
- Icon lead: rounded rect 36×36pt, 15pt icon, background = accent at 9%
- Title: sans 14 medium
- Subtitle: mono 11 dim
- Trailing chevron: 13pt dim
- Padding: 20pt horizontal, 10pt vertical
- Caps: max 20 buses, max 30 stops shown

### Postal code (6-digit query)

Triggers OneMap geocode. Header: "POSTAL CODE · N STOPS · RADIUS". Each row:

- Distance column (left): mono 15 semibold "NNN" + mono 9 "m"; walk time mono 8 uppercase tracking 0.4, `faint`
- Divider
- Stop name (sans 14) + stop code (mono 11 dim)
- Row: `surface` rounded 12, 1pt `line` stroke

---

## 8. Nearby (NearbyView)

### Header

"Nearby" (sans 28 semibold) + radius chip top-right (`scope` icon + "XXXM" mono 11 semibold tracking 1).

### Sort buttons

"SORT" label (mono 10 medium tracking 1.2) + 3 capsule buttons:

- Active: solid `fg` background, `bg` text (contrast)
- Inactive: outline `line`, dim text
- Transition: `easeInOut(0.3s)`

### Row (NearbyRowFlat)

```
 52m │ Stop Name                  ARRIVING
 6 MIN │ STOP XXXXX  88 156 +4
```

- Distance column (right-aligned, 52pt wide): mono 17 semibold "NN" + mono 10 "m"
- Walk time: mono 8 uppercase tracking 0.4, faint
- Divider 1pt `line`
- Stop name (sans 15 semibold) + stop code (mono 10 faint)
- "ARRIVING" pill (mint, mono 9 bold tracking 0.6) — only when ≤60s
- Service chips inline: mono 10 bus numbers — arriving = mint bg + dark text; others = `lineHi` bg + fg text
- Arriving row: `accent` at 5% background + 35% border, mint stroke
- Non-arriving: `glassSurface()` background, 1pt `line` stroke
- Cornerradius 14; padding 14pt horizontal, 12pt vertical

Sticky compact bar pattern matches Home.

---

## 9. Onboarding (OnboardingView)

**5 steps:**

1. **Hero (LEYNE)** — time + arriving card mock
2. **Pin** — stack of 3 sample cards
3. **Narrow** — card with tracking checkboxes
4. **Notification** — banner + alt UI
5. **Location** — iOS location prompt mock (last step; tapping Continue prompts + dismisses)

### Layout

```
[Back][Skip]
[Large visual mock — centered, 280–320pt tall]
EYEBROW              ← mono 11 tracking 1.4
Step title           ← sans 30 semibold
Step subtitle        ← sans 15
Footnote (mono 11) if present
[• • — • •]          ← dot indicators
[ Continue ]         ← sans 16 semibold, mint, full-width
```

### Transitions

- Step-to-step: `.opacity + .move(.trailing)` over 0.4s, custom curve `(0.2, 0.8, 0.2, 1)`
- Back disabled on step 0
- Continue full-width mint; disabled on final step once location prompt has fired

### Dot indicators

- Active: 20×6pt, `accent`
- Inactive: 6×6pt, `line`
- 6pt gap between dots

### Copy examples (current iOS-native)

- Step 1: "Your bus stops, always on top."
- Step 4: "See stops near you."

### Mock styling

- Cards: `glassSurface()`, cornerRadius 18
- Normal shadow: radius 7, Y 4
- Arriving mock shadow: radius 15, Y 8, with mint tint
- Pin stack: 3 cards with 10pt spacing
- Location mock: rounded rect 270pt wide, system-prompt style

---

## 10. Surfaces — Liquid Glass

All raised elements use `glassSurface()` or `glassSurfaceHi()`:

```swift
glassSurface() = ZStack {
    surface.opacity(0.4)          // warm tint underneath
    Rectangle().fill(.regularMaterial)  // iOS 26 glass
}
```

- `glassSurface` opacity tint: 0.4
- `glassSurfaceHi` opacity tint: 0.5 (used by the Detail hero only)
- On iOS 18–25 it falls back to opaque `surface` / `surfaceHi`

**Where it's used:**

- Pinned cards
- Sheets (Search, Add)
- Sticky top bars (Home + Nearby compact bar)
- Service-list card and Notify card on Detail Mode A
- Hero card (Detail Mode B) — uses `glassSurfaceHi`
- Onboarding mock cards

Inline rows and the page background stay solid for legibility — glass is only for raised, modal, or persistent-chrome surfaces.

---

## 11. Motion catalogue

| Element | Trigger | Duration | Easing | Notes |
|---|---|---|---|---|
| Sticky bar show/hide | scroll past -12pt | 0.22s | easeInOut | opacity + 6pt Y |
| Search / Onboarding open | — | 0.3s | easeInOut | `.opacity` |
| Detail push | tap service / pin | 0.36s | easeInOut | `.move(.trailing) + .opacity` |
| Pull indicator | pull > 4pt | 0.18s | easeOut | arrow rotation + opacity |
| Refresh spinner | active | 0.7s | linear | repeatForever, no autoreverse |
| Pinned card entrance | first appear | 0.42s/card | easeOut | 60ms stagger, max 7 cards |
| Pinned card unpin | gesture | 0.36s | curve(0.5, 0.05, 0.2, 1) | scale 0.97 + 36pt X |
| Heartbeat | etaSec ≤ 60 | 1.4s | easeInOut | scale 1.0↔1.012, repeatForever |
| Heartbeat fade-out | etaSec > 60 | 0.3s | easeInOut | one-shot settle to 1.0 |
| ETA countdown | each second | 0.4s | easeInOut | `.numericText(countsDown: true)` |
| Onboarding step | next | 0.4s | curve(0.2, 0.8, 0.2, 1) | `.opacity + .move(.trailing)` |
| Swipe hint pulse | first pager open | 0.9s | easeInOut | chevron ±3pt X, repeatForever |
| Swipe hint dismiss | first swipe / 5s | 0.3s | easeIn | opacity |
| Service row press | tap | 0.18s | spring(0.18, 0.75) | scale 0.98 → 1.0 |
| Edit-mode drop | drop | 0.42s | spring(0.42, 0.82) | reorder slide |
| Live Activity toggle | tap | 0.2s | easeInOut | background swap |
| Coachmark appear | first card appear | 0.4s | easeOut | ring pulse |
| Coachmark dismiss | 6s / interaction | 0.3s | easeIn | opacity |
| Pin button tap | tap | 0.22s | spring(0.22, 0.5) | scale pulse 0.78 → 1.0 |

---

## 12. Spacing & sizing tokens

| Token | Value | Use |
|---|---|---|
| Card cornerRadius | 18pt | Pinned cards, service rows, hero, map |
| Small cornerRadius | 12pt | Search field, recent chips, postal rows |
| Tiny cornerRadius | 8pt | Bus badges, toggle pills |
| Hairline | 1pt | All borders & dividers |
| Strong border | 1.6pt | Global hero card |
| Service row vertical padding | 12–14pt | Pinned + detail rows |
| Service row horizontal padding | 14–16pt | Pinned + detail rows |
| Map height | 240pt | Detail Mode B |
| Sticky bar height | 48pt | + safe-area top |
| FlowChip height | 38pt | Recent searches |
| Distance column width | 52pt | Nearby + postal rows |
| Bus badge minWidth | 30–56pt | Sized to fit number |
| Icon circle | 36–64pt | Varies by context |
| Pressable row scale | 0.98 default | Press feedback (0.96 / 0.94 for big targets) |

---

## 13. State & user-facing behavior

### Pin model

- A pin = stop code + nickname + optional `tracked` array + optional `primaryBus`
- `tracked == nil` → all services shown (default)
- `tracked == [busNos]` → explicit subset
- Empty `tracked` is never stored — unpin instead

### Freshness states (live chip)

| State | Window | Color |
|---|---|---|
| Live | <30s | green (`live`) + shadow |
| Stale | 30s–5min | amber (`warn`), no shadow |
| Offline | >5min or error | red (`crit`) |

### Live Activities (iOS only)

- ActivityKit-based; triggered manually via Detail Mode B "Start Live Activity"
- Key: `"stopCode|busNo"`
- Only one active at a time — new trigger replaces prior
- Updates via background polling (1s app tick)
- Visible on lock screen + Dynamic Island

### Notifications

- 2-minute pre-arrival threshold
- Banner + haptic + sound, user-toggleable

### Hidden service filtering

- `tracked` controls visibility on Home / Nearby
- Detail Mode A always shows ALL services at the stop
- Home card subtitle shows "N/M tracked"

### Recent searches

- Max 8, oldest dropped on overflow
- Persisted to `UserDefaults` under `"leyne.recents"`
- Auto-deduplicated case-insensitive

### Haptics

- `.success()` for pin / add
- `.tap()` for UI interactions
- Disabled when `m.haptic == false`

---

## 14. Key design distinctions (Variant B Smart Hero)

These are the load-bearing choices — change them and you've drifted from the spec.

1. **No full-bleed hero card on Home.** Variant B removes the giant "LEAVE NOW" card. The global hero treatment (mint border, mint primary-row background, larger shadow) is applied to whichever pinned card has the smallest ETA-walk margin. Hierarchy stays flat; the answer "which bus & when" stays unmissable.

2. **Liquid Glass on iOS 26.** All raised surfaces use `.regularMaterial` with an opaque warm tint underneath so parchment carries through. Fallback to opaque on iOS 18–25.

3. **Operator stripe identity.** Non-arriving, non-primary rows show a 3pt left edge in operator color. Quiet identity that never competes with the arriving pill.

4. **Heartbeat scale animation.** Arriving cards continuously pulse (1.012 over 1.4s) — signals "your bus is here" without layout shift.

5. **Staggered list entrance.** Pinned cards fade + rise with 60ms per-index stagger, capped at 7 cards. Builds discovery on first Home appearance.

6. **Primary-bus user choice.** Long-press → "Make primary" locks a bus as the card's hero regardless of ETA. Falls back to auto-soonest if cleared.

7. **Glass top bars.** Search field, Detail back button, and sticky scroll headers all sit on glass — reads as persistent system chrome, matches the tab bar's vocabulary.

---

## 15. Platform notes

- **iOS 26 minimum** for Liquid Glass; iOS 18–25 fall back to opaque surfaces
- `safeAreaInset(.top)` for sticky search field
- `safeAreaInset(.bottom)` for bottom sheets
- `.scrollDismissesKeyboard(.immediately)` on search ScrollView
- Avoid stacking two `safeAreaInset` layers on a ScrollView — collapses content height on iOS 26 (root cause of the search no-results regression)
- Live Activities require `LeyneActivityAttributes` model + `Activity.activityUpdates` for restoration after cold launch
