import Foundation

@MainActor
final class WindowEventRelay {
    private var appActiveContinuations: [UUID: AsyncStream<Bool>.Continuation] = [:]
    private var windowKeyContinuations: [UUID: AsyncStream<Bool>.Continuation] = [:]
    private var focusedSlotContinuations: [UUID: AsyncStream<SurfaceSlot>.Continuation] = [:]
    private var chromeContinuations: [UUID: AsyncStream<WindowChromeState>.Continuation] = [:]

    func appActiveStream() -> AsyncStream<Bool> {
        let streamID = UUID()
        return AsyncStream { continuation in
            appActiveContinuations[streamID] = continuation
            continuation.onTermination = { @Sendable _ in
                Task { @MainActor [weak self] in
                    self?.appActiveContinuations.removeValue(forKey: streamID)
                }
            }
        }
    }

    func windowKeyStream() -> AsyncStream<Bool> {
        let streamID = UUID()
        return AsyncStream { continuation in
            windowKeyContinuations[streamID] = continuation
            continuation.onTermination = { @Sendable _ in
                Task { @MainActor [weak self] in
                    self?.windowKeyContinuations.removeValue(forKey: streamID)
                }
            }
        }
    }

    func focusedSurfaceSlotStream() -> AsyncStream<SurfaceSlot> {
        let streamID = UUID()
        return AsyncStream { continuation in
            focusedSlotContinuations[streamID] = continuation
            continuation.onTermination = { @Sendable _ in
                Task { @MainActor [weak self] in
                    self?.focusedSlotContinuations.removeValue(forKey: streamID)
                }
            }
        }
    }

    func windowChromeStream() -> AsyncStream<WindowChromeState> {
        let streamID = UUID()
        return AsyncStream { continuation in
            chromeContinuations[streamID] = continuation
            continuation.onTermination = { @Sendable _ in
                Task { @MainActor [weak self] in
                    self?.chromeContinuations.removeValue(forKey: streamID)
                }
            }
        }
    }

    func publishAppActive(_ isActive: Bool) {
        for continuation in appActiveContinuations.values {
            continuation.yield(isActive)
        }
    }

    func publishWindowKey(_ isKey: Bool) {
        for continuation in windowKeyContinuations.values {
            continuation.yield(isKey)
        }
    }

    func publishFocusedSurfaceSlot(_ slot: SurfaceSlot) {
        for continuation in focusedSlotContinuations.values {
            continuation.yield(slot)
        }
    }

    func publishWindowChrome(_ state: WindowChromeState) {
        for continuation in chromeContinuations.values {
            continuation.yield(state)
        }
    }

}
