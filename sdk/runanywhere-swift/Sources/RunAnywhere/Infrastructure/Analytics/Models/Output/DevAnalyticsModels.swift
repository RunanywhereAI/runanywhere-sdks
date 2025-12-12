//
//  DevAnalyticsModels.swift
//  RunAnywhere SDK
//
//  Models for development analytics submission to Supabase
//

import Foundation

// MARK: - Request Model

public struct DevAnalyticsSubmissionRequest: Codable, Sendable {
    public let generationId: String
    public let deviceId: String
    public let modelId: String
    public let tokensPerSecond: Double
    public let totalGenerationTimeMs: Double
    public let inputTokens: Int
    public let outputTokens: Int
    public let success: Bool
    public let buildToken: String
    public let sdkVersion: String
    public let timestamp: String
    public let hostAppIdentifier: String?
    public let hostAppName: String?
    public let hostAppVersion: String?

    public init(
        generationId: String,
        deviceId: String,
        modelId: String,
        tokensPerSecond: Double,
        totalGenerationTimeMs: Double,
        inputTokens: Int,
        outputTokens: Int,
        success: Bool,
        buildToken: String,
        sdkVersion: String,
        timestamp: String,
        hostAppIdentifier: String? = nil,
        hostAppName: String? = nil,
        hostAppVersion: String? = nil
    ) {
        self.generationId = generationId
        self.deviceId = deviceId
        self.modelId = modelId
        self.tokensPerSecond = tokensPerSecond
        self.totalGenerationTimeMs = totalGenerationTimeMs
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.success = success
        self.buildToken = buildToken
        self.sdkVersion = sdkVersion
        self.timestamp = timestamp
        self.hostAppIdentifier = hostAppIdentifier
        self.hostAppName = hostAppName
        self.hostAppVersion = hostAppVersion
    }

    enum CodingKeys: String, CodingKey {
        case generationId = "generation_id"
        case deviceId = "device_id"
        case modelId = "model_id"
        case tokensPerSecond = "tokens_per_second"
        case totalGenerationTimeMs = "total_generation_time_ms"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case success
        case buildToken = "build_token"
        case sdkVersion = "sdk_version"
        case timestamp
        case hostAppIdentifier = "host_app_identifier"
        case hostAppName = "host_app_name"
        case hostAppVersion = "host_app_version"
    }
}

// MARK: - Response Model

public struct DevAnalyticsSubmissionResponse: Codable, Sendable {
    public let success: Bool
    public let analyticsId: String?

    public init(success: Bool, analyticsId: String?) {
        self.success = success
        self.analyticsId = analyticsId
    }

    enum CodingKeys: String, CodingKey {
        case success
        case analyticsId = "analytics_id"
    }
}
