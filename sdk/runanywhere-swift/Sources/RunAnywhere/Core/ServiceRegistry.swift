//
//  ServiceRegistry.swift
//  RunAnywhere SDK
//
//  Central registry for service providers.
//  Manages registration and creation of AI services (LLM, STT, TTS, VAD).
//

import Foundation

// MARK: - Service Provider Types

/// Typealias for LLM service factory
public typealias LLMServiceFactory = @Sendable (LLMConfiguration) async throws -> LLMService

/// Typealias for STT service factory
public typealias STTServiceFactory = @Sendable (STTConfiguration) async throws -> STTService

/// Typealias for TTS service factory
public typealias TTSServiceFactory = @Sendable (TTSConfiguration) async throws -> TTSService

/// Typealias for VAD service factory
public typealias VADServiceFactory = @Sendable (VADConfiguration) async throws -> VADService

/// Typealias for can-handle predicate (takes optional model/voice ID)
public typealias CanHandlePredicate = @Sendable (String?) -> Bool

// MARK: - Provider Structs

/// LLM Service Provider registration
private struct LLMProvider: Sendable {
    let name: String
    let priority: Int
    let canHandle: CanHandlePredicate
    let factory: LLMServiceFactory
}

/// STT Service Provider registration
private struct STTProvider: Sendable {
    let name: String
    let priority: Int
    let canHandle: CanHandlePredicate
    let factory: STTServiceFactory
}

/// TTS Service Provider registration
private struct TTSProvider: Sendable {
    let name: String
    let priority: Int
    let canHandle: CanHandlePredicate
    let factory: TTSServiceFactory
}

/// VAD Service Provider registration
private struct VADProvider: Sendable {
    let name: String
    let priority: Int
    let canHandle: CanHandlePredicate
    let factory: VADServiceFactory
}

// MARK: - ServiceRegistry

/// Central registry for AI service providers.
///
/// The ServiceRegistry manages registration and creation of AI services.
/// Providers register themselves with a priority and a `canHandle` predicate
/// that determines if they can handle a specific model/voice ID request.
///
/// ## Usage
///
/// ```swift
/// // Register a provider
/// ServiceRegistry.shared.registerLLM(
///     name: "LlamaCPP",
///     priority: 100,
///     canHandle: { modelId in modelId?.contains("gguf") == true },
///     factory: { config in try await LlamaCPPService(config: config) }
/// )
///
/// // Create a service (finds best matching provider)
/// let service = try await ServiceRegistry.shared.createLLM(config: .init(modelId: "my-model.gguf"))
/// ```
@MainActor
public final class ServiceRegistry {

    // MARK: - Singleton

    /// Shared instance
    public static let shared = ServiceRegistry()

    // MARK: - Private State

    private var llmProviders: [LLMProvider] = []
    private var sttProviders: [STTProvider] = []
    private var ttsProviders: [TTSProvider] = []
    private var vadProviders: [VADProvider] = []

    private let logger = SDKLogger(category: "ServiceRegistry")

    private init() {}

    // MARK: - Public State

    /// Whether any LLM provider is registered
    public var hasLLM: Bool { !llmProviders.isEmpty }

    /// Whether any STT provider is registered
    public var hasSTT: Bool { !sttProviders.isEmpty }

    /// Whether any TTS provider is registered
    public var hasTTS: Bool { !ttsProviders.isEmpty }

    /// Whether any VAD provider is registered
    public var hasVAD: Bool { !vadProviders.isEmpty }

    // MARK: - LLM Registration

    /// Register an LLM service provider.
    ///
    /// - Parameters:
    ///   - name: Provider name for logging/debugging
    ///   - priority: Higher priority providers are tried first
    ///   - canHandle: Predicate to check if provider can handle a model ID
    ///   - factory: Factory function to create the service
    public func registerLLM(
        name: String,
        priority: Int,
        canHandle: @Sendable @escaping (String?) -> Bool,
        factory: @Sendable @escaping (LLMConfiguration) async throws -> LLMService
    ) {
        let provider = LLMProvider(name: name, priority: priority, canHandle: canHandle, factory: factory)
        llmProviders.append(provider)
        llmProviders.sort { $0.priority > $1.priority }
        logger.info("Registered LLM provider: \(name) (priority: \(priority))")
    }

    /// Create an LLM service for the given configuration.
    ///
    /// - Parameter config: LLM configuration
    /// - Returns: Configured LLM service
    /// - Throws: SDKError if no provider can handle the request
    public func createLLM(config: LLMConfiguration) async throws -> LLMService {
        logger.debug("Creating LLM service for model: \(config.modelId ?? "nil")")

        // Find provider that can handle this model
        if let provider = llmProviders.first(where: { $0.canHandle(config.modelId) }) {
            logger.debug("Using LLM provider: \(provider.name)")
            return try await provider.factory(config)
        }

        // No provider found
        throw SDKError.llm(.serviceNotAvailable, "No LLM provider can handle model: \(config.modelId ?? "nil")")
    }

