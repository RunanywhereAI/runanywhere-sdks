//
//  ONNXModelStorageStrategy.swift
//  RunAnywhere SDK - ONNX Runtime Module
//
//  Implements ModelStorageStrategy for ONNX models to handle nested directory structures.
//  Download and extraction is handled by the SDK's built-in AlamofireDownloadService
//  and ModelExtractionService based on the model's artifactType.
//

import Foundation
import RunAnywhere

/// Storage strategy for ONNX models that handles nested directory structures
/// (e.g., sherpa-onnx archives extract to subdirectories like /model-name/encoder.onnx)
///
/// Note: This class only handles post-download model detection and path resolution.
/// All download and extraction is handled by the SDK automatically based on `ModelInfo.artifactType`.
public final class ONNXModelStorageStrategy: ModelStorageStrategy {
    private let logger = SDKLogger(category: "ONNXModelStorageStrategy")

    public init() {}

    // MARK: - ModelStorageStrategy Implementation

    /// Find the model path within a model folder (handles nested sherpa-onnx structure)
    public func findModelPath(modelId: String, in modelFolder: URL) -> URL? {
        // First check if there's a direct .onnx file at root
        if let directModel = findOnnxFile(in: modelFolder) {
            return directModel
        }

        // Check for nested subdirectory (sherpa-onnx tar.bz2 structure)
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: modelFolder, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return nil
        }

        for item in contents {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                // Check this subdirectory for .onnx files
                if let nestedModel = findOnnxFile(in: item) {
                    return nestedModel
                }
            }
        }

        return nil
    }

    /// Detect if an ONNX model exists in the given folder (supports nested directories)
    public func detectModel(in modelFolder: URL) -> (format: ModelFormat, size: Int64)? {
        if findOnnxFileRecursive(in: modelFolder) != nil {
            let size = calculateDirectorySize(at: modelFolder)
            return (.onnx, size)
        }
        return nil
    }

    /// Check if model storage is valid (has .onnx file)
    public func isValidModelStorage(at modelFolder: URL) -> Bool {
        return findOnnxFileRecursive(in: modelFolder) != nil
    }

    /// Get detailed model storage info
    public func getModelStorageInfo(at modelFolder: URL) -> ModelStorageDetails? {
        guard let onnxFile = findOnnxFileRecursive(in: modelFolder) else { return nil }

        let totalSize = calculateDirectorySize(at: modelFolder)
        let fileCount = countFiles(in: modelFolder)

        return ModelStorageDetails(
            format: .onnx,
            totalSize: totalSize,
            fileCount: fileCount,
            primaryFile: onnxFile.lastPathComponent,
            isDirectoryBased: true
        )
    }

    // MARK: - Helper Methods

    /// Find .onnx file in a directory (non-recursive)
    private func findOnnxFile(in folder: URL) -> URL? {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return nil
        }

        for item in contents where item.pathExtension.lowercased() == "onnx" {
            return item
        }
        return nil
    }

    /// Find .onnx file recursively (up to 2 levels deep for sherpa-onnx structure)
    private func findOnnxFileRecursive(in folder: URL, depth: Int = 0) -> URL? {
        let maxDepth = 2 // sherpa-onnx structure: modelFolder/vits-xxx/model.onnx
        if depth > maxDepth { return nil }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return nil
        }

        // First check for .onnx files at this level
        for item in contents where item.pathExtension.lowercased() == "onnx" {
            return item
        }

        // Then recursively check subdirectories
        for item in contents {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                if let found = findOnnxFileRecursive(in: item, depth: depth + 1) {
                    return found
                }
            }
        }

        return nil
    }

    /// Calculate total size of a directory
    private func calculateDirectorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [], errorHandler: nil) else {
            return 0
        }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(size)
            }
        }
        return totalSize
    }

    /// Count files in a directory recursively
    private func countFiles(in url: URL) -> Int {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [], errorHandler: nil) else {
            return 0
        }

        var count = 0
        for case let fileURL as URL in enumerator {
            if let isFile = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile, isFile {
                count += 1
            }
        }
        return count
    }
}
