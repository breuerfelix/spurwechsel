import XCTest
@testable import spurwechsel

final class AppFeatureCommandSupportTests: XCTestCase {
    func testAdjustedTerminalFontSizeIncreaseUsesOnePointStep() {
        let feature = AppFeature()

        XCTAssertEqual(
            feature.adjustedTerminalFontSize(currentSize: 12.0, direction: 1),
            13.0
        )
        XCTAssertEqual(
            feature.adjustedTerminalFontSize(currentSize: 12.3, direction: 1),
            13.3
        )
    }

    func testAdjustedTerminalFontSizeDecreaseUsesOnePointStep() {
        let feature = AppFeature()

        XCTAssertEqual(
            feature.adjustedTerminalFontSize(currentSize: 12.5, direction: -1),
            11.5
        )
        XCTAssertEqual(
            feature.adjustedTerminalFontSize(currentSize: 12.3, direction: -1),
            11.3
        )
    }

    func testAdjustedTerminalFontSizeClampsToMinimum() {
        let feature = AppFeature()

        XCTAssertEqual(
            feature.adjustedTerminalFontSize(currentSize: 1.0, direction: -1),
            nil
        )
        XCTAssertEqual(
            feature.adjustedTerminalFontSize(currentSize: 1.2, direction: -1),
            1.0
        )
    }
}
