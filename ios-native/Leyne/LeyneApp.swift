import SwiftUI
import CoreSpotlight
import UserNotifications

@main
struct LeyneApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var store = DataStore.shared
    @StateObject private var location = LocationManager.shared
    @UIApplicationDelegateAdaptor(LeyneAppDelegate.self) private var delegate

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
                }
                // Spotlight handoff — when a user taps a pinned-stop
                // result in iOS system search, iOS launches/foregrounds
                // Leyne with a CoreSpotlight activity carrying the stop
                // code. We translate that into the same open-stop path
                // the in-app search uses.
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    if let code = Spotlight.openedStopCode(from: activity) {
                        model.openFromSearch(stopCode: code)
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
        let userInfo = response.notification.request.content.userInfo
        NotificationCenter.default.post(
            name: .leyneOpenStopFromNotification,
            object: nil,
            userInfo: userInfo)
        completionHandler()
    }
}
