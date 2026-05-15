import CoreGraphics
import Foundation

enum ThemeMode: String, CaseIterable, Hashable {
    case dark
    case light

    var title: String {
        rawValue.capitalized
    }

    var symbolName: String {
        switch self {
        case .dark:
            return "moon.stars.fill"
        case .light:
            return "sun.max.fill"
        }
    }
}

struct ConfigNotificationState: Equatable {
    var title: String
    var message: String
    var detailMessage: String?
}

struct MainViewPreviewConfiguration: Equatable {
    var isEnabled: Bool
    var selectedView: PreviewViewKind
}

struct AppLayoutState: Equatable {
    var selectedMainView: MainViewKind = .agent
    var previewConfigurations: [MainViewKind: MainViewPreviewConfiguration] = [:]
    var preferredFocusedSlotByMainView: [MainViewKind: SurfaceSlot] = [:]
    var preferredPreviewWidth: CGFloat?
    var preferredLeftSidebarWidth: CGFloat?
    var preferredRightSidebarWidth: CGFloat?
    var showsLeftSidebar = true
    var showsRightSidebar = true
    var themeMode: ThemeMode = .dark

    var effectiveShowsLeftSidebar: Bool {
        switch selectedMainView {
        case .terminal, .vscode:
            return false
        case .agent:
            return showsLeftSidebar
        }
    }

    var effectivePreviewConfiguration: MainViewPreviewConfiguration? {
        guard let config = previewConfigurations[selectedMainView] else {
            return nil
        }
        guard !config.selectedView.conflicts(with: selectedMainView) else {
            return nil
        }
        return config
    }

    var previewEnabled: Bool {
        effectivePreviewConfiguration?.isEnabled ?? false
    }

    var selectedPreviewView: PreviewViewKind? {
        effectivePreviewConfiguration?.selectedView
    }

    mutating func toggleLeftSidebar() {
        showsLeftSidebar.toggle()
    }

    mutating func toggleRightSidebar() {
        showsRightSidebar.toggle()
    }

    mutating func selectMainView(_ view: MainViewKind) {
        selectedMainView = view
    }

    mutating func rememberFocusedSlot(_ slot: SurfaceSlot) {
        preferredFocusedSlotByMainView[selectedMainView] = slot
    }

    func preferredFocusedSlot(for mainView: MainViewKind) -> SurfaceSlot {
        preferredFocusedSlotByMainView[mainView] ?? .main
    }

    mutating func togglePreview() {
        let fallbackPreviewView = PreviewViewKind.allCases.first(where: { !$0.conflicts(with: selectedMainView) }) ?? .terminal
        let current = previewConfigurations[selectedMainView] ?? MainViewPreviewConfiguration(
            isEnabled: false,
            selectedView: fallbackPreviewView
        )
        var updated = current
        updated.isEnabled.toggle()
        if updated.selectedView.conflicts(with: selectedMainView) {
            updated.selectedView = fallbackPreviewView
        }
        previewConfigurations[selectedMainView] = updated
    }

    mutating func selectPreviewView(_ view: PreviewViewKind) {
        guard !view.conflicts(with: selectedMainView) else { return }
        var updated = previewConfigurations[selectedMainView] ?? MainViewPreviewConfiguration(isEnabled: false, selectedView: view)
        updated.isEnabled = true
        updated.selectedView = view
        previewConfigurations[selectedMainView] = updated
    }

    mutating func setPreferredPreviewWidth(
        _ width: CGFloat,
        allowedRange: ClosedRange<CGFloat>
    ) {
        preferredPreviewWidth = min(max(width, allowedRange.lowerBound), allowedRange.upperBound)
    }

    mutating func setPreferredLeftSidebarWidth(
        _ width: CGFloat,
        allowedRange: ClosedRange<CGFloat>
    ) {
        preferredLeftSidebarWidth = min(max(width, allowedRange.lowerBound), allowedRange.upperBound)
    }

    mutating func setPreferredRightSidebarWidth(
        _ width: CGFloat,
        allowedRange: ClosedRange<CGFloat>
    ) {
        preferredRightSidebarWidth = min(max(width, allowedRange.lowerBound), allowedRange.upperBound)
    }

    mutating func toggleTheme() {
        themeMode = themeMode == .dark ? .light : .dark
    }
}

struct WindowChromeState: Equatable {
    var topBarFrameInWindow: CGRect?
    var trafficLightsReservedLeadingWidth: CGFloat = 0
    var isFullScreen = false
}

struct WindowChromeLayout: Equatable {
    let closeButtonOrigin: CGPoint
    let miniaturizeButtonOrigin: CGPoint
    let zoomButtonOrigin: CGPoint
    let reservedLeadingWidth: CGFloat
}

enum WindowChromeLayoutResolver {
    static func resolveLayout(
        topBarFrameInWindow: CGRect,
        closeButtonFrame: CGRect,
        miniaturizeButtonFrame: CGRect,
        zoomButtonFrame: CGRect,
        leadingPadding: CGFloat,
        iconGap: CGFloat
    ) -> WindowChromeLayout {
        let miniOffset = miniaturizeButtonFrame.minX - closeButtonFrame.minX
        let zoomOffset = zoomButtonFrame.minX - closeButtonFrame.minX
        let closeOrigin = CGPoint(
            x: topBarFrameInWindow.minX + leadingPadding,
            y: topBarFrameInWindow.midY - (closeButtonFrame.height / 2)
        )
        let miniOrigin = CGPoint(x: closeOrigin.x + miniOffset, y: closeOrigin.y)
        let zoomOrigin = CGPoint(x: closeOrigin.x + zoomOffset, y: closeOrigin.y)
        let clusterMaxX = max(
            closeOrigin.x + closeButtonFrame.width,
            miniOrigin.x + miniaturizeButtonFrame.width,
            zoomOrigin.x + zoomButtonFrame.width
        )
        let reservedLeadingWidth = max(0, clusterMaxX - topBarFrameInWindow.minX + iconGap)

        return WindowChromeLayout(
            closeButtonOrigin: closeOrigin,
            miniaturizeButtonOrigin: miniOrigin,
            zoomButtonOrigin: zoomOrigin,
            reservedLeadingWidth: reservedLeadingWidth
        )
    }
}