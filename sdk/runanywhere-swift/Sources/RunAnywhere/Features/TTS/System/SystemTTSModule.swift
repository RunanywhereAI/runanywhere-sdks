//
//  SystemTTSModule.swift
//  RunAnywhere SDK
//
//  Built-in System TTS module using AVSpeechSynthesizer.
//  Auto-registered during SDK initialization as a fallback TTS option.
//

import Foundation

// MARK: - System TTS Module

/// Built-in System TTS module using Apple's AVSpeechSynthesizer.
///
/// This is automatically registered by the SDK as a low-priority fallback
/// when no other TTS providers (like ONNX) are available or when
/// explicitly requested via the "system-tts" model ID.
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

    /// Register System TTS with the ServiceRegistry
    @MainActor
    public static func register(priority: Int) {
        ServiceRegistry.shared.registerTTS(
            name: moduleName,
            priority: priority,
            canHandle: { voiceId in
                canHandleVoice(voiceId)
            },
            factory: { _ in
                try await createService()
            }
        )
        logger.info("System TTS registered (priority: \(priority))")
    }

    // MARK: - Private

    /// Check if this provider can handle the given voice ID
    private static func canHandleVoice(_ voiceId: String?) -> Bool {
        guard let voiceId = voiceId?.lowercased() else {
            // System TTS can handle nil (fallback)
            return true
        }

        // Explicitly handle system-tts requests
        return voiceId == "system-tts" || voiceId == "system_tts" || voiceId == "system"
    }

    /// Create a SystemTTSService instance
    private static func createService() async throws -> TTSService {
        let service = SystemTTSService()
        try await service.initialize()
        return service
    }
}

// MARK: - Auto-Registration

extension SystemTTS {
    /// Auto-register for discovery when SDK initializes
    public static let autoRegister: Void = {
        ModuleDiscovery.register(SystemTTS.self)
    }()
}
