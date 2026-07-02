// SPDX-License-Identifier: MIT

import Foundation

/// Host-owned service hooks for side effects requested by rendered A2UI.
///
/// The renderer validates and requests; the embedding app decides whether to
/// perform the side effect.
public struct A2UIHostServices: Sendable {
    public typealias OpenURLHandler = @Sendable (URL) throws -> Void
    public typealias MediaURLHandler = @Sendable (_ url: URL, _ purpose: A2UIURLPurpose) throws -> URL

    public var urlPolicy: A2UIURLPolicy
    private let openURLHandler: OpenURLHandler?
    private let mediaURLHandler: MediaURLHandler?

    public init(
        urlPolicy: A2UIURLPolicy = .strict,
        openURL: OpenURLHandler? = nil,
        mediaURL: MediaURLHandler? = nil
    ) {
        self.urlPolicy = urlPolicy
        self.openURLHandler = openURL
        self.mediaURLHandler = mediaURL
    }

    public static let denying = A2UIHostServices()

    /// Unsafe convenience for trusted local fixtures that allows renderers to
    /// load validated media URLs directly. Never use this for agent/MCP
    /// provenance: direct renderer fetches can still hit DNS-rebinding hosts
    /// and leak client network metadata.
    public static let unsafeDirectMedia = A2UIHostServices(mediaURL: { url, _ in url })

    public func resolveURL(
        _ rawValue: String,
        baseURL: URL? = nil,
        purpose: A2UIURLPurpose
    ) throws -> URL {
        try A2UISafeURL.resolve(rawValue, baseURL: baseURL, purpose: purpose, policy: urlPolicy)
    }

    public func allowedURL(
        _ rawValue: String,
        baseURL: URL? = nil,
        purpose: A2UIURLPurpose
    ) -> URL? {
        try? resolveURL(rawValue, baseURL: baseURL, purpose: purpose)
    }

    public func openURL(_ url: URL) throws {
        try urlPolicy.validate(url, purpose: .openURL)
        guard let openURLHandler else {
            throw A2uiExpressionError("openUrl requires a host-provided URL handler.", expression: "openUrl")
        }
        try openURLHandler(url)
    }

    public func mediaURL(
        _ rawValue: String,
        baseURL: URL? = nil,
        purpose: A2UIURLPurpose
    ) throws -> URL {
        guard purpose != .openURL else {
            throw A2uiExpressionError("mediaURL is only for media URL purposes.", expression: "url")
        }
        let url = try resolveURL(rawValue, baseURL: baseURL, purpose: purpose)
        guard let mediaURLHandler else {
            throw A2uiExpressionError("Media URLs require a host-provided media handler.", expression: "url")
        }
        let resolved = try mediaURLHandler(url, purpose)
        try validateMediaHandlerOutput(resolved, purpose: purpose)
        return resolved
    }

    public func allowedMediaURL(
        _ rawValue: String,
        baseURL: URL? = nil,
        purpose: A2UIURLPurpose
    ) -> URL? {
        try? mediaURL(rawValue, baseURL: baseURL, purpose: purpose)
    }

    private func validateMediaHandlerOutput(_ url: URL, purpose: A2UIURLPurpose) throws {
        guard let scheme = url.scheme?.lowercased(), urlPolicy.allowedSchemes.contains(scheme) else {
            throw A2uiExpressionError(
                "Unsupported media handler URL scheme for \(purpose.rawValue): \(url.scheme ?? "none")",
                expression: "url"
            )
        }
        guard let host = url.host, !host.isEmpty else {
            throw A2uiExpressionError("Media handler URL for \(purpose.rawValue) must include a host.", expression: "url")
        }
        if !urlPolicy.allowsUserInfo && (url.user != nil || url.password != nil) {
            throw A2uiExpressionError("Media handler URL userinfo is not allowed for \(purpose.rawValue).", expression: "url")
        }
    }
}
