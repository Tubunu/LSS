import SwiftUI

@main
struct LongShotApp: App {
    @StateObject private var captureManager = Phase0CaptureManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Phase0CaptureView(manager: captureManager)
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
