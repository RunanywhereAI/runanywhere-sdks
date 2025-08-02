import Foundation

/// Service for orchestrating model validation
public class ValidationService: ModelValidator {

    // MARK: - Properties

    private let formatDetector: FormatDetector
    private let metadataExtractor: MetadataExtractor
    private let checksumValidator: ChecksumValidator
    private let dependencyChecker: DependencyChecker

    private let coreMLValidator = CoreMLValidator()
    private let tfliteValidator = TFLiteValidator()
    private let onnxValidator = ONNXValidator()
    private let ggufValidator = GGUFValidator()
    private let mlxValidator = MLXValidator()

    private let logger = SDKLogger(category: "ValidationService")

    // MARK: - Initialization

    public init(
        formatDetector: FormatDetector? = nil,
        metadataExtractor: MetadataExtractor? = nil,
        checksumValidator: ChecksumValidator? = nil,
        dependencyChecker: DependencyChecker? = nil
    ) {
        self.formatDetector = formatDetector ?? FormatDetectorImpl()
        self.metadataExtractor = metadataExtractor ?? MetadataExtractorImpl()
        self.checksumValidator = checksumValidator ?? ChecksumValidator()

        // Get framework registry from service container
        let frameworkRegistry = ServiceContainer.shared.frameworkAdapterRegistry
        self.dependencyChecker = dependencyChecker ?? DependencyChecker(frameworkRegistry: frameworkRegistry)
    }

    // MARK: - ModelValidator Protocol

    public func validateModel(_ model: ModelInfo, at path: URL) async throws -> ValidationResult {
        var warnings: [ValidationWarning] = []
        var errors: [ValidationError] = []

        logger.info("Starting validation for model: \(model.id)")

        // Check if file exists
        guard FileManager.default.fileExists(atPath: path.path) else {
            errors.append(.corruptedFile(reason: "File not found at path"))
            return ValidationResult(isValid: false, errors: errors)
        }

        // Validate file size if provided
        if let expectedSize = model.downloadSize {
            let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
            if let fileSize = attributes[.size] as? Int64 {
                if fileSize != expectedSize {
                    warnings.append(ValidationWarning(
                        code: "size_mismatch",
                        message: "File size differs from expected",
                        severity: .medium
                    ))
                }
            }
        }

        // Validate checksum if provided
        if let expectedChecksum = model.checksum {
            let isValid = try await validateChecksum(path, expected: expectedChecksum)
            if !isValid {
                let actual = try await checksumValidator.calculateChecksum(for: path, using: .sha256)
                errors.append(.checksumMismatch(expected: expectedChecksum, actual: actual))
            }
        }

        // Validate format
        let formatValid = try await validateFormat(path, expectedFormat: model.format)
        if !formatValid {
            let detectedFormat = formatDetector.detectFormat(at: path)
            errors.append(.invalidFormat(expected: model.format, actual: detectedFormat?.rawValue))
        }

        // Check dependencies
        let missingDeps = try await validateDependencies(model)
        if !missingDeps.isEmpty {
            errors.append(.missingDependencies(missingDeps))
        }

        // Extract and validate metadata
        let metadata = await metadataExtractor.extractMetadata(from: path, format: model.format)

        // Framework-specific validation
        if let frameworkErrors = try await validateFrameworkSpecific(model, at: path) {
            errors.append(contentsOf: frameworkErrors)
        }

        // Check hardware requirements
        if let hwWarnings = validateHardwareRequirements(model, metadata: metadata) {
            warnings.append(contentsOf: hwWarnings)
        }

        logger.info("Validation complete. Errors: \(errors.count), Warnings: \(warnings.count)")

        return ValidationResult(
            isValid: errors.isEmpty,
            warnings: warnings,
            errors: errors,
            metadata: metadata
        )
    }

    public func validateChecksum(_ file: URL, expected: String) async throws -> Bool {
        return try await checksumValidator.validate(file, expected: expected)
    }

    public func validateFormat(_ file: URL, expectedFormat: ModelFormat) async throws -> Bool {
        let detected = formatDetector.detectFormat(at: file)
        return detected == expectedFormat
    }

    public func validateDependencies(_ model: ModelInfo) async throws -> [MissingDependency] {
        return try await dependencyChecker.checkDependencies(for: model)
    }

    // MARK: - Private Methods

    private func validateFrameworkSpecific(_ model: ModelInfo, at path: URL) async throws -> [ValidationError]? {
        switch model.format {
        case .mlmodel, .mlpackage:
            return try await coreMLValidator.validate(at: path)
        case .tflite:
            return try await tfliteValidator.validate(at: path)
        case .onnx:
            return try await onnxValidator.validate(at: path)
        case .gguf:
            return try await ggufValidator.validate(at: path)
        case .mlx:
            return try await mlxValidator.validate(at: path)
        default:
            return nil
        }
    }

    private func validateHardwareRequirements(_ model: ModelInfo, metadata: ModelMetadata?) -> [ValidationWarning]? {
        var warnings: [ValidationWarning] = []

        // Check memory requirements
        if let minMemory = metadata?.requirements?.minMemory {
            let availableMemory = ProcessInfo.processInfo.physicalMemory
            if Int64(availableMemory) < minMemory {
                warnings.append(ValidationWarning(
                    code: "insufficient_memory",
                    message: "Model requires \(ByteCountFormatter.string(fromByteCount: minMemory, countStyle: .memory))",
                    severity: .high
                ))
            }
        }

        // Check OS version requirements
        if let minOS = metadata?.requirements?.minOSVersion {
            let currentOS = ProcessInfo.processInfo.operatingSystemVersion
            let currentOSString = "\(currentOS.majorVersion).\(currentOS.minorVersion)"
            if currentOSString.compare(minOS, options: .numeric) == .orderedAscending {
                warnings.append(ValidationWarning(
                    code: "os_version_mismatch",
                    message: "Model requires OS version \(minOS) or higher",
                    severity: .medium
                ))
            }
        }

        return warnings.isEmpty ? nil : warnings
    }
}
