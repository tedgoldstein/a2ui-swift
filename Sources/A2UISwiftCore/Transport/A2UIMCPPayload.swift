// SPDX-License-Identifier: MIT

import Foundation

/// Errors raised while extracting A2UI messages from MCP resource payloads.
public enum A2UIMCPPayloadError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedMimeType(String?)
    case missingText
    case unsupportedBlob
    case payloadTooLarge(Int, Int)
    case invalidResourceShape
    case invalidJSON(singleMessageError: String, messageArrayError: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedMimeType(let mimeType):
            return "Unsupported MCP resource MIME type: \(mimeType ?? "nil")"
        case .missingText:
            return "MCP A2UI resource is missing text content."
        case .unsupportedBlob:
            return "MCP A2UI blob resources are not supported."
        case .payloadTooLarge(let byteCount, let maximumBytes):
            return "MCP A2UI payload is too large: \(byteCount) bytes exceeds \(maximumBytes)."
        case .invalidResourceShape:
            return "MCP content is not a resource or embedded resource object."
        case .invalidJSON(let singleMessageError, let messageArrayError):
            return "MCP A2UI JSON did not decode as a message or message array. Single: \(singleMessageError). Array: \(messageArrayError)."
        }
    }
}

/// SDK-neutral shape for an MCP text resource carrying A2UI JSON.
public struct A2UIMCPResource: Equatable, Sendable {
    public let uri: String?
    public let mimeType: String?
    public let text: String?
    public let blob: String?

    public init(
        uri: String? = nil,
        mimeType: String?,
        text: String? = nil,
        blob: String? = nil
    ) {
        self.uri = uri
        self.mimeType = mimeType
        self.text = text
        self.blob = blob
    }
}

/// Thin MCP ingress helper for `application/a2ui+json` resources.
///
/// This intentionally avoids depending on a specific MCP Swift SDK. Host apps can
/// pass dictionaries decoded from MCP `ResourceContents` or Tool-result
/// `EmbeddedResource` objects and route the resulting messages to their renderer.
public enum A2UIMCPPayload {
    public static let mimeType = "application/a2ui+json"
    public static let defaultMaximumPayloadBytes = 1_000_000

    public static func messages(
        fromText text: String,
        mimeType: String?,
        maximumPayloadBytes: Int = defaultMaximumPayloadBytes
    ) throws -> [A2uiMessage] {
        try requireA2UIMimeType(mimeType)
        let byteCount = text.utf8.count
        guard byteCount <= maximumPayloadBytes else {
            throw A2UIMCPPayloadError.payloadTooLarge(byteCount, maximumPayloadBytes)
        }
        let data = Data(text.utf8)

        let decoder = JSONDecoder()
        do {
            let single = try decoder.decode(A2uiMessage.self, from: data)
            return [single]
        } catch {
            let singleError = String(describing: error)
            do {
                return try decoder.decode([A2uiMessage].self, from: data)
            } catch {
                throw A2UIMCPPayloadError.invalidJSON(
                    singleMessageError: singleError,
                    messageArrayError: String(describing: error)
                )
            }
        }
    }

    public static func messages(
        fromResource resource: A2UIMCPResource,
        maximumPayloadBytes: Int = defaultMaximumPayloadBytes
    ) throws -> [A2uiMessage] {
        if resource.blob != nil {
            throw A2UIMCPPayloadError.unsupportedBlob
        }
        guard let text = resource.text else { throw A2UIMCPPayloadError.missingText }
        return try messages(fromText: text, mimeType: resource.mimeType, maximumPayloadBytes: maximumPayloadBytes)
    }

    public static func messages(
        fromResource resource: [String: AnyCodable],
        maximumPayloadBytes: Int = defaultMaximumPayloadBytes
    ) throws -> [A2uiMessage] {
        let resource = try decodeResource(resource)
        return try messages(fromResource: resource, maximumPayloadBytes: maximumPayloadBytes)
    }

    public static func messages(
        fromEmbeddedResource content: [String: AnyCodable],
        maximumPayloadBytes: Int = defaultMaximumPayloadBytes
    ) throws -> [A2uiMessage] {
        if let resource = content["resource"]?.dictionaryValue {
            return try messages(fromResource: resource, maximumPayloadBytes: maximumPayloadBytes)
        }
        if content["mimeType"] != nil || content["text"] != nil || content["blob"] != nil {
            return try messages(fromResource: content, maximumPayloadBytes: maximumPayloadBytes)
        }
        throw A2UIMCPPayloadError.invalidResourceShape
    }

    private static func decodeResource(_ resource: [String: AnyCodable]) throws -> A2UIMCPResource {
        let uri = resource["uri"]?.stringValue
        let mimeType = resource["mimeType"]?.stringValue
        let text = resource["text"]?.stringValue
        let blob = resource["blob"]?.stringValue
        if blob != nil && text == nil {
            return A2UIMCPResource(uri: uri, mimeType: mimeType, blob: blob)
        }
        guard let text else { throw A2UIMCPPayloadError.missingText }
        return A2UIMCPResource(uri: uri, mimeType: mimeType, text: text, blob: blob)
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
    func addMCPResource(
        _ content: [String: AnyCodable],
        maximumPayloadBytes: Int = A2UIMCPPayload.defaultMaximumPayloadBytes
    ) throws {
        for message in try A2UIMCPPayload.messages(
            fromEmbeddedResource: content,
            maximumPayloadBytes: maximumPayloadBytes
        ) {
            addMessage(message)
        }
    }
}
