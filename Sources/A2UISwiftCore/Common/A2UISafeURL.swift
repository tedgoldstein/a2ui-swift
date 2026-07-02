// SPDX-License-Identifier: MIT

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

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

    /// Unsafe escape hatch for trusted development fixtures. This permits URL
    /// credentials, localhost, private/link-local networks, `.local` names, and
    /// relative URL host changes. Do not use it for untrusted agent or
    /// MCP-provided UI.
    public static let unsafeAllowLocalNetwork = A2UIURLPolicy(
        allowsUserInfo: true,
        allowsLocalhost: true,
        allowsPrivateNetworkHosts: true,
        allowsLinkLocalHosts: true,
        allowsDotLocalHosts: true,
        allowsRelativeHostChanges: true
    )

    @available(*, deprecated, renamed: "unsafeAllowLocalNetwork")
    public static let permissiveHTTP = unsafeAllowLocalNetwork

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
        if let network = Self.networkKind(normalized) {
            switch network {
            case .localhost where !allowsLocalhost:
                throw A2uiExpressionError("Loopback URLs are not allowed for \(purpose.rawValue).", expression: "url")
            case .privateNetwork where !allowsPrivateNetworkHosts:
                throw A2uiExpressionError("Private or reserved network URLs are not allowed for \(purpose.rawValue).", expression: "url")
            case .linkLocal where !allowsLinkLocalHosts:
                throw A2uiExpressionError("Link-local URLs are not allowed for \(purpose.rawValue).", expression: "url")
            default:
                break
            }
        } else if !allowsPrivateNetworkHosts && Self.isAmbiguousNumericHost(normalized) {
            throw A2uiExpressionError("Ambiguous numeric URL hosts are not allowed for \(purpose.rawValue).", expression: "url")
        }
    }

    private enum NetworkKind {
        case localhost
        case privateNetwork
        case linkLocal
    }

    private static func normalizedHost(_ host: String) -> String {
        var normalized = host
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        while normalized.count > 1, normalized.hasSuffix(".") {
            normalized.removeLast()
        }
        return normalized
    }

    private static func isLocalhost(_ host: String) -> Bool {
        host == "localhost" || host.hasSuffix(".localhost")
    }

    private static func isDotLocalHost(_ host: String) -> Bool {
        host == "local" || host.hasSuffix(".local")
    }

    private static func networkKind(_ host: String) -> NetworkKind? {
        let hostWithoutZone = host.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? host
        if let octets = ipv4Octets(hostWithoutZone) {
            return ipv4NetworkKind(octets)
        }
        if let bytes = ipv6Bytes(hostWithoutZone) {
            return ipv6NetworkKind(bytes)
        }
        return nil
    }

    private static func ipv4Octets(_ host: String) -> [UInt8]? {
        #if canImport(Darwin) || canImport(Glibc)
        var address = in_addr()
        guard inet_aton(host, &address) == 1 else { return nil }
        return withUnsafeBytes(of: address) { Array($0) }
        #else
        return nil
        #endif
    }

    private static func ipv6Bytes(_ host: String) -> [UInt8]? {
        #if canImport(Darwin) || canImport(Glibc)
        var address = in6_addr()
        guard inet_pton(AF_INET6, host, &address) == 1 else { return nil }
        return withUnsafeBytes(of: address) { Array($0) }
        #else
        return nil
        #endif
    }

    private static func ipv4NetworkKind(_ octets: [UInt8]) -> NetworkKind? {
        guard octets.count == 4 else { return nil }

        switch (octets[0], octets[1], octets[2]) {
        case (0, _, _), (127, _, _):
            return .localhost
        case (10, _, _), (192, 168, _):
            return .privateNetwork
        case (172, 16...31, _), (100, 64...127, _), (198, 18...19, _):
            return .privateNetwork
        case (192, 0, 0), (192, 0, 2), (198, 51, 100), (203, 0, 113):
            return .privateNetwork
        case (224...255, _, _):
            return .privateNetwork
        case (169, 254, _):
            return .linkLocal
        default:
            return nil
        }
    }

    private static func ipv6NetworkKind(_ bytes: [UInt8]) -> NetworkKind? {
        guard bytes.count == 16 else { return nil }
        if bytes.allSatisfy({ $0 == 0 }) {
            return .localhost
        }
        if bytes[0..<15].allSatisfy({ $0 == 0 }), bytes[15] == 1 {
            return .localhost
        }
        if bytes[0..<10].allSatisfy({ $0 == 0 }),
           bytes[10] == 0xff,
           bytes[11] == 0xff {
            return ipv4NetworkKind(Array(bytes[12..<16]))
        }
        if bytes[0..<12].allSatisfy({ $0 == 0 }),
           bytes[12..<16].contains(where: { $0 != 0 }) {
            return ipv4NetworkKind(Array(bytes[12..<16]))
        }
        if bytes[0] == 0xfe, (bytes[1] & 0xc0) == 0x80 {
            return .linkLocal
        }
        if (bytes[0] & 0xfe) == 0xfc || bytes[0] == 0xff {
            return .privateNetwork
        }
        if bytes[0] == 0x20, bytes[1] == 0x01, bytes[2] == 0x0d, bytes[3] == 0xb8 {
            return .privateNetwork
        }
        return nil
    }

    private static func isAmbiguousNumericHost(_ host: String) -> Bool {
        if isCanonicalDottedDecimalIPv4(host) {
            return false
        }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty, labels.allSatisfy({ !$0.isEmpty }) else { return false }
        return labels.allSatisfy { label in
            let lower = label.lowercased()
            if lower.hasPrefix("0x") {
                return containsOnly(lower.dropFirst(2), allowed: .a2uiHexDigits)
            }
            return containsOnly(lower[...], allowed: .decimalDigits)
        }
    }

    private static func isCanonicalDottedDecimalIPv4(_ host: String) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count == 4 else { return false }
        return labels.allSatisfy { label in
            guard containsOnly(label, allowed: .decimalDigits),
                  let value = Int(label),
                  (0...255).contains(value)
            else { return false }
            return label == "0" || !label.hasPrefix("0")
        }
    }

    private static func containsOnly<S: StringProtocol>(_ text: S, allowed: CharacterSet) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

private extension CharacterSet {
    static let a2uiHexDigits = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
}

/// URL validation shared by local A2UI functions and media components.
///
/// A2UI payloads can cross trust boundaries. Host applications should inject a
/// policy appropriate for the provenance of the payload. Host-string validation
/// is defense-in-depth only: DNS rebinding can still make a public hostname
/// resolve to a private address at connection time, so untrusted media should be
/// delegated through host-owned fetch/proxy/cache services.
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
