// Lyne — sensory feedback system.
// Haptic-only (UIKit generators). Four intensities: tap / select / success / arrival.
//
// The app stays quiet by default — only select/success/arrival fire ambiently.

import SwiftUI
import UIKit

final class Feedback: ObservableObject {
    static let shared = Feedback()

    @Published var haptic = true

    func config(haptic: Bool) {
        self.haptic = haptic
    }

    // ─── Public intensities ───────────────────────────────────
    func tap() {
        vibrate(.light)
    }

    func select() {
        vibrate(.soft)
    }

    func success() {
        notify(.success)
    }

    /// Arrival is intentionally minimal: a single gentle vibration.
    func arrival() {
        vibrate(.soft)
    }

    // ─── Haptics ──────────────────────────────────────────────
    private func vibrate(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard haptic else { return }
        let g = UIImpactFeedbackGenerator(style: style)
        g.prepare(); g.impactOccurred()
    }
    private func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard haptic else { return }
        let g = UINotificationFeedbackGenerator()
        g.prepare(); g.notificationOccurred(type)
    }
}
