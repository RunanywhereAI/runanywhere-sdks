//
//  ExtractionService.swift
//  RunAnywhere SDK
//
//  Centralized service for extracting model archives.
//  Uses native C++ extraction via libarchive (rac_extract_archive).
//  Located in Download as it's part of the download post-processing pipeline.
//

import CRACommons
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
public protocol ExtractionServiceProtocol: Sendable {
    /// Extract an archive based on the model's artifact type
    /// - Parameters:
    ///   - archiveURL: URL to the downloaded archive
    ///   - destinationURL: Directory to extract to
    ///   - artifactType: The model's artifact type (determines extraction method)
    ///   - framework: Inference framework (used for post-extraction model path finding)
    ///   - format: Model format (used for post-extraction model path finding)
    ///   - progressHandler: Optional callback for extraction progress (0.0 to 1.0)
    /// - Returns: Result containing the path to the extracted model
    func extract(
        archiveURL: URL,
        to destinationURL: URL,
        artifactType: ModelArtifactType,
        framework: InferenceFramework,
        format: ModelFormat,
        progressHandler: ((Double) -> Void)?
    ) async throws -> ExtractionResult
}

// MARK: - Protocol Extension for Backward Compatibility

extension ExtractionServiceProtocol {
    /// Convenience method without framework/format (defaults to .unknown)
    func extract(
        archiveURL: URL,
        to destinationURL: URL,
        artifactType: ModelArtifactType,
        progressHandler: ((Double) -> Void)?
    ) async throws -> ExtractionResult {
        return try await extract(
            archiveURL: archiveURL,
            to: destinationURL,
            artifactType: artifactType,
            framework: .unknown,
            format: .unknown,
            progressHandler: progressHandler
        )
    }
}

// MARK: - Default Extraction Service

/// Default implementation of the model extraction service
/// Uses native C++ extraction via libarchive for all archive types
public final class DefaultExtractionService: ExtractionServiceProtocol, @unchecked Sendable {
    private let logger = SDKLogger(category: "ExtractionService")

    public init() {}

    public func extract(
        archiveURL: URL,
        to destinationURL: URL,
        artifactType: ModelArtifactType,
        framework: InferenceFramework,
        format: ModelFormat,
        progressHandler: ((Double) -> Void)?
    ) async throws -> ExtractionResult {
        let startTime = Date()

        guard case .archive(_, let structure, _) = artifactType else {
            throw SDKException.download(.extractionFailed, "Artifact type does not require extraction")
        }

        logger.info("Starting extraction", metadata: [
            "archiveURL": archiveURL.path,
            "destination": destinationURL.path
        ])

        // Ensure destination exists
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        // Report starting
        progressHandler?(0.0)

        // Use native C++ extraction (libarchive) — auto-detects format from file contents
        let result = rac_extract_archive(
            archiveURL.path,
            destinationURL.path,
            nil,  // no progress callback needed (we report 0.0 and 1.0)
            nil   // no user data
        )

        guard result == RAC_SUCCESS else {
            throw SDKException.download(.extractionFailed, "Native extraction failed with code: \(result)")
        }

        // Find the actual model path using C++ rac_find_model_path_after_extraction()
        // This consolidates the previously duplicated findModelPath/findNestedDirectory/findSingleModelFile logic
        let modelPath = CppBridge.Download.findModelPathAfterExtraction(
            extractedDir: destinationURL,
            structure: structure,
            framework: framework,
            format: format
        ) ?? destinationURL

        // Calculate extracted size using C++ file manager (single source of truth)
        let extractedSize = CppBridge.FileManager.calculateDirectorySize(at: destinationURL)

        let duration = Date().timeIntervalSince(startTime)

        logger.info("Extraction completed", metadata: [
            "modelPath": modelPath.path,
            "extractedSize": extractedSize,
            "durationSeconds": duration
        ])

        progressHandler?(1.0)

        return ExtractionResult(
            modelPath: modelPath,
            extractedSize: extractedSize,
            fileCount: 0,
            durationSeconds: duration
        )
    }

}
