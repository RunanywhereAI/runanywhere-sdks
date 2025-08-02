import Foundation

/// Service for orchestrating model validation
public class ValidationService {

    public init() {}

    /// Validate a model at the given URL
    public func validate(_ url: URL) async throws -> ValidationResult {
        var warnings: [ValidationWarning] = []
        var errors: [ValidationError] = []
        var metadata: ModelMetadata?

        // Check file exists
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            errors.append(.corruptedFile(reason: "File does not exist"))
            return ValidationResult(
                isValid: false,
                warnings: warnings,
                errors: errors,
                metadata: nil
            )
        }

        // Check file size
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[.size] as? Int64 {
                if fileSize == 0 {
                    errors.append(.corruptedFile(reason: "File is empty"))
                } else if fileSize < 1000 {
                    warnings.append(
                        ValidationWarning(
                            code: "small_file",
                            message: "File size is unusually small",
                            severity: .high
                        )
                    )
                }
            }
        } catch {
            warnings.append(
                ValidationWarning(
                    code: "size_check_failed",
                    message: "Could not verify file size",
                    severity: .low
                )
            )
        }

        // Basic format validation
        let pathExtension = url.pathExtension.lowercased()
        if pathExtension.isEmpty {
            warnings.append(
                ValidationWarning(
                    code: "no_extension",
                    message: "File has no extension",
                    severity: .medium
                )
            )
        }

        // Try to extract metadata
        metadata = ModelMetadata(
            modelType: pathExtension,
            architecture: "unknown"
        )

        let isValid = errors.isEmpty

        return ValidationResult(
            isValid: isValid,
            warnings: warnings,
            errors: errors,
            metadata: metadata
        )
    }
}
