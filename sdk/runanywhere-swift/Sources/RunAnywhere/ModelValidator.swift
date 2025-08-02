import Foundation

// MARK: - Compatibility Layer

/// Legacy UnifiedModelValidator - now uses ValidationService
public class UnifiedModelValidator {
    private let validationService = ValidationService()

    public init() {}

    public func validateModel(_ model: ModelInfo, at path: URL) async throws -> ValidationResult {
        return try await validationService.validateModel(model, at: path)
    }

    public func validateChecksum(_ file: URL, expected: String) async throws -> Bool {
        return try await validationService.validateChecksum(file, expected: expected)
    }

    public func validateFormat(_ file: URL, expectedFormat: ModelFormat) async throws -> Bool {
        return try await validationService.validateFormat(file, expectedFormat: expectedFormat)
    }

    public func validateDependencies(_ model: ModelInfo) async throws -> [MissingDependency] {
        return try await validationService.validateDependencies(model)
    }
}

// Legacy exports for backward compatibility
public typealias ModelFormatDetector = FormatDetectorImpl
