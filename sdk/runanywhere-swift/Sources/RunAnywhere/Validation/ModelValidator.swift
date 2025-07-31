import Foundation
import CryptoKit
#if canImport(CoreML)
import CoreML
#endif

/// Protocol for model validation operations
public protocol ModelValidator {
    func validateModel(_ model: ModelInfo, at path: URL) async throws -> ValidationResult
    func validateChecksum(_ file: URL, expected: String) async throws -> Bool
    func validateFormat(_ file: URL, expectedFormat: ModelFormat) async throws -> Bool
    func validateDependencies(_ model: ModelInfo) async throws -> [MissingDependency]
}

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

/// Validation error types
public enum ValidationError: LocalizedError {
    case checksumMismatch(expected: String, actual: String)
    case invalidFormat(expected: ModelFormat, actual: String?)
    case missingDependencies([MissingDependency])
    case corruptedFile(reason: String)
    case incompatibleVersion(required: String, found: String)
    case invalidMetadata(reason: String)
    case fileSizeMismatch(expected: Int64, actual: Int64)
    case missingRequiredFiles([String])
    case unsupportedArchitecture(String)
    case invalidSignature
    
    public var errorDescription: String? {
        switch self {
        case .checksumMismatch(let expected, let actual):
            return "Checksum mismatch: expected \(expected), got \(actual)"
        case .invalidFormat(let expected, let actual):
            return "Invalid format: expected \(expected.rawValue), got \(actual ?? "unknown")"
        case .missingDependencies(let deps):
            return "Missing dependencies: \(deps.map { $0.name }.joined(separator: ", "))"
        case .corruptedFile(let reason):
            return "File corrupted: \(reason)"
        case .incompatibleVersion(let required, let found):
            return "Incompatible version: requires \(required), found \(found)"
        case .invalidMetadata(let reason):
            return "Invalid metadata: \(reason)"
        case .fileSizeMismatch(let expected, let actual):
            return "File size mismatch: expected \(expected) bytes, got \(actual) bytes"
        case .missingRequiredFiles(let files):
            return "Missing required files: \(files.joined(separator: ", "))"
        case .unsupportedArchitecture(let arch):
            return "Unsupported architecture: \(arch)"
        case .invalidSignature:
            return "Invalid model signature"
        }
    }
}

/// Missing dependency information
public struct MissingDependency {
    public let name: String
    public let version: String?
    public let type: DependencyType
    
    public enum DependencyType {
        case framework
        case library
        case model
        case tokenizer
        case configuration
    }
    
    public init(name: String, version: String? = nil, type: DependencyType) {
        self.name = name
        self.version = version
        self.type = type
    }
}

/// Model metadata extracted during validation
public struct ModelMetadata {
    public var author: String?
    public var description: String?
    public var version: String?
    public var modelType: String?
    public var architecture: String?
    public var quantization: String?
    public var formatVersion: String?
    
    public var inputShapes: [String: [Int]]?
    public var outputShapes: [String: [Int]]?
    
    public var contextLength: Int?
    public var embeddingDimension: Int?
    public var layerCount: Int?
    public var parameterCount: Int64?
    public var tensorCount: Int?
    
    public var requirements: ModelRequirements?
    public var createdDate: Date?
    public var lastModified: Date?
    
    public init() {}
}

/// Model requirements
public struct ModelRequirements {
    public let minOSVersion: String?
    public let minMemory: Int64?
    public let requiredFrameworks: [String]
    public let requiredAccelerators: [HardwareAcceleration]
    
    public init(
        minOSVersion: String? = nil,
        minMemory: Int64? = nil,
        requiredFrameworks: [String] = [],
        requiredAccelerators: [HardwareAcceleration] = []
    ) {
        self.minOSVersion = minOSVersion
        self.minMemory = minMemory
        self.requiredFrameworks = requiredFrameworks
        self.requiredAccelerators = requiredAccelerators
    }
}

