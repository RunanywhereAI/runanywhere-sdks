//
//  SystemTTSModule.swift
//  RunAnywhere SDK
//
//  Built-in System TTS module using AVSpeechSynthesizer.
//  Platform-specific fallback when no other TTS providers are available.
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
/// SystemTTS registers with the C++ service registry via Swift callbacks,
/// making it discoverable alongside C++ backends.
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

    // MARK: - Registration State

    private static var isRegistered = false

    /// Register System TTS module with the C++ service registry.
    ///
    /// This registers SystemTTS as a platform service in C++, making it
    /// discoverable via `CppBridge.Services.listProviders(for: .tts)`.
    @MainActor
    public static func register(priority: Int = 10) {
        guard !isRegistered else { return }

        logger.info("Registering SystemTTS with C++ registry (priority: \(priority))...")

        // Register module with C++ (for module discovery)
        var moduleInfo = rac_module_info_t()
        let version = "1.0.0"
        let description = "Apple System TTS via AVSpeechSynthesizer"

        moduleId.withCString { idPtr in
            moduleName.withCString { namePtr in
                version.withCString { versionPtr in
                    description.withCString { descPtr in
                        moduleInfo.id = idPtr
                        moduleInfo.name = namePtr
                        moduleInfo.version = versionPtr
                        moduleInfo.description = descPtr

                        var caps: [rac_capability_t] = [RAC_CAPABILITY_TTS]
                        caps.withUnsafeBufferPointer { capsPtr in
                            moduleInfo.capabilities = capsPtr.baseAddress
                            moduleInfo.num_capabilities = 1
                            _ = rac_module_register(&moduleInfo)
                        }
                    }
                }
            }
        }

        // Register service provider with C++ (via callbacks)
        let success = CppBridge.Services.registerPlatformService(
            name: moduleName,
            capability: .tts,
            priority: priority,
            canHandle: { voiceId in
                canHandle(voiceId: voiceId)
            },
            create: {
                try await createService()
            }
        )

        if success {
            isRegistered = true
            logger.info("✅ SystemTTS registered with C++ registry")
        } else {
            logger.error("❌ Failed to register SystemTTS with C++ registry")
        }
    }

    /// Unregister System TTS module
    public static func unregister() {
        guard isRegistered else { return }

        CppBridge.Services.unregisterPlatformService(name: moduleName, capability: .tts)
        _ = moduleId.withCString { rac_module_unregister($0) }

        isRegistered = false
        logger.info("SystemTTS unregistered")
    }

    // MARK: - Public API

    /// Check if this provider can handle the given voice ID
    public static func canHandle(voiceId: String?) -> Bool {
        guard let voiceId = voiceId?.lowercased() else {
            // System TTS can handle nil (fallback)
            return true
        }

        // Explicitly handle system-tts requests
        return voiceId == "system-tts" || voiceId == "system_tts" || voiceId == "system"
    }

    /// Create a SystemTTSService instance
    public static func createService() async throws -> SystemTTSService {
        let service = SystemTTSService()
        try await service.initialize()
        return service
    }
}

// MARK: - Auto-Registration

extension SystemTTS {
    /// Auto-register for discovery when SDK initializes
    public static let autoRegister: Void = {
        Task { @MainActor in
            SystemTTS.register()
        }
    }()
}
