import Foundation

enum ExternalWorkspaceDeepLinkError: LocalizedError, Equatable {
    case unsupportedScheme(String)
    case unsupportedAction(String)
    case missingQueryItem(String)
    case invalidBase64Payload(String)
    case invalidUTF8Payload(String)
    case pathNotAbsolute(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedScheme(scheme):
            return "Unsupported deep-link scheme: \(scheme)"
        case let .unsupportedAction(action):
            return "Unsupported deep-link action: \(action)"
        case let .missingQueryItem(name):
            return "Deep link missing query item: \(name)"
        case let .invalidBase64Payload(name):
            return "Deep link payload is not valid base64url: \(name)"
        case let .invalidUTF8Payload(name):
            return "Deep link payload is not valid UTF-8: \(name)"
        case let .pathNotAbsolute(name):
            return "Deep link path must be absolute: \(name)"
        }
    }
}

struct ExternalWorkspaceDeepLinkRequest: Equatable {
    static let scheme = "spurwechsel"
    static let actionOpenWorkspace = "open-workspace"
    static let workspaceKey = "workspace_b64"
    static let projectKey = "project_b64"

    let workspacePath: String
    let projectPath: String

    init(url: URL) throws {
        let loweredScheme = url.scheme?.lowercased() ?? ""
        guard loweredScheme == Self.scheme else {
            throw ExternalWorkspaceDeepLinkError.unsupportedScheme(url.scheme ?? "nil")
        }

        let action = (url.host?.isEmpty == false ? url.host : nil) ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard action == Self.actionOpenWorkspace else {
            throw ExternalWorkspaceDeepLinkError.unsupportedAction(action)
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ExternalWorkspaceDeepLinkError.unsupportedAction(action)
        }

        workspacePath = try Self.decodeAbsolutePath(from: components, key: Self.workspaceKey)
        projectPath = try Self.decodeAbsolutePath(from: components, key: Self.projectKey)
    }

    private static func decodeAbsolutePath(from components: URLComponents, key: String) throws -> String {
        guard let value = components.queryItems?.first(where: { $0.name == key })?.value, !value.isEmpty else {
            throw ExternalWorkspaceDeepLinkError.missingQueryItem(key)
        }

        let decodedData: Data
        if let data = decodeBase64URL(value) {
            decodedData = data
        } else {
            throw ExternalWorkspaceDeepLinkError.invalidBase64Payload(key)
        }

        guard let decodedPath = String(data: decodedData, encoding: .utf8) else {
            throw ExternalWorkspaceDeepLinkError.invalidUTF8Payload(key)
        }

        guard decodedPath.hasPrefix("/") else {
            throw ExternalWorkspaceDeepLinkError.pathNotAbsolute(key)
        }

        return decodedPath
    }

    private static func decodeBase64URL(_ value: String) -> Data? {
        var normalized = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder != 0 {
            normalized += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: normalized)
    }
}
