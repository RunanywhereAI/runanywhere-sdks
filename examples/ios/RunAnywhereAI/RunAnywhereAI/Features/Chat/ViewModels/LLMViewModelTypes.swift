//
//  LLMViewModelTypes.swift
//  RunAnywhereAI
//
//  Supporting types for LLMViewModel
//

import Foundation

// MARK: - LLM Error

enum LLMError: LocalizedError {
    case noModelLoaded

    var errorDescription: String? {
        switch self {
        case .noModelLoaded:
            return "No model is loaded. Please select and load a model from the Models tab first."
        }
    }
}

// MARK: - Generation Metrics

struct GenerationMetricsFromSDK: Sendable {
    let generationId: String
    let modelId: String
    let inputTokens: Int
    let outputTokens: Int
    let durationMs: Double
    let tokensPerSecond: Double
    let timeToFirstTokenMs: Double?
}

// MARK: - Download Progress Delegate

/// URLSession delegate that reports download progress via a callback.
final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress(progress)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Handled by the async download call
    }
}
