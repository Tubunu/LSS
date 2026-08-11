import SwiftUI

@main
struct LongShotApp: App {
    @StateObject private var captureManager = ScreenCaptureManager()
    @Environment(\.scenePhase) private var scenePhase

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
