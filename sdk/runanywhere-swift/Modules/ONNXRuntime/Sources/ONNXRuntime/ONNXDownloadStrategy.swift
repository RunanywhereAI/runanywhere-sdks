import Foundation
import RunAnywhere
import CRunAnywhereONNX

/// Custom download strategy for ONNX models that handles .tar.bz2 archives and direct .onnx files
public class ONNXDownloadStrategy: DownloadStrategy {
    private let logger = SDKLogger(category: "ONNXDownloadStrategy")

    public init() {}

    public func canHandle(model: ModelInfo) -> Bool {
        guard let url = model.downloadURL else { return false }
        let urlString = url.absoluteString.lowercased()

        let isONNX = model.compatibleFrameworks.contains(.onnx)

        // Handle tar.bz2 archives (sherpa-onnx models) - macOS only
        let isTarBz2 = urlString.hasSuffix(".tar.bz2")

        // Handle direct .onnx files (HuggingFace Piper models) - works on all platforms
        let isDirectOnnx = urlString.hasSuffix(".onnx")

        let canHandle = isONNX && (isTarBz2 || isDirectOnnx)
        logger.debug("canHandle(\(model.id)): \(canHandle) (url: \(url.absoluteString))")
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

        let urlString = downloadURL.absoluteString.lowercased()

        if urlString.hasSuffix(".onnx") {
            // Handle direct ONNX files (download model + config)
            return try await downloadDirectOnnx(model: model, downloadURL: downloadURL, to: destinationFolder, progressHandler: progressHandler)
        } else if urlString.hasSuffix(".tar.bz2") {
            // Handle tar.bz2 archives (macOS only)
            return try await downloadTarBz2Archive(model: model, downloadURL: downloadURL, to: destinationFolder, progressHandler: progressHandler)
        } else {
            throw DownloadError.invalidURL
        }
    }

    // MARK: - Direct ONNX File Download (for HuggingFace Piper models)

    /// Downloads direct .onnx files along with their companion .onnx.json config
    private func downloadDirectOnnx(
        model: ModelInfo,
        downloadURL: URL,
        to destinationFolder: URL,
        progressHandler: ((Double) -> Void)?
    ) async throws -> URL {
        logger.info("Downloading direct ONNX model: \(model.id)")

        // Create model folder
        let modelFolder = destinationFolder
        try FileManager.default.createDirectory(at: modelFolder, withIntermediateDirectories: true)

        // Get the model filename from URL
        let modelFilename = downloadURL.lastPathComponent
        let modelDestination = modelFolder.appendingPathComponent(modelFilename)

        // Also download the companion .onnx.json config file
        let configURL = URL(string: downloadURL.absoluteString + ".json")!
        let configFilename = modelFilename + ".json"
        let configDestination = modelFolder.appendingPathComponent(configFilename)

        logger.info("Downloading model file: \(modelFilename)")
        logger.info("Downloading config file: \(configFilename)")

        // Download model file (0% - 45%)
        try await downloadFile(from: downloadURL, to: modelDestination) { progress in
            progressHandler?(progress * 0.45)
        }

        logger.info("Model file downloaded, now downloading config...")
        progressHandler?(0.5)

        // Download config file (50% - 95%)
        do {
            try await downloadFile(from: configURL, to: configDestination) { progress in
                progressHandler?(0.5 + progress * 0.45)
            }
            logger.info("Config file downloaded successfully")
        } catch {
            // Config file might not exist for some models, log warning but continue
            logger.warning("Config file download failed (model may still work): \(error.localizedDescription)")
        }

        progressHandler?(1.0)

        logger.info("Direct ONNX model download complete: \(modelFolder.path)")
        return modelFolder
    }

    /// Helper to download a single file (iOS 14+ compatible)
    private func downloadFile(from url: URL, to destination: URL, progressHandler: ((Double) -> Void)?) async throws {
        logger.debug("Downloading file from: \(url.absoluteString)")

        // Download using URLSession with continuation for iOS 14 compatibility
        let tempURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let task = URLSession.shared.downloadTask(with: url) { (downloadedURL, response, error) in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    continuation.resume(throwing: DownloadError.invalidResponse)
                    return
                }

                guard let downloadedURL = downloadedURL else {
                    continuation.resume(throwing: DownloadError.invalidResponse)
                    return
                }

                continuation.resume(returning: downloadedURL)
            }
            task.resume()
        }

        // Move to destination
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)

        progressHandler?(1.0)
    }

    // MARK: - Native Archive Extraction

    /// Extract archive using native libarchive implementation from runanywhere-core
    /// This handles tar.bz2, tar.gz, tar.xz, and zip formats
    private func extractArchiveNative(from archiveURL: URL, to destinationURL: URL) throws {
        // Ensure destination directory exists
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        // Call the native C function from runanywhere-core via CRunAnywhereONNX
        let result = archiveURL.path.withCString { archivePath in
            destinationURL.path.withCString { destPath in
                ra_extract_archive(archivePath, destPath)
            }
        }

        // Check result code
        switch result {
        case RA_SUCCESS:
            logger.info("Native archive extraction succeeded")
        case RA_ERROR_NOT_IMPLEMENTED:
            logger.error("Archive extraction not implemented in this build")
            throw DownloadError.extractionFailed("Archive extraction not available (libarchive not linked)")
        case RA_ERROR_IO:
            logger.error("Archive extraction I/O error")
            throw DownloadError.extractionFailed("Archive extraction failed: I/O error")
        default:
            logger.error("Archive extraction failed with code: \(result.rawValue)")
            throw DownloadError.extractionFailed("Archive extraction failed with code: \(result.rawValue)")
        }
    }

    // MARK: - tar.bz2 Archive Download

    private func downloadTarBz2Archive(
        model: ModelInfo,
        downloadURL: URL,
        to destinationFolder: URL,
        progressHandler: ((Double) -> Void)?
    ) async throws -> URL {
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

        // Extract the archive using native libarchive implementation from runanywhere-core
        // This is much more robust than trying to decompress in Swift
        try extractArchiveNative(from: archivePath, to: modelFolder)

        logger.info("Archive extracted successfully to: \(modelFolder.path)")

        // Clean up the archive
        try? FileManager.default.removeItem(at: archivePath)

        // Find the extracted model directory
        // Sherpa-ONNX archives typically extract to a subdirectory with the model name
        let contents = try FileManager.default.contentsOfDirectory(atPath: modelFolder.path)
        logger.debug("Extracted contents: \(contents.joined(separator: ", "))")

        // If there's a single subdirectory, the actual model files are in there
        var modelURL = modelFolder
        if contents.count == 1,
           let subdirName = contents.first {
            let subdirPath = modelFolder.appendingPathComponent(subdirName).path
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