/// Unified model validator implementation
public class UnifiedModelValidator: ModelValidator {
    private let metadataExtractor = MetadataExtractor()
    private let formatDetector = ModelFormatDetector()
    
    public init() {}
    
    public func validateModel(_ model: ModelInfo, at path: URL) async throws -> ValidationResult {
        var warnings: [ValidationWarning] = []
        var errors: [ValidationError] = []
        
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
                errors.append(.checksumMismatch(
                    expected: expectedChecksum,
                    actual: try calculateChecksum(for: path)
                ))
            }
        }
        
        // Validate format
        let formatValid = try await validateFormat(path, expectedFormat: model.format)
        if !formatValid {
            let detectedFormat = formatDetector.detectFormat(at: path)
            errors.append(.invalidFormat(
                expected: model.format,
                actual: detectedFormat?.rawValue
            ))
        }
        
        // Check dependencies
        let missingDeps = try await validateDependencies(model)
        if !missingDeps.isEmpty {
            errors.append(.missingDependencies(missingDeps))
        }
        
        // Extract and validate metadata
        let metadata = try await extractAndValidateMetadata(from: path, format: model.format)
        
        // Framework-specific validation
        if let frameworkErrors = try await validateFrameworkSpecific(model, at: path) {
            errors.append(contentsOf: frameworkErrors)
        }
        
        // Check hardware requirements
        if let hwWarnings = validateHardwareRequirements(model, metadata: metadata) {
            warnings.append(contentsOf: hwWarnings)
        }
        
        return ValidationResult(
            isValid: errors.isEmpty,
            warnings: warnings,
            errors: errors,
            metadata: metadata
        )
    }
    
    public func validateChecksum(_ file: URL, expected: String) async throws -> Bool {
        let calculated = try calculateChecksum(for: file)
        return calculated.lowercased() == expected.lowercased()
    }
    
    public func validateFormat(_ file: URL, expectedFormat: ModelFormat) async throws -> Bool {
        let detected = formatDetector.detectFormat(at: file)
        return detected == expectedFormat
    }
    
    public func validateDependencies(_ model: ModelInfo) async throws -> [MissingDependency] {
        var missing: [MissingDependency] = []
        
        // Check tokenizer dependencies
        if let tokenizerFormat = model.tokenizerFormat {
            if !isTokenizerAvailable(tokenizerFormat) {
                missing.append(MissingDependency(
                    name: "\(tokenizerFormat.rawValue) tokenizer",
                    type: .tokenizer
                ))
            }
        }
        
        // Check framework dependencies
        for framework in model.compatibleFrameworks {
            if !isFrameworkAvailable(framework) {
                missing.append(MissingDependency(
                    name: framework.rawValue,
                    type: .framework
                ))
            }
        }
        
        return missing
    }
    
    // MARK: - Private Methods
    
    private func extractAndValidateMetadata(from url: URL, format: ModelFormat) async throws -> ModelMetadata {
        await metadataExtractor.extractMetadata(from: url, format: format)
    }
    
    private func validateFrameworkSpecific(_ model: ModelInfo, at path: URL) async throws -> [ValidationError]? {
        switch model.format {
        #if canImport(CoreML)
        case .mlmodel, .mlpackage:
            return try await validateCoreMLModel(at: path)
        #endif
        case .tflite:
            return try await validateTFLiteModel(at: path)
        case .onnx:
            return try await validateONNXModel(at: path)
        case .safetensors:
            return try await validateSafetensorsModel(at: path)
        case .gguf, .ggml:
            return try await validateGGUFModel(at: path)
        default:
            return nil
        }
    }
    
    #if canImport(CoreML)
    private func validateCoreMLModel(at path: URL) async throws -> [ValidationError]? {
        var errors: [ValidationError] = []
        
        do {
            let compiledURL: URL
            
            if path.pathExtension == "mlmodelc" {
                compiledURL = path
            } else {
                // Try to compile the model
                compiledURL = try MLModel.compileModel(at: path)
                defer {
                    try? FileManager.default.removeItem(at: compiledURL)
                }
            }
            
            // Try to load the model
            _ = try MLModel(contentsOf: compiledURL)
        } catch {
            errors.append(.corruptedFile(reason: "Failed to load Core ML model: \(error.localizedDescription)"))
        }
        
        return errors.isEmpty ? nil : errors
    }
    #endif
    
    private func validateTFLiteModel(at path: URL) async throws -> [ValidationError]? {
        // Basic validation - check file header
        guard let data = try? Data(contentsOf: path, options: .mappedIfSafe) else {
            return [.corruptedFile(reason: "Cannot read model file")]
        }
        
        // TFLite files start with specific magic bytes
        let header = data.prefix(8)
        // Add actual TFLite header validation here
        
        return nil
    }
    
    private func validateONNXModel(at path: URL) async throws -> [ValidationError]? {
        // ONNX validation
        guard let data = try? Data(contentsOf: path, options: .mappedIfSafe) else {
            return [.corruptedFile(reason: "Cannot read model file")]
        }
        
        // ONNX files are protobuf format
        // Add actual ONNX validation here
        
        return nil
    }
    
    private func validateSafetensorsModel(at path: URL) async throws -> [ValidationError]? {
        // Safetensors validation
        guard let file = try? FileHandle(forReadingFrom: path) else {
            return [.corruptedFile(reason: "Cannot open model file")]
        }
        defer { try? file.close() }
        
        // Read header size
        let headerSizeData = file.readData(ofLength: 8)
        guard headerSizeData.count == 8 else {
            return [.corruptedFile(reason: "Invalid safetensors header")]
        }
        
        return nil
    }
    
    private func validateGGUFModel(at path: URL) async throws -> [ValidationError]? {
        // GGUF validation
        guard let file = try? FileHandle(forReadingFrom: path) else {
            return [.corruptedFile(reason: "Cannot open model file")]
        }
        defer { try? file.close() }
        
        // Check GGUF magic
        let magic = file.readData(ofLength: 4)
        guard String(data: magic, encoding: .utf8) == "GGUF" else {
            return [.invalidFormat(expected: .gguf, actual: "unknown")]
        }
        
        return nil
    }
    
    private func validateHardwareRequirements(_ model: ModelInfo, metadata: ModelMetadata?) -> [ValidationWarning]? {
        var warnings: [ValidationWarning] = []
        
        // Check OS version requirements
        if let minOS = metadata?.requirements?.minOSVersion {
            let currentOS = ProcessInfo.processInfo.operatingSystemVersionString
            // Add version comparison logic
        }
        
        // Check memory requirements
        if let minMemory = metadata?.requirements?.minMemory {
            let availableMemory = UnifiedMemoryManager.shared.getAvailableMemory()
            if availableMemory < minMemory {
                warnings.append(ValidationWarning(
                    code: "insufficient_memory",
                    message: "Model requires \(ByteCountFormatter.string(fromByteCount: minMemory, countStyle: .memory))",
                    severity: .high
                ))
            }
        }
        
        return warnings.isEmpty ? nil : warnings
    }
    
    private func calculateChecksum(for url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func isTokenizerAvailable(_ format: TokenizerFormat) -> Bool {
        // Check if tokenizer adapter is registered
        // This would integrate with UnifiedTokenizerManager
        true // Placeholder
    }
    
    private func isFrameworkAvailable(_ framework: LLMFramework) -> Bool {
        // Check if framework is available on this platform
        switch framework {
        #if canImport(CoreML)
        case .coreML:
            return true
        #endif
        case .tensorFlowLite:
            // Check if TensorFlow Lite is available
            return Bundle.main.path(forResource: "TensorFlowLiteC", ofType: "framework") != nil
        default:
            return true // Placeholder
        }
    }
}

