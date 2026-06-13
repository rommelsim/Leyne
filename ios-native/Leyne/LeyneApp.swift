import SwiftUI
import CoreSpotlight
import UserNotifications
import StoreKit
import FirebaseCore

@main
struct LeyneApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var store = DataStore.shared
    @StateObject private var location = LocationManager.shared
    @UIApplicationDelegateAdaptor(LeyneAppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Pin the running marketing version into the model before the first
        // view renders, so the What's New gate is stable from the start.
        let v = (Bundle.main.infoDictionary?["CFBundleShortVersionString"]
                 as? String) ?? ""
        if !v.isEmpty { AppModel.bootVersion = v }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(Feedback.shared)
                .environmentObject(store)
                .environmentObject(location)
                .preferredColorScheme(model.themeMode.preferredColorScheme)
                .task {
                    // Record the version once the model exists, then
                    // bootstrap reference data.
                    if let v = AppModel.bootVersion { model.setCurrentVersion(v) }
                    await store.bootstrap()
                    // Reference data is now loaded, so favourite-service stop
                    // names / destinations resolve — re-publish the snapshot
                    // the Favourite Service widget reads.
                    model.republishFavServicesToWidget()
                }
                // Spotlight handoff — when a user taps a pinned-stop
                // result in iOS system search, iOS launches/foregrounds
                // Leyne with a CoreSpotlight activity carrying the stop
                // code. We translate that into the same open-stop path
                // the in-app search uses.
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    // Spotlight tap → opening a specific stop; skip App Open.
                    AppOpenAdManager.shared.suppressNextPresentation()
                    if let code = Spotlight.openedStopCode(from: activity) {
                        model.openFromSearch(stopCode: code)
                    }
                }
                // App Open ad: present on WARM foreground only. scenePhase steps
                // through .inactive between .background and .active, so we can't
                // rely on the previous phase being .background on return — we
                // track backgrounding explicitly (noteBackgrounded). Cold launch
                // never hits .background, so it never shows there. The brief delay
                // lets a notification / widget / Spotlight handler set the
                // suppression flag before we decide.
                .onChange(of: scenePhase) { _, new in
                    switch new {
                    case .background:
                        AppOpenAdManager.shared.noteBackgrounded()
                    case .active:
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(500))
                            AppOpenAdManager.shared
                                .showIfReturningToForeground(model: model)
                        }
                    default:
                        break
                    }
                }
        }
    }
}

/// NotificationCenter event name posted whenever the user taps an arrival
/// or alight notification — RootView subscribes and drives the
/// drill-down via AppModel.open.
extension Notification.Name {
    static let leyneOpenStopFromNotification =
        Notification.Name("LeyneOpenStopFromNotification")
}

// MARK: - App delegate
//
// Owns the UNUserNotificationCenter delegate so arrival alerts present as a
// banner + sound when the app is in the foreground (otherwise iOS silences
// them by default). Background / locked delivery uses the system's normal
// notification chrome and needs no delegate wiring.
final class LeyneAppDelegate: NSObject, UIApplicationDelegate,
                              UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions:
                     [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Firebase Analytics + Crashlytics. Guarded on the config file so a build
        // without GoogleService-Info.plist (the file is git-ignored — forks / CI)
        // degrades to no-op analytics instead of crashing at launch. Crashlytics
        // starts automatically once the app is configured.
        if Bundle.main.url(forResource: "GoogleService-Info",
                           withExtension: "plist") != nil {
            FirebaseApp.configure()
        }
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler:
                                @escaping () -> Void) {
        // Tap → broadcast the stopCode + busNo so RootView can drill into
        // DetailView for that bus. Two notification kinds:
        //   • "arrival" — userInfo carries stopCode + busNo directly
        //   • "alight"  — userInfo carries only busNo; the stopCode comes
        //                 from the persisted ActiveAlight on AppModel
        // Tap is taking the user to a stop/bus — skip the App Open ad on the
        // foreground this triggers (hop to the main actor for the manager).
        Task { @MainActor in AppOpenAdManager.shared.suppressNextPresentation() }
        // A useful-notification tap is the strongest "this app delivered value"
        // signal — count it toward the App Store ratings prompt (fires once, on
        // the 2nd such moment).
        Task { @MainActor in ReviewPrompt.recordValueMomentAndMaybeAsk() }
        // A notification tap is a strong value signal — record it for retention
        // analysis. categoryIdentifier distinguishes arrival vs alight when set.
        AnalyticsService.log(.notificationTapped(
            kind: response.notification.request.content.categoryIdentifier))
        let userInfo = response.notification.request.content.userInfo
        NotificationCenter.default.post(
            name: .leyneOpenStopFromNotification,
            object: nil,
            userInfo: userInfo)
        completionHandler()
    }
}

/// ReviewPrompt — asks for an App Store rating at the moment of proven value.
///
/// The strongest in-app signal that Leyne delivered value is the user TAPPING a
/// useful arrival/alight notification. We count those "value moments" and, on
/// the 2nd one, fire Apple's `requestReview` flow once per install. Asking at a
/// high-sentiment moment maximises 4–5★ responses. StoreKit itself caps the
/// prompt to ~3×/365 days, so this never nags; our guard just ensures one
/// high-quality ask. Mirrors the Android `ReviewPrompt` (review_prompt.dart).
enum ReviewPrompt {
    private static let valueMomentsKey = "leyne.review.valueMoments"
    private static let requestedKey = "leyne.review.requested"
    /// Ask on the Nth qualifying value moment — not a cold first-tap ask.
    private static let askOnMoment = 2

    @MainActor
    static func recordValueMomentAndMaybeAsk() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: requestedKey) { return }

        let moments = defaults.integer(forKey: valueMomentsKey) + 1
        defaults.set(moments, forKey: valueMomentsKey)
        guard moments >= askOnMoment else { return }

        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive })
            as? UIWindowScene else { return }

        // Let the user land on their bus first — the prompt arrives a beat
        // after the value, not on top of the navigation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if #available(iOS 16.0, *) {
                AppStore.requestReview(in: scene)
            } else {
                SKStoreReviewController.requestReview(in: scene)
            }
        }
        // Mark asked regardless of whether StoreKit chose to show the sheet —
        // we gave it our one high-quality opportunity.
        defaults.set(true, forKey: requestedKey)
    }
}
