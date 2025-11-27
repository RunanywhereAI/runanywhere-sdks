import Foundation
import RunAnywhere

/// Custom storage strategy for WhisperKit models that handles downloading and file management
public class WhisperKitStorageStrategy: ModelStorageStrategy, DownloadStrategy {
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
    private let logger = SDKLogger(category: "WhisperKitDownload")

    public init() {
        // Public initializer for use outside the module
    }

    // MARK: - ModelStorageStrategy Implementation

    public func findModelPath(modelId: String, in modelFolder: URL) -> URL? {
        // WhisperKit models are directory-based, return the folder itself
        let fileManager = FileManager.default

        // Check if the required .mlmodelc directories exist
        let audioEncoderPath = modelFolder.appendingPathComponent("AudioEncoder.mlmodelc")
        let textDecoderPath = modelFolder.appendingPathComponent("TextDecoder.mlmodelc")

        // If core components exist, return the folder as the model path
        if fileManager.fileExists(atPath: audioEncoderPath.path) &&
           fileManager.fileExists(atPath: textDecoderPath.path) {
            logger.debug("Found WhisperKit model at: \(modelFolder.path)")
            return modelFolder
        }

        return nil
    }

    public func detectModel(in modelFolder: URL) -> (format: ModelFormat, size: Int64)? {
        // Check if this is a valid WhisperKit model folder
        let fileManager = FileManager.default

        // Required components for a WhisperKit model
        let requiredComponents = [
            "AudioEncoder.mlmodelc",
            "TextDecoder.mlmodelc"
        ]

        // Check if required components exist
        for component in requiredComponents {
            let componentPath = modelFolder.appendingPathComponent(component)
            if !fileManager.fileExists(atPath: componentPath.path) {
                return nil
            }
        }

        // Calculate total size of all files
        let totalSize = calculateDirectorySize(at: modelFolder)

        // WhisperKit models are Core ML models
        return (.mlmodel, totalSize)
    }

    public func isValidModelStorage(at modelFolder: URL) -> Bool {
        // Check if all required WhisperKit components are present
        let fileManager = FileManager.default

        // At minimum, we need AudioEncoder and TextDecoder
        let audioEncoderPath = modelFolder.appendingPathComponent("AudioEncoder.mlmodelc")
        let textDecoderPath = modelFolder.appendingPathComponent("TextDecoder.mlmodelc")

        return fileManager.fileExists(atPath: audioEncoderPath.path) &&
               fileManager.fileExists(atPath: textDecoderPath.path)
    }

    public func getModelStorageInfo(at modelFolder: URL) -> ModelStorageDetails? {
        guard let modelInfo = detectModel(in: modelFolder) else { return nil }

        // Count all files in the model folder
        let fileManager = FileManager.default
        var fileCount = 0

        if let enumerator = fileManager.enumerator(at: modelFolder, includingPropertiesForKeys: nil) {
            for _ in enumerator {
                fileCount += 1
            }
        }

        return ModelStorageDetails(
            format: modelInfo.format,
            totalSize: modelInfo.size,
            fileCount: fileCount,
            primaryFile: nil, // WhisperKit is multi-file
            isDirectoryBased: true
        )
    }

    private func calculateDirectorySize(at url: URL) -> Int64 {
        var totalSize: Int64 = 0

        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: []) {
            for case let fileURL as URL in enumerator {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        }

        return totalSize
    }

    public func canHandle(model: ModelInfo) -> Bool {
        // Handle speech recognition models compatible with WhisperKit
        return model.category == .speechRecognition &&
               (model.preferredFramework == .whisperKit ||
                model.compatibleFrameworks.contains(.whisperKit))
    }

    public func download(
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