// MARK: - Model Format Detector

/// Detects model format from file
public class ModelFormatDetector {
    public func detectFormat(at url: URL) -> ModelFormat? {
        let ext = url.pathExtension.lowercased()
        
        // First try by extension
        if let format = ModelFormat(rawValue: ext) {
            return format
        }
        
        // Check for specific extensions
        switch ext {
        case "mlmodel", "mlmodelc":
            return .mlmodel
        case "mlpackage":
            return .mlpackage
        case "tflite":
            return .tflite
        case "onnx":
            return .onnx
        case "ort":
            return .ort
        case "safetensors":
            return .safetensors
        case "gguf":
            return .gguf
        case "ggml":
            return .ggml
        case "pte":
            return .pte
        case "bin":
            // Need to check file content for bin files
            return detectBinaryFormat(at: url)
        default:
            // Try to detect by reading file header
            return detectByContent(at: url)
        }
    }
    
    private func detectBinaryFormat(at url: URL) -> ModelFormat? {
        // Check if it's part of a larger model structure
        let parentDir = url.deletingLastPathComponent()
        let files = try? FileManager.default.contentsOfDirectory(at: parentDir, includingPropertiesForKeys: nil)
        
        // Check for accompanying files that indicate format
        if let files = files {
            if files.contains(where: { $0.lastPathComponent == "config.json" }) {
                return .safetensors // Likely HuggingFace format
            }
        }
        
        return .bin
    }
    
