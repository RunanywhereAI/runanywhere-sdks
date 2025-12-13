//
//  TTSService.swift
//  RunAnywhere SDK
//
//  Protocol defining Text-to-Speech service capabilities
//

import Foundation

/// Protocol for text-to-speech services
public protocol TTSService: AnyObject { // swiftlint:disable:this avoid_any_object

    // MARK: - Framework Identification

    /// The inference framework used by this service.
    /// Required for analytics and performance tracking.
    var inferenceFramework: InferenceFrameworkType { get }

    /// Initialize the TTS service
    func initialize() async throws

    /// Synthesize text to audio
    /// - Parameters:
    ///   - text: The text to synthesize
    ///   - options: Synthesis options
    /// - Returns: Audio data
    func synthesize(text: String, options: TTSOptions) async throws -> Data

    /// Stream synthesis for long text
    /// - Parameters:
    ///   - text: The text to synthesize
    ///   - options: Synthesis options
    ///   - onChunk: Callback for each audio chunk
    func synthesizeStream(
        text: String,
        options: TTSOptions,
        onChunk: @escaping (Data) -> Void
    ) async throws

    /// Stop current synthesis
    func stop()

    /// Check if currently synthesizing
    var isSynthesizing: Bool { get }

    /// Get available voices
    var availableVoices: [String] { get }

    /// Cleanup resources
    func cleanup() async
}
