// SPDX-License-Identifier: MIT

import Foundation

/// Errors raised while extracting A2UI messages from MCP resource payloads.
public enum A2UIMCPPayloadError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedMimeType(String?)
    case missingText
    case invalidResourceShape

    public var errorDescription: String? {
        switch self {
        case .unsupportedMimeType(let mimeType):
            return "Unsupported MCP resource MIME type: \(mimeType ?? "nil")"
        case .missingText:
            return "MCP A2UI resource is missing text content."
        case .invalidResourceShape:
            return "MCP content is not a resource or embedded resource object."
        }
    }
}

/// Thin MCP ingress helper for `application/a2ui+json` resources.
///
/// This intentionally avoids depending on a specific MCP Swift SDK. Host apps can
/// pass dictionaries decoded from MCP `ResourceContents` or Tool-result
/// `EmbeddedResource` objects and route the resulting messages to their renderer.
public enum A2UIMCPPayload {
    public static let mimeType = "application/a2ui+json"

    public static func messages(fromText text: String, mimeType: String?) throws -> [A2uiMessage] {
        try requireA2UIMimeType(mimeType)
        guard let data = text.data(using: .utf8) else {
            throw A2UIMCPPayloadError.missingText
        }

        let decoder = JSONDecoder()
        if let single = try? decoder.decode(A2uiMessage.self, from: data) {
            return [single]
        }
        return try decoder.decode([A2uiMessage].self, from: data)
    }

    public static func messages(fromResource resource: [String: AnyCodable]) throws -> [A2uiMessage] {
        let mimeType = resource["mimeType"]?.stringValue ?? resource["mime_type"]?.stringValue
        let text = resource["text"]?.stringValue ?? resource["content"]?.stringValue
        guard let text else { throw A2UIMCPPayloadError.missingText }
        return try messages(fromText: text, mimeType: mimeType)
    }

    public static func messages(fromEmbeddedResource content: [String: AnyCodable]) throws -> [A2uiMessage] {
        if let resource = content["resource"]?.dictionaryValue {
            return try messages(fromResource: resource)
        }
        if content["mimeType"] != nil || content["mime_type"] != nil {
            return try messages(fromResource: content)
        }
        throw A2UIMCPPayloadError.invalidResourceShape
    }

    private static func requireA2UIMimeType(_ mimeType: String?) throws {
        let normalized = mimeType?
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalized == Self.mimeType else {
            throw A2UIMCPPayloadError.unsupportedMimeType(mimeType)
        }
    }
}

public extension A2UITransportAdapter {
    /// Feeds A2UI messages carried by an MCP Resource or EmbeddedResource object.
    func addMCPResource(_ content: [String: AnyCodable]) throws {
        for message in try A2UIMCPPayload.messages(fromEmbeddedResource: content) {
            addMessage(message)
        }
    }
}