    private func detectByContent(at url: URL) -> ModelFormat? {
        guard let file = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? file.close() }
        
        let headerData = file.readData(ofLength: 16)
        
        // Check for known magic bytes
        if let magic = String(data: headerData.prefix(4), encoding: .utf8) {
            switch magic {
            case "GGUF":
                return .gguf
            case "GGML":
                return .ggml
            default:
                break
            }
        }
        
        // Check for other patterns
        // Add more format detection logic here
        
        return nil
    }
}

// MARK: - Metadata Extractor

/// Extracts metadata from model files
public class MetadataExtractor {
    private let cache = MetadataCache()
    
    public func extractMetadata(from url: URL, format: ModelFormat) async -> ModelMetadata {
        // Check cache first
        if let cached = cache.get(for: url) {
            return cached
        }
        
        let metadata = await extractForFormat(from: url, format: format)
        cache.store(metadata, for: url)
        
        return metadata
    }
    
    private func extractForFormat(from url: URL, format: ModelFormat) async -> ModelMetadata {
        switch format {
        #if canImport(CoreML)
        case .mlmodel, .mlpackage:
            return await extractCoreMLMetadata(from: url)
        #endif
        case .tflite:
            return await extractTFLiteMetadata(from: url)
        case .onnx:
            return await extractONNXMetadata(from: url)
        case .safetensors:
            return await extractSafetensorsMetadata(from: url)
        case .gguf:
            return await extractGGUFMetadata(from: url)
        default:
            return await extractGenericMetadata(from: url)
        }
    }
    
    #if canImport(CoreML)
    private func extractCoreMLMetadata(from url: URL) async -> ModelMetadata {
        var metadata = ModelMetadata()
        
        if url.pathExtension == "mlpackage" {
            // Read Metadata.json from mlpackage
            let metadataURL = url.appendingPathComponent("Metadata.json")
            if let data = try? Data(contentsOf: metadataURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                metadata.author = json["MLModelAuthor"] as? String
                metadata.description = json["MLModelDescription"] as? String
                metadata.version = json["MLModelVersion"] as? String
            }
        }
        
        // Try to load model to get more info
        if let model = try? MLModel(contentsOf: url) {
            let description = model.modelDescription
            metadata.inputShapes = description.inputDescriptionsByName.compactMapValues { desc in
                desc.multiArrayConstraint?.shape.map { $0.intValue }
            }
            metadata.outputShapes = description.outputDescriptionsByName.compactMapValues { desc in
                desc.multiArrayConstraint?.shape.map { $0.intValue }
            }
        }
        
        return metadata
    }
    #endif
    
