// SPDX-License-Identifier: MIT

import Foundation

/// URL validation shared by local A2UI functions and media components.
///
/// A2UI payloads can cross trust boundaries. Only HTTP(S) URLs are allowed for
/// renderer-initiated side effects or network media loads.
public enum A2UISafeURL {
    public static let allowedSchemes: Set<String> = ["http", "https"]

    public static func resolve(_ rawValue: String, baseURL: URL? = nil) throws -> URL {
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
        guard let scheme = resolved.scheme?.lowercased(), allowedSchemes.contains(scheme) else {
            throw A2uiExpressionError("Unsupported URL scheme: \(resolved.scheme ?? "none")", expression: "url")
        }
        return resolved
    }

    public static func allowed(_ rawValue: String, baseURL: URL? = nil) -> URL? {
        try? resolve(rawValue, baseURL: baseURL)
    }
}
