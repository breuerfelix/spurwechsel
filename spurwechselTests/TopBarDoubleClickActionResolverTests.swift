import XCTest
@testable import spurwechsel

final class TopBarDoubleClickActionResolverTests: XCTestCase {
    func testResolveReturnsMiniaturizeForMinimizeAction() {
        let defaults = makeDefaults()
        defaults.set("Minimize", forKey: "AppleActionOnDoubleClick")

        XCTAssertEqual(
            TopBarDoubleClickActionResolver.resolve(userDefaults: defaults),
            .miniaturize
        )
    }

    func testResolveReturnsNoneForNoneAction() {
        let defaults = makeDefaults()
        defaults.set("None", forKey: "AppleActionOnDoubleClick")

        XCTAssertEqual(
            TopBarDoubleClickActionResolver.resolve(userDefaults: defaults),
            .none
        )
    }

    func testResolveFallsBackToZoomWhenActionMissingAndLegacyDisabled() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: "AppleMiniaturizeOnDoubleClick")

        XCTAssertEqual(
            TopBarDoubleClickActionResolver.resolve(userDefaults: defaults),
            .zoom
        )
    }

    func testResolveUsesLegacyMiniaturizeFlagWhenActionMissing() {
        let defaults = makeDefaults()
        defaults.set(Data([0x00]), forKey: "AppleActionOnDoubleClick")
        defaults.removeObject(forKey: "AppleMiniaturizeOnDoubleClick")
        defaults.set(true, forKey: "AppleMiniaturizeOnDoubleClick")
        defaults.synchronize()

        XCTAssertEqual(
            TopBarDoubleClickActionResolver.resolve(userDefaults: defaults),
            .miniaturize
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "TopBarDoubleClickActionResolverTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create UserDefaults suite: \(suiteName)")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

final class WindowChromeLayoutResolverTests: XCTestCase {
    func testResolveLayoutCentersButtonsInTopBarAndComputesReservedInset() {
        let topBarFrame = CGRect(x: 20, y: 700, width: 1200, height: 50)
        let closeButtonFrame = CGRect(x: 14, y: 730, width: 14, height: 14)
        let miniaturizeButtonFrame = CGRect(x: 36, y: 730, width: 14, height: 14)
        let zoomButtonFrame = CGRect(x: 58, y: 730, width: 14, height: 14)

        let layout = WindowChromeLayoutResolver.resolveLayout(
            topBarFrameInWindow: topBarFrame,
            closeButtonFrame: closeButtonFrame,
            miniaturizeButtonFrame: miniaturizeButtonFrame,
            zoomButtonFrame: zoomButtonFrame,
            leadingPadding: 14,
            iconGap: 8
        )

        XCTAssertEqual(layout.closeButtonOrigin.x, 34)
        XCTAssertEqual(layout.closeButtonOrigin.y, 718)
        XCTAssertEqual(layout.miniaturizeButtonOrigin.x, 56)
        XCTAssertEqual(layout.zoomButtonOrigin.x, 78)
        XCTAssertEqual(layout.reservedLeadingWidth, 80)
    }

    func testResolveLayoutPreservesExistingButtonOffsets() {
        let topBarFrame = CGRect(x: 0, y: 400, width: 1000, height: 50)
        let closeButtonFrame = CGRect(x: 12, y: 0, width: 13, height: 13)
        let miniaturizeButtonFrame = CGRect(x: 35, y: 0, width: 13, height: 13)
        let zoomButtonFrame = CGRect(x: 61, y: 0, width: 13, height: 13)

        let layout = WindowChromeLayoutResolver.resolveLayout(
            topBarFrameInWindow: topBarFrame,
            closeButtonFrame: closeButtonFrame,
            miniaturizeButtonFrame: miniaturizeButtonFrame,
            zoomButtonFrame: zoomButtonFrame,
            leadingPadding: 14,
            iconGap: 8
        )

        XCTAssertEqual(layout.miniaturizeButtonOrigin.x - layout.closeButtonOrigin.x, 23)
        XCTAssertEqual(layout.zoomButtonOrigin.x - layout.closeButtonOrigin.x, 49)
    }
}
