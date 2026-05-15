import ComposableArchitecture
import SwiftUI

struct ShellOverlayHost: View {
    let shellStore: StoreOf<ShellFeature>
    let commandPaletteStore: StoreOf<CommandPaletteFeature>
    let projects: ProjectsState
    let theme: SpurTheme
    let configNotification: ConfigNotificationState?
    let shortcutBinding: (CommandID) -> ResolvedShortcutBinding?
    let dismissConfigNotification: () -> Void

    var body: some View {
        ZStack {
            CommandPaletteSceneView(
                shellStore: shellStore,
                store: commandPaletteStore,
                projects: projects,
                theme: theme,
                shortcutBinding: shortcutBinding
            )

            VStack {
                if let configNotification {
                    ConfigNotificationBannerView(
                        state: configNotification,
                        theme: theme,
                        dismiss: dismissConfigNotification
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, SpurSpacing.md)
                    .padding(.horizontal, SpurSpacing.md)
                    .zIndex(10)
                }

                Spacer()
            }
        }
    }
}
