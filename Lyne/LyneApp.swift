import SwiftUI

@main
struct LyneApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var store = DataStore.shared
    @StateObject private var location = LocationManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(Feedback.shared)
                .environmentObject(store)
                .environmentObject(location)
                .preferredColorScheme(model.isDark ? .dark : .light)
                .task { await store.bootstrap() }
                // Gather UMP + ATT consent, then start the Mobile Ads SDK.
                // Runs once; deferred to here (scene active) so the ATT
                // prompt can actually display.
                .task { await AdConsent.gatherThenStart() }
        }
    }
}
