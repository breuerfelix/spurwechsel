import ComposableArchitecture
import XCTest
@testable import spurwechsel

@MainActor
final class ShellFeatureTests: XCTestCase {
    func testTogglePreviewUpdatesLayout() async {
        let store = TestStore(initialState: ShellFeature.State(
            layout: PreviewFixtures.layoutState,
            resolvedShortcuts: SpurwechselConfig().resolvedShortcuts,
            terminalConfig: TerminalConfig(),
            themeSet: .default,
            configNotification: nil,
            commandBarShouldRestorePreviousFocus: true,
            surfaceFocusRequest: nil,
            windowChrome: WindowChromeState()
        )) {
            ShellFeature()
        }

        await store.send(.togglePreview) {
            $0.layout.togglePreview()
        }
    }

    func testPersistLayoutActionDoesNotMutateState() async {
        let initial = ShellFeature.State(
            layout: PreviewFixtures.layoutState,
            resolvedShortcuts: SpurwechselConfig().resolvedShortcuts,
            terminalConfig: TerminalConfig(),
            themeSet: .default,
            configNotification: nil,
            commandBarShouldRestorePreviousFocus: true,
            surfaceFocusRequest: nil,
            windowChrome: WindowChromeState()
        )
        let store = TestStore(initialState: initial) {
            ShellFeature()
        }

        await store.send(.persistLayout)
        XCTAssertEqual(store.state, initial)
    }
}
