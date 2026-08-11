import Foundation

enum CaptureState: Equatable, Sendable {
    case idle
    case selectingContent
    case starting
    case capturing
    case stopping
    case completed
    case failed(message: String)

    var title: String {
        switch self {
        case .idle:
            "准备就绪"
        case .selectingContent:
            "等待选择整个屏幕"
        case .starting:
            "正在启动捕获"
        case .capturing:
            "正在捕获"
        case .stopping:
            "正在停止"
        case .completed:
            "捕获已完成"
        case let .failed(message):
            message
        }
    }

    var isBusy: Bool {
        switch self {
        case .selectingContent, .starting, .capturing, .stopping:
            true
        case .idle, .completed, .failed:
            false
        }
    }

    var canStart: Bool {
        switch self {
        case .idle, .completed, .failed:
            true
        case .selectingContent, .starting, .capturing, .stopping:
            false
        }
    }

    var canStop: Bool {
        switch self {
        case .starting, .capturing:
            true
        case .idle, .selectingContent, .stopping, .completed, .failed:
            false
        }
    }
}
