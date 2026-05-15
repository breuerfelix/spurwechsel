import XCTest
import GhosttyTerminal
@testable import spurwechsel

final class GhosttyUserConfigLoaderTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("spurwechsel-ghostty-loader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
    }

    func testLoadMergesDefaultPathsWithLaterFilesOverridingEarlierOnes() throws {
        let xdgHome = temporaryDirectoryURL.appendingPathComponent("xdg", isDirectory: true)
        let xdgGhostty = xdgHome.appendingPathComponent("ghostty", isDirectory: true)
        let home = temporaryDirectoryURL.appendingPathComponent("home", isDirectory: true)
        let macGhostty = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("com.mitchellh.ghostty", isDirectory: true)

        try FileManager.default.createDirectory(at: xdgGhostty, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: macGhostty, withIntermediateDirectories: true)

        try """
        font-size = 11
        cursor-style = block
        """.appending("\n").write(
            to: xdgGhostty.appendingPathComponent("config.ghostty"),
            atomically: true,
            encoding: .utf8
        )

        try """
        font-size = 12
        cursor-style = underline
        """.appending("\n").write(
            to: xdgGhostty.appendingPathComponent("config"),
            atomically: true,
            encoding: .utf8
        )

        try """
        font-size = 13
        cursor-style = bar
        """.appending("\n").write(
            to: macGhostty.appendingPathComponent("config.ghostty"),
            atomically: true,
            encoding: .utf8
        )

        let loader = GhosttyUserConfigLoader(
            fileManager: .default,
            environment: ["XDG_CONFIG_HOME": xdgHome.path],
            homeDirectoryPath: home.path
        )

        let loaded = loader.load()

        XCTAssertEqual(loaded.surfaceFontSize, 13)
        XCTAssertTrue(loaded.terminalConfiguration.rendered.contains("cursor-style = bar"))
        XCTAssertFalse(loaded.terminalConfiguration.rendered.contains("cursor-style = underline"))
    }

    func testConfigFileIncludesLoadAtEndOfParentFile() throws {
        let xdgHome = temporaryDirectoryURL.appendingPathComponent("xdg", isDirectory: true)
        let xdgGhostty = xdgHome.appendingPathComponent("ghostty", isDirectory: true)
        let home = temporaryDirectoryURL.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: xdgGhostty, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        try """
        font-size = 10
        config-file = nested.ghostty
        font-size = 11
        """.appending("\n").write(
            to: xdgGhostty.appendingPathComponent("config.ghostty"),
            atomically: true,
            encoding: .utf8
        )
        try "font-size = 12\n".write(
            to: xdgGhostty.appendingPathComponent("nested.ghostty"),
            atomically: true,
            encoding: .utf8
        )

        let loader = GhosttyUserConfigLoader(
            fileManager: .default,
            environment: ["XDG_CONFIG_HOME": xdgHome.path],
            homeDirectoryPath: home.path
        )

        let loaded = loader.load()
        XCTAssertEqual(loaded.surfaceFontSize, 12)
        XCTAssertTrue(loaded.terminalConfiguration.rendered.contains("font-size = 12"))
        XCTAssertFalse(loaded.terminalConfiguration.rendered.contains("font-size = 11"))
    }

    func testSanitizerKeepsOnlyCuratedKeys() throws {
        let xdgHome = temporaryDirectoryURL.appendingPathComponent("xdg", isDirectory: true)
        let xdgGhostty = xdgHome.appendingPathComponent("ghostty", isDirectory: true)
        let home = temporaryDirectoryURL.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: xdgGhostty, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        try """
        font-family = "Iosevka Term"
        cursor-style = underline
        copy-on-select = clipboard
        mouse-scroll-multiplier = precision:0.5,discrete:2
        scrollback-limit = 5000000
        background-opacity = 0.5
        background-blur = 10
        desktop-notifications = true
        window-padding-x = 8
        window-padding-y = 8
        """.appending("\n").write(
            to: xdgGhostty.appendingPathComponent("config.ghostty"),
            atomically: true,
            encoding: .utf8
        )

        let loader = GhosttyUserConfigLoader(
            fileManager: .default,
            environment: ["XDG_CONFIG_HOME": xdgHome.path],
            homeDirectoryPath: home.path
        )
        let loaded = loader.load()
        let rendered = loaded.terminalConfiguration.rendered

        XCTAssertTrue(rendered.contains("font-family = Iosevka Term"))
        XCTAssertTrue(rendered.contains("cursor-style = underline"))
        XCTAssertTrue(rendered.contains("copy-on-select = clipboard"))
        XCTAssertTrue(rendered.contains("mouse-scroll-multiplier = precision:0.5,discrete:2"))
        XCTAssertTrue(rendered.contains("scrollback-limit = 5000000"))

        XCTAssertFalse(rendered.contains("background-opacity"))
        XCTAssertFalse(rendered.contains("background-blur"))
        XCTAssertFalse(rendered.contains("desktop-notifications"))
        XCTAssertFalse(rendered.contains("window-padding-x"))
        XCTAssertFalse(rendered.contains("window-padding-y"))
    }

    func testInvalidCuratedValuesAreDropped() throws {
        let xdgHome = temporaryDirectoryURL.appendingPathComponent("xdg", isDirectory: true)
        let xdgGhostty = xdgHome.appendingPathComponent("ghostty", isDirectory: true)
        let home = temporaryDirectoryURL.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: xdgGhostty, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        try """
        cursor-opacity = 2.0
        font-thicken-strength = 999
        mouse-scroll-multiplier = fast
        copy-on-select = banana
        scrollback-limit = -3
        """.appending("\n").write(
            to: xdgGhostty.appendingPathComponent("config.ghostty"),
            atomically: true,
            encoding: .utf8
        )

        let loader = GhosttyUserConfigLoader(
            fileManager: .default,
            environment: ["XDG_CONFIG_HOME": xdgHome.path],
            homeDirectoryPath: home.path
        )
        let loaded = loader.load()
        let rendered = loaded.terminalConfiguration.rendered

        XCTAssertFalse(rendered.contains("cursor-opacity"))
        XCTAssertFalse(rendered.contains("font-thicken-strength"))
        XCTAssertFalse(rendered.contains("mouse-scroll-multiplier"))
        XCTAssertFalse(rendered.contains("copy-on-select"))
        XCTAssertFalse(rendered.contains("scrollback-limit"))
    }

    func testInvalidBooleanDoesNotClearPreviousValidValue() throws {
        let xdgHome = temporaryDirectoryURL.appendingPathComponent("xdg", isDirectory: true)
        let xdgGhostty = xdgHome.appendingPathComponent("ghostty", isDirectory: true)
        let home = temporaryDirectoryURL.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: xdgGhostty, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        try """
        selection-clear-on-copy = true
        selection-clear-on-copy = maybe
        """.appending("\n").write(
            to: xdgGhostty.appendingPathComponent("config.ghostty"),
            atomically: true,
            encoding: .utf8
        )

        let loader = GhosttyUserConfigLoader(
            fileManager: .default,
            environment: ["XDG_CONFIG_HOME": xdgHome.path],
            homeDirectoryPath: home.path
        )
        let loaded = loader.load()
        let rendered = loaded.terminalConfiguration.rendered

        XCTAssertTrue(rendered.contains("selection-clear-on-copy = true"))
    }
}
