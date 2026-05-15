import Foundation

struct UIStateFile: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var layout: UILayoutState
    var workspace: UIWorkspaceState

    init(
        version: Int = UIStateFile.currentVersion,
        layout: UILayoutState = UILayoutState(),
        workspace: UIWorkspaceState = UIWorkspaceState()
    ) {
        self.version = version
        self.layout = layout
        self.workspace = workspace
    }

    enum CodingKeys: String, CodingKey {
        case version
        case layout
        case workspace
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        layout = try container.decodeIfPresent(UILayoutState.self, forKey: .layout) ?? UILayoutState()
        workspace = try container.decodeIfPresent(UIWorkspaceState.self, forKey: .workspace) ?? UIWorkspaceState()
    }
}

struct UILayoutState: Codable, Equatable {
    var preferredLeftSidebarWidth: Double?
    var preferredRightSidebarWidth: Double?
    var preferredPreviewWidth: Double?
    var themeMode: String?

    init(
        preferredLeftSidebarWidth: Double? = nil,
        preferredRightSidebarWidth: Double? = nil,
        preferredPreviewWidth: Double? = nil,
        themeMode: String? = nil
    ) {
        self.preferredLeftSidebarWidth = preferredLeftSidebarWidth
        self.preferredRightSidebarWidth = preferredRightSidebarWidth
        self.preferredPreviewWidth = preferredPreviewWidth
        self.themeMode = themeMode
    }
}

struct UIWorkspaceState: Codable, Equatable {
    var collapsedProjectPaths: [String]
    var collapsedSectionIDs: [String]

    init(
        collapsedProjectPaths: [String] = [],
        collapsedSectionIDs: [String] = []
    ) {
        self.collapsedProjectPaths = collapsedProjectPaths
        self.collapsedSectionIDs = collapsedSectionIDs
    }

    enum CodingKeys: String, CodingKey {
        case collapsedProjectPaths
        case collapsedSectionIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        collapsedProjectPaths = try container.decodeIfPresent([String].self, forKey: .collapsedProjectPaths) ?? []
        collapsedSectionIDs = try container.decodeIfPresent([String].self, forKey: .collapsedSectionIDs) ?? []
    }
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
