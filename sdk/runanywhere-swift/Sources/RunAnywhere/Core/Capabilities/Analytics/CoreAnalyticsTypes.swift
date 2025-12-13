//
//  CoreAnalyticsTypes.swift
//  RunAnywhere SDK
//
//  Core analytics types used across all capabilities.
//

import Foundation

// MARK: - Analytics Metrics Protocol

/// Base protocol for analytics metrics
public protocol AnalyticsMetrics: Sendable {
    var totalEvents: Int { get }
    var startTime: Date { get }
    var lastEventTime: Date? { get }
}

// MARK: - Inference Framework

/// Inference frameworks used for tracking which engine is processing requests.
/// Use "none" for services that don't require a model/framework.
public enum InferenceFrameworkType: String, Codable, Sendable {
    case llamaCpp = "llama_cpp"
    case whisperKit = "whisper_kit"
    case onnx = "onnx"
    case coreML = "core_ml"
    case foundationModels = "foundation_models"
    case mlx = "mlx"
    case builtIn = "built_in"  // For simple services like energy-based VAD
    case none = "none"         // For services that don't use a model
    case unknown = "unknown"
}

// MARK: - Model Lifecycle Event Types

/// Event types for model lifecycle across all capabilities
public enum ModelLifecycleEventType: String, Codable, Sendable {
    case loadingStarted = "model_loading_started"
    case loadCompleted = "model_load_completed"
    case loadFailed = "model_load_failed"
    case unloadCompleted = "model_unload_completed"
    case downloadStarted = "model_download_started"
    case downloadProgress = "model_download_progress"
    case downloadCompleted = "model_download_completed"
    case downloadFailed = "model_download_failed"
    case error = "model_lifecycle_error"
}

// MARK: - Model Lifecycle Metrics

/// Metrics for model lifecycle operations
public struct ModelLifecycleMetrics: AnalyticsMetrics, Sendable {
    public let totalEvents: Int
    public let startTime: Date
    public let lastEventTime: Date?
    public let totalLoads: Int
    public let successfulLoads: Int
    public let failedLoads: Int
    public let averageLoadTimeMs: Double
    public let totalUnloads: Int
    public let totalDownloads: Int
    public let successfulDownloads: Int
    public let failedDownloads: Int
    public let totalBytesDownloaded: Int64
    public let framework: InferenceFrameworkType

    public init(
        totalEvents: Int = 0,
        startTime: Date = Date(),
        lastEventTime: Date? = nil,
        totalLoads: Int = 0,
        successfulLoads: Int = 0,
        failedLoads: Int = 0,
        averageLoadTimeMs: Double = -1,  // -1 indicates N/A for services without models
        totalUnloads: Int = 0,
        totalDownloads: Int = 0,
        successfulDownloads: Int = 0,
        failedDownloads: Int = 0,
        totalBytesDownloaded: Int64 = 0,
        framework: InferenceFrameworkType = .unknown
    ) {
        self.totalEvents = totalEvents
        self.startTime = startTime
        self.lastEventTime = lastEventTime
        self.totalLoads = totalLoads
        self.successfulLoads = successfulLoads
        self.failedLoads = failedLoads
        self.averageLoadTimeMs = averageLoadTimeMs
        self.totalUnloads = totalUnloads
        self.totalDownloads = totalDownloads
        self.successfulDownloads = successfulDownloads
        self.failedDownloads = failedDownloads
        self.totalBytesDownloaded = totalBytesDownloaded
        self.framework = framework
    }
}
