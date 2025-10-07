import Foundation
#if canImport(CoreML)
import CoreML
#endif

/// Validator for Core ML models
public class CoreMLValidator {

    // MARK: - Properties

    private let logger = SDKLogger(category: "CoreMLValidator")

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Validates a Core ML model
    /// - Parameter url: The URL of the model file
    /// - Returns: Array of validation errors, nil if valid
    public func validate(at url: URL) async throws -> [ValidationError]? {
        #if canImport(CoreML)
        var errors: [ValidationError] = []

        logger.debug("Validating Core ML model: \(url.lastPathComponent)")

        do {
            let compiledURL: URL

            if url.pathExtension == "mlmodelc" {
                compiledURL = url
            } else {
                // Try to compile the model
                logger.debug("Compiling Core ML model")
                compiledURL = try MLModel.compileModel(at: url)
            }

            // Try to load the model
            _ = try MLModel(contentsOf: compiledURL)
            logger.info("Core ML model validated successfully")

            // Clean up compiled model if we created it
            if url.pathExtension != "mlmodelc" {
                try? FileManager.default.removeItem(at: compiledURL)
            }

        } catch let error as NSError {
            let reason = interpretCoreMLError(error)
            errors.append(.corruptedFile(reason: reason))
            logger.error("Core ML validation failed: \(reason)")
        }

        return errors.isEmpty ? nil : errors
        #else
        logger.warning("Core ML not available on this platform")
        return [.invalidFormat(expected: .mlmodel, actual: "unsupported")]
        #endif
    }

    // MARK: - Private Methods

    #if canImport(CoreML)
    private func interpretCoreMLError(_ error: NSError) -> String {
        // Interpret common Core ML errors
        switch error.code {
        case 0:
            return "Model file is corrupted or invalid"
        case 1:
            return "Model format is not supported"
        case 2:
            return "Model requires a newer version of Core ML"
        case 3:
            return "Model compilation failed"
        case 4:
            return "Model has invalid input/output specifications"
        default:
            return "Failed to load Core ML model: \(error.localizedDescription)"
        }
    }
    #endif
}
