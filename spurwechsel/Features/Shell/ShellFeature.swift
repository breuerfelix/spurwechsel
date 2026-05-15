import ComposableArchitecture
import Foundation

struct ShellFeature: Reducer {
    @Dependency(\.windowClient) var windowClient

    @ObservableState
    struct State: Equatable {
        var layout: AppLayoutState
        var resolvedShortcuts: [ResolvedShortcutBinding]
        var themeSet: ThemeSet
        var configNotification: ConfigNotificationState?
        var dismissedConfigNotificationSignature: String? = nil
        var commandBarShouldRestorePreviousFocus: Bool
        var surfaceFocusRequest: SurfaceFocusRequest?
        var windowChrome: WindowChromeState
    }

    enum Action {
        case startWindowObservation
        case selectMainView(MainViewKind)
        case selectPreviewView(PreviewViewKind)
        case persistLayout
        case dismissConfigNotification
        case setConfigNotification(ConfigNotificationState?)
        case updateConfigDiagnosticsNotification(ConfigNotificationState?)
        case setLeftSidebarVisible(Bool)
        case togglePreview
        case toggleLeftSidebar
        case toggleRightSidebar
        case toggleTheme
        case rememberFocusedSlot(SurfaceSlot)
        case setPreferredPreviewWidth(CGFloat, ClosedRange<CGFloat>)
        case setPreferredLeftSidebarWidth(CGFloat, ClosedRange<CGFloat>)
        case setPreferredRightSidebarWidth(CGFloat, ClosedRange<CGFloat>)
        case setLayout(AppLayoutState)
        case setTopBarFrameInWindow(CGRect?)
        case setWindowChrome(WindowChromeState)
        case setCommandBarFocusRestore(Bool)
        case setResolvedShortcuts([ResolvedShortcutBinding])
        case setThemeSet(ThemeSet)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .startWindowObservation:
                return .merge(
                    .run { send in
                        let stream = await windowClient.focusedSurfaceSlotStream()
                        for await slot in stream {
                            await send(.rememberFocusedSlot(slot))
                        }
                    }
                    ,
                    .run { send in
                        let stream = await windowClient.windowChromeStream()
                        for await chromeState in stream {
                            await send(.setWindowChrome(chromeState))
                        }
                    }
                    
                )
            case let .selectMainView(view):
                state.layout.selectMainView(view)
            case let .selectPreviewView(view):
                state.layout.selectPreviewView(view)
            case .persistLayout:
                break
            case .dismissConfigNotification:
                state.dismissedConfigNotificationSignature = configNotificationSignature(state.configNotification)
                state.configNotification = nil
            case let .setConfigNotification(notification):
                state.configNotification = notification
                if notification != nil {
                    state.dismissedConfigNotificationSignature = nil
                }
            case let .updateConfigDiagnosticsNotification(notification):
                let signature = configNotificationSignature(notification)
                if notification == nil {
                    state.configNotification = nil
                    state.dismissedConfigNotificationSignature = nil
                } else if state.dismissedConfigNotificationSignature != signature {
                    state.configNotification = notification
                }
            case let .setLeftSidebarVisible(isVisible):
                state.layout.showsLeftSidebar = isVisible
            case .togglePreview:
                state.layout.togglePreview()
            case .toggleLeftSidebar:
                state.layout.toggleLeftSidebar()
            case .toggleRightSidebar:
                state.layout.toggleRightSidebar()
            case .toggleTheme:
                state.layout.toggleTheme()
            case let .rememberFocusedSlot(slot):
                state.layout.rememberFocusedSlot(slot)
            case let .setPreferredPreviewWidth(width, allowedRange):
                state.layout.setPreferredPreviewWidth(width, allowedRange: allowedRange)
            case let .setPreferredLeftSidebarWidth(width, allowedRange):
                state.layout.setPreferredLeftSidebarWidth(width, allowedRange: allowedRange)
            case let .setPreferredRightSidebarWidth(width, allowedRange):
                state.layout.setPreferredRightSidebarWidth(width, allowedRange: allowedRange)
            case let .setLayout(layout):
                state.layout = layout
            case let .setTopBarFrameInWindow(frame):
                state.windowChrome.topBarFrameInWindow = frame
            case let .setWindowChrome(windowChrome):
                state.windowChrome = windowChrome
            case let .setCommandBarFocusRestore(shouldRestore):
                state.commandBarShouldRestorePreviousFocus = shouldRestore
            case let .setResolvedShortcuts(shortcuts):
                state.resolvedShortcuts = shortcuts
            case let .setThemeSet(themeSet):
                state.themeSet = themeSet
            }
            return .none
        }
    }
}

private func configNotificationSignature(_ notification: ConfigNotificationState?) -> String? {
    guard let notification else {
        return nil
    }
    return [
        notification.title,
        notification.message,
        notification.detailMessage ?? ""
    ].joined(separator: "|")
}
