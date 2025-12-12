//
//  TTSFrameworkAdapter.swift
//  RunAnywhere SDK
//
//  Protocol for TTS framework adapters
//

import Foundation

/// Protocol for TTS framework adapters
///
/// Framework adapters bridge between the generic TTS interface and
/// specific framework implementations (e.g., AVSpeechSynthesizer, ONNX, etc.)
public protocol TTSFrameworkAdapter: ComponentAdapter where ServiceType: TTSService {
    /// Create a TTS service for the given configuration
    /// - Parameter configuration: TTS configuration
    /// - Returns: A configured TTSService instance
    func createTTSService(configuration: TTSConfiguration) async throws -> ServiceType
}
