import Foundation

enum SurfaceKind: String, CaseIterable, Hashable {
    case agent
    case terminal
    case vscode

    var title: String {
        switch self {
        case .vscode:
            return "VSCode"
        default:
            return rawValue.capitalized
        }
    }

    var symbolName: String {
        switch self {
        case .agent:
            return "sparkles.rectangle.stack"
        case .terminal:
            return "terminal"
        case .vscode:
            return "chevron.left.forwardslash.chevron.right"
        }
    }
}

typealias MainViewKind = SurfaceKind
typealias PreviewViewKind = SurfaceKind

extension SurfaceKind {
    func conflicts(with mainView: MainViewKind) -> Bool {
        self == mainView
    }

    var mainViewKind: MainViewKind {
        self
    }
}

enum SurfaceDescriptor: Hashable {
    case agentSession(UUID)
    case agentWorkspace(String)
    case workspaceTerminal(String)
    case vscodeWorkspace(String)

    var mainView: MainViewKind {
        switch self {
        case .agentSession, .agentWorkspace:
            return .agent
        case .workspaceTerminal:
            return .terminal
        case .vscodeWorkspace:
            return .vscode
        }
    }
}

typealias SurfaceTabID = SurfaceDescriptor

struct SurfaceTab: Identifiable, Equatable {
    let id: SurfaceTabID
    var title: String
    var workspaceSelection: WorkspaceSelection
    var sessionID: UUID?

    var mainView: MainViewKind {
        id.mainView
    }
}

struct SurfaceTabState: Equatable {
    var tabs: [SurfaceTab] = []
    var selectedTabID: SurfaceTabID?

    var selectedTab: SurfaceTab? {
        guard let selectedTabID else { return nil }
        return tabs.first(where: { $0.id == selectedTabID })
    }
}

enum SurfacePlacement: Hashable {
    case main
    case preview
}

typealias SurfaceSlot = SurfacePlacement

struct SurfaceFocusRequest: Equatable {
    let id: Int
    let slot: SurfaceSlot
}

struct SurfaceMountState: Equatable {
    private(set) var mountedBySlot: [SurfaceSlot: SurfaceTabID] = [:]

    var mainSurfaceID: SurfaceTabID? {
        mountedBySlot[.main]
    }

    var previewSurfaceID: SurfaceTabID? {
        mountedBySlot[.preview]
    }

    mutating func mount(_ surfaceID: SurfaceTabID?, in slot: SurfaceSlot) {
        if let surfaceID {
            for occupiedSlot in mountedBySlot.keys where occupiedSlot != slot && mountedBySlot[occupiedSlot] == surfaceID {
                mountedBySlot.removeValue(forKey: occupiedSlot)
            }
            mountedBySlot[slot] = surfaceID
        } else {
            mountedBySlot.removeValue(forKey: slot)
        }
    }
}