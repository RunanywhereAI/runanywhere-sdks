//
//  SystemTTSModule.swift
//  RunAnywhere SDK
//
//  Built-in System TTS module using AVSpeechSynthesizer.
//  Platform-specific fallback when no other TTS providers are available.
//
//  Registration is now handled by the C++ platform backend. This module
//  provides the Swift service implementation that the C++ backend calls.
//

import CRACommons
import Foundation

// MARK: - System TTS Module

/// Built-in System TTS module using Apple's AVSpeechSynthesizer.
///
/// This is a platform-specific (iOS/macOS) TTS provider that serves as
/// a fallback when no other TTS providers (like ONNX Piper) are available
/// or when explicitly requested via the "system-tts" voice ID.
///
/// The C++ platform backend handles registration with the service registry.
/// This Swift module provides the actual implementation through callbacks.
///
/// ## Usage
///
/// ```swift
/// // Use system TTS explicitly
/// try await RunAnywhere.speak("Hello", voiceId: "system-tts")
///
/// // Or as automatic fallback when no other TTS is available
/// try await RunAnywhere.speak("Hello")
/// ```
public enum SystemTTS: RunAnywhereModule {
    private static let logger = SDKLogger(category: "SystemTTS")

    // MARK: - RunAnywhereModule Conformance

    public static let moduleId = "system-tts"
    public static let moduleName = "System TTS"
    public static let capabilities: Set<SDKComponent> = [.tts]
    public static let defaultPriority: Int = 10  // Low priority - fallback only

    /// System TTS uses Apple's built-in speech synthesis
    public static let inferenceFramework: InferenceFramework = .systemTTS

    // MARK: - Public API

    /// Check if this provider can handle the given voice ID
    public static func canHandle(voiceId: String?) -> Bool {
        guard let voiceId = voiceId else {
            // System TTS can handle nil (fallback for TTS)
            return true
        }

        let lowercasedId = voiceId.lowercased()
        return lowercasedId.contains("system-tts")
            || lowercasedId.contains("system_tts")
            || lowercasedId == "system"
            || lowercasedId == "system-tts-default"
    }

    /// Create a SystemTTSService instance
    @MainActor
    public static func createService() async throws -> SystemTTSService {
        let service = SystemTTSService()
        try await service.initialize()
        return service
    }
}
