//
//  ModelConverter.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/27/25.
//

import Foundation
import CoreML
import Combine

/// Model converter for converting between different LLM formats
class ModelConverter: ObservableObject {
    static let shared = ModelConverter()

    // MARK: - Published Properties
    @Published var isConverting = false
    @Published var conversionProgress: Double = 0.0
    @Published var conversionStatus: String = ""

    // MARK: - Private Properties
    private let fileManager = FileManager.default
    private let processQueue = DispatchQueue(label: "com.runanywhere.modelconverter", qos: .userInitiated)
    private var cancellables = Set<AnyCancellable>()

    // Conversion scripts directory
    private var scriptsDirectory: URL {
        Bundle.main.bundleURL.appendingPathComponent("ConversionScripts")
    }

    // Temporary directory for conversions
    private var tempDirectory: URL {
        fileManager.temporaryDirectory.appendingPathComponent("ModelConversions")
    }

    // MARK: - Initialization
    init() {
        setupTempDirectory()
    }

    // MARK: - Public Methods

    /// Convert model from one format to another
    func convertModel(
        from sourceURL: URL,
        sourceFormat: ModelFormat,
        targetFormat: ModelFormat,
        options: ConversionOptions = .default
    ) async throws -> URL {
        guard sourceFormat != targetFormat else {
            throw ConversionError.sameFormat
        }

        guard isConversionSupported(from: sourceFormat, to: targetFormat) else {
            throw ConversionError.unsupportedConversion
        }

        isConverting = true
        conversionProgress = 0.0
        conversionStatus = "Starting conversion..."

        defer {
            isConverting = false
            conversionProgress = 1.0
        }

        // Perform conversion based on formats
        switch (sourceFormat, targetFormat) {
        case (.gguf, .coreML):
            return try await convertGGUFToCoreML(sourceURL, options: options)
        case (.gguf, .onnx):
            return try await convertGGUFToONNX(sourceURL, options: options)
        case (.onnx, .coreML):
            return try await convertONNXToCoreML(sourceURL, options: options)
        case (.onnx, .tflite):
            return try await convertONNXToTFLite(sourceURL, options: options)
        case (.mlx, .coreML):
            return try await convertMLXToCoreML(sourceURL, options: options)
        case (.coreML, .gguf):
            return try await convertCoreMLToGGUF(sourceURL, options: options)
        default:
            throw ConversionError.unsupportedConversion
        }
    }

    /// Check if conversion is supported
    func isConversionSupported(from source: ModelFormat, to target: ModelFormat) -> Bool {
        let supportedConversions: Set<ConversionPair> = [
            ConversionPair(from: .gguf, to: .coreML),
            ConversionPair(from: .gguf, to: .onnx),
            ConversionPair(from: .onnx, to: .coreML),
            ConversionPair(from: .onnx, to: .tflite),
            ConversionPair(from: .mlx, to: .coreML),
            ConversionPair(from: .coreML, to: .gguf)
        ]

        return supportedConversions.contains(ConversionPair(from: source, to: target))
    }

    /// Get available target formats for a source format
    func getAvailableTargetFormats(for source: ModelFormat) -> [ModelFormat] {
        var targets: [ModelFormat] = []

        for target in ModelFormat.allCases {
            if isConversionSupported(from: source, to: target) {
                targets.append(target)
            }
        }

        return targets
    }

    /// Validate model before conversion
    func validateModel(at url: URL, format: ModelFormat) async throws -> ModelValidationInfo {
        conversionStatus = "Validating model..."

        // Check file exists
        guard fileManager.fileExists(atPath: url.path) else {
            throw ConversionError.fileNotFound
        }

        // Check file size
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int64 ?? 0

        // Format-specific validation
        switch format {
        case .gguf:
            return try await validateGGUFModel(at: url, fileSize: fileSize)
        case .coreML:
            return try await validateCoreMLModel(at: url, fileSize: fileSize)
        case .onnx:
            return try await validateONNXModel(at: url, fileSize: fileSize)
        case .mlx:
            return try await validateMLXModel(at: url, fileSize: fileSize)
        case .tflite:
            return try await validateTFLiteModel(at: url, fileSize: fileSize)
        case .pte:
            return try await validatePTEModel(at: url, fileSize: fileSize)
        case .ggml, .pytorch, .safetensors, .picoLLM, .other, .onnxRuntime, .mlPackage, .mlc:
            // For unsupported formats, return basic validation
            return ModelValidationInfo(
                isValid: false,
                format: format,
                fileSize: fileSize,
                warnings: ["Validation not implemented for \(format.displayName) format"]
            )
        }
    }

