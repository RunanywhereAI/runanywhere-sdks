//
//  STTConfiguration.swift
//  RunAnywhere SDK
//
//  Configuration for STT component
//

import Foundation

// MARK: - STT Configuration

/// Configuration for STT component (conforms to ComponentConfiguration and ComponentInitParameters protocols)
public struct STTConfiguration: ComponentConfiguration, ComponentInitParameters {
    /// Component type
    public var componentType: SDKComponent { .stt }

    /// Model ID
    public let modelId: String?

    // Model parameters
    public let language: String
    public let sampleRate: Int
    public let enablePunctuation: Bool
    public let enableDiarization: Bool
    public let vocabularyList: [String]
    public let maxAlternatives: Int
    public let enableTimestamps: Bool

    public init(
        modelId: String? = nil,
        language: String = "en-US",
        sampleRate: Int = 16000,
        enablePunctuation: Bool = true,
        enableDiarization: Bool = false,
        vocabularyList: [String] = [],
        maxAlternatives: Int = 1,
        enableTimestamps: Bool = true
    ) {
        self.modelId = modelId
        self.language = language
        self.sampleRate = sampleRate
        self.enablePunctuation = enablePunctuation
        self.enableDiarization = enableDiarization
        self.vocabularyList = vocabularyList
        self.maxAlternatives = maxAlternatives
        self.enableTimestamps = enableTimestamps
    }

    public func validate() throws {
        guard sampleRate > 0 && sampleRate <= 48000 else {
            throw RunAnywhereError.validationFailed("Sample rate must be between 1 and 48000 Hz")
        }
        guard maxAlternatives > 0 && maxAlternatives <= 10 else {
            throw RunAnywhereError.validationFailed("Max alternatives must be between 1 and 10")
        }
    }
}
