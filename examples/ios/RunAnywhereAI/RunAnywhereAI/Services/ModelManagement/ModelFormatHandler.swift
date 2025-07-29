//
//  ModelFormatHandler.swift
//  RunAnywhereAI
//
//  Protocol and implementations for handling different model formats
//

import Foundation

// MARK: - Protocol

protocol ModelFormatHandler {
    /// Check if this handler can process the given URL/format
    func canHandle(url: URL, format: ModelFormat) -> Bool
    
    /// Check if the URL represents a directory-based model
    func isDirectoryBasedModel(url: URL) -> Bool
    
    /// Verify the downloaded model exists and is valid
    func verifyDownloadedModel(at url: URL) throws
    
    /// Process the downloaded model (copy/move/extract as needed)
    func processDownloadedModel(from sourceURL: URL, to destinationDirectory: URL, modelInfo: ModelInfo) async throws -> URL
    
    /// Calculate the size of the model (for files or directories)
    func calculateModelSize(at url: URL) -> Int64
    
    /// Check if this model requires special download handling
    func requiresSpecialDownload(url: URL) -> Bool
}

// MARK: - Base Implementation

class BaseModelFormatHandler: ModelFormatHandler {
    func canHandle(url: URL, format: ModelFormat) -> Bool {
        return false // Override in subclasses
    }
    
    func isDirectoryBasedModel(url: URL) -> Bool {
        return false // Most formats are single files
    }
    
    func verifyDownloadedModel(at url: URL) throws {
        // Basic verification - check if file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ModelDownloadError.networkError(NSError(
                domain: "ModelDownload",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Downloaded model not found at: \(url.lastPathComponent)"]
            ))
        }
    }
    
    func processDownloadedModel(from sourceURL: URL, to destinationDirectory: URL, modelInfo: ModelInfo) async throws -> URL {
        // Default implementation - just copy the file
        let destinationURL = destinationDirectory.appendingPathComponent(modelInfo.name)
        
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        
        do {
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        } catch {
            // If move fails, try copy
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            try? FileManager.default.removeItem(at: sourceURL)
        }
        
        return destinationURL
    }
    
    func calculateModelSize(at url: URL) -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
    
    func requiresSpecialDownload(url: URL) -> Bool {
        return false
    }
}

// MARK: - ML Package Handler

class MLPackageFormatHandler: BaseModelFormatHandler {
    override func canHandle(url: URL, format: ModelFormat) -> Bool {
        return format == .mlPackage || url.pathExtension == "mlpackage"
    }
    
    override func isDirectoryBasedModel(url: URL) -> Bool {
        return true // .mlpackage files are directories
    }
    
    override func verifyDownloadedModel(at url: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ModelDownloadError.networkError(NSError(
                domain: "ModelDownload",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Downloaded .mlpackage directory not found: \(url.lastPathComponent)"]
            ))
        }
        
        // Verify it has the expected structure
        let manifestPath = url.appendingPathComponent("Manifest.json")
        guard FileManager.default.fileExists(atPath: manifestPath.path) else {
            throw ModelDownloadError.networkError(NSError(
                domain: "ModelDownload",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Invalid .mlpackage structure - missing Manifest.json"]
            ))
        }
    }
    
    override func processDownloadedModel(from sourceURL: URL, to destinationDirectory: URL, modelInfo: ModelInfo) async throws -> URL {
        // For .mlpackage downloaded via HuggingFaceDirectoryDownloader,
        // the sourceURL is already the final location
        if sourceURL.path.contains("/Models/") && sourceURL.pathExtension == "mlpackage" {
            // Already in the correct location, just verify
            try verifyDownloadedModel(at: sourceURL)
            return sourceURL
        }
        
        // Otherwise, use default copy behavior
        return try await super.processDownloadedModel(from: sourceURL, to: destinationDirectory, modelInfo: modelInfo)
    }
    
    override func calculateModelSize(at url: URL) -> Int64 {
        // For directories, calculate total size recursively
        return calculateDirectorySize(at: url)
    }
    
    override func requiresSpecialDownload(url: URL) -> Bool {
        // .mlpackage from HuggingFace requires directory download
        return url.absoluteString.contains("huggingface.co") && url.pathExtension == "mlpackage"
    }
    
    private func calculateDirectorySize(at url: URL) -> Int64 {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0
        
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        
        for case let fileURL as URL in enumerator {
            if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(fileSize)
            }
        }
        
        return totalSize
    }
}

// MARK: - GGUF Handler

class GGUFFormatHandler: BaseModelFormatHandler {
    override func canHandle(url: URL, format: ModelFormat) -> Bool {
        return format == .gguf || url.pathExtension == "gguf"
    }
}

// MARK: - Core ML Handler

class CoreMLFormatHandler: BaseModelFormatHandler {
    override func canHandle(url: URL, format: ModelFormat) -> Bool {
        return format == .coreML || url.pathExtension == "mlmodel" || url.pathExtension == "mlmodelc"
    }
}

// MARK: - Compressed Archive Handler

class CompressedArchiveHandler: BaseModelFormatHandler {
    override func canHandle(url: URL, format: ModelFormat) -> Bool {
        let compressedExtensions = ["zip", "gz", "tar", "tgz"]
        return compressedExtensions.contains(url.pathExtension) || 
               url.lastPathComponent.contains(".tar.gz")
    }
    
    override func processDownloadedModel(from sourceURL: URL, to destinationDirectory: URL, modelInfo: ModelInfo) async throws -> URL {
        // Handle different compression formats
        if sourceURL.pathExtension == "zip" {
            try FileManager.default.unzipItem(at: sourceURL, to: destinationDirectory)
            
            // Find the extracted model
            let contents = try FileManager.default.contentsOfDirectory(
                at: destinationDirectory,
                includingPropertiesForKeys: nil
            )
            
            if let firstItem = contents.first {
                return firstItem
            }
            return destinationDirectory
        } else if sourceURL.pathExtension == "gz" || sourceURL.lastPathComponent.contains(".tar.gz") {
            // For now, just copy the archive - proper extraction needs a library
            let destinationURL = destinationDirectory.appendingPathComponent(sourceURL.lastPathComponent)
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            
            // TODO: Implement proper tar.gz extraction
            print("Note: tar.gz extraction not implemented. Archive saved at: \(destinationURL.path)")
            
            return destinationURL
        }
        
        // For other formats, use default behavior
        return try await super.processDownloadedModel(from: sourceURL, to: destinationDirectory, modelInfo: modelInfo)
    }
}

// MARK: - Model Format Manager

class ModelFormatManager {
    static let shared = ModelFormatManager()
    
    private let handlers: [ModelFormatHandler] = [
        MLPackageFormatHandler(),
        GGUFFormatHandler(),
        CoreMLFormatHandler(),
        CompressedArchiveHandler(),
        BaseModelFormatHandler() // Fallback
    ]
    
    private init() {}
    
    /// Get the appropriate handler for a model
    func getHandler(for url: URL, format: ModelFormat) -> ModelFormatHandler {
        return handlers.first { $0.canHandle(url: url, format: format) } ?? BaseModelFormatHandler()
    }
    
    /// Check if a model is directory-based
    func isDirectoryBasedModel(_ url: URL, format: ModelFormat) -> Bool {
        let handler = getHandler(for: url, format: format)
        return handler.isDirectoryBasedModel(url: url)
    }
    
    /// Check if a model requires special download handling
    func requiresSpecialDownload(_ url: URL, format: ModelFormat) -> Bool {
        let handler = getHandler(for: url, format: format)
        return handler.requiresSpecialDownload(url: url)
    }
}