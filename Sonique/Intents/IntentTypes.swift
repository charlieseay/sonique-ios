import Foundation

/// Response from SoniqueBar POST /intent/<name>
struct IntentAPIResponse: Codable, Equatable {
    let success: Bool
    let message: String
    let error: String?
    let data: [String: String]?

    init(success: Bool, message: String, error: String? = nil, data: [String: String]? = nil) {
        self.success = success
        self.message = message
        self.error = error
        self.data = data
    }
}

/// Result surfaced to App Intent perform() handlers.
struct IntentBarResult: Equatable {
    let success: Bool
    let message: String
    let errorCode: String?

    static let unreachable = IntentBarResult(
        success: false,
        message: "I can't reach the brain right now.",
        errorCode: "unreachable"
    )
}

/// Validates intent parameters before they are sent to SoniqueBar.
enum IntentParameterValidator {
    static let maxMessageLength = 4000
    static let maxTitleLength = 500

    static func validateMessage(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Message cannot be empty." }
        if trimmed.count > maxMessageLength {
            return "Message is too long (max \(maxMessageLength) characters)."
        }
        return nil
    }

    static func validateTitle(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Title cannot be empty." }
        if trimmed.count > maxTitleLength {
            return "Title is too long (max \(maxTitleLength) characters)."
        }
        return nil
    }

    /// Channel names: alphanumeric, dash, underscore only — no shell metacharacters.
    static func sanitizeChannel(_ channel: String) -> String {
        let stripped = channel.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(stripped.unicodeScalars.filter { allowed.contains($0) })
    }

    static func sanitizeRepo(_ repo: String) -> String {
        let trimmed = repo.trimmingCharacters(in: .whitespacesAndNewlines)
        let stopChars = CharacterSet(charactersIn: ";|&$`\"'<>()")
        let truncated = String(trimmed.unicodeScalars.prefix { !stopChars.contains($0) })
        let segmentAllowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let parts = truncated.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return "" }

        func cleanSegment(_ segment: String) -> String {
            let cleaned = String(segment.unicodeScalars.filter { segmentAllowed.contains($0) })
            return cleaned.contains("..") ? "" : cleaned
        }

        let owner = cleanSegment(parts[0])
        let name = cleanSegment(parts[1])
        guard !owner.isEmpty, !name.isEmpty else { return "" }
        return "\(owner)/\(name)"
    }
}

/// Parses SoniqueBar intent JSON responses (testable without network).
enum IntentResponseParser {
    static func parse(_ data: Data) -> IntentAPIResponse? {
        try? JSONDecoder().decode(IntentAPIResponse.self, from: data)
    }

    static func parseFallback(_ data: Data) -> IntentAPIResponse? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? String ?? json["response"] as? String else {
            return nil
        }
        let success = json["success"] as? Bool ?? true
        return IntentAPIResponse(
            success: success,
            message: message,
            error: json["error"] as? String,
            data: json["data"] as? [String: String]
        )
    }
}
