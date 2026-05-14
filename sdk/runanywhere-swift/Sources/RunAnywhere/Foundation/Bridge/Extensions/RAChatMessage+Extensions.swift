//
//  RAChatMessage+Extensions.swift
//  RunAnywhere SDK
//
//  Extensions for proto-generated chat types.
//


// MARK: - MessageRole convenience

public extension RAMessageRole {
    /// Canonical lowercase wire string (JSON compat). Mirrors the convention
    /// used by hand-written enums in Kotlin / Dart / RN / Web.
    var wireString: String {
        switch self {
        case .user:        return "user"
        case .assistant:   return "assistant"
        case .system:      return "system"
        case .tool:        return "tool"
        default:           return "unspecified"
        }
    }

    /// Initialize from a wire string (e.g. parsed from JSON).
    init?(wireString: String) {
        switch wireString.lowercased() {
        case "user":        self = .user
        case "assistant":   self = .assistant
        case "system":      self = .system
        case "tool":        self = .tool
        default:            return nil
        }
    }
}

extension RAMessageRole: Codable {
    public init(from decoder: Swift.Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RAMessageRole(wireString: raw) ?? .unspecified
    }

    public func encode(to encoder: Swift.Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.wireString)
    }
}
