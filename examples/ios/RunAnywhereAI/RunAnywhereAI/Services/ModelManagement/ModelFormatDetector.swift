//
//  ModelFormatDetector.swift
//  RunAnywhereAI
//
//  Created by Assistant on 7/27/25.
//

import Foundation
import UniformTypeIdentifiers

/// Automatic model format detection
class ModelFormatDetector {
    static let shared = ModelFormatDetector()
    
    // MARK: - Magic Numbers / File Signatures
    private let fileSignatures: [ModelFormat: [UInt8]] = [
        .gguf: [0x47, 0x47, 0x55, 0x46], // "GGUF"
        .onnx: [0x08, 0x01], // ONNX protobuf header
        .tflite: [0x54, 0x46, 0x4C, 0x33], // "TFL3"
        .pte: [0x50, 0x54, 0x45, 0x31], // "PTE1" (PyTorch Edge)
    ]
    
    // MARK: - Public Methods
    
    /// Detect model format from file
    func detectFormat(at url: URL) async throws -> ModelFormatInfo {
        // Check if file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FormatDetectionError.fileNotFound
        }
        
        // Get file attributes
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        
        // Try multiple detection methods
        var detectedFormat: ModelFormat?
        var confidence: Double = 0.0
        var metadata: ModelMetadata?
        
        // 1. Check file extension
        if let formatByExtension = detectByExtension(url) {
            detectedFormat = formatByExtension
            confidence = 0.8
        }
        
        // 2. Check file signature/magic number
        if let formatBySignature = try detectBySignature(url) {
            detectedFormat = formatBySignature
            confidence = max(confidence, 0.95)
        }
        
        // 3. Check directory structure (for packages)
        if let formatByStructure = detectByStructure(url) {
            detectedFormat = formatByStructure
            confidence = max(confidence, 0.9)
        }
        
        // 4. Deep inspection for metadata
        if let format = detectedFormat {
            metadata = try await extractMetadata(from: url, format: format)
            if metadata != nil {
                confidence = 1.0
            }
        }
        
        guard let finalFormat = detectedFormat else {
            throw FormatDetectionError.unknownFormat
        }
        