    // MARK: - Conversion Methods

    private func convertGGUFToCoreML(_ sourceURL: URL, options: ConversionOptions) async throws -> URL {
        conversionStatus = "Converting GGUF to Core ML..."
        conversionProgress = 0.1

        // Create output path
        let outputURL = tempDirectory.appendingPathComponent(
            sourceURL.deletingPathExtension().lastPathComponent + ".mlpackage"
        )

        // Simulate conversion steps
        // In production, this would call actual conversion tools
        try await simulateConversion(
            steps: [
                "Loading GGUF model...",
                "Extracting model architecture...",
                "Converting weights to Core ML format...",
                "Optimizing for Neural Engine...",
                "Packaging model..."
            ]
        )

        // For demo, copy a placeholder
        if !fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)
            let configURL = outputURL.appendingPathComponent("config.json")
            try Data("{}".utf8).write(to: configURL)
        }

        conversionProgress = 1.0
        conversionStatus = "Conversion completed"

        return outputURL
    }

    private func convertGGUFToONNX(_ sourceURL: URL, options: ConversionOptions) async throws -> URL {
        conversionStatus = "Converting GGUF to ONNX..."
        conversionProgress = 0.1

        let outputURL = tempDirectory.appendingPathComponent(
            sourceURL.deletingPathExtension().lastPathComponent + ".onnx"
        )

        try await simulateConversion(
            steps: [
                "Reading GGUF file...",
                "Extracting tensor data...",
                "Building ONNX graph...",
                "Optimizing model...",
                "Saving ONNX model..."
            ]
        )

        // Create placeholder
        try Data().write(to: outputURL)

        conversionProgress = 1.0
        conversionStatus = "Conversion completed"

        return outputURL
    }

    private func convertONNXToCoreML(_ sourceURL: URL, options: ConversionOptions) async throws -> URL {
        conversionStatus = "Converting ONNX to Core ML..."
        conversionProgress = 0.1

        let outputURL = tempDirectory.appendingPathComponent(
            sourceURL.deletingPathExtension().lastPathComponent + ".mlpackage"
        )

        try await simulateConversion(
            steps: [
                "Loading ONNX model...",
                "Analyzing model structure...",
                "Converting operations to Core ML...",
                "Applying quantization...",
                "Creating MLPackage..."
            ]
        )

        if !fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)
            let configURL = outputURL.appendingPathComponent("config.json")
            try Data("{}".utf8).write(to: configURL)
        }

        conversionProgress = 1.0
        conversionStatus = "Conversion completed"

        return outputURL
    }

    private func convertONNXToTFLite(_ sourceURL: URL, options: ConversionOptions) async throws -> URL {
        conversionStatus = "Converting ONNX to TFLite..."
        conversionProgress = 0.1

        let outputURL = tempDirectory.appendingPathComponent(
            sourceURL.deletingPathExtension().lastPathComponent + ".tflite"
        )

        try await simulateConversion(
            steps: [
                "Loading ONNX model...",
                "Converting to TensorFlow format...",
                "Applying TFLite optimizations...",
                "Quantizing model...",
                "Generating TFLite file..."
            ]
        )

        try Data().write(to: outputURL)

        conversionProgress = 1.0
        conversionStatus = "Conversion completed"

        return outputURL
    }

    private func convertMLXToCoreML(_ sourceURL: URL, options: ConversionOptions) async throws -> URL {
        conversionStatus = "Converting MLX to Core ML..."
        conversionProgress = 0.1

        let outputURL = tempDirectory.appendingPathComponent(
            sourceURL.deletingPathExtension().lastPathComponent + ".mlpackage"
        )

        try await simulateConversion(
            steps: [
                "Loading MLX model...",
                "Extracting safetensors...",
                "Converting to Core ML ops...",
                "Optimizing for Apple Silicon...",
                "Packaging model..."
            ]
        )

        if !fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)
            let configURL = outputURL.appendingPathComponent("config.json")
            try Data("{}".utf8).write(to: configURL)
        }

        conversionProgress = 1.0
        conversionStatus = "Conversion completed"

        return outputURL
    }

    private func convertCoreMLToGGUF(_ sourceURL: URL, options: ConversionOptions) async throws -> URL {
        conversionStatus = "Converting Core ML to GGUF..."
        conversionProgress = 0.1

        let outputURL = tempDirectory.appendingPathComponent(
            sourceURL.deletingPathExtension().lastPathComponent + ".gguf"
        )

        try await simulateConversion(
            steps: [
                "Loading Core ML model...",
                "Extracting weights...",
                "Converting to GGUF format...",
                "Applying quantization...",
                "Writing GGUF file..."
            ]
        )

        try Data().write(to: outputURL)

        conversionProgress = 1.0
        conversionStatus = "Conversion completed"

        return outputURL
    }

    // MARK: - Validation Methods

    private func validateGGUFModel(at url: URL, fileSize: Int64) async throws -> ModelValidationInfo {
        // Check GGUF magic number
        guard let file = FileHandle(forReadingAtPath: url.path) else {
            throw ConversionError.cannotReadFile
        }
        defer { file.closeFile() }

        let magic = file.readData(ofLength: 4)
        let isValid = magic == Data([0x47, 0x47, 0x55, 0x46]) // "GGUF"

        return ModelValidationInfo(
            isValid: isValid,
            format: .gguf,
            fileSize: fileSize,
            warnings: isValid ? [] : ["Invalid GGUF file format"]
        )
    }

    private func validateCoreMLModel(at url: URL, fileSize: Int64) async throws -> ModelValidationInfo {
        let isPackage = url.pathExtension == "mlpackage"
        let isModel = url.pathExtension == "mlmodel"
        let isValid = isPackage || isModel

        return ModelValidationInfo(
            isValid: isValid,
            format: .coreML,
            fileSize: fileSize,
            warnings: isValid ? [] : ["Invalid Core ML model format"]
        )
    }

    private func validateONNXModel(at url: URL, fileSize: Int64) async throws -> ModelValidationInfo {
        let isValid = url.pathExtension == "onnx"

        return ModelValidationInfo(
            isValid: isValid,
            format: .onnx,
            fileSize: fileSize,
            warnings: isValid ? [] : ["Invalid ONNX model format"]
        )
    }

    private func validateMLXModel(at url: URL, fileSize: Int64) async throws -> ModelValidationInfo {
        let isValid = url.pathExtension == "safetensors"

        return ModelValidationInfo(
            isValid: isValid,
            format: .mlx,
            fileSize: fileSize,
            warnings: isValid ? [] : ["Invalid MLX model format"]
        )
    }

    private func validateTFLiteModel(at url: URL, fileSize: Int64) async throws -> ModelValidationInfo {
        let isValid = url.pathExtension == "tflite"

        return ModelValidationInfo(
            isValid: isValid,
            format: .tflite,
            fileSize: fileSize,
            warnings: isValid ? [] : ["Invalid TFLite model format"]
        )
    }

    private func validatePTEModel(at url: URL, fileSize: Int64) async throws -> ModelValidationInfo {
        let isValid = url.pathExtension == "pte"

        return ModelValidationInfo(
            isValid: isValid,
            format: .pte,
            fileSize: fileSize,
            warnings: isValid ? [] : ["Invalid PTE model format"]
        )
    }

    // MARK: - Helper Methods

    private func setupTempDirectory() {
        try? fileManager.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
    }

    private func simulateConversion(steps: [String]) async throws {
        let stepProgress = 0.8 / Double(steps.count)

        for (index, step) in steps.enumerated() {
            await MainActor.run {
                conversionStatus = step
                conversionProgress = 0.1 + (Double(index) * stepProgress)
            }

            // Simulate processing time
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
    }
}

// MARK: - Supporting Types

struct ConversionOptions {
    let quantizationBits: Int
    let optimizeForDevice: Bool
    let preserveMetadata: Bool

    static let `default` = ConversionOptions(
        quantizationBits: 4,
        optimizeForDevice: true,
        preserveMetadata: true
    )
}

struct ConversionPair: Hashable {
    let from: ModelFormat
    let to: ModelFormat
}

struct ModelValidationInfo {
    let isValid: Bool
    let format: ModelFormat
    let fileSize: Int64
    let warnings: [String]
}

enum ConversionError: LocalizedError {
    case sameFormat
    case unsupportedConversion
    case fileNotFound
    case cannotReadFile
    case conversionFailed(String)
    case insufficientMemory
    case invalidModel

    var errorDescription: String? {
        switch self {
        case .sameFormat:
            return "Source and target formats are the same"
        case .unsupportedConversion:
            return "This conversion is not supported"
        case .fileNotFound:
            return "Model file not found"
        case .cannotReadFile:
            return "Cannot read model file"
        case .conversionFailed(let reason):
            return "Conversion failed: \(reason)"
        case .insufficientMemory:
            return "Insufficient memory for conversion"
        case .invalidModel:
            return "Invalid model file"
        }
    }
}
