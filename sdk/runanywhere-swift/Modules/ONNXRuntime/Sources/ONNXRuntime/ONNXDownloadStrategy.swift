import Foundation
import RunAnywhere
import CRunAnywhereONNX
import os

/// Custom download strategy for ONNX models that handles .tar.bz2 archives
public class ONNXDownloadStrategy: DownloadStrategy {
    private let logger = Logger(subsystem: "com.runanywhere.onnx", category: "ONNXDownloadStrategy")

    public init() {}

    public func canHandle(model: ModelInfo) -> Bool {
        // Handle ONNX models with tar.bz2 archives (sherpa-onnx models)
        guard let url = model.downloadURL else { return false }

        let isTarBz2 = url.absoluteString.hasSuffix(".tar.bz2")
        let isONNX = model.compatibleFrameworks.contains(.onnx)

        let canHandle = isTarBz2 && isONNX
        logger.debug("canHandle(\(model.id)): \(canHandle) (url: \(url.absoluteString, privacy: .public))")
        return canHandle
    }

    public func download(
        model: ModelInfo,
        to destinationFolder: URL,
        progressHandler: ((Double) -> Void)?
    ) async throws -> URL {
        guard let downloadURL = model.downloadURL else {
            throw DownloadError.invalidURL
        }

        logger.info("Downloading sherpa-onnx archive for model: \(model.id)")

        // Use the provided destination folder
        let modelFolder = destinationFolder

        // Download the .tar.bz2 archive to a temporary location
        let tempDirectory = FileManager.default.temporaryDirectory
        let archivePath = tempDirectory.appendingPathComponent("\(model.id).tar.bz2")

        logger.info("Downloading archive to: \(archivePath.path)")

        // Download using URLSession with continuation for iOS 14 compatibility
        let tempURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let task = URLSession.shared.downloadTask(with: downloadURL) { (url, response, error) in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    continuation.resume(throwing: DownloadError.invalidResponse)
                    return
                }

                guard let url = url else {
                    continuation.resume(throwing: DownloadError.invalidResponse)
                    return
                }

                continuation.resume(returning: url)
            }
            task.resume()
        }

        // Move downloaded file to archive path
        try? FileManager.default.removeItem(at: archivePath)
        try FileManager.default.moveItem(at: tempURL, to: archivePath)

        // Report download complete (50% - download done, extraction next)
        progressHandler?(0.5)

        logger.info("Archive downloaded, extracting to: \(modelFolder.path)")

        // Extract the archive using ra_extract_tar_bz2
        let extractPath = modelFolder.path
        let status = ra_extract_tar_bz2(archivePath.path, extractPath)

        guard status == 0 else {
            logger.error("Failed to extract archive: status \(status)")
            throw DownloadError.extractionFailed("tar.bz2 extraction failed with status \(status)")
        }

        logger.info("Archive extracted successfully to: \(extractPath)")

        // Clean up the archive
        try? FileManager.default.removeItem(at: archivePath)

        // Find the extracted model directory
        // Sherpa-ONNX archives typically extract to a subdirectory with the model name
        let contents = try FileManager.default.contentsOfDirectory(atPath: extractPath)
        logger.debug("Extracted contents: \(contents.joined(separator: ", "))")

        // If there's a single subdirectory, the actual model files are in there
        var modelURL = URL(fileURLWithPath: extractPath)
        if contents.count == 1,
           let subdirName = contents.first {
            let subdirPath = (extractPath as NSString).appendingPathComponent(subdirName)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: subdirPath, isDirectory: &isDirectory),
               isDirectory.boolValue {
                // Model files are in the subdirectory
                modelURL = URL(fileURLWithPath: subdirPath)
                logger.info("Model files are in subdirectory: \(subdirName)")
            }
        }

        // Report completion (100%)
        progressHandler?(1.0)

        logger.info("Model download and extraction complete: \(modelURL.path)")

        return modelURL
    }
}
