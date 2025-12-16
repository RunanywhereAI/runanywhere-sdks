//
//  ModelExtractionService.swift
//  RunAnywhere SDK
//
//  Centralized service for extracting model archives.
//  Uses pure Swift extraction via SWCompression (no native C library dependency).
//  Located in ModelManagement as it uses ModelArtifactType and is model-specific.
//

import Foundation

// MARK: - Extraction Result

/// Result of an extraction operation
public struct ExtractionResult: Sendable {
    /// Path to the extracted model (could be file or directory)
    public let modelPath: URL

    /// Total extracted size in bytes
    public let extractedSize: Int64

    /// Number of files extracted
    public let fileCount: Int

    /// Duration of extraction in seconds
    public let durationSeconds: TimeInterval

    public init(modelPath: URL, extractedSize: Int64, fileCount: Int, durationSeconds: TimeInterval) {
        self.modelPath = modelPath
        self.extractedSize = extractedSize
        self.fileCount = fileCount
        self.durationSeconds = durationSeconds
    }
}

// MARK: - Extraction Service Protocol

/// Protocol for model extraction service
public protocol ModelExtractionServiceProtocol: Sendable {
    /// Extract an archive based on the model's artifact type
    /// - Parameters:
    ///   - archiveURL: URL to the downloaded archive
    ///   - destinationURL: Directory to extract to
    ///   - artifactType: The model's artifact type (determines extraction method)
    ///   - progressHandler: Optional callback for extraction progress (0.0 to 1.0)
    /// - Returns: Result containing the path to the extracted model
    func extract(
        archiveURL: URL,
        to destinationURL: URL,
        artifactType: ModelArtifactType,
        progressHandler: ((Double) -> Void)?
    ) async throws -> ExtractionResult
}

// MARK: - Default Extraction Service

/// Default implementation of the model extraction service
/// Uses pure Swift extraction via SWCompression for all archive types
public final class DefaultModelExtractionService: ModelExtractionServiceProtocol, @unchecked Sendable {
    private let logger = SDKLogger(category: "ModelExtractionService")

    public init() {}

    public func extract(
        archiveURL: URL,
        to destinationURL: URL,
        artifactType: ModelArtifactType,
        progressHandler: ((Double) -> Void)?
    ) async throws -> ExtractionResult {
        let startTime = Date()

        guard case .archive(let archiveType, let structure, _) = artifactType else {
            throw DownloadError.extractionFailed("Artifact type does not require extraction")
        }

        logger.info("Starting extraction", metadata: [
            "archiveURL": archiveURL.path,
            "destination": destinationURL.path,
            "archiveType": archiveType.rawValue
        ])

        // Ensure destination exists
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        // Report starting
        progressHandler?(0.0)

        // Perform extraction based on archive type using pure Swift (SWCompression)
        switch archiveType {
        case .zip:
            try ArchiveUtility.extractZipArchive(from: archiveURL, to: destinationURL, progressHandler: progressHandler)
        case .tarBz2:
            try ArchiveUtility.extractTarBz2Archive(from: archiveURL, to: destinationURL, progressHandler: progressHandler)
        case .tarGz:
            try ArchiveUtility.extractTarGzArchive(from: archiveURL, to: destinationURL, progressHandler: progressHandler)
        case .tarXz:
            try ArchiveUtility.extractTarXzArchive(from: archiveURL, to: destinationURL, progressHandler: progressHandler)
        }

        // Find the actual model path based on structure
        let modelPath = findModelPath(in: destinationURL, structure: structure)

        // Calculate extracted size and file count
        let (extractedSize, fileCount) = calculateExtractionStats(at: destinationURL)

        let duration = Date().timeIntervalSince(startTime)

        logger.info("Extraction completed", metadata: [
            "modelPath": modelPath.path,
            "extractedSize": extractedSize,
            "fileCount": fileCount,
            "durationSeconds": duration
        ])

        progressHandler?(1.0)

        return ExtractionResult(
            modelPath: modelPath,
            extractedSize: extractedSize,
            fileCount: fileCount,
            durationSeconds: duration
        )
    }

    // MARK: - Helper Methods

    /// Find the actual model path based on archive structure
    private func findModelPath(in extractedDir: URL, structure: ArchiveStructure) -> URL {
        switch structure {
        case .singleFileNested:
            // Look for a single model file, possibly in a subdirectory
            return findSingleModelFile(in: extractedDir) ?? extractedDir

        case .nestedDirectory:
            // Common pattern: archive contains one subdirectory with all the files
            // e.g., sherpa-onnx archives extract to: extractedDir/vits-xxx/
            return findNestedDirectory(in: extractedDir)

        case .directoryBased, .unknown:
            // Return the extraction directory itself
            return extractedDir
        }
    }

    /// Find nested directory (for archives that extract to a subdirectory)
    private func findNestedDirectory(in extractedDir: URL) -> URL {
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(at: extractedDir, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return extractedDir
        }

        // Filter out hidden files and macOS resource forks
        let visibleContents = contents.filter {
            !$0.lastPathComponent.hasPrefix(".") && !$0.lastPathComponent.hasPrefix("._")
        }

        // If there's a single visible subdirectory, return it
        if visibleContents.count == 1, let first = visibleContents.first {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: first.path, isDirectory: &isDir), isDir.boolValue {
                return first
            }
        }

        return extractedDir
    }

    /// Find a single model file in a directory (recursive, up to 2 levels)
    private func findSingleModelFile(in directory: URL, depth: Int = 0) -> URL? {
        guard depth < 2 else { return nil }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return nil
        }

        // Known model file extensions
        let modelExtensions = Set(["gguf", "ggml", "onnx", "mlmodel", "mlpackage", "tflite", "pte", "safetensors"])

        // Look for model files at this level
        for item in contents where modelExtensions.contains(item.pathExtension.lowercased()) {
            return item
        }

        // Recursively check subdirectories
        for item in contents {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                if let found = findSingleModelFile(in: item, depth: depth + 1) {
                    return found
                }
            }
        }

        return nil
    }

    /// Calculate size and file count for extracted content
    private func calculateExtractionStats(at url: URL) -> (Int64, Int) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: []
        ) else {
            return (0, 0)
        }

        var totalSize: Int64 = 0
        var fileCount = 0

        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]) {
                if values.isRegularFile == true {
                    fileCount += 1
                    totalSize += Int64(values.fileSize ?? 0)
                }
            }
        }

        return (totalSize, fileCount)
    }
}
