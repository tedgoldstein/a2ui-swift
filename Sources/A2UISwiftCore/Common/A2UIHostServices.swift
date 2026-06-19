// SPDX-License-Identifier: MIT

import Foundation

/// Host-owned service hooks for side effects requested by rendered A2UI.
///
/// The renderer validates and requests; the embedding app decides whether to
/// perform the side effect.
public struct A2UIHostServices: Sendable {
    public typealias OpenURLHandler = @Sendable (URL) throws -> Void

    public var urlPolicy: A2UIURLPolicy
    private let openURLHandler: OpenURLHandler?

    public init(
        urlPolicy: A2UIURLPolicy = .strict,
        openURL: OpenURLHandler? = nil
    ) {
        self.urlPolicy = urlPolicy
        self.openURLHandler = openURL
    }

    public static let denying = A2UIHostServices()

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
}
