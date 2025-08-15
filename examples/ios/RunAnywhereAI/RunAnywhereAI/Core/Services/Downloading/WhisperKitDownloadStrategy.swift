import Foundation
import RunAnywhereSDK
import os

/// Custom download strategy for WhisperKit models that require multiple files
class WhisperKitDownloadStrategy: DownloadStrategy {
    // WhisperKit model structure: mlmodelc directories contain multiple files
    // Note: Not all models have all files, we'll check existence before downloading
    private let mlmodelcFiles = [
        "AudioEncoder.mlmodelc": [
            "coremldata.bin",
            "metadata.json",
            "model.mil",
            "model.mlmodel",
            "weights/weight.bin"
        ],
        "MelSpectrogram.mlmodelc": [
            "coremldata.bin",
            "metadata.json",
            "model.mil"
            // Note: MelSpectrogram doesn't have model.mlmodel
        ],
        "TextDecoder.mlmodelc": [
            "coremldata.bin",
            "metadata.json",
            "model.mil",
            "model.mlmodel",
            "weights/weight.bin"
        ]
    ]

    private let configFiles = [
        "config.json",
        "generation_config.json"
    ]

    // Use the SDK's logger directly
    private let logger = os.Logger(subsystem: "com.runanywhere.app", category: "WhisperKitDownload")

    func canHandle(model: ModelInfo) -> Bool {
        // Handle models marked as WhisperKit
        model.preferredFramework == .whisperKit ||
        model.compatibleFrameworks.contains(.whisperKit)
    }

