import AppKit
import Combine
import Darwin
import Foundation
import GhosttyTerminal
import os

enum TerminalSessionID: Hashable {
    case agent(UUID)
    case workspace(String)
}

struct TerminalRegistryShutdownSummary: Equatable {
    var sessionCount: Int
    var forcedKillCount: Int
    var timedOutCount: Int
}

struct TerminalSessionShutdownSummary: Equatable {
    var didForceKill: Bool
    var didTimeout: Bool
}

@MainActor
private final class TerminalSurfaceDelegateBridge:
    TerminalSurfaceViewDelegate,
    TerminalSurfaceTitleDelegate,
    TerminalSurfaceGridResizeDelegate,
    TerminalSurfaceFocusDelegate,
    TerminalSurfaceCloseDelegate,
    TerminalSurfaceCommandFinishedDelegate,
    TerminalSurfaceDesktopNotificationDelegate
{
    private weak var terminalState: TerminalViewState?
    private let onTitleChange: (String) -> Void
    private let onDesktopNotification: (String, String) -> Void

    init(
        terminalState: TerminalViewState,
        onTitleChange: @escaping (String) -> Void,
        onDesktopNotification: @escaping (String, String) -> Void
    ) {
        self.terminalState = terminalState
        self.onTitleChange = onTitleChange
        self.onDesktopNotification = onDesktopNotification
    }

    func terminalDidChangeTitle(_ title: String) {
        terminalState?.terminalDidChangeTitle(title)
        onTitleChange(title)
    }

    func terminalDidResize(_ size: TerminalGridMetrics) {
        terminalState?.terminalDidResize(size)
    }

    func terminalDidChangeFocus(_ focused: Bool) {
        terminalState?.terminalDidChangeFocus(focused)
    }

    func terminalDidClose(processAlive: Bool) {
        terminalState?.terminalDidClose(processAlive: processAlive)
    }

    func terminalDidFinishCommand(exitCode: Int?, durationNanos: UInt64) {
        terminalState?.terminalDidFinishCommand(exitCode: exitCode, durationNanos: durationNanos)
    }

    func terminalDidRequestDesktopNotification(title: String, body: String) {
        onDesktopNotification(title, body)
    }
}

@MainActor
final class TerminalSessionRegistry {
    private var controllers: [TerminalSessionID: LocalShellTerminalSessionController] = [:]

    func acquire(
        id: TerminalSessionID,
        makeController: () -> LocalShellTerminalSessionController
    ) -> LocalShellTerminalSessionController {
        if let existing = controllers[id] {
            return existing
        }
        let controller = makeController()
        controllers[id] = controller
        return controller
    }

    func controller(for id: TerminalSessionID) -> LocalShellTerminalSessionController? {
        controllers[id]
    }

    func setAttached(id: TerminalSessionID, attached: Bool) {
        guard let controller = controllers[id] else { return }
        if attached {
            controller.markSurfaceActive()
        } else {
            controller.markSurfaceInactive()
        }
    }

    func release(id: TerminalSessionID) {
        controllers.removeValue(forKey: id)?.dispose()
    }

    func prune(keepingIDs: Set<TerminalSessionID>) {
        for id in Array(controllers.keys) where !keepingIDs.contains(id) {
            controllers.removeValue(forKey: id)?.dispose()
        }
    }

    func shutdownAll(
        graceTimeout: TimeInterval,
        forceKillTimeout: TimeInterval
    ) async -> TerminalRegistryShutdownSummary {
        let activeControllers = Array(controllers.values)
        let summaries = await withTaskGroup(
            of: TerminalSessionShutdownSummary.self,
            returning: [TerminalSessionShutdownSummary].self
        ) { group in
            for controller in activeControllers {
                group.addTask { @MainActor in
                    await controller.shutdown(
                        graceTimeout: graceTimeout,
                        forceKillTimeout: forceKillTimeout
                    )
                }
            }

            var collected: [TerminalSessionShutdownSummary] = []
            collected.reserveCapacity(activeControllers.count)
            for await summary in group {
                collected.append(summary)
            }
            return collected
        }

        let forcedKillCount = summaries.reduce(into: 0) { partialResult, summary in
            if summary.didForceKill {
                partialResult += 1
            }
        }
        let timedOutCount = summaries.reduce(into: 0) { partialResult, summary in
            if summary.didTimeout {
                partialResult += 1
            }
        }
        controllers.removeAll()
        return TerminalRegistryShutdownSummary(
            sessionCount: activeControllers.count,
            forcedKillCount: forcedKillCount,
            timedOutCount: timedOutCount
        )
    }
}

