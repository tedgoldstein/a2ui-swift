// SPDX-License-Identifier: MIT

import Foundation

/// The reason an A2UI payload wants to resolve a URL.
public enum A2UIURLPurpose: String, Sendable {
    case openURL
    case image
    case audio
    case video
}

/// Host-configurable policy for URLs that can trigger platform side effects or
/// network media loads.
public struct A2UIURLPolicy: Equatable, Sendable {
    public var allowedSchemes: Set<String>
    public var allowedHosts: Set<String>?
    public var deniedHosts: Set<String>
    public var allowsUserInfo: Bool
    public var allowsLocalhost: Bool
    public var allowsPrivateNetworkHosts: Bool
    public var allowsLinkLocalHosts: Bool
    public var allowsDotLocalHosts: Bool
    public var allowsRelativeHostChanges: Bool

    public init(
        allowedSchemes: Set<String> = A2UISafeURL.allowedSchemes,
        allowedHosts: Set<String>? = nil,
        deniedHosts: Set<String> = [],
        allowsUserInfo: Bool = false,
        allowsLocalhost: Bool = false,
        allowsPrivateNetworkHosts: Bool = false,
        allowsLinkLocalHosts: Bool = false,
        allowsDotLocalHosts: Bool = false,
        allowsRelativeHostChanges: Bool = false
    ) {
        self.allowedSchemes = Set(allowedSchemes.map { $0.lowercased() })
        self.allowedHosts = allowedHosts.map { Set($0.map { Self.normalizedHost($0) }) }
        self.deniedHosts = Set(deniedHosts.map { Self.normalizedHost($0) })
        self.allowsUserInfo = allowsUserInfo
        self.allowsLocalhost = allowsLocalhost
        self.allowsPrivateNetworkHosts = allowsPrivateNetworkHosts
        self.allowsLinkLocalHosts = allowsLinkLocalHosts
        self.allowsDotLocalHosts = allowsDotLocalHosts
        self.allowsRelativeHostChanges = allowsRelativeHostChanges
    }

    public static let strict = A2UIURLPolicy()

    /// Useful for trusted development fixtures. Do not use this for untrusted
    /// agent or MCP-provided UI.
    public static let permissiveHTTP = A2UIURLPolicy(
        allowsUserInfo: true,
        allowsLocalhost: true,
        allowsPrivateNetworkHosts: true,
        allowsLinkLocalHosts: true,
        allowsDotLocalHosts: true,
        allowsRelativeHostChanges: true
    )

    public func validate(_ url: URL, baseURL: URL? = nil, purpose: A2UIURLPurpose = .openURL) throws {
        guard let scheme = url.scheme?.lowercased(), allowedSchemes.contains(scheme) else {
            throw A2uiExpressionError(
                "Unsupported URL scheme for \(purpose.rawValue): \(url.scheme ?? "none")",
                expression: "url"
            )
        }
        guard let host = url.host, !host.isEmpty else {
            throw A2uiExpressionError("URL for \(purpose.rawValue) must include a host.", expression: "url")
        }

        let normalized = Self.normalizedHost(host)
        if !allowsUserInfo && (url.user != nil || url.password != nil) {
            throw A2uiExpressionError("URL userinfo is not allowed for \(purpose.rawValue).", expression: "url")
        }
        if let allowedHosts, !allowedHosts.contains(normalized) {
            throw A2uiExpressionError("URL host is not allowed for \(purpose.rawValue): \(host)", expression: "url")
        }
        if deniedHosts.contains(normalized) {
            throw A2uiExpressionError("URL host is denied for \(purpose.rawValue): \(host)", expression: "url")
        }
        if let baseURL, !allowsRelativeHostChanges,
           let baseHost = baseURL.host.map(Self.normalizedHost),
           baseHost != normalized {
            throw A2uiExpressionError("URL host changes are not allowed for \(purpose.rawValue).", expression: "url")
        }
        if !allowsLocalhost && Self.isLocalhost(normalized) {
            throw A2uiExpressionError("Localhost URLs are not allowed for \(purpose.rawValue).", expression: "url")
        }
        if !allowsDotLocalHosts && Self.isDotLocalHost(normalized) {
            throw A2uiExpressionError(".local URLs are not allowed for \(purpose.rawValue).", expression: "url")
        }
        if let network = Self.ipv4NetworkKind(normalized) {
            switch network {
            case .localhost where !allowsLocalhost:
                throw A2uiExpressionError("Loopback URLs are not allowed for \(purpose.rawValue).", expression: "url")
            case .privateNetwork where !allowsPrivateNetworkHosts:
                throw A2uiExpressionError("Private network URLs are not allowed for \(purpose.rawValue).", expression: "url")
            case .linkLocal where !allowsLinkLocalHosts:
                throw A2uiExpressionError("Link-local URLs are not allowed for \(purpose.rawValue).", expression: "url")
            default:
                break
            }
        }
        if let network = Self.ipv6NetworkKind(normalized) {
            switch network {
            case .localhost where !allowsLocalhost:
                throw A2uiExpressionError("Loopback URLs are not allowed for \(purpose.rawValue).", expression: "url")
            case .privateNetwork where !allowsPrivateNetworkHosts:
                throw A2uiExpressionError("Private network URLs are not allowed for \(purpose.rawValue).", expression: "url")
            case .linkLocal where !allowsLinkLocalHosts:
                throw A2uiExpressionError("Link-local URLs are not allowed for \(purpose.rawValue).", expression: "url")
            default:
                break
            }
        }
    }

