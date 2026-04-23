import SwiftUI

private enum VSCodeViewDensity {
    static let statusOverlayPadding: CGFloat = SpurSpacing.lg
    static let contentCornerRadius: CGFloat = 12
}

struct VSCodeMainView: View {
    @ObservedObject var store: EditorSurfaceStore
    let workspaceID: String
    let isSurfaceSelected: Bool
    let surfaceSlot: SurfaceSlot
    let focusRequest: SurfaceFocusRequest?
    let onSurfaceFocused: (SurfaceSlot) -> Void

    private var theme: SpurTheme { store.theme }
    private var session: EditorSessionState { store.editorSession(for: workspaceID) }

    var body: some View {
        ZStack {
            theme.backgroundSecondary.ignoresSafeArea()

            ZStack {
                theme.backgroundSecondary
                    .ignoresSafeArea()

                if let runtime = store.vscodeWebRuntime(forWorkspaceID: workspaceID) {
                    EmbeddedWebViewHost(
                        runtime: runtime,
                        isActive: isSurfaceSelected,
                        surfaceSlot: surfaceSlot,
                        focusRequest: focusRequest,
                        onSurfaceFocused: onSurfaceFocused
                    )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if showStatusOverlay {
                    SurfaceStateView(
                        icon: statusIcon,
                        title: statusTitle,
                        message: statusMessage,
                        theme: theme,
                        emphasis: statusEmphasis
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
    }

    private var showStatusOverlay: Bool {
        guard session.workspaceSelectionID == workspaceID else {
            return true
        }
        return !(session.status == .running && session.workspaceAddress != nil)
    }

    private var statusIcon: String {
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

    private var statusTitle: String {
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

    private var statusMessage: String {
        if let errorMessage = session.errorMessage {
            return errorMessage
        }
        return session.statusMessage
    }

    private var statusEmphasis: SurfaceStateView.Emphasis {
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
}
