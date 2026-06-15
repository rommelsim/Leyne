import SwiftUI
import CoreSpotlight
import UserNotifications
import StoreKit
import FirebaseCore
import BackgroundTasks

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
                .environmentObject(PromptCenter.shared)
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
                        LeyneAppDelegate.scheduleAlertsRefresh()
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
        // Background app refresh — poll LTA train alerts opportunistically so a
        // newly-detected disruption can fire its local notification even if the
        // app hasn't been opened. Must register before launch completes.
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.alertsRefreshTaskID, using: nil
        ) { task in
            Self.handleAlertsRefresh(task as! BGAppRefreshTask)
        }
        return true
    }

    // MARK: - Background app refresh

    static let alertsRefreshTaskID = "com.leyne.Leyne.alertsRefresh"

    /// Request the next opportunistic refresh (~15 min out). iOS decides the
    /// actual timing from usage patterns, so this is best-effort, not a guarantee.
    static func scheduleAlertsRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: alertsRefreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Runs when iOS grants a refresh window: refresh alerts (which fires the
    /// new-disruption notification), reschedule the next pass, and report done.
    static func handleAlertsRefresh(_ task: BGAppRefreshTask) {
        scheduleAlertsRefresh()
        let work = Task { @MainActor in
            await DataStore.shared.refreshAlertsInBackground()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
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
        // signal — feed it to the prompt coordinator as a successful journey.
        Task { @MainActor in PromptCenter.shared.noteSuccessfulJourney() }
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
