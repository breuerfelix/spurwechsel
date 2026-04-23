import AppKit
import SwiftUI

struct TopBarView: View {
    private enum TopBarChromeMetrics {
        static let trafficLightFallbackInsetWidth: CGFloat = 60
        static let topInsetAdjustment: CGFloat = 2
        static let barHeight: CGFloat = 50
        static let commandBarHeight: CGFloat = 35
    }

    @ObservedObject var shellStore: ShellStore
    let previewModels: [PreviewContentModel]
    let windowChromeState: WindowChromeState
    let onTopBarFrameChange: (CGRect) -> Void
    let openCommandBar: () -> Void
    let toggleLeftSidebar: () -> Void
    let toggleRightSidebar: () -> Void
    let togglePreview: () -> Void
    let selectMainView: (MainViewKind) -> Void
    let selectPreviewView: (PreviewViewKind) -> Void

    private var theme: SpurTheme { shellStore.theme }

    private var availablePreviewModels: [PreviewContentModel] {
        previewModels.filter { !$0.id.conflicts(with: shellStore.layout.selectedMainView) }
    }

    private var leadingInsetWidth: CGFloat {
        if windowChromeState.isFullScreen {
            return 0
        }
        let computedInset = windowChromeState.trafficLightsReservedLeadingWidth
        guard computedInset > 0 else {
            return TopBarChromeMetrics.trafficLightFallbackInsetWidth
        }
        return computedInset
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                topBarInteractionBackground

                HStack(spacing: SpurSpacing.md) {
                    HStack(spacing: SpurSpacing.sm) {
                        Color.clear
                            .frame(width: leadingInsetWidth, height: 1)
                            .allowsHitTesting(false)

                        ChromeIconButton(
                            systemName: "sidebar.left",
                            title: "Toggle left sidebar",
                            theme: theme,
                            isSelected: false,
                            showsSelection: false,
                            accessibilityID: "topbar.sidebar.left"
                        ) {
                            toggleLeftSidebar()
                        }

                        ForEach(MainViewKind.allCases, id: \.self) { view in
                            ChromeIconButton(
                                systemName: view.symbolName,
                                title: view.title,
                                theme: theme,
                                isSelected: shellStore.layout.selectedMainView == view,
                                accessibilityID: "topbar.view.\(view.rawValue)"
                            ) {
                                selectMainView(view)
                            }
                        }
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: SpurSpacing.sm) {
                        if !availablePreviewModels.isEmpty {
                            if shellStore.layout.previewEnabled {
                                ForEach(availablePreviewModels) { model in
                                    ChromeIconButton(
                                        systemName: model.symbolName,
                                        title: model.title,
                                        theme: theme,
                                        isSelected: shellStore.layout.selectedPreviewView == model.id,
                                        accessibilityID: "topbar.preview.\(model.id.rawValue)"
                                    ) {
                                        selectPreviewView(model.id)
                                    }
                                }
                            }

                            ChromeIconButton(
                                systemName: "rectangle.split.2x1",
                                title: "Toggle preview",
                                theme: theme,
                                isSelected: shellStore.layout.previewEnabled,
                                accessibilityID: "topbar.preview.toggle"
                            ) {
                                togglePreview()
                            }
                        }

                        ChromeIconButton(
                            systemName: "sidebar.right",
                            title: "Toggle projects",
                            theme: theme,
                            isSelected: false,
                            showsSelection: false,
                            accessibilityID: "topbar.sidebar.right"
                        ) {
                            toggleRightSidebar()
                        }
                    }
                }
                .padding(.horizontal, SpurSpacing.md)
                .offset(y: TopBarChromeMetrics.topInsetAdjustment)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                commandBar(width: min(max(proxy.size.width * 0.30, 300), 580))
                    .offset(y: TopBarChromeMetrics.topInsetAdjustment)
            }
        }
        .frame(height: TopBarChromeMetrics.barHeight)
        .background(
            TopBarFrameReporterView(
                onFrameChange: onTopBarFrameChange
            )
        )
    }

    private var topBarInteractionBackground: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                handleTopBarDoubleClick()
            }
            .gesture(WindowDragGesture())
            .allowsWindowActivationEvents()
    }

    private func commandBar(width: CGFloat) -> some View {
        Button {
            openCommandBar()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(theme.foregroundDim)
                Text("Search commands")
                    .foregroundStyle(theme.foregroundMuted)
                    .font(.system(size: 14, weight: .medium))
                Spacer(minLength: 0)
                Text("⌘K")
                    .foregroundStyle(theme.foregroundDim)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(theme.panelRaised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(theme.border, lineWidth: 1)
                    )
            }
            .padding(.horizontal, 16)
            .frame(width: width, height: TopBarChromeMetrics.commandBarHeight)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.panelMuted)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.clear, lineWidth: 0)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("topbar.commandbar")
    }

    private func handleTopBarDoubleClick() {
        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow else {
            return
        }
        switch TopBarDoubleClickActionResolver.resolve(userDefaults: .standard) {
        case .zoom:
            window.performZoom(nil)
        case .miniaturize:
            window.performMiniaturize(nil)
        case .none:
            break
        }
    }
}

private struct TopBarFrameReporterView: NSViewRepresentable {
    let onFrameChange: (CGRect) -> Void

    func makeNSView(context: Context) -> TopBarFrameReporterNSView {
        let view = TopBarFrameReporterNSView()
        view.onFrameChange = onFrameChange
        return view
    }

    func updateNSView(_ nsView: TopBarFrameReporterNSView, context: Context) {
        nsView.onFrameChange = onFrameChange
        nsView.publishFrameIfNeeded()
    }
}

private final class TopBarFrameReporterNSView: NSView {
    var onFrameChange: ((CGRect) -> Void)?
    private var lastFrameInWindow: CGRect?

    override func layout() {
        super.layout()
        publishFrameIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        publishFrameIfNeeded()
    }

    func publishFrameIfNeeded() {
        guard let onFrameChange, window != nil else {
            return
        }
        let frameInWindow = convert(bounds, to: nil)
        guard lastFrameInWindow != frameInWindow else {
            return
        }
        lastFrameInWindow = frameInWindow
        DispatchQueue.main.async {
            onFrameChange(frameInWindow)
        }
    }
}

enum TopBarDoubleClickAction: Equatable {
    case zoom
    case miniaturize
    case none
}

enum TopBarDoubleClickActionResolver {
    private static let actionKey = "AppleActionOnDoubleClick"
    private static let miniaturizeKey = "AppleMiniaturizeOnDoubleClick"

    static func resolve(userDefaults: UserDefaults) -> TopBarDoubleClickAction {
        if let action = userDefaults.string(forKey: actionKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
            switch action {
            case "minimize":
                return .miniaturize
            case "none":
                return .none
            default:
                return .zoom
            }
        }

        if userDefaults.bool(forKey: miniaturizeKey) {
            return .miniaturize
        }

        return .zoom
    }
}
