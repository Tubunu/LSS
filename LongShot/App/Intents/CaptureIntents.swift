import AppIntents
import Foundation

struct StartCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "开始滚动长截图"
    static var description = IntentDescription("打开 LongShot 并唤起屏幕捕获选择器")
    static var openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        ScreenCaptureManager.shared.startCaptureSelection()
        return .result()
    }
}

struct StopCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "停止滚动截图"
    static var description = IntentDescription("停止当前屏幕捕获并进入长截图拼接")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        ScreenCaptureManager.shared.stopCapture()
        return .result()
    }
}
