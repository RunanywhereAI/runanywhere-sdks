//
//  GenerationEventData.swift
//  RunAnywhere SDK
//
//  LLM/Generation-specific event data models
//

import Foundation

// MARK: - Generation Event Data Models

/// Generation start event data
public struct GenerationStartData: AnalyticsEventData {
    public let generationId: String
    public let modelId: String
    public let executionTarget: String
    public let promptTokens: Int
    public let maxTokens: Int

    public init(generationId: String, modelId: String, executionTarget: String, promptTokens: Int, maxTokens: Int) {
        self.generationId = generationId
        self.modelId = modelId
        self.executionTarget = executionTarget
        self.promptTokens = promptTokens
        self.maxTokens = maxTokens
    }

}

/// Generation completion event data with full telemetry fields
public struct GenerationCompletionData: AnalyticsEventData {
    // Model info
    public let modelId: String
    public let modelName: String?
    public let framework: String?

    // Device info
    public let device: String?
    public let osVersion: String?
    public let platform: String?
    public let sdkVersion: String?

    // Common performance metrics
    public let processingTimeMs: Double?
    public let success: Bool
    public let errorMessage: String?
    public let errorCode: String?

    // LLM-specific fields
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let totalTokens: Int?
    public let tokensPerSecond: Double?
    public let timeToFirstTokenMs: Double?
    public let promptEvalTimeMs: Double?
    public let generationTimeMs: Double?
    public let contextLength: Int?
    public let temperature: Double?
    public let maxTokens: Int?

    /// Full initializer with all telemetry fields
    public init(
        modelId: String,
        modelName: String?,
        framework: String?,
        device: String?,
        osVersion: String?,
        platform: String?,
        sdkVersion: String?,
        processingTimeMs: Double?,
        success: Bool,
        errorMessage: String? = nil,
        errorCode: String? = nil,
        inputTokens: Int?,
        outputTokens: Int?,
        totalTokens: Int?,
        tokensPerSecond: Double?,
        timeToFirstTokenMs: Double?,
        promptEvalTimeMs: Double? = nil,
        generationTimeMs: Double?,
        contextLength: Int? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil
    ) {
        self.modelId = modelId
        self.modelName = modelName
        self.framework = framework
        self.device = device
        self.osVersion = osVersion
        self.platform = platform
        self.sdkVersion = sdkVersion
        self.processingTimeMs = processingTimeMs
        self.success = success
        self.errorMessage = errorMessage
        self.errorCode = errorCode
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.tokensPerSecond = tokensPerSecond
        self.timeToFirstTokenMs = timeToFirstTokenMs
        self.promptEvalTimeMs = promptEvalTimeMs
        self.generationTimeMs = generationTimeMs
        self.contextLength = contextLength
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}

/// Streaming update event data
public struct StreamingUpdateData: AnalyticsEventData {
    public let generationId: String
    public let tokensGenerated: Int

    public init(generationId: String, tokensGenerated: Int) {
        self.generationId = generationId
        self.tokensGenerated = tokensGenerated
    }

}

/// First token event data
public struct FirstTokenData: AnalyticsEventData {
    public let generationId: String
    public let timeToFirstTokenMs: Double

    public init(generationId: String, timeToFirstTokenMs: Double) {
        self.generationId = generationId
        self.timeToFirstTokenMs = timeToFirstTokenMs
    }
}

/// Model loading event data with full telemetry fields
public struct ModelLoadingData: AnalyticsEventData {
    // Model info
    public let modelId: String
    public let modelName: String?
    public let framework: String?

    // Device info
    public let device: String?
    public let osVersion: String?
    public let platform: String?
    public let sdkVersion: String?

    // Performance metrics
    public let processingTimeMs: Double?
    public let success: Bool
    public let errorMessage: String?
    public let errorCode: String?

    public init(
        modelId: String,
        loadTimeMs: Double,
        success: Bool,
        errorCode: String? = nil
    ) {
        self.modelId = modelId
        self.modelName = nil
        self.framework = nil
        self.device = nil
        self.osVersion = nil
        self.platform = nil
        self.sdkVersion = nil
        self.processingTimeMs = loadTimeMs
        self.success = success
        self.errorMessage = nil
        self.errorCode = errorCode
    }

    public init(
        modelId: String,
        modelName: String?,
        framework: String?,
        device: String?,
        osVersion: String?,
        platform: String?,
        sdkVersion: String?,
        processingTimeMs: Double?,
        success: Bool,
        errorMessage: String? = nil,
        errorCode: String? = nil
    ) {
        self.modelId = modelId
        self.modelName = modelName
        self.framework = framework
        self.device = device
        self.osVersion = osVersion
        self.platform = platform
        self.sdkVersion = sdkVersion
        self.processingTimeMs = processingTimeMs
        self.success = success
        self.errorMessage = errorMessage
        self.errorCode = errorCode
    }
}

/// Model unloading event data
public struct ModelUnloadingData: AnalyticsEventData {
    public let modelId: String
    public let timestamp: TimeInterval

    public init(modelId: String) {
        self.modelId = modelId
        self.timestamp = Date().timeIntervalSince1970
    }
}
