import SwiftUI
import ComposableArchitecture

private enum VSCodeViewDensity {
    static let statusOverlayPadding: CGFloat = SpurSpacing.lg
    static let contentCornerRadius: CGFloat = 12
}

struct VSCodeMainView: View {
    let workspaceID: String
    let isSurfaceSelected: Bool
    let surfaceSlot: SurfaceSlot
    let focusRequest: SurfaceFocusRequest?
    let onSurfaceFocused: (SurfaceSlot) -> Void
    let theme: SpurTheme
    let editorStore: StoreOf<EditorFeature>
    let runtime: EmbeddedWebViewRuntime?

    var body: some View {
        let session = currentSession
        let _ = debugRenderTrace(session)
        ZStack {
            theme.backgroundSecondary.ignoresSafeArea()

            ZStack {
                theme.backgroundSecondary
                    .ignoresSafeArea()

                if let runtime {
                    EmbeddedWebViewHost(
                        runtime: runtime,
                        isActive: isSurfaceSelected,
                        surfaceSlot: surfaceSlot,
                        focusRequest: focusRequest,
                        onSurfaceFocused: onSurfaceFocused
                    )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if showStatusOverlay(for: session) {
                    SurfaceStateView(
                        icon: statusIcon(for: session),
                        title: statusTitle(for: session),
                        message: statusMessage(for: session),
                        theme: theme,
                        emphasis: statusEmphasis(for: session)
                    )
                    .padding(VSCodeViewDensity.statusOverlayPadding)
                }
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: VSCodeViewDensity.contentCornerRadius,
                    style: .continuous
                )
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            debugLifecycleTrace("onAppear", session)
        }
        .onChange(of: session.status) { oldValue, newValue in
            debugLifecycleTrace("status \(String(describing: oldValue)) -> \(String(describing: newValue))", session)
        }
        .onChange(of: session.browserPhase) { oldValue, newValue in
            debugLifecycleTrace("browserPhase \(String(describing: oldValue)) -> \(String(describing: newValue))", session)
        }
    }

    private var currentSession: EditorSessionState {
        editorStore.state.sessionsByWorkspaceID[workspaceID]
            ?? EditorSessionState(
                workspaceSelectionID: workspaceID,
                workspaceName: nil,
                workspacePath: nil,
                serverAddress: nil,
                workspaceAddress: nil,
                status: .idle,
                statusMessage: "Select VSCode view to start code-server.",
                errorMessage: nil,
                lastOutputLine: nil
            )
    }

    private func showStatusOverlay(for session: EditorSessionState) -> Bool {
        switch session.status {
        case .running:
            if case .ready = session.browserPhase {
                return false
            }
            return true
        default:
            return true
        }
    }

    private func statusIcon(for session: EditorSessionState) -> String {
        if case .failed = session.browserPhase {
            return "exclamationmark.triangle"
        }
        switch session.status {
        case .running:
            return "network"
        case .starting, .stopping:
            return "clock.arrow.circlepath"
        case .missingWorkspace:
            return "folder.badge.questionmark"
        case .authRequired:
            return "person.badge.key"
        case .cliMissing, .portInUse:
            return "exclamationmark.triangle"
        case .startupFailed, .urlNotFound:
            return "bolt.horizontal.circle"
        case .idle, .stopped:
            return "play.square"
        }
    }

    private func statusTitle(for session: EditorSessionState) -> String {
        switch session.status {
        case .running:
            return "Connecting VSCode session"
        case .starting:
            return "Starting code-server"
        case .stopping:
            return "Stopping code-server"
        case .missingWorkspace:
            return "Select workspace"
        case .authRequired:
            return "Authentication required"
        case .cliMissing:
            return "code-server missing"
        case .portInUse:
            return "Port already in use"
        case .startupFailed:
            return "code-server startup failed"
        case .urlNotFound:
            return "Server URL missing"
        case .idle, .stopped:
            return "code-server stopped"
        }
    }

    private func statusMessage(for session: EditorSessionState) -> String {
        if let errorMessage = session.errorMessage {
            return errorMessage
        }
        return session.statusMessage
    }

    private func statusEmphasis(for session: EditorSessionState) -> SurfaceStateView.Emphasis {
        if case .failed = session.browserPhase {
            return .error
        }
        switch session.status {
        case .cliMissing, .portInUse, .startupFailed, .urlNotFound:
            return .error
        case .authRequired:
            return .warning
        case .starting, .stopping, .running:
            return .info
        case .missingWorkspace, .idle, .stopped:
            return .neutral
        }
    }

    private func debugRenderTrace(_ session: EditorSessionState) {
        #if DEBUG
        print("[VSCodeDebug][VSCodeMainView] render workspaceID=\(workspaceID) sessionWorkspaceID=\(session.workspaceSelectionID ?? "nil") status=\(String(describing: session.status)) phase=\(String(describing: session.browserPhase)) showOverlay=\(showStatusOverlay(for: session))")
        #endif
    }

    private func debugLifecycleTrace(_ message: String, _ session: EditorSessionState) {
        #if DEBUG
        print("[VSCodeDebug][VSCodeMainView] \(message) workspaceID=\(workspaceID) showOverlay=\(showStatusOverlay(for: session))")
        #endif
    }
}
