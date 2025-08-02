import Foundation

/// Protocol for model validation
public protocol ModelValidator {
    /// Validate a model at the given URL
    /// - Parameter url: URL to the model file
    /// - Returns: Validation result
    func validate(_ url: URL) async throws -> ValidationResult
}