@MainActor
final class LocalShellTerminalSessionController: ObservableObject {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "dev.breuer.spurwechsel",
        category: "TerminalSwitchPerf"
    )
    private static func agentStatusTrace(_ message: String) {
        #if DEBUG
        print(message)
        #else
        logger.debug("\(message, privacy: .public)")
        #endif
    }

    struct LaunchPlan {
        let workingDirectory: String
        let startupCommand: String?
    }

    let sessionID: UUID
    let startupTitle: String
    let launchPlan: LaunchPlan
    let terminalTheme: TerminalTheme

    @Published private(set) var terminalTitle: String
    @Published private(set) var isSurfaceActive = false

    let terminalState: TerminalViewState
    let terminalView: TerminalView
    let retainedSurface: RetainedHostedSurface<TerminalView>
    private var terminalDelegateBridge: TerminalSurfaceDelegateBridge?

    private let onTitleChange: (String) -> Void
    private let onProcessTerminated: (Int32?) -> Void
    private let onDesktopNotification: (String, String) -> Void
    private var hasProcessTerminated = false
    private var didEmitProcessTermination = false
    private var isDisposed = false
    private var shutdownTask: Task<TerminalSessionShutdownSummary, Never>?

    init(
        sessionID: UUID,
        startupTitle: String,
        launchPlan: LaunchPlan,
        terminalTheme: TerminalTheme = ThemeSet.default.terminalTheme,
        startProcess: Bool = true,
        onTitleChange: @escaping (String) -> Void,
        onProcessTerminated: @escaping (Int32?) -> Void,
        onDesktopNotification: @escaping (String, String) -> Void = { _, _ in }
    ) {
        self.sessionID = sessionID
        self.startupTitle = startupTitle
        self.launchPlan = launchPlan
        self.terminalTheme = terminalTheme
        self.terminalTitle = startupTitle
        self.onTitleChange = onTitleChange
        self.onProcessTerminated = onProcessTerminated
        self.onDesktopNotification = onDesktopNotification

        let configuration = Self.makeTerminalConfiguration(
            startupCommand: startProcess ? launchPlan.startupCommand : nil
        )
        terminalState = TerminalViewState(
            theme: terminalTheme,
            terminalConfiguration: configuration
        )
        terminalState.configuration = TerminalSurfaceOptions(
            backend: .exec,
            fontSize: 14,
            workingDirectory: launchPlan.workingDirectory,
            context: .window
        )
        let terminalView = TerminalView(frame: .zero)
        terminalView.controller = terminalState.controller
        terminalView.configuration = terminalState.configuration
        self.terminalView = terminalView
        retainedSurface = RetainedHostedSurface(view: terminalView)
        let terminalDelegateBridge = TerminalSurfaceDelegateBridge(
            terminalState: terminalState,
            onTitleChange: { [weak self] title in
                self?.handleTitleChange(title)
            },
            onDesktopNotification: { [weak self] title, body in
                self?.handleDesktopNotification(title: title, body: body)
            }
        )
        self.terminalDelegateBridge = terminalDelegateBridge
        terminalView.delegate = terminalDelegateBridge
        Self.agentStatusTrace("[agent-status] delegate attached session=\(sessionID.uuidString) title=\(startupTitle)")

        terminalState.onClose = { [weak self] processAlive in
            guard let self else { return }
            if processAlive {
                return
            }
            self.emitProcessTerminationOnce(exitCode: nil)
        }
        terminalState.onCommandFinished = { [weak self] exitCode, _ in
            guard let self else { return }
            self.emitProcessTerminationOnce(exitCode: exitCode.map(Int32.init))
        }

    }

    private func handleTitleChange(_ title: String) {
        terminalTitle = title
        onTitleChange(title)
    }

    private func handleDesktopNotification(title: String, body: String) {
        let compactBody = body.replacingOccurrences(of: "\n", with: "\\n")
        let bodyPreview = compactBody.count > 240 ? String(compactBody.prefix(240)) + "..." : compactBody
        Self.agentStatusTrace("[agent-status] desktop notification session=\(self.sessionID.uuidString) title=\(title) bodyPreview=\(bodyPreview)")
        onDesktopNotification(title, body)
    }

    var debugLabel: String {
        "\(startupTitle)#\(String(sessionID.uuidString.prefix(8)))"
    }

    func markSurfaceInactive() {
        isSurfaceActive = false
        Self.logger.debug(
            "[switch-perf] surface inactive controller=\(self.debugLabel, privacy: .public)"
        )
    }

    func markSurfaceActive() {
        isSurfaceActive = true
        Self.logger.debug(
            "[switch-perf] surface active controller=\(self.debugLabel, privacy: .public)"
        )
    }

    func sendText(_ text: String) {
        guard !text.isEmpty else {
            return
        }
        terminalView.sendText(text)
    }

    func dispose() {
        guard !isDisposed else {
            return
        }
        isDisposed = true
        shutdownTask?.cancel()
        terminalView.requestSurfaceClose()
        terminalView.freeSurface()
    }

    func shutdown(
        graceTimeout: TimeInterval,
        forceKillTimeout: TimeInterval
    ) async -> TerminalSessionShutdownSummary {
        if let shutdownTask {
            return await shutdownTask.value
        }

        let task = Task { @MainActor [weak self] in
            guard let self else {
                return TerminalSessionShutdownSummary(
                    didForceKill: false,
                    didTimeout: false
                )
            }
            return await self.performShutdown(
                graceTimeout: graceTimeout,
                forceKillTimeout: forceKillTimeout
            )
        }
        shutdownTask = task
        let summary = await task.value
        shutdownTask = nil
        return summary
    }

    static func makeCommandLaunchPlan(command: String, workingDirectory: String) -> LaunchPlan {
        let wrappedCommand = makeLoginShellCommand(command: command)
        return LaunchPlan(
            workingDirectory: workingDirectory,
            startupCommand: wrappedCommand
        )
    }

    static func makeDefaultShellLaunchPlan(workingDirectory: String) -> LaunchPlan {
        LaunchPlan(
            workingDirectory: workingDirectory,
            startupCommand: nil
        )
    }

    private static func makeTerminalConfiguration(startupCommand: String?) -> TerminalConfiguration {
        TerminalConfiguration { builder in
            builder.withFontSize(14)
            builder.withCursorStyle(.block)
            builder.withCursorStyleBlink(true)
            builder.withBackgroundOpacity(1)
            builder.withBackgroundBlur(0)
            if let startupCommand {
                builder.withCustom("command", startupCommand)
            }
        }
    }

    private static func makeLoginShellCommand(command: String) -> String {
        let shellPath = resolveUserShellPath()
        return "\(shellQuote(shellPath)) -ilc \(shellQuote(command))"
    }

    private static func resolveUserShellPath() -> String {
        if let shellCString = getpwuid(getuid())?.pointee.pw_shell {
            let shell = String(cString: shellCString).trimmingCharacters(in: .whitespacesAndNewlines)
            if !shell.isEmpty {
                return shell
            }
        }

        if let shell = ProcessInfo.processInfo.environment["SHELL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !shell.isEmpty {
            return shell
        }

        return "/bin/zsh"
    }

    private static func shellQuote(_ raw: String) -> String {
        "'\(raw.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private func performShutdown(
        graceTimeout: TimeInterval,
        forceKillTimeout: TimeInterval
    ) async -> TerminalSessionShutdownSummary {
        if isDisposed {
            return TerminalSessionShutdownSummary(didForceKill: false, didTimeout: false)
        }

        if hasProcessTerminated || terminalView.surfaceProcessExited() {
            terminalView.freeSurface()
            isDisposed = true
            return TerminalSessionShutdownSummary(didForceKill: false, didTimeout: false)
        }

        terminalView.requestSurfaceClose()
        let didExitDuringGrace = await waitForProcessExit(timeout: graceTimeout)
        if didExitDuringGrace {
            terminalView.freeSurface()
            isDisposed = true
            return TerminalSessionShutdownSummary(didForceKill: false, didTimeout: false)
        }

        terminalView.freeSurface()
        let didExitAfterForce = await waitForProcessExit(timeout: forceKillTimeout)
        isDisposed = true
        return TerminalSessionShutdownSummary(
            didForceKill: true,
            didTimeout: !didExitAfterForce
        )
    }

    private func waitForProcessExit(timeout: TimeInterval) async -> Bool {
        let clampedTimeout = max(timeout, 0)
        let deadline = Date().timeIntervalSinceReferenceDate + clampedTimeout

        while true {
            if hasProcessTerminated || terminalView.surfaceProcessExited() {
                if !hasProcessTerminated {
                    emitProcessTerminationOnce(exitCode: nil)
                }
                return true
            }
            if Date().timeIntervalSinceReferenceDate >= deadline {
                return false
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func emitProcessTerminationOnce(exitCode: Int32?) {
        guard !didEmitProcessTermination else {
            return
        }
        didEmitProcessTermination = true
        hasProcessTerminated = true
        onProcessTerminated(exitCode)
    }
}

typealias AgentTerminalSessionController = LocalShellTerminalSessionController
