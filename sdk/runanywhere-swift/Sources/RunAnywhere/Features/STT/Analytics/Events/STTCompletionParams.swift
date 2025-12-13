//
//  STTCompletionParams.swift
//  RunAnywhere SDK
//
//  Parameters for STT transcription completion tracking
//

import Foundation

// MARK: - STT Completion Parameters

/// Parameters for STT transcription completion tracking
public struct STTTranscriptionCompletionParams {
    public let sessionId: String
    public let modelId: String
    public let modelName: String
    public let framework: LLMFramework
    public let language: String
    public let audioDurationMs: Double
    public let processingTimeMs: Double
    public let wordCount: Int
    public let characterCount: Int
    public let confidence: Float

    public init(
        sessionId: String,
        modelId: String,
        modelName: String,
        framework: LLMFramework,
        language: String,
        audioDurationMs: Double,
        processingTimeMs: Double,
        wordCount: Int,
        characterCount: Int,
        confidence: Float
    ) {
        self.sessionId = sessionId
        self.modelId = modelId
        self.modelName = modelName
        self.framework = framework
        self.language = language
        self.audioDurationMs = audioDurationMs
        self.processingTimeMs = processingTimeMs
        self.wordCount = wordCount
        self.characterCount = characterCount
        self.confidence = confidence
    }
}
