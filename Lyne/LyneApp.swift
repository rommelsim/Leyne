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
        }
    }
}
