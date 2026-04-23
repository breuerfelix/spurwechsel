import Darwin
import Foundation

struct VSCodeServerShutdownSummary: Equatable {
    var didForceKill: Bool
    var didTimeout: Bool
}

final class VSCodeServerRuntime {
    enum FailureReason: Equatable {
        case cliMissing
        case portInUse
        case startupFailed
        case authRequired
        case urlNotFound
    }

    enum Event {
        case starting(workspaceID: String, workspacePath: String, serverURL: URL)
        case outputLine(String)
        case authRequired(String)
        case serverReady(URL)
        case stopped
        case failed(reason: FailureReason, message: String, lastOutputLine: String?)
    }

    var onEvent: ((Event) -> Void)?

    private let queue = DispatchQueue(
        label: "dev.breuer.spurwechsel.vscode-server",
        qos: .userInitiated
    )
    private static let serverURLRegex = try! NSRegularExpression(
        pattern: #"https?://[^\s"']+"#
    )

    private var process: Process?
    private var currentProcessID: UUID?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var requestedStop = false
    private var hasResolvedServerURL = false
    private var expectedServerPort: Int?
    private var sawAuthPrompt = false
    private var sawOutput = false
    private var lastOutputLine: String?
    private var shutdownWaiters: [CheckedContinuation<VSCodeServerShutdownSummary, Never>] = []
    private var shutdownInFlight = false
    private var shutdownDidForceKill = false
    private var forceKillWorkItem: DispatchWorkItem?
    private var shutdownTimeoutWorkItem: DispatchWorkItem?

