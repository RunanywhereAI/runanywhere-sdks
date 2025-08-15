import Foundation
import RunAnywhereSDK
import os

/// Custom download strategy for WhisperKit models that require multiple files
class WhisperKitDownloadStrategy: DownloadStrategy {

    // WhisperKit models need these 5 files
    private let requiredFiles = [
        "AudioEncoder.mlmodelc",
        "MelSpectrogram.mlmodelc",
        "TextDecoder.mlmodelc",
        "config.json",
        "generation_config.json"
    ]

    // Use the SDK's logger directly
    private let logger = os.Logger(subsystem: "com.runanywhere.app", category: "WhisperKitDownload")

    func canHandle(model: ModelInfo) -> Bool {
        // Handle models marked as WhisperKit
        return model.preferredFramework == .whisperKit ||
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
            // Expected format: https://huggingface.co/argmaxinc/whisperkit-coreml/resolve/main/{model_path}/
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

        // Download each required file
        for (index, fileName) in requiredFiles.enumerated() {
            let fileURLString = "\(baseURL)\(modelPath)/\(fileName)"
            guard let fileURL = URL(string: fileURLString) else {
                throw DownloadError.invalidURL
            }

            logger.debug("Downloading \(fileName) from \(fileURL.absoluteString)")

            // Download file using URLSession
            let (localURL, response) = try await URLSession.shared.download(from: fileURL)

            // Check response
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw DownloadError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
            }

            // Move to destination
            let destPath = destinationFolder.appendingPathComponent(fileName)

            // Remove existing file if present
            if FileManager.default.fileExists(atPath: destPath.path) {
                try FileManager.default.removeItem(at: destPath)
            }

            try FileManager.default.moveItem(at: localURL, to: destPath)
            logger.debug("Saved \(fileName) to \(destPath.path)")

            // Report progress
            let progress = Double(index + 1) / Double(requiredFiles.count)
            progressHandler?(progress)
        }

        logger.info("WhisperKit download complete for model: \(model.id)")
        return destinationFolder
    }

    private func mapToHuggingFacePath(_ modelId: String) -> String {
        // Map model IDs to HuggingFace repository paths
        switch modelId {
        case "whisper-tiny": return "openai_whisper-tiny.en"
        case "whisper-base": return "openai_whisper-base"
        case "whisper-small": return "openai_whisper-small"
        case "whisper-medium": return "openai_whisper-medium"
        case "whisper-large": return "openai_whisper-large-v3"
        default: return modelId
        }
    }
}
