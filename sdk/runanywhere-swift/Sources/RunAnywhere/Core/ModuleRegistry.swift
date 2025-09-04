import Foundation

// MARK: - Module Registration System

/// Central registry for external AI module implementations
///
/// This allows optional dependencies to register their implementations
/// at runtime, enabling a plugin-based architecture where modules like
/// WhisperCPP, llama.cpp, and FluidAudioDiarization can be added as needed.
///
/// Example usage in your app:
/// ```swift
/// import RunAnywhere
/// import WhisperCPP  // Optional dependency
/// import LlamaCPP     // Optional dependency
///
/// // In your app initialization:
/// ModuleRegistry.shared.registerSTT(WhisperSTTProvider())
/// ModuleRegistry.shared.registerLLM(LlamaProvider())
/// ```
@MainActor
public final class ModuleRegistry {
    // MARK: - Singleton

    public static let shared = ModuleRegistry()

    // MARK: - Properties

    private var sttProviders: [STTServiceProvider] = []
    private var llmProviders: [LLMServiceProvider] = []
    private var speakerDiarizationProviders: [SpeakerDiarizationServiceProvider] = []
    private var vlmProviders: [VLMServiceProvider] = []
    private var wakeWordProviders: [WakeWordServiceProvider] = []

    private init() {}

    // MARK: - Registration Methods

    /// Register a Speech-to-Text provider (e.g., WhisperCPP)
    public func registerSTT(_ provider: STTServiceProvider) {
        sttProviders.append(provider)
        print("[ModuleRegistry] Registered STT provider: \(provider.name)")
    }

    /// Register a Language Model provider (e.g., llama.cpp)
    public func registerLLM(_ provider: LLMServiceProvider) {
        llmProviders.append(provider)
        print("[ModuleRegistry] Registered LLM provider: \(provider.name)")
    }

    /// Register a Speaker Diarization provider (e.g., FluidAudioDiarization)
    public func registerSpeakerDiarization(_ provider: SpeakerDiarizationServiceProvider) {
        speakerDiarizationProviders.append(provider)
        print("[ModuleRegistry] Registered Speaker Diarization provider: \(provider.name)")
    }

    /// Register a Vision Language Model provider
    public func registerVLM(_ provider: VLMServiceProvider) {
        vlmProviders.append(provider)
        print("[ModuleRegistry] Registered VLM provider: \(provider.name)")
    }

    /// Register a Wake Word Detection provider
    public func registerWakeWord(_ provider: WakeWordServiceProvider) {
        wakeWordProviders.append(provider)
        print("[ModuleRegistry] Registered Wake Word provider: \(provider.name)")
    }

    // MARK: - Provider Access

    /// Get an STT provider for the specified model
    public func sttProvider(for modelId: String? = nil) -> STTServiceProvider? {
        if let modelId = modelId {
            return sttProviders.first { $0.canHandle(modelId: modelId) }
        }
        return sttProviders.first
    }

    /// Get an LLM provider for the specified model
    public func llmProvider(for modelId: String? = nil) -> LLMServiceProvider? {
        if let modelId = modelId {
            return llmProviders.first { $0.canHandle(modelId: modelId) }
        }
        return llmProviders.first
    }

    /// Get a Speaker Diarization provider
    public func speakerDiarizationProvider(for modelId: String? = nil) -> SpeakerDiarizationServiceProvider? {
        if let modelId = modelId {
            return speakerDiarizationProviders.first { $0.canHandle(modelId: modelId) }
        }
        return speakerDiarizationProviders.first
    }

    /// Get a VLM provider for the specified model
    public func vlmProvider(for modelId: String? = nil) -> VLMServiceProvider? {
        if let modelId = modelId {
            return vlmProviders.first { $0.canHandle(modelId: modelId) }
        }
        return vlmProviders.first
    }

    /// Get a Wake Word provider
    public func wakeWordProvider(for modelId: String? = nil) -> WakeWordServiceProvider? {
        if let modelId = modelId {
            return wakeWordProviders.first { $0.canHandle(modelId: modelId) }
        }
        return wakeWordProviders.first
    }

    // MARK: - Availability Checking

    /// Check if STT is available
    public var hasSTT: Bool { !sttProviders.isEmpty }

    /// Check if LLM is available
    public var hasLLM: Bool { !llmProviders.isEmpty }

    /// Check if Speaker Diarization is available
    public var hasSpeakerDiarization: Bool { !speakerDiarizationProviders.isEmpty }

    /// Check if VLM is available
    public var hasVLM: Bool { !vlmProviders.isEmpty }

    /// Check if Wake Word Detection is available
    public var hasWakeWord: Bool { !wakeWordProviders.isEmpty }

    /// Get list of all registered modules
    public var registeredModules: [String] {
        var modules: [String] = []
        if hasSTT { modules.append("STT") }
        if hasLLM { modules.append("LLM") }
        if hasSpeakerDiarization { modules.append("SpeakerDiarization") }
        if hasVLM { modules.append("VLM") }
        if hasWakeWord { modules.append("WakeWord") }
        return modules
    }
}

// MARK: - Service Provider Protocols

// Service provider protocols are defined in their respective component files:
// - STTServiceProvider in STTComponent.swift
// - LLMServiceProvider in LLMComponent.swift
// - WakeWordServiceProvider in WakeWordComponent.swift
// - VLMServiceProvider and SpeakerDiarizationServiceProvider defined below

/// Provider for Vision Language Model services
public protocol VLMServiceProvider {
    func createVLMService(configuration: VLMConfiguration) async throws -> VLMService
    func canHandle(modelId: String?) -> Bool
    var name: String { get }
}

/// Provider for Speaker Diarization services
public protocol SpeakerDiarizationServiceProvider {
    func createSpeakerDiarizationService(configuration: SpeakerDiarizationConfiguration) async throws -> SpeakerDiarizationService
    func canHandle(modelId: String?) -> Bool
    var name: String { get }
}


// MARK: - SDK Component Extension
// Note: SDKComponent.wakeWord is now defined in the enum itself

// MARK: - Module Auto-Registration

/// Protocol for modules that can auto-register themselves
public protocol AutoRegisteringModule {
    static func register()
}

/// Example implementation for external modules:
/// ```swift
/// // In WhisperCPP module
/// public struct WhisperModule: AutoRegisteringModule {
///     public static func register() {
///         ModuleRegistry.shared.registerSTT(WhisperSTTProvider())
///     }
/// }
/// ```
