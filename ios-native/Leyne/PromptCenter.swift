//  PromptCenter.swift
//
//  Coordinates Leyne's two soft, contextual prompts:
//    • an App Store **review** nudge, and
//    • a "Buy me a coffee" **support** nudge.
//
//  Both are paced by one coordinator so the user is asked at a good moment but
//  never nagged: at most ONE prompt per app session, a minimum gap between any
//  two asks, the review at most twice per install (and never again once rated —
//  Apple also caps its own sheet to ~3/year), and the coffee nudge rarely.
//
//  App-Store-compliant: the review path opens the App Store review composer
//  (apps.apple.com/.../?action=write-review) — Apple-sanctioned for "Rate us"
//  buttons, always works, and isn't quota-limited. (StoreKit's `requestReview`
//  is suppressed on TestFlight/Simulator and capped to ~3/year, so it "did
//  nothing" in testing.) We never mimic the rating UI or solicit a specific star
//  count — the in-app card is only a soft pre-prompt. The legacy `ReviewPrompt`
//  (notification-tap ask) is folded in here; its `leyne.review.requested` key is
//  reused so already-asked users aren't re-prompted after this ships.

import SwiftUI

/// One source of truth for the app's outbound links (also used by Settings).
enum AppLinks {
    /// Stripe Payment Link for "Support Leyne" — PayNow + cards + Apple Pay,
    /// settles SGD. Leyne is ad-funded, not paywalled; this is optional.
    static let coffee = URL(string: "https://buy.stripe.com/6oU3cv5689oB3PI6R68so00")!

    /// Leyne's App Store numeric ID (apps.apple.com/sg/app/leyne/id6770481761).
    static let appStoreID = "6770481761"
    /// Opens the App Store review composer directly — always works (unlike
    /// StoreKit's quota-limited / TestFlight-suppressed `requestReview`).
    static let writeReview = URL(
        string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")!
}

/// The two prompts Leyne can present.
enum AppPrompt: String, Identifiable {
    case rateApp, buyCoffee
    var id: String { rawValue }
}

@MainActor
final class PromptCenter: ObservableObject {
    static let shared = PromptCenter()

    /// Drives the sheet in `RootView`. Set to present; cleared on dismiss/action.
    @Published var active: AppPrompt?

    // ── Tunables ──────────────────────────────────────────────────────────
    /// Never prompt before the user has opened the app this many times — don't
    /// pester a first-time user even if they complete a journey immediately.
    private let minOpensBeforeAnyPrompt = 2
    /// Open-count fallback trigger for the review (the journey trigger usually
    /// fires first for engaged users).
    private let reviewAfterOpens = 4
    /// The coffee nudge waits until the app is clearly part of the user's routine.
    private let coffeeAfterOpens = 12
    /// Hard floor between any two prompts of any kind.
    private let minDaysBetweenPrompts = 3
    /// Re-offer coffee at most this often.
    private let coffeeCooldownDays = 45
    /// Show the review pre-prompt at most this many times, then stop.
    private let maxReviewAsks = 2

    // ── Persistence ───────────────────────────────────────────────────────
    private let kOpens        = "leyne.prompts.appOpens"
    private let kLastPrompt   = "leyne.prompts.lastPromptAt"
    private let kReviewAsks   = "leyne.prompts.reviewAsks"
    private let kReviewDone   = "leyne.review.requested"     // legacy key (reused)
    private let kCoffeeLastAt = "leyne.prompts.coffeeLastAt"

    private let d = UserDefaults.standard
    /// Only one prompt per launch, regardless of how many triggers fire.
    private var shownThisSession = false

    private init() {}

    // MARK: - Triggers

    /// Call once per app launch (after onboarding). Counts the open and may
    /// surface a prompt on the Nth open.
    func noteAppOpen() {
        let n = d.integer(forKey: kOpens) + 1
        d.set(n, forKey: kOpens)
        evaluate(opens: n, afterJourney: false)
    }

    /// Call when the user's tracked bus actually arrives (an arrival alert is
    /// fulfilled) or they tap a useful Leyne notification — the strongest
    /// "Leyne just worked for me" moments.
    func noteSuccessfulJourney() {
        evaluate(opens: d.integer(forKey: kOpens), afterJourney: true)
    }

    // MARK: - Decision

    private func evaluate(opens: Int, afterJourney: Bool) {
        guard active == nil, !shownThisSession else { return }
        guard opens >= minOpensBeforeAnyPrompt else { return }
        if let last = lastPromptDate, daysSince(last) < Double(minDaysBetweenPrompts) { return }

        let reviewDone = d.bool(forKey: kReviewDone)
        let reviewAsks = d.integer(forKey: kReviewAsks)

        // 1) Review first — until rated, or we've asked the cap of times.
        if !reviewDone, reviewAsks < maxReviewAsks, afterJourney || opens >= reviewAfterOpens {
            present(.rateApp); return
        }
        // 2) Coffee — only once the review is resolved, and sparingly.
        let reviewResolved = reviewDone || reviewAsks >= maxReviewAsks
        if reviewResolved, opens >= coffeeAfterOpens, coffeeCooldownElapsed {
            present(.buyCoffee); return
        }
    }

    private func present(_ p: AppPrompt) {
        shownThisSession = true
        d.set(Date().timeIntervalSince1970, forKey: kLastPrompt)
        if p == .rateApp { d.set(d.integer(forKey: kReviewAsks) + 1, forKey: kReviewAsks) }
        active = p
    }

    // MARK: - Actions (called from PromptCard)

    func confirmReview(open: (URL) -> Void) {
        d.set(true, forKey: kReviewDone)   // rated — never ask again
        active = nil
        open(AppLinks.writeReview)         // App Store review composer (always works)
    }

    /// "Not now" — the ask is already counted; the min-gap + ask cap pace any
    /// re-ask, so we don't mark it done (the user may rate later).
    func declineReview() { active = nil }

    func confirmCoffee(open: (URL) -> Void) {
        d.set(Date().timeIntervalSince1970, forKey: kCoffeeLastAt)
        active = nil
        open(AppLinks.coffee)
    }

    func declineCoffee() {
        d.set(Date().timeIntervalSince1970, forKey: kCoffeeLastAt)  // cooldown either way
        active = nil
    }

    // MARK: - Helpers

    private var lastPromptDate: Date? {
        let t = d.double(forKey: kLastPrompt)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    private func daysSince(_ date: Date) -> Double { -date.timeIntervalSinceNow / 86_400 }

    private var coffeeCooldownElapsed: Bool {
        let t = d.double(forKey: kCoffeeLastAt)
        guard t > 0 else { return true }
        return daysSince(Date(timeIntervalSince1970: t)) >= Double(coffeeCooldownDays)
    }
}
