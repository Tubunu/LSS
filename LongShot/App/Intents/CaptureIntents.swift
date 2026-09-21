import AppIntents
import Foundation

public struct StartCaptureIntent: AppIntent {
    public static var title: LocalizedStringResource = "开始滚动长截图"
    public static var description = IntentDescription("打开 LongShot 并唤起屏幕捕获选择器")
    public static var openAppWhenRun: Bool = true

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        ScreenCaptureManager.shared.startCaptureSelection()
        return .result()
    }
}

public struct StopCaptureIntent: AppIntent {
    public static var title: LocalizedStringResource = "停止滚动截图"
    public static var description = IntentDescription("停止当前屏幕捕获并进入长截图拼接")

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        ScreenCaptureManager.shared.stopCapture()
        return .result()
    }
}
