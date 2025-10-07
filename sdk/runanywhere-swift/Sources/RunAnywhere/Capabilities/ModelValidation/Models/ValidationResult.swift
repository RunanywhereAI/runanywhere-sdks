import Foundation

/// Result of model validation
public struct ValidationResult {
    public let isValid: Bool
    public let warnings: [ValidationWarning]
    public let errors: [ValidationError]
    public let metadata: ModelMetadata?

    public init(
        isValid: Bool,
        warnings: [ValidationWarning] = [],
        errors: [ValidationError] = [],
        metadata: ModelMetadata? = nil
    ) {
        self.isValid = isValid
        self.warnings = warnings
        self.errors = errors
        self.metadata = metadata
    }
}
