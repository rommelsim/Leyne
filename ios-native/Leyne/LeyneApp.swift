import SwiftUI
import CoreSpotlight

@main
struct LeyneApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var store = DataStore.shared
    @StateObject private var location = LocationManager.shared

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
