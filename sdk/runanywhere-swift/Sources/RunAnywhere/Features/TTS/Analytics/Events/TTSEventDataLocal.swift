//
//  TTSEventDataLocal.swift
//  RunAnywhere SDK
//
//  Local TTS event data models for internal analytics tracking
//

import Foundation

// MARK: - TTS Event Data Models

/// TTS synthesis start event data
public struct TTSSynthesisStartData: AnalyticsEventData {
    public let characterCount: Int
    public let voice: String
    public let language: String
    public let startTimestamp: TimeInterval

    public init(characterCount: Int, voice: String, language: String) {
        self.characterCount = characterCount
        self.voice = voice
        self.language = language
        self.startTimestamp = Date().timeIntervalSince1970
    }
}

/// TTS synthesis completion event data
public struct TTSSynthesisCompletionData: AnalyticsEventData {
    public let characterCount: Int
    public let audioDurationMs: Double
    public let audioSizeBytes: Int
    public let processingTimeMs: Double
    public let charactersPerSecond: Double
    public let realTimeFactor: Double

    public init(
        characterCount: Int,
        audioDurationMs: Double,
        audioSizeBytes: Int,
        processingTimeMs: Double
    ) {
        self.characterCount = characterCount
        self.audioDurationMs = audioDurationMs
        self.audioSizeBytes = audioSizeBytes
        self.processingTimeMs = processingTimeMs
        self.charactersPerSecond = processingTimeMs > 0 ? Double(characterCount) / (processingTimeMs / 1000.0) : 0
        self.realTimeFactor = audioDurationMs > 0 ? processingTimeMs / audioDurationMs : 0
    }
}