    func start(workspaceID: String, workspacePath: String, port: Int) {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            self.stopRunningProcess(emitStopped: false)
            let resolvedPort = Self.normalizedServerPort(port)
            guard Self.isLoopbackPortAvailable(port: resolvedPort) else {
                self.emit(.failed(
                    reason: .portInUse,
                    message: "code-server cannot start because port \(resolvedPort) is already in use on 127.0.0.1.",
                    lastOutputLine: nil
                ))
                return
            }

            let serverURL = URL(string: "http://127.0.0.1:\(resolvedPort)/")!
            let userDataDirectory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".vscode", isDirectory: true)
                .path
            let extensionsDirectory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".vscode/extensions", isDirectory: true)
                .path
            let shellPath = Self.resolveUserShellPath()
            let launchCommand = Self.makeCodeServerLaunchCommand(
                userDataDirectory: userDataDirectory,
                extensionsDirectory: extensionsDirectory,
                port: resolvedPort
            )

            let process = Process()
            let processID = UUID()
            process.executableURL = URL(fileURLWithPath: shellPath)
            process.arguments = [
                "-ilc",
                launchCommand
            ]
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            process.standardInput = Pipe()
            var environment = ProcessInfo.processInfo.environment
            environment["EXTENSIONS_GALLERY"] = #"{"serviceUrl": "https://marketplace.visualstudio.com/_apis/public/gallery", "itemUrl": "https://marketplace.visualstudio.com/items"}"#
            process.environment = environment

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            self.process = process
            self.currentProcessID = processID
            self.stdoutPipe = stdoutPipe
            self.stderrPipe = stderrPipe
            self.stdoutBuffer.removeAll(keepingCapacity: true)
            self.stderrBuffer.removeAll(keepingCapacity: true)
            self.requestedStop = false
            self.hasResolvedServerURL = false
            self.expectedServerPort = resolvedPort
            self.sawAuthPrompt = false
            self.sawOutput = false
            self.lastOutputLine = nil

            stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                self?.handlePipeData(handle.availableData, fromStdErr: false, processID: processID)
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                self?.handlePipeData(handle.availableData, fromStdErr: true, processID: processID)
            }
            process.terminationHandler = { [weak self] terminatedProcess in
                self?.handleTermination(status: terminatedProcess.terminationStatus, processID: processID)
            }

            self.emit(.starting(workspaceID: workspaceID, workspacePath: workspacePath, serverURL: serverURL))

            do {
                try process.run()
                self.scheduleReadinessProbe(
                    serverURL: serverURL,
                    processID: processID,
                    attemptsRemaining: 40
                )
            } catch {
                self.cleanupAfterExit()
                if Self.looksLikeAddressInUse(error.localizedDescription) {
                    self.emit(.failed(
                        reason: .portInUse,
                        message: "code-server cannot start because port \(resolvedPort) is already in use on 127.0.0.1.",
                        lastOutputLine: self.lastOutputLine
                    ))
                    return
                }
                self.emit(.failed(
                    reason: .startupFailed,
                    message: "Failed to start code-server process: \(error.localizedDescription)",
                    lastOutputLine: self.lastOutputLine
                ))
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            self.stopRunningProcess(emitStopped: true)
        }
    }

    func shutdown(
        graceTimeout: TimeInterval,
        forceKillTimeout: TimeInterval
    ) async -> VSCodeServerShutdownSummary {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: VSCodeServerShutdownSummary(
                        didForceKill: false,
                        didTimeout: false
                    ))
                    return
                }

                self.shutdownWaiters.append(continuation)
                guard !self.shutdownInFlight else {
                    return
                }
                self.shutdownInFlight = true
                self.shutdownDidForceKill = false

                guard let process = self.process else {
                    self.resolveShutdownWaiters(didTimeout: false)
                    return
                }

                self.requestedStop = true
                if process.isRunning {
                    process.terminate()
                    let processID = self.currentProcessID
                    self.scheduleForceKill(processID: processID, after: graceTimeout)
                    self.scheduleShutdownTimeout(
                        processID: processID,
                        after: graceTimeout + forceKillTimeout
                    )
                } else {
                    self.cleanupAfterExit()
                    self.emit(.stopped)
                    self.resolveShutdownWaiters(didTimeout: false)
                }
            }
        }
    }

    private func stopRunningProcess(emitStopped: Bool) {
        guard let process else {
            if emitStopped {
                emit(.stopped)
            }
            resolveShutdownWaiters(didTimeout: false)
            return
        }

        requestedStop = requestedStop || emitStopped

        if process.isRunning {
            process.terminate()
        } else {
            cleanupAfterExit()
            if requestedStop {
                requestedStop = false
                emit(.stopped)
            }
            resolveShutdownWaiters(didTimeout: false)
        }
    }

    private func handlePipeData(_ data: Data, fromStdErr: Bool, processID: UUID) {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            guard self.currentProcessID == processID else {
                return
            }

            guard !data.isEmpty else {
                return
            }

            if fromStdErr {
                self.stderrBuffer.append(data)
                self.drainLines(from: &self.stderrBuffer)
            } else {
                self.stdoutBuffer.append(data)
                self.drainLines(from: &self.stdoutBuffer)
            }
        }
    }

    private func drainLines(from buffer: inout Data) {
        while let lineBreakIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[..<lineBreakIndex]
            buffer.removeSubrange(...lineBreakIndex)

            guard var line = String(data: lineData, encoding: .utf8) else {
                continue
            }

            if line.hasSuffix("\r") {
                line.removeLast()
            }

            processOutputLine(line)
        }
    }

    private func processOutputLine(_ rawLine: String) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else {
            return
        }

        sawOutput = true
        lastOutputLine = line
        emit(.outputLine(line))

        if !hasResolvedServerURL,
           let serverURL = Self.extractServerURL(from: line),
           serverURL.port == expectedServerPort {
            hasResolvedServerURL = true
            emit(.serverReady(serverURL))
            return
        }

        if !hasResolvedServerURL, Self.looksLikeAuthPrompt(line) {
            sawAuthPrompt = true
            emit(.authRequired(line))
        }
    }

    private func handleTermination(status: Int32, processID: UUID) {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            guard self.currentProcessID == processID else {
                return
            }

            let requestedStop = self.requestedStop
            let hadTunnelURL = self.hasResolvedServerURL
            let hadAuthPrompt = self.sawAuthPrompt
            let sawOutput = self.sawOutput
            let lastOutputLine = self.lastOutputLine
            self.cleanupAfterExit()

            if requestedStop {
                self.requestedStop = false
                self.resolveShutdownWaiters(didTimeout: false)
                self.emit(.stopped)
                return
            }

            if hadTunnelURL {
                self.emit(.failed(
                    reason: .startupFailed,
                    message: "code-server process exited unexpectedly (code \(status)).",
                    lastOutputLine: lastOutputLine
                ))
                return
            }

            if hadAuthPrompt {
                self.emit(.failed(
                    reason: .authRequired,
                    message: "code-server requires authentication before URL is available.",
                    lastOutputLine: lastOutputLine
                ))
                return
            }

            if status == 0 {
                self.emit(.failed(
                    reason: .urlNotFound,
                    message: "code-server started but local URL was not ready in time.",
                    lastOutputLine: lastOutputLine
                ))
                return
            }
            if status == 127 || Self.looksLikeCodeServerMissing(lastOutputLine) {
                self.emit(.failed(
                    reason: .cliMissing,
                    message: "code-server not found in shell PATH.",
                    lastOutputLine: lastOutputLine
                ))
                return
            }

            let message: String
            if let lastOutputLine, Self.looksLikeAddressInUse(lastOutputLine) {
                self.emit(.failed(
                    reason: .portInUse,
                    message: "code-server cannot start because port \(self.expectedServerPort ?? CodeServerConfig.defaultPort) is already in use on 127.0.0.1.",
                    lastOutputLine: lastOutputLine
                ))
                return
            }
            if sawOutput {
                message = "code-server exited before URL was ready (code \(status))."
            } else {
                message = "code-server process failed to start."
            }
            self.emit(.failed(
                reason: .startupFailed,
                message: message,
                lastOutputLine: lastOutputLine
            ))
        }
    }

    private func cleanupAfterExit() {
        forceKillWorkItem?.cancel()
        forceKillWorkItem = nil
        shutdownTimeoutWorkItem?.cancel()
        shutdownTimeoutWorkItem = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe = nil
        process?.terminationHandler = nil
        process = nil
        currentProcessID = nil
        stdoutBuffer.removeAll(keepingCapacity: true)
        stderrBuffer.removeAll(keepingCapacity: true)
        hasResolvedServerURL = false
        expectedServerPort = nil
        sawAuthPrompt = false
        sawOutput = false
        lastOutputLine = nil
    }

    private func scheduleForceKill(processID: UUID?, after timeout: TimeInterval) {
        forceKillWorkItem?.cancel()
        let clamped = max(timeout, 0)
        let workItem = DispatchWorkItem { [weak self] in
            self?.forceKillIfStillRunning(processID: processID)
        }
        forceKillWorkItem = workItem
        queue.asyncAfter(deadline: .now() + clamped, execute: workItem)
    }

    private func scheduleShutdownTimeout(processID: UUID?, after timeout: TimeInterval) {
        shutdownTimeoutWorkItem?.cancel()
        let clamped = max(timeout, 0)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            guard self.shutdownInFlight else {
                return
            }
            if let processID, self.currentProcessID != processID {
                return
            }
            self.resolveShutdownWaiters(didTimeout: true)
        }
        shutdownTimeoutWorkItem = workItem
        queue.asyncAfter(deadline: .now() + clamped, execute: workItem)
    }

    private func forceKillIfStillRunning(processID: UUID?) {
        guard shutdownInFlight else {
            return
        }
        if let processID, currentProcessID != processID {
            return
        }
        guard let process, process.isRunning else {
            return
        }

        shutdownDidForceKill = true
        let pid = process.processIdentifier
        if pid > 0 {
            _ = Darwin.kill(pid_t(pid), SIGKILL)
        } else {
            process.terminate()
        }
    }

    private func resolveShutdownWaiters(didTimeout: Bool) {
        guard shutdownInFlight else {
            return
        }
        shutdownInFlight = false
        forceKillWorkItem?.cancel()
        forceKillWorkItem = nil
        shutdownTimeoutWorkItem?.cancel()
        shutdownTimeoutWorkItem = nil

        let summary = VSCodeServerShutdownSummary(
            didForceKill: shutdownDidForceKill,
            didTimeout: didTimeout
        )
        shutdownDidForceKill = false

        let waiters = shutdownWaiters
        shutdownWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: summary)
        }
    }

    private func emit(_ event: Event) {
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(event)
        }
    }

    private static func makeCodeServerLaunchCommand(
        userDataDirectory: String,
        extensionsDirectory: String,
        port: Int
    ) -> String {
        let bindAddress = "127.0.0.1:\(port)"
        return [
            "exec",
            "code-server",
            "--auth", "none",
            "--disable-workspace-trust",
            "--disable-getting-started-override",
            "--user-data-dir", shellQuote(userDataDirectory),
            "--extensions-dir", shellQuote(extensionsDirectory),
            "--bind-addr", shellQuote(bindAddress)
        ].joined(separator: " ")
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

    private static func extractServerURL(from line: String) -> URL? {
        let lineRange = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = serverURLRegex.firstMatch(in: line, options: [], range: lineRange),
              let matchRange = Range(match.range, in: line)
        else {
            return nil
        }
        return URL(string: String(line[matchRange]))
    }

    private func scheduleReadinessProbe(
        serverURL: URL,
        processID: UUID,
        attemptsRemaining: Int
    ) {
        guard attemptsRemaining > 0 else {
            return
        }

        queue.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else {
                return
            }
            guard self.currentProcessID == processID else {
                return
            }
            guard self.process?.isRunning == true else {
                return
            }
            guard !self.hasResolvedServerURL else {
                return
            }

            let healthURL = serverURL.appendingPathComponent("healthz")
            var request = URLRequest(url: healthURL)
            request.timeoutInterval = 0.9
            request.cachePolicy = .reloadIgnoringLocalCacheData

            URLSession.shared.dataTask(with: request) { [weak self] _, response, _ in
                guard let self else {
                    return
                }
                self.queue.async {
                    guard self.currentProcessID == processID else {
                        return
                    }
                    if let httpResponse = response as? HTTPURLResponse,
                       (200 ..< 400).contains(httpResponse.statusCode),
                       !self.hasResolvedServerURL {
                        self.hasResolvedServerURL = true
                        self.emit(.serverReady(serverURL))
                    } else {
                        self.scheduleReadinessProbe(
                            serverURL: serverURL,
                            processID: processID,
                            attemptsRemaining: attemptsRemaining - 1
                        )
                    }
                }
            }.resume()
        }
    }

    private static func looksLikeAuthPrompt(_ line: String) -> Bool {
        let normalized = line.lowercased()
        return normalized.contains("sign in")
            || normalized.contains("authenticate")
            || normalized.contains("device code")
            || normalized.contains("login")
            || normalized.contains("auth")
    }

    private static func normalizedServerPort(_ port: Int) -> Int {
        guard (1 ... 65535).contains(port) else {
            return CodeServerConfig.defaultPort
        }
        return port
    }

    private static func looksLikeAddressInUse(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("eaddrinuse")
            || normalized.contains("address already in use")
            || normalized.contains("already in use")
    }

    private static func looksLikeCodeServerMissing(_ message: String?) -> Bool {
        guard let message else {
            return false
        }
        let normalized = message.lowercased()
        return normalized.contains("command not found")
            && normalized.contains("code-server")
    }

    private static func isLoopbackPortAvailable(port: Int) -> Bool {
        let socketFD = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        if socketFD < 0 {
            return false
        }
        defer { Darwin.close(socketFD) }

        var reuseAddress: Int32 = 1
        _ = withUnsafePointer(to: &reuseAddress) { pointer in
            Darwin.setsockopt(
                socketFD,
                SOL_SOCKET,
                SO_REUSEADDR,
                pointer,
                socklen_t(MemoryLayout<Int32>.size)
            )
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr = in_addr(s_addr: in_addr_t(UInt32(INADDR_LOOPBACK).bigEndian))

        let bindResult = withUnsafePointer(to: &address) { addressPointer in
            addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(socketFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            return false
        }

        return Darwin.listen(socketFD, 1) == 0
    }
}
