import XCTest
@testable import spurwechsel

final class UIStateStoreTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("UIStateStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
    }

    func testSaveAndLoadRoundTrip() throws {
        let stateURL = temporaryDirectoryURL.appendingPathComponent("ui-state.json")
        let store = UIStateStore(stateURL: stateURL)
        let input = UIStateFile(
            layout: UILayoutState(
                preferredLeftSidebarWidth: 301,
                preferredRightSidebarWidth: 277,
                preferredPreviewWidth: 512,
                themeMode: "light"
            ),
            workspace: UIWorkspaceState(
                collapsedProjectPaths: ["/tmp/repo-a", "/tmp/repo-b"],
                collapsedSectionIDs: ["tools", "other"]
            )
        )

        try store.save(input)
        let output = store.load()

        XCTAssertEqual(output, input)
    }

    func testLoadReturnsDefaultsWhenFileIsInvalidJSON() throws {
        let stateURL = temporaryDirectoryURL.appendingPathComponent("ui-state.json")
        try "invalid".write(to: stateURL, atomically: true, encoding: .utf8)
        let store = UIStateStore(stateURL: stateURL)

        XCTAssertEqual(store.load(), UIStateFile())
    }

    func testLoadBackfillsNewFieldsForLegacyStateFile() throws {
        let stateURL = temporaryDirectoryURL.appendingPathComponent("ui-state.json")
        let legacyJSON = """
        {
          "version": 1,
          "layout": {
            "preferredLeftSidebarWidth": 300,
            "preferredRightSidebarWidth": 280
          }
        }
        """
        try legacyJSON.write(to: stateURL, atomically: true, encoding: .utf8)
        let store = UIStateStore(stateURL: stateURL)

        let output = store.load()
        XCTAssertEqual(output.layout.preferredLeftSidebarWidth, 300)
        XCTAssertEqual(output.layout.preferredRightSidebarWidth, 280)
        XCTAssertNil(output.layout.preferredPreviewWidth)
        XCTAssertNil(output.layout.themeMode)
        XCTAssertEqual(output.workspace, UIWorkspaceState())
    }
}
