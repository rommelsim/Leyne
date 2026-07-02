// WhereSia — the one thin line-icon set.
//
// A single, consistent, single-weight outline set: SF Symbols rendered at a
// light weight in monochrome at the theme text colour, no fill, no emoji. This
// is the WhereSia iconography contract — every glyph in the app comes from here
// so the whole set can change in one place. The transit-identity glyphs the
// product leans on (single- vs double-deck bus, wheelchair-access, the live
// arriving wave, train/MRT, bookmark) each get a distinct symbol.

import SwiftUI

/// Semantic glyph names → SF Symbol. Named by what they mean in WhereSia, not
/// by the underlying symbol, so a symbol swap is a one-line change here.
enum WSGlyph {
    // Transit identity
    case busSingle, busDouble, busBendy, wheelchair, live, train, bookmark, bookmarkFilled
    // Navigation / tab bar
    case home, saved, alerts, me
    // Chrome
    case search, scope, location, back, chevron, chevronDown, close, edit, share
    case gear, sun, textSize, info, database, lift, filters, clock, bellRing

    var systemName: String {
        switch self {
        case .busSingle:      return "bus"
        case .busDouble:      return "bus.doubledecker"
        // SF Symbols has no articulated/"bendy" bus glyph, so we differentiate
        // deliberately within the existing outline set: the filled variant of
        // the same base symbol, distinct from busSingle's outline "bus" and
        // busDouble's entirely different silhouette.
        case .busBendy:       return "bus.fill"
        case .wheelchair:     return "figure.roll"
        case .live:           return "dot.radiowaves.up.forward"
        case .train:          return "tram"
        case .bookmark:       return "bookmark"
        case .bookmarkFilled: return "bookmark.fill"
        case .home:           return "house"
        case .saved:          return "bookmark"
        case .alerts:         return "bell"
        case .me:             return "person"
        case .search:         return "magnifyingglass"
        case .scope:          return "scope"
        case .location:       return "location"
        case .back:           return "chevron.left"
        case .chevron:        return "chevron.right"
        case .chevronDown:    return "chevron.down"
        case .close:          return "xmark"
        case .edit:           return "pencil"
        case .share:          return "square.and.arrow.up"
        case .gear:           return "gearshape"
        case .sun:            return "sun.max"
        case .textSize:       return "textformat.size"
        case .info:           return "info.circle"
        case .database:       return "externaldrive"
        case .lift:           return "arrow.up.arrow.down.square"
        case .filters:        return "line.3.horizontal.decrease"
        case .clock:          return "clock"
        case .bellRing:       return "bell.badge"
        }
    }
}

/// A single WhereSia icon. Thin, single-weight, monochrome. `pulse` animates the
/// live/arriving wave (gated behind Reduce Motion by the caller's environment).
struct WSIcon: View {
    let glyph: WSGlyph
    var size: CGFloat = 22
    var weight: Font.Weight = .light
    var color: Color? = nil
    var pulse: Bool = false

    @Environment(\.ws) private var ws
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: glyph.systemName)
            .font(.system(size: size, weight: weight))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(color ?? ws.text)
            .symbolEffect(.pulse, isActive: pulse && !reduceMotion)
            .accessibilityHidden(true)
    }
}
