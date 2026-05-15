import AppKit
import ComposableArchitecture
import SwiftUI

struct AppWindowBridge: View {
    @Dependency(\.appControlClient) private var appControlClient
    @Dependency(\.windowClient) private var windowClient

    let topBarFrameInWindow: CGRect?
    let isCommandBarPresented: Bool
    let shouldRestoreCommandBarFocus: Bool
    let shortcutBindings: [ResolvedShortcutBinding]
    let dispatchShortcut: (CommandID) -> Void

    var body: some View {
        WindowActivityObserver(
            onWindowKeyChange: { isKey in
                windowClient.publishWindowKey(isKey)
            },
            onApplicationActiveChange: { isActive in
                windowClient.publishAppActive(isActive)
            },
            onKeyDownIntercept: handleKeyDownEvent(_:focusedSurfaceSlot:),
            handleWindowCloseRequest: handleWindowCloseRequest,
            onFocusedSurfaceSlotChange: { slot in
                windowClient.publishFocusedSurfaceSlot(slot)
            },
            onWindowChromeStateChange: { state in
                windowClient.publishWindowChrome(state)
            },
            topBarFrameInWindow: topBarFrameInWindow,
            isCommandBarPresented: isCommandBarPresented,
            shouldRestoreCommandBarFocus: shouldRestoreCommandBarFocus
        )
        .frame(width: 0, height: 0)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            windowClient.publishAppActive(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            windowClient.publishAppActive(false)
        }
    }

    private func handleWindowCloseRequest() -> Bool {
        appControlClient.requestApplicationQuit()
        return false
    }

    private func handleKeyDownEvent(
        _ event: NSEvent,
        focusedSurfaceSlot _: SurfaceSlot?
    ) -> KeyDownInterceptResult {
        guard event.type == .keyDown else {
            return .passThrough
        }

        if let command = matchedShortcutCommand(for: event) {
            dispatchShortcut(command)
            return .consume
        }

        return .passThrough
    }

    private func normalizedShortcutKey(from event: NSEvent) -> String? {
        guard let rawKey = event.charactersIgnoringModifiers else {
            return nil
        }

        let normalizedKey = ResolvedShortcutBinding.normalizeKey(rawKey)
        guard normalizedKey.count == 1 else {
            return nil
        }

        return normalizedKey
    }

    private func shortcutModifiers(from event: NSEvent) -> Set<ShortcutModifier> {
        let normalizedFlags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        var modifiers = Set<ShortcutModifier>()

        if normalizedFlags.contains(.command) {
            modifiers.insert(.command)
        }
        if normalizedFlags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if normalizedFlags.contains(.option) {
            modifiers.insert(.option)
        }
        if normalizedFlags.contains(.control) {
            modifiers.insert(.control)
        }

        return modifiers
    }

    private func matchedShortcutCommand(for event: NSEvent) -> CommandID? {
        guard let eventKey = normalizedShortcutKey(from: event) else {
            return nil
        }
        let eventModifiers = shortcutModifiers(from: event)
        return shortcutBindings.first(where: {
            $0.key == eventKey && $0.modifiers == eventModifiers
        })?.command
    }
}