    func download(
        model: ModelInfo,
        to destinationFolder: URL,
        progressHandler: ((Double) -> Void)?
    ) async throws -> URL {
        logger.info("Starting WhisperKit download for model: \(model.id)")

        // Get base URL from model's downloadURL or use default HuggingFace URL
        let baseURL: String
        if let modelURL = model.downloadURL {
            // Extract base URL from provided URL
            let urlString = modelURL.absoluteString
            if let range = urlString.range(of: "/resolve/main/") {
                baseURL = String(urlString[..<range.upperBound])
            } else {
                baseURL = "https://huggingface.co/argmaxinc/whisperkit-coreml/resolve/main/"
            }
        } else {
            // Default HuggingFace base URL
            baseURL = "https://huggingface.co/argmaxinc/whisperkit-coreml/resolve/main/"
        }

        // Map model ID to HuggingFace path
        let modelPath = mapToHuggingFacePath(model.id)

        // Create destination folder if needed
        try FileManager.default.createDirectory(
            at: destinationFolder,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Calculate total files to download
        var totalFiles = configFiles.count
        for (_, files) in mlmodelcFiles {
            totalFiles += files.count
        }
        var filesDownloaded = 0

        // Download mlmodelc directories
        for (mlmodelcDir, files) in mlmodelcFiles {
            let dirPath = destinationFolder.appendingPathComponent(mlmodelcDir)

            // Create mlmodelc directory structure
            try FileManager.default.createDirectory(
                at: dirPath,
                withIntermediateDirectories: true,
                attributes: nil
            )

            // Create subdirectories if needed
            let analyticsPath = dirPath.appendingPathComponent("analytics")
            let weightsPath = dirPath.appendingPathComponent("weights")
            try FileManager.default.createDirectory(at: analyticsPath, withIntermediateDirectories: true, attributes: nil)
            try FileManager.default.createDirectory(at: weightsPath, withIntermediateDirectories: true, attributes: nil)

            // Download each file in the mlmodelc directory
            for file in files {
                let fileURLString = "\(baseURL)\(modelPath)/\(mlmodelcDir)/\(file)"
                guard let fileURL = URL(string: fileURLString) else {
                    logger.error("Invalid URL: \(fileURLString)")
                    throw DownloadError.invalidURL
                }

                logger.debug("Attempting to download \(file) from \(fileURL.absoluteString)")

                do {
                    // Download file using URLSession
                    let (localURL, response) = try await URLSession.shared.download(from: fileURL)

                    // Check response
                    guard let httpResponse = response as? HTTPURLResponse else {
                        logger.warning("File \(file) might not exist, skipping")
                        filesDownloaded += 1
                        let progress = Double(filesDownloaded) / Double(totalFiles)
                        progressHandler?(progress)
                        continue
                    }

                    if httpResponse.statusCode == 404 {
                        // File doesn't exist, skip it
                        logger.info("File \(file) not found (404), skipping - this is normal for some models")
                        filesDownloaded += 1
                        let progress = Double(filesDownloaded) / Double(totalFiles)
                        progressHandler?(progress)
                        continue
                    }

                    guard httpResponse.statusCode == 200 else {
                        logger.error("Failed to download \(file): HTTP \(httpResponse.statusCode)")
                        throw DownloadError.httpError(httpResponse.statusCode)
                    }

                    // Determine destination path
                    let destPath = dirPath.appendingPathComponent(file)

                    // Remove existing file if present
                    if FileManager.default.fileExists(atPath: destPath.path) {
                        try FileManager.default.removeItem(at: destPath)
                    }

                    // Move to destination
                    try FileManager.default.moveItem(at: localURL, to: destPath)
                    logger.debug("Saved \(file) to \(destPath.path)")

                    filesDownloaded += 1
                    let progress = Double(filesDownloaded) / Double(totalFiles)
                    progressHandler?(progress)
                } catch {
                    // Log error but continue with other files
                    logger.warning("Failed to download \(file): \(error.localizedDescription), continuing...")
                    filesDownloaded += 1
                    let progress = Double(filesDownloaded) / Double(totalFiles)
                    progressHandler?(progress)
                }
            }
        }

        // Download config files
        for configFile in configFiles {
            let fileURLString = "\(baseURL)\(modelPath)/\(configFile)"
            guard let fileURL = URL(string: fileURLString) else {
                throw DownloadError.invalidURL
            }

            logger.debug("Downloading \(configFile) from \(fileURL.absoluteString)")

            // Download file using URLSession
            let (localURL, response) = try await URLSession.shared.download(from: fileURL)

            // Check response
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                logger.error("Failed to download \(configFile): HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                throw DownloadError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
            }

            // Move to destination
            let destPath = destinationFolder.appendingPathComponent(configFile)

            // Remove existing file if present
            if FileManager.default.fileExists(atPath: destPath.path) {
                try FileManager.default.removeItem(at: destPath)
            }

            try FileManager.default.moveItem(at: localURL, to: destPath)
            logger.debug("Saved \(configFile) to \(destPath.path)")

            filesDownloaded += 1
            let progress = Double(filesDownloaded) / Double(totalFiles)
            progressHandler?(progress)
        }

        logger.info("WhisperKit download complete for model: \(model.id)")
        return destinationFolder
    }

    private func mapToHuggingFacePath(_ modelId: String) -> String {
        // Map model IDs to HuggingFace repository paths
        // Handle both short names and full user-prefixed IDs
        let cleanId = modelId
            .replacingOccurrences(of: "user-", with: "")
            .components(separatedBy: "-")
            .dropLast() // Remove the hash suffix if present
            .joined(separator: "-")

        switch cleanId {
        case "whisper-tiny", "openai_whisper-tiny": return "openai_whisper-tiny.en"
        case "whisper-base", "openai_whisper-base": return "openai_whisper-base"
        case "whisper-small", "openai_whisper-small": return "openai_whisper-small"
        case "whisper-medium", "openai_whisper-medium": return "openai_whisper-medium"
        case "whisper-large", "openai_whisper-large": return "openai_whisper-large-v3"
        default:
            // Try to extract model name from complex IDs
            if modelId.contains("whisper-tiny") || modelId.contains("whisper_tiny") {
                return "openai_whisper-tiny.en"
            } else if modelId.contains("whisper-base") || modelId.contains("whisper_base") {
                return "openai_whisper-base"
            } else if modelId.contains("whisper-small") || modelId.contains("whisper_small") {
                return "openai_whisper-small"
            }
            return modelId
        }
    }
}