        return ModelFormatInfo(
            format: finalFormat,
            confidence: confidence,
            fileSize: fileSize,
            metadata: metadata
        )
    }
    
    /// Detect all model files in directory
    func detectModelsInDirectory(_ directory: URL) async throws -> [DetectedModel] {
        var detectedModels: [DetectedModel] = []
        
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        
        while let fileURL = enumerator?.nextObject() as? URL {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                guard resourceValues.isRegularFile == true else { continue }
                
                if let formatInfo = try? await detectFormat(at: fileURL) {
                    detectedModels.append(
                        DetectedModel(
                            url: fileURL,
                            formatInfo: formatInfo
                        )
                    )
                }
            } catch {
                // Skip files that can't be detected
                continue
            }
        }
        
        return detectedModels
    }
    
    /// Validate model file integrity
    func validateModel(at url: URL) async throws -> ModelValidationResult {
        let formatInfo = try await detectFormat(at: url)
        
        var isValid = true
        var issues: [String] = []
        
        // Format-specific validation
        switch formatInfo.format {
        case .gguf:
            let ggufValidation = try validateGGUF(at: url)
            isValid = isValid && ggufValidation.isValid
            issues.append(contentsOf: ggufValidation.issues)
            
        case .coreML:
            let coremlValidation = try validateCoreML(at: url)
            isValid = isValid && coremlValidation.isValid
            issues.append(contentsOf: coremlValidation.issues)
            
        case .onnx:
            let onnxValidation = try validateONNX(at: url)
            isValid = isValid && onnxValidation.isValid
            issues.append(contentsOf: onnxValidation.issues)
            
        default:
            // Basic validation for other formats
            if formatInfo.fileSize == 0 {
                isValid = false
                issues.append("File is empty")
            }
        }
        
        return ModelValidationResult(
            format: formatInfo.format,
            isValid: isValid,
            issues: issues,
            metadata: formatInfo.metadata
        )
    }
    
    // MARK: - Private Detection Methods
    
    private func detectByExtension(_ url: URL) -> ModelFormat? {
        let ext = url.pathExtension.lowercased()
        
        switch ext {
        case "gguf":
            return .gguf
        case "mlmodel", "mlpackage":
            return .coreML
        case "onnx":
            return .onnx
        case "tflite":
            return .tflite
        case "pte":
            return .pte
        case "safetensors":
            return .mlx
        default:
            return nil
        }
    }
    
    private func detectBySignature(_ url: URL) throws -> ModelFormat? {
        guard let file = FileHandle(forReadingAtPath: url.path) else {
            throw FormatDetectionError.cannotReadFile
        }
        defer { file.closeFile() }
        
        // Read first few bytes
        let headerData = file.readData(ofLength: 16)
        guard headerData.count >= 4 else { return nil }
        
        // Check against known signatures
        for (format, signature) in fileSignatures {
            if headerData.starts(with: signature) {
                return format
            }
        }
        
        // Special case for Core ML (zip/directory structure)
        if headerData.starts(with: [0x50, 0x4B]) { // PK (zip)
            return .coreML
        }
        
        return nil
    }
    
    private func detectByStructure(_ url: URL) -> ModelFormat? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return nil
        }
        
        if isDirectory.boolValue {
            // Check for Core ML package structure
            let modelPath = url.appendingPathComponent("model.mil")
            let metadataPath = url.appendingPathComponent("metadata.json")
            
            if FileManager.default.fileExists(atPath: modelPath.path) ||
               FileManager.default.fileExists(atPath: metadataPath.path) {
                return .coreML
            }
        }
        
        return nil
    }
    
    // MARK: - Metadata Extraction
    
    private func extractMetadata(from url: URL, format: ModelFormat) async throws -> ModelMetadata? {
        switch format {
        case .gguf:
            return try extractGGUFMetadata(from: url)
        case .coreML:
            return try extractCoreMLMetadata(from: url)
        case .onnx:
            return try extractONNXMetadata(from: url)
        default:
            return nil
        }
    }
    
    private func extractGGUFMetadata(from url: URL) throws -> ModelMetadata {
        guard let file = FileHandle(forReadingAtPath: url.path) else {
            throw FormatDetectionError.cannotReadFile
        }
        defer { file.closeFile() }
        
        // Skip magic number
        file.seek(toFileOffset: 4)
        
        // Read version
        let versionData = file.readData(ofLength: 4)
        let version = versionData.withUnsafeBytes { $0.load(as: UInt32.self) }
        
        // For demo, return basic metadata
        return ModelMetadata(
            architecture: "Unknown",
            parameters: nil,
            quantization: "Unknown",
            contextLength: nil,
            vocabularySize: nil,
            version: String(version)
        )
    }
    
    private func extractCoreMLMetadata(from url: URL) throws -> ModelMetadata {
        // Check if it's a package
        let metadataURL = url.appendingPathComponent("metadata.json")
        
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            _ = try Data(contentsOf: metadataURL)
            // Parse metadata JSON
            // For demo, return placeholder
        }
        
        return ModelMetadata(
            architecture: "Core ML",
            parameters: nil,
            quantization: "Default",
            contextLength: nil,
            vocabularySize: nil,
            version: "1.0"
        )
    }
    
    private func extractONNXMetadata(from url: URL) throws -> ModelMetadata {
        // ONNX uses protobuf, simplified extraction for demo
        return ModelMetadata(
            architecture: "ONNX",
            parameters: nil,
            quantization: "Default",
            contextLength: nil,
            vocabularySize: nil,
            version: "1.0"
        )
    }
    
    // MARK: - Validation Methods
    
    private func validateGGUF(at url: URL) throws -> (isValid: Bool, issues: [String]) {
        var issues: [String] = []
        
        guard let file = FileHandle(forReadingAtPath: url.path) else {
            return (false, ["Cannot read file"])
        }
        defer { file.closeFile() }
        
        // Check magic number
        let magic = file.readData(ofLength: 4)
        if magic != Data([0x47, 0x47, 0x55, 0x46]) {
            issues.append("Invalid GGUF magic number")
        }
        
        // Check file size
        let fileSize = file.seekToEndOfFile()
        if fileSize < 1024 { // Minimum reasonable size
            issues.append("File too small to be a valid model")
        }
        
        return (issues.isEmpty, issues)
    }
    
    private func validateCoreML(at url: URL) throws -> (isValid: Bool, issues: [String]) {
        var issues: [String] = []
        
        // Check if it's a valid package or model file
        let isPackage = url.pathExtension == "mlpackage"
        let isModel = url.pathExtension == "mlmodel"
        
        if !isPackage && !isModel {
            issues.append("Not a valid Core ML file extension")
        }
        
        if isPackage {
            // Check for required files
            let requiredFiles = ["model.mil", "metadata.json"]
            for file in requiredFiles {
                let filePath = url.appendingPathComponent(file)
                if !FileManager.default.fileExists(atPath: filePath.path) {
                    issues.append("Missing required file: \(file)")
                }
            }
        }
        
        return (issues.isEmpty, issues)
    }
    
    private func validateONNX(at url: URL) throws -> (isValid: Bool, issues: [String]) {
        var issues: [String] = []
        
        guard let file = FileHandle(forReadingAtPath: url.path) else {
            return (false, ["Cannot read file"])
        }
        defer { file.closeFile() }
        
        // Basic ONNX validation
        let header = file.readData(ofLength: 8)
        if header.count < 8 {
            issues.append("File too small to be valid ONNX")
        }
        
        return (issues.isEmpty, issues)
    }
}

// MARK: - Supporting Types

struct ModelFormatInfo {
    let format: ModelFormat
    let confidence: Double
    let fileSize: Int64
    let metadata: ModelMetadata?
}

struct ModelMetadata {
    let architecture: String?
    let parameters: Int64?
    let quantization: String?
    let contextLength: Int?
    let vocabularySize: Int?
    let version: String?
}

struct DetectedModel {
    let url: URL
    let formatInfo: ModelFormatInfo
}

struct ModelValidationResult {
    let format: ModelFormat
    let isValid: Bool
    let issues: [String]
    let metadata: ModelMetadata?
}

enum FormatDetectionError: LocalizedError {
    case fileNotFound
    case cannotReadFile
    case unknownFormat
    case invalidFormat
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Model file not found"
        case .cannotReadFile:
            return "Cannot read model file"
        case .unknownFormat:
            return "Unknown model format"
        case .invalidFormat:
            return "Invalid model format"
        }
    }
}