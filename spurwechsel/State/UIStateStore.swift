import Foundation

struct UIStateFile: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var layout: UILayoutState

    init(
        version: Int = UIStateFile.currentVersion,
        layout: UILayoutState = UILayoutState()
    ) {
        self.version = version
        self.layout = layout
    }
}

struct UILayoutState: Codable, Equatable {
    var preferredLeftSidebarWidth: Double?
    var preferredRightSidebarWidth: Double?
}

struct UIStateStore {
    let stateURL: URL
    private let fileManager: FileManager

    init(
        stateURL: URL = UIStateStore.defaultStateURL(),
        fileManager: FileManager = .default
    ) {
        self.stateURL = stateURL
        self.fileManager = fileManager
    }

    static func defaultStateURL(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> URL {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        let directoryName = bundleIdentifier ?? "dev.breuer.spurwechsel"
        return applicationSupportURL
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent("ui-state.json", isDirectory: false)
    }

    func load() -> UIStateFile {
        guard fileManager.fileExists(atPath: stateURL.path) else {
            return UIStateFile()
        }

        do {
            let data = try Data(contentsOf: stateURL)
            return try JSONDecoder().decode(UIStateFile.self, from: data)
        } catch {
            return UIStateFile()
        }
    }

    func save(_ state: UIStateFile) throws {
        let parentDirectoryURL = stateURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentDirectoryURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        try data.write(to: stateURL, options: .atomic)
    }
}