    private enum NetworkKind {
        case localhost
        case privateNetwork
        case linkLocal
    }

    private static func normalizedHost(_ host: String) -> String {
        host
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func isLocalhost(_ host: String) -> Bool {
        host == "localhost" || host.hasSuffix(".localhost")
    }

    private static func isDotLocalHost(_ host: String) -> Bool {
        host == "local" || host.hasSuffix(".local")
    }

    private static func ipv4NetworkKind(_ host: String) -> NetworkKind? {
        let pieces = host.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 4 else { return nil }
        var octets: [Int] = []
        for piece in pieces {
            guard let value = Int(piece), (0...255).contains(value) else { return nil }
            octets.append(value)
        }

        switch (octets[0], octets[1]) {
        case (0, _), (127, _):
            return .localhost
        case (10, _), (192, 168):
            return .privateNetwork
        case (172, 16...31), (100, 64...127), (198, 18...19):
            return .privateNetwork
        case (169, 254):
            return .linkLocal
        default:
            return nil
        }
    }

    private static func ipv6NetworkKind(_ host: String) -> NetworkKind? {
        if host == "::1" || host == "0:0:0:0:0:0:0:1" {
            return .localhost
        }
        if host.hasPrefix("::ffff:") {
            return ipv4NetworkKind(String(host.dropFirst("::ffff:".count)))
        }
        guard let first = host.split(separator: ":", maxSplits: 1).first,
              let hextet = Int(first, radix: 16)
        else { return nil }
        if (hextet & 0xffc0) == 0xfe80 {
            return .linkLocal
        }
        if (hextet & 0xfe00) == 0xfc00 {
            return .privateNetwork
        }
        return nil
    }
}

/// URL validation shared by local A2UI functions and media components.
///
/// A2UI payloads can cross trust boundaries. Host applications should inject a
/// policy appropriate for the provenance of the payload.
public enum A2UISafeURL {
    public static let allowedSchemes: Set<String> = ["http", "https"]

    public static func resolve(
        _ rawValue: String,
        baseURL: URL? = nil,
        purpose: A2UIURLPurpose = .openURL,
        policy: A2UIURLPolicy = .strict
    ) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw A2uiExpressionError("Invalid URL specified: \(rawValue)", expression: "url")
        }

        let url: URL?
        if let baseURL {
            url = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
        } else {
            url = URL(string: trimmed)
        }

        guard let resolved = url else {
            throw A2uiExpressionError("Invalid URL specified: \(rawValue)", expression: "url")
        }
        try policy.validate(resolved, baseURL: baseURL, purpose: purpose)
        return resolved
    }

    public static func allowed(
        _ rawValue: String,
        baseURL: URL? = nil,
        purpose: A2UIURLPurpose = .openURL,
        policy: A2UIURLPolicy = .strict
    ) -> URL? {
        try? resolve(rawValue, baseURL: baseURL, purpose: purpose, policy: policy)
    }
}