    private func extractTFLiteMetadata(from url: URL) async -> ModelMetadata {
        var metadata = ModelMetadata()
        metadata.formatVersion = "3" // TFLite v3 is common
        
        // TFLite metadata extraction would require parsing the flatbuffer format
        // This is a placeholder implementation
        
        return metadata
    }
    
    private func extractONNXMetadata(from url: URL) async -> ModelMetadata {
        var metadata = ModelMetadata()
        
        // ONNX metadata extraction would require protobuf parsing
        // This is a placeholder implementation
        
        return metadata
    }
    
    private func extractSafetensorsMetadata(from url: URL) async -> ModelMetadata {
        var metadata = ModelMetadata()
        
        // Read safetensors header
        if let file = try? FileHandle(forReadingFrom: url) {
            defer { try? file.close() }
            
            // First 8 bytes contain header size
            let headerSizeData = file.readData(ofLength: 8)
            guard headerSizeData.count == 8 else { return metadata }
            
            let headerSize = headerSizeData.withUnsafeBytes { $0.load(as: UInt64.self) }
            let headerData = file.readData(ofLength: Int(headerSize))
            
            if let json = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any] {
                // Extract tensor information
                if let tensors = json["tensors"] as? [String: Any] {
                    metadata.tensorCount = tensors.count
                    metadata.parameterCount = calculateParameterCount(from: tensors)
                }
                
                // Extract model config if present
                if let config = json["__metadata__"] as? [String: Any] {
                    metadata.modelType = config["model_type"] as? String
                    metadata.architecture = config["architecture"] as? String
                }
            }
        }
        
        return metadata
    }
    
    private func extractGGUFMetadata(from url: URL) async -> ModelMetadata {
        var metadata = ModelMetadata()
        
        // GGUF has rich metadata in header
        if let file = try? FileHandle(forReadingFrom: url) {
            defer { try? file.close() }
            
            // Read GGUF magic and version
            let magic = file.readData(ofLength: 4)
            guard String(data: magic, encoding: .utf8) == "GGUF" else { return metadata }
            
            let version = file.readData(ofLength: 4).withUnsafeBytes { $0.load(as: UInt32.self) }
            metadata.formatVersion = String(version)
            
            // Would need full GGUF parser for complete metadata
            // This is a placeholder
        }
        
        return metadata
    }
    
    private func extractGenericMetadata(from url: URL) async -> ModelMetadata {
        var metadata = ModelMetadata()
        
        // Get file attributes
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
            metadata.createdDate = attributes[.creationDate] as? Date
            metadata.lastModified = attributes[.modificationDate] as? Date
        }
        
        return metadata
    }
    
    private func calculateParameterCount(from tensors: [String: Any]) -> Int64 {
        var total: Int64 = 0
        
        for (_, value) in tensors {
            if let tensorInfo = value as? [String: Any],
               let shape = tensorInfo["shape"] as? [Int] {
                let count = shape.reduce(1, *)
                total += Int64(count)
            }
        }
        
        return total
    }
}

// MARK: - Metadata Cache

/// Simple cache for extracted metadata
private class MetadataCache {
    private var cache: [URL: (metadata: ModelMetadata, timestamp: Date)] = [:]
    private let cacheTimeout: TimeInterval = 3600 // 1 hour
    private let lock = NSLock()
    
    func get(for url: URL) -> ModelMetadata? {
        lock.lock()
        defer { lock.unlock() }
        
        guard let entry = cache[url] else { return nil }
        
        // Check if cache is still valid
        if Date().timeIntervalSince(entry.timestamp) > cacheTimeout {
            cache.removeValue(forKey: url)
            return nil
        }
        
        return entry.metadata
    }
    
    func store(_ metadata: ModelMetadata, for url: URL) {
        lock.lock()
        defer { lock.unlock() }
        
        cache[url] = (metadata, Date())
    }
}