    // MARK: - STT Registration

    /// Register an STT service provider.
    ///
    /// - Parameters:
    ///   - name: Provider name for logging/debugging
    ///   - priority: Higher priority providers are tried first
    ///   - canHandle: Predicate to check if provider can handle a model ID
    ///   - factory: Factory function to create the service
    public func registerSTT(
        name: String,
        priority: Int,
        canHandle: @Sendable @escaping (String?) -> Bool,
        factory: @Sendable @escaping (STTConfiguration) async throws -> STTService
    ) {
        let provider = STTProvider(name: name, priority: priority, canHandle: canHandle, factory: factory)
        sttProviders.append(provider)
        sttProviders.sort { $0.priority > $1.priority }
        logger.info("Registered STT provider: \(name) (priority: \(priority))")
    }

    /// Create an STT service for the given configuration.
    ///
    /// - Parameter config: STT configuration
    /// - Returns: Configured STT service
    /// - Throws: SDKError if no provider can handle the request
    public func createSTT(config: STTConfiguration) async throws -> STTService {
        logger.debug("Creating STT service for model: \(config.modelId ?? "nil")")

        if let provider = sttProviders.first(where: { $0.canHandle(config.modelId) }) {
            logger.debug("Using STT provider: \(provider.name)")
            return try await provider.factory(config)
        }

        throw SDKError.stt(.serviceNotAvailable, "No STT provider can handle model: \(config.modelId ?? "nil")")
    }

    // MARK: - TTS Registration

    /// Register a TTS service provider.
    ///
    /// - Parameters:
    ///   - name: Provider name for logging/debugging
    ///   - priority: Higher priority providers are tried first
    ///   - canHandle: Predicate to check if provider can handle a voice ID
    ///   - factory: Factory function to create the service
    public func registerTTS(
        name: String,
        priority: Int,
        canHandle: @Sendable @escaping (String?) -> Bool,
        factory: @Sendable @escaping (TTSConfiguration) async throws -> TTSService
    ) {
        let provider = TTSProvider(name: name, priority: priority, canHandle: canHandle, factory: factory)
        ttsProviders.append(provider)
        ttsProviders.sort { $0.priority > $1.priority }
        logger.info("Registered TTS provider: \(name) (priority: \(priority))")
    }

    /// Create a TTS service for the given configuration.
    ///
    /// - Parameter config: TTS configuration
    /// - Returns: Configured TTS service
    /// - Throws: SDKError if no provider can handle the request
    public func createTTS(config: TTSConfiguration) async throws -> TTSService {
        logger.debug("Creating TTS service for voice: \(config.voice)")

        if let provider = ttsProviders.first(where: { $0.canHandle(config.modelId) }) {
            logger.debug("Using TTS provider: \(provider.name)")
            return try await provider.factory(config)
        }

        throw SDKError.tts(.serviceNotAvailable, "No TTS provider can handle voice: \(config.voice)")
    }

    // MARK: - VAD Registration

    /// Register a VAD service provider.
    ///
    /// - Parameters:
    ///   - name: Provider name for logging/debugging
    ///   - priority: Higher priority providers are tried first
    ///   - canHandle: Predicate to check if provider can handle the request
    ///   - factory: Factory function to create the service
    public func registerVAD(
        name: String,
        priority: Int,
        canHandle: @Sendable @escaping (String?) -> Bool,
        factory: @Sendable @escaping (VADConfiguration) async throws -> VADService
    ) {
        let provider = VADProvider(name: name, priority: priority, canHandle: canHandle, factory: factory)
        vadProviders.append(provider)
        vadProviders.sort { $0.priority > $1.priority }
        logger.info("Registered VAD provider: \(name) (priority: \(priority))")
    }

    /// Create a VAD service for the given configuration.
    ///
    /// - Parameter config: VAD configuration
    /// - Returns: Configured VAD service
    /// - Throws: SDKError if no provider can handle the request
    public func createVAD(config: VADConfiguration) async throws -> VADService {
        logger.debug("Creating VAD service")

        if let provider = vadProviders.first(where: { $0.canHandle(config.modelId) }) {
            logger.debug("Using VAD provider: \(provider.name)")
            return try await provider.factory(config)
        }

        throw SDKError.vad(.serviceNotAvailable, "No VAD provider available")
    }

    // MARK: - Reset

    /// Reset the registry, removing all providers.
    ///
    /// - Important: This should only be called by `RunAnywhere.reset()`.
    internal func reset() {
        llmProviders.removeAll()
        sttProviders.removeAll()
        ttsProviders.removeAll()
        vadProviders.removeAll()
        logger.info("ServiceRegistry reset")
    }
}
