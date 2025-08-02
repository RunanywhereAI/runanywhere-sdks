import Foundation
#if canImport(CoreML)
import CoreML
#endif

/// Implementation of metadata extraction from model files
public class MetadataExtractorImpl: MetadataExtractor {

    // MARK: - Properties

    private let logger = SDKLogger(category: "MetadataExtractor")
    private let cache = MetadataCache()

    // MARK: - Initialization

    public init() {}

    // MARK: - MetadataExtractor Protocol

    public func extractMetadata(from url: URL, format: ModelFormat) async -> ModelMetadata {
        // Check cache first
        if let cached = cache.get(for: url) {
            logger.debug("Returning cached metadata for: \(url.lastPathComponent)")
            return cached
        }

        logger.debug("Extracting metadata for: \(url.lastPathComponent), format: \(format.rawValue)")

        let metadata = await extractForFormat(from: url, format: format)
        cache.store(metadata, for: url)

        return metadata
    }

    // MARK: - Private Methods

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
        case .ggml:
            return await extractGGMLMetadata(from: url)
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
        do {
            let compiledURL: URL
            if url.pathExtension == "mlmodelc" {
                compiledURL = url
            } else {
                compiledURL = try MLModel.compileModel(at: url)
                defer {
                    try? FileManager.default.removeItem(at: compiledURL)
                }
            }

            let model = try MLModel(contentsOf: compiledURL)
            let description = model.modelDescription

            metadata.inputShapes = description.inputDescriptionsByName.compactMapValues { desc in
                desc.multiArrayConstraint?.shape.map { $0.intValue }
            }
            metadata.outputShapes = description.outputDescriptionsByName.compactMapValues { desc in
                desc.multiArrayConstraint?.shape.map { $0.intValue }
            }
        } catch {
            logger.error("Failed to load Core ML model: \(error)")
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
            metadata.modelType = "llama" // Common for GGUF
        }

        return metadata
    }

    private func extractGGMLMetadata(from url: URL) async -> ModelMetadata {
        var metadata = ModelMetadata()

        // GGML format detection
        if let file = try? FileHandle(forReadingFrom: url) {
            defer { try? file.close() }

            // Read magic
            let magic = file.readData(ofLength: 4)
            if String(data: magic, encoding: .utf8) == "GGML" {
                metadata.formatVersion = "1"
                metadata.modelType = "llama" // Common for GGML
            }
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
