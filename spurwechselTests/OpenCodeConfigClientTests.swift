import XCTest
@testable import spurwechsel

final class OpenCodeConfigClientTests: XCTestCase {
    func testPrefersLocalConfigWhenPresent() {
        let localPath = "/repo/opencode.json"
        let globalPath = "/home/test/.config/opencode/opencode.json"
        let files: [String: Data] = [
            localPath: Data("{\"plugin\":[\"warp\"]}".utf8),
            globalPath: Data("{\"plugin\":[\"not-warp\"]}".utf8)
        ]

        let probe = makeProbe(files: files)

        XCTAssertTrue(probe.isWarpPluginInstalled(workingDirectory: "/repo"))
    }

    func testFallsBackToGlobalConfigWhenLocalMissing() {
        let files: [String: Data] = [
            "/home/test/.config/opencode/opencode.json": Data("{\"plugin\":[{\"name\":\"warp\"}]}".utf8)
        ]

        let probe = makeProbe(files: files)

        XCTAssertTrue(probe.isWarpPluginInstalled(workingDirectory: "/repo"))
    }

    func testReturnsFalseWhenConfigMissing() {
        let probe = makeProbe(files: [:])

        XCTAssertFalse(probe.isWarpPluginInstalled(workingDirectory: "/repo"))
    }

    func testReturnsFalseForMalformedJSON() {
        let files: [String: Data] = [
            "/repo/opencode.json": Data("{not-json".utf8)
        ]

        let probe = makeProbe(files: files)

        XCTAssertFalse(probe.isWarpPluginInstalled(workingDirectory: "/repo"))
    }

    func testSupportsStringPluginEntries() {
        let files: [String: Data] = [
            "/repo/opencode.json": Data("{\"plugin\":[\"@warp-dot-dev/opencode-warp\"]}".utf8)
        ]

        let probe = makeProbe(files: files)

        XCTAssertTrue(probe.isWarpPluginInstalled(workingDirectory: "/repo"))
    }

    func testSupportsObjectPluginEntries() {
        let files: [String: Data] = [
            "/repo/opencode.json": Data("{\"plugin\":[{\"name\":\"@warp-dot-dev/opencode-warp\"}]}".utf8)
        ]

        let probe = makeProbe(files: files)

        XCTAssertTrue(probe.isWarpPluginInstalled(workingDirectory: "/repo"))
    }

    private func makeProbe(files: [String: Data]) -> OpenCodeConfigProbe {
        OpenCodeConfigProbe(
            fileExists: { path in files[path] != nil },
            readData: { path in
                guard let data = files[path] else {
                    throw NSError(domain: "OpenCodeConfigClientTests", code: 1)
                }
                return data
            },
            homeDirectoryPath: { "/home/test" }
        )
    }
}
