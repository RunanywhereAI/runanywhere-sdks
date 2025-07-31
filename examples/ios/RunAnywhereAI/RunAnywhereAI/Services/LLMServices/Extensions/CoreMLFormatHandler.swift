//
//  CoreMLFormatHandler.swift
//  RunAnywhereAI
//
//  Core ML specific model format handling
//

import Foundation
import CoreML

// MARK: - Core ML Format Handler

class CoreMLFormatHandler: MLPackageFormatHandler {

    override func canHandle(url: URL, format: ModelFormat) -> Bool {
        // Core ML handles both .mlmodel and .mlpackage formats
        return format == .coreML || format == .mlPackage
    }

    override func verifyDownloadedModel(at url: URL) throws {
        // First do basic verification
        try super.verifyDownloadedModel(at: url)

        // Additional Core ML specific checks
        if url.pathExtension == "mlmodel" {
            // For .mlmodel files, ensure they can be compiled
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw LLMError.modelNotFound
            }

            // Check file size is reasonable
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let fileSize = attributes[.size] as? Int64, fileSize > 0 else {
                throw LLMError.initializationFailed("Invalid Core ML model file")
            }
        } else if url.pathExtension == "mlmodelc" {
            // For compiled models, check structure
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw LLMError.initializationFailed("Compiled model is not a directory")
            }
        }
    }

    /// Check if model needs compilation
    func needsCompilation(at url: URL) -> Bool {
        return url.pathExtension == "mlmodel"
    }

    /// Compile Core ML model if needed
    func compileModelIfNeeded(at url: URL) async throws -> URL {
        if needsCompilation(at: url) {
            // Check if already compiled
            let compiledModelName = url.lastPathComponent + "c"
            let compiledModelPath = url.deletingLastPathComponent().appendingPathComponent(compiledModelName)

            if FileManager.default.fileExists(atPath: compiledModelPath.path) {
                return compiledModelPath
            } else {
                // Compile the model
                return try await MLModel.compileModel(at: url)
            }
        }

        return url
    }
}

// MARK: - Core ML Model Info Extensions

extension ModelInfo {
    /// Check if this model is compatible with Core ML
    var isCoreMLCompatible: Bool {
        return framework == .coreML &&
               (format == .coreML || format == .mlPackage)
    }
}

// MARK: - Model Format Extensions for Core ML

extension ModelFormat {
    /// Check if this format is supported by Core ML
    var isCoreMLSupported: Bool {
        switch self {
        case .coreML, .mlPackage:
            return true
        default:
            return false
        }
    }
}
