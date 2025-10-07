import Foundation

/// Privacy mode settings
public enum PrivacyMode: String, Codable, Sendable {
    /// Standard privacy protection
    case standard

    /// Enhanced privacy with stricter PII detection
    case strict

    /// Custom privacy rules
    case custom
}
