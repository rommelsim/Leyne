// Spotlight — indexes the user's pinned bus stops into Core Spotlight so
// iOS system search returns them as results, and tapping a result opens
// the stop directly inside Leyne. Mirrors the pin set on every change.

import Foundation
import CoreSpotlight
import UniformTypeIdentifiers
import os

private let spotlightLog = Logger(subsystem: "com.leyne.Leyne", category: "Spotlight")

enum Spotlight {
    /// Domain groups every Leyne entry under one identifier so we can wipe
    /// the whole set in one call when reindexing or clearing on logout.
    static let domain = "com.lyne.pinnedStops"

    /// Replace the Spotlight index with the current pin set. Each pin
    /// becomes a `CSSearchableItem` keyed by its stop code. Bus numbers
    /// tracked at that stop become keywords so a user searching "88"
    /// from Spotlight finds the stops where they ride 88. The stop code
    /// itself is also a keyword — SG commuters often recall stops by
    /// their 5-digit code rather than by name.
    ///
    /// `stopName` is injected (rather than reading DataStore directly)
    /// so this stays a free function and can be called from anywhere.
    @MainActor
    static func updateIndex(pins: [Pin], stopName: (String) -> String) {
        let items: [CSSearchableItem] = pins.map { pin in
            let attrs = CSSearchableItemAttributeSet(contentType: .item)
            let resolvedName = stopName(pin.code)
            let displayName = pin.nickname.isEmpty ? resolvedName : pin.nickname
            attrs.displayName = displayName
            attrs.title = displayName
            attrs.contentDescription = "Bus stop \(pin.code) · pinned in SG Transit"
            var keywords: [String] = [pin.code, resolvedName]
            if let tracked = pin.tracked, !tracked.isEmpty {
                keywords.append(contentsOf: tracked)
            }
            attrs.keywords = keywords
            return CSSearchableItem(
                uniqueIdentifier: pin.code,
                domainIdentifier: domain,
                attributeSet: attrs
            )
        }

        // Wipe-then-write keeps the index correct when pins are removed —
        // diffing is more complex than this is worth at the scale Leyne
        // operates (typically <20 pins per user).
        CSSearchableIndex.default().deleteSearchableItems(
            withDomainIdentifiers: [domain]
        ) { wipeError in
            if let wipeError {
                spotlightLog.error("wipe failed: \(wipeError.localizedDescription, privacy: .public)")
            }
            guard !items.isEmpty else { return }
            CSSearchableIndex.default().indexSearchableItems(items) { error in
                if let error {
                    spotlightLog.error("index failed: \(error.localizedDescription, privacy: .public)")
                } else {
                    spotlightLog.notice("indexed \(items.count) pinned stops")
                }
            }
        }
    }

    /// Extracts the stop code from the `NSUserActivity` iOS hands us when
    /// the user taps a Spotlight result. Returns nil if this isn't a
    /// Spotlight activity or doesn't carry our identifier.
    static func openedStopCode(from userActivity: NSUserActivity) -> String? {
        guard userActivity.activityType == CSSearchableItemActionType else {
            return nil
        }
        return userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String
    }
}
