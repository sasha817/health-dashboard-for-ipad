import SwiftUI

@main
struct HealthForiPadApp: App {
    @State private var store = DashboardStore.shared
    @Environment(\.scenePhase) private var phase
    init() { BackgroundSync.register() }
    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environment(store)
        }
        .onChange(of: phase) { _, p in if p == .background { BackgroundSync.schedule() } }
    }
}
