import SwiftUI

@main
struct LongShotApp: App {
    @StateObject private var captureManager = ScreenCaptureManager.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        SessionGarbageCollector.cleanupStaleSessions()
    }

    var body: some Scene {
        WindowGroup {
            HomeView(captureManager: captureManager)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                captureManager.appDidEnterBackground()
            case .active:
                captureManager.appDidBecomeActive()
            default:
                break
            }
        }
    }
}
