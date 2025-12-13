//
//  TTSCompletionParams.swift
//  RunAnywhere SDK
//
//  Parameters for TTS synthesis completion tracking
//

import Foundation

/// Parameters for TTS synthesis completion tracking
public struct TTSSynthesisCompletionParams {
    public let synthesisId: String
    public let modelId: String
    public let modelName: String
    public let framework: LLMFramework
    public let language: String
    public let characterCount: Int
    public let audioDurationMs: Double
    public let audioSizeBytes: Int
    public let sampleRate: Int
    public let processingTimeMs: Double

    public init(
        synthesisId: String,
        modelId: String,
        modelName: String,
        framework: LLMFramework,
        language: String,
        characterCount: Int,
        audioDurationMs: Double,
        audioSizeBytes: Int,
        sampleRate: Int,
        processingTimeMs: Double
    ) {
        self.synthesisId = synthesisId
        self.modelId = modelId
        self.modelName = modelName
        self.framework = framework
        self.language = language
        self.characterCount = characterCount
        self.audioDurationMs = audioDurationMs
        self.audioSizeBytes = audioSizeBytes
        self.sampleRate = sampleRate
        self.processingTimeMs = processingTimeMs
    }
}
