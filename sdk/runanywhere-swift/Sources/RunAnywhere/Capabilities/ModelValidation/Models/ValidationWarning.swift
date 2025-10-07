import Foundation

/// Validation warning
public struct ValidationWarning {
    public let code: String
    public let message: String
    public let severity: Severity

    public enum Severity {
        case low
        case medium
        case high
    }

    public init(code: String, message: String, severity: Severity = .medium) {
        self.code = code
        self.message = message
        self.severity = severity
    }
}
