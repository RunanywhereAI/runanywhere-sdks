//
//  SwiftTransformersModelHandler.swift
//  RunAnywhereAI
//
//  Swift Transformers specific model handling
//

import Foundation

// MARK: - Swift Transformers Model Handler

class SwiftTransformersModelHandler: MLPackageFormatHandler {
    
    override func canHandle(url: URL, format: ModelFormat) -> Bool {
        // Swift Transformers uses .mlpackage format
        return super.canHandle(url: url, format: format)
    }
    
    override func verifyDownloadedModel(at url: URL) throws {
        // First do basic mlpackage verification
        try super.verifyDownloadedModel(at: url)
        
        // Additional Swift Transformers specific checks
        let dataPath = url.appendingPathComponent("Data/com.apple.CoreML")
        guard FileManager.default.fileExists(atPath: dataPath.path) else {
            throw LLMError.initializationFailed("Invalid Swift Transformers model structure")
        }
        
        // Check for model.mlmodel file
        let modelPath = dataPath.appendingPathComponent("model.mlmodel")
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw LLMError.initializationFailed("Missing model.mlmodel in Swift Transformers package")
        }
    }
}

// MARK: - Framework-specific Model Info

extension ModelInfo {
    /// Check if this model is compatible with Swift Transformers
    var isSwiftTransformersCompatible: Bool {
        return framework == .swiftTransformers && 
               (format == .mlPackage || format == .coreML)
    }
    
    /// Get the expected download behavior for this model
    var downloadBehavior: DownloadBehavior {
        if framework == .swiftTransformers && format == .mlPackage {
            return .directory
        }
        return .file
    }
    
    enum DownloadBehavior {
        case file
        case directory
        case archive
    }
}

// MARK: - Model Format Extensions for Swift Transformers

extension ModelFormat {
    /// Check if this format is supported by Swift Transformers
    var isSwiftTransformersSupported: Bool {
        switch self {
        case .mlPackage, .coreML:
            return true
        default:
            return false
        }
    }
}

// MARK: - Swift Transformers Model Registry

extension ModelURLRegistry {
    /// Register Swift Transformers specific model handler
    func registerSwiftTransformersHandler() {
        // This would be called during app initialization
        // to register custom handlers for specific frameworks
    }
    
    /// Validate Swift Transformers model requirements
    func validateSwiftTransformersModel(_ modelInfo: ModelInfo) -> Bool {
        // Ensure model has correct format
        guard modelInfo.isSwiftTransformersCompatible else {
            return false
        }
        
        // Ensure download URL is valid for directory downloads
        if let url = modelInfo.downloadURL,
           modelInfo.downloadBehavior == .directory {
            return url.absoluteString.contains(".mlpackage")
        }
        
        return true
    }
}