//
//  DefaultTTSAdapter.swift
//  RunAnywhere SDK
//
//  Default TTS adapter using system TTS
//

import Foundation

/// Default TTS adapter using system TTS
///
/// This adapter creates SystemTTSService instances which use
/// Apple's AVSpeechSynthesizer for text-to-speech synthesis.
public final class DefaultTTSAdapter: ComponentAdapter {
    public typealias ServiceType = SystemTTSService

    // MARK: - Initialization

    public init() {}

    // MARK: - ComponentAdapter

    public func createService(configuration: any ComponentConfiguration) async throws -> SystemTTSService {
        guard let ttsConfig = configuration as? TTSConfiguration else {
            throw TTSError.invalidConfiguration(reason: "Expected TTSConfiguration")
        }
        return try await createTTSService(configuration: ttsConfig)
    }

    // MARK: - TTS Service Creation

    public func createTTSService(configuration: TTSConfiguration) async throws -> SystemTTSService {
        let service = SystemTTSService()
        try await service.initialize()
        return service
    }
}
