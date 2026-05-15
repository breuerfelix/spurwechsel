import ComposableArchitecture
import Foundation

struct AppCommandRouter {
    private let appFeature: AppFeature

    init(appFeature: AppFeature) {
        self.appFeature = appFeature
    }

    func handleCommandPaletteCommand(
        _ state: inout AppFeature.State,
        command: CommandID,
        projectContextID: UUID?,
        workspaceContext: WorkspaceSelection?
    ) -> Effect<AppFeature.Action> {
        appFeature.handleCommandPaletteCommand(
            &state,
            command: command,
            projectContextID: projectContextID,
            workspaceContext: workspaceContext
        )
    }
}
