import Foundation

struct CaptureDiagnosticsSnapshot: Equatable, Sendable {
    var receivedFrames = 0
    var validFrames = 0
    var invalidFrames = 0
    var selectedFrames = 0
    var width = 0
    var height = 0
    var lastTimestamp: Double?
    var backgroundFrameDelta = 0
    var backgroundDuration: TimeInterval = 0
}

final class CaptureDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private var value = CaptureDiagnosticsSnapshot()
    private var lastPublishedTimestamp = 0.0

    func reset() {
        lock.withLock {
            value = CaptureDiagnosticsSnapshot()
            lastPublishedTimestamp = 0
        }
    }

    func recordValidFrame(width: Int, height: Int, timestamp: Double) -> Bool {
        lock.withLock {
            value.receivedFrames += 1
            value.validFrames += 1
            value.width = width
            value.height = height
            value.lastTimestamp = timestamp

            guard timestamp - lastPublishedTimestamp >= 0.25 else { return false }
            lastPublishedTimestamp = timestamp
            return true
        }
    }

    func recordInvalidFrame() {
        lock.withLock {
            value.receivedFrames += 1
            value.invalidFrames += 1
        }
    }

    func recordSelectedFrame() {
        lock.withLock {
            value.selectedFrames += 1
        }
    }

    func recordBackgroundResult(frameDelta: Int, duration: TimeInterval) {
        lock.withLock {
            value.backgroundFrameDelta = max(0, frameDelta)
            value.backgroundDuration = max(0, duration)
        }
    }

    func snapshot() -> CaptureDiagnosticsSnapshot {
        lock.withLock { value }
    }
}
