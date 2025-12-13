//
//  ServiceRegistry.swift
//  RunAnywhere SDK
//
//  Unified registry for all AI service implementations.
//  Simple, clean architecture: Module → Service → Capability → Public API
//

import Foundation

// MARK: - Service Factory Types

/// Factory closure for creating STT services
public typealias STTServiceFactory = @Sendable (STTConfiguration) async throws -> STTService

/// Factory closure for creating LLM services
public typealias LLMServiceFactory = @Sendable (LLMConfiguration) async throws -> LLMService

/// Factory closure for creating TTS services
public typealias TTSServiceFactory = @Sendable (TTSConfiguration) async throws -> TTSService

/// Factory closure for creating VAD services
public typealias VADServiceFactory = @Sendable (VADConfiguration) async throws -> VADService

/// Factory closure for creating Speaker Diarization services
public typealias SpeakerDiarizationServiceFactory = @Sendable (SpeakerDiarizationConfiguration) async throws -> SpeakerDiarizationService

// MARK: - Service Registration

/// Registration info for a service factory
public struct ServiceRegistration<Factory>: Sendable where Factory: Sendable {
    public let name: String
    public let priority: Int
    public let canHandle: @Sendable (String?) -> Bool
    public let factory: Factory

    public init(
        name: String,
        priority: Int = 100,
        canHandle: @escaping @Sendable (String?) -> Bool,
        factory: Factory
    ) {
        self.name = name
        self.priority = priority
        self.canHandle = canHandle
        self.factory = factory
    }
}

// MARK: - Service Registry

/// Unified registry for all AI services
///
/// This is the single source of truth for service registration.
/// External modules register their factory closures here, and
/// capabilities use this registry to create service instances.
///
/// ## Usage
///
/// ### Registering a Service (in your module)
/// ```swift
/// import RunAnywhere
///
/// // Register your service
/// ServiceRegistry.shared.registerSTT(
///     name: "WhisperKit",
///     canHandle: { modelId in
///         modelId?.contains("whisper") ?? false
///     },
///     factory: { config in
///         let service = WhisperKitSTT()
///         try await service.initialize(modelPath: config.modelId)
///         return service
///     }
/// )
/// ```
@MainActor
public final class ServiceRegistry {
    public static let shared = ServiceRegistry()

    // MARK: - Storage

    private var sttRegistrations: [ServiceRegistration<STTServiceFactory>] = []
    private var llmRegistrations: [ServiceRegistration<LLMServiceFactory>] = []
    private var ttsRegistrations: [ServiceRegistration<TTSServiceFactory>] = []
    private var vadRegistrations: [ServiceRegistration<VADServiceFactory>] = []
    private var speakerDiarizationRegistrations: [ServiceRegistration<SpeakerDiarizationServiceFactory>] = []

    private let logger = SDKLogger(category: "ServiceRegistry")

    private init() {}

    // MARK: - STT Registration

    /// Register an STT service factory
    public func registerSTT(
        name: String,
        priority: Int = 100,
        canHandle: @escaping @Sendable (String?) -> Bool,
        factory: @escaping STTServiceFactory
    ) {
        let registration = ServiceRegistration(
            name: name,
            priority: priority,
            canHandle: canHandle,
            factory: factory
        )
        sttRegistrations.append(registration)
        sttRegistrations.sort { $0.priority > $1.priority }
        logger.info("Registered STT service: \(name) (priority: \(priority))")
    }

    /// Create an STT service for the given model
    public func createSTT(for modelId: String?, config: STTConfiguration) async throws -> STTService {
        guard let registration = sttRegistrations.first(where: { $0.canHandle(modelId) }) else {
            throw CapabilityError.providerNotFound("STT service for model: \(modelId ?? "default")")
        }

        logger.info("Creating STT service: \(registration.name) for model: \(modelId ?? "default")")
        return try await registration.factory(config)
    }

    /// Check if any STT service is registered
    public var hasSTT: Bool { !sttRegistrations.isEmpty }

    // MARK: - LLM Registration

    /// Register an LLM service factory
    public func registerLLM(
        name: String,
        priority: Int = 100,
        canHandle: @escaping @Sendable (String?) -> Bool,
        factory: @escaping LLMServiceFactory
    ) {
        let registration = ServiceRegistration(
            name: name,
            priority: priority,
            canHandle: canHandle,
            factory: factory
        )
        llmRegistrations.append(registration)
        llmRegistrations.sort { $0.priority > $1.priority }
        logger.info("Registered LLM service: \(name) (priority: \(priority))")
    }

    /// Create an LLM service for the given model
    public func createLLM(for modelId: String?, config: LLMConfiguration) async throws -> LLMService {
        guard let registration = llmRegistrations.first(where: { $0.canHandle(modelId) }) else {
            throw CapabilityError.providerNotFound("LLM service for model: \(modelId ?? "default")")
        }

        logger.info("Creating LLM service: \(registration.name) for model: \(modelId ?? "default")")
        return try await registration.factory(config)
    }

    /// Check if any LLM service is registered
    public var hasLLM: Bool { !llmRegistrations.isEmpty }

    // MARK: - TTS Registration

    /// Register a TTS service factory
    public func registerTTS(
        name: String,
        priority: Int = 100,
        canHandle: @escaping @Sendable (String?) -> Bool,
        factory: @escaping TTSServiceFactory
    ) {
        let registration = ServiceRegistration(
            name: name,
            priority: priority,
            canHandle: canHandle,
            factory: factory
        )
        ttsRegistrations.append(registration)
        ttsRegistrations.sort { $0.priority > $1.priority }
        logger.info("Registered TTS service: \(name) (priority: \(priority))")
    }

    /// Create a TTS service for the given voice
    public func createTTS(for voiceId: String?, config: TTSConfiguration) async throws -> TTSService {
        guard let registration = ttsRegistrations.first(where: { $0.canHandle(voiceId) }) else {
            throw CapabilityError.providerNotFound("TTS service for voice: \(voiceId ?? "default")")
        }

        logger.info("Creating TTS service: \(registration.name) for voice: \(voiceId ?? "default")")
        return try await registration.factory(config)
    }

    /// Check if any TTS service is registered
    public var hasTTS: Bool { !ttsRegistrations.isEmpty }

    // MARK: - VAD Registration

    /// Register a VAD service factory
    public func registerVAD(
        name: String,
        priority: Int = 100,
        factory: @escaping VADServiceFactory
    ) {
        let registration = ServiceRegistration<VADServiceFactory>(
            name: name,
            priority: priority,
            canHandle: { _ in true },
            factory: factory
        )
        vadRegistrations.append(registration)
        vadRegistrations.sort { $0.priority > $1.priority }
        logger.info("Registered VAD service: \(name) (priority: \(priority))")
    }

    /// Create a VAD service
    public func createVAD(config: VADConfiguration) async throws -> VADService {
        guard let registration = vadRegistrations.first else {
            throw CapabilityError.providerNotFound("VAD service")
        }

        logger.info("Creating VAD service: \(registration.name)")
        return try await registration.factory(config)
    }

    /// Check if any VAD service is registered
    public var hasVAD: Bool { !vadRegistrations.isEmpty }

    // MARK: - Speaker Diarization Registration

    /// Register a Speaker Diarization service factory
    public func registerSpeakerDiarization(
        name: String,
        priority: Int = 100,
        canHandle: @escaping @Sendable (String?) -> Bool = { _ in true },
        factory: @escaping SpeakerDiarizationServiceFactory
    ) {
        let registration = ServiceRegistration(
            name: name,
            priority: priority,
            canHandle: canHandle,
            factory: factory
        )
        speakerDiarizationRegistrations.append(registration)
        speakerDiarizationRegistrations.sort { $0.priority > $1.priority }
        logger.info("Registered Speaker Diarization service: \(name) (priority: \(priority))")
    }

    /// Create a Speaker Diarization service
    public func createSpeakerDiarization(
        for modelId: String? = nil,
        config: SpeakerDiarizationConfiguration
    ) async throws -> SpeakerDiarizationService {
        guard let registration = speakerDiarizationRegistrations.first(where: { $0.canHandle(modelId) }) else {
            throw CapabilityError.providerNotFound("Speaker Diarization service")
        }

        logger.info("Creating Speaker Diarization service: \(registration.name)")
        return try await registration.factory(config)
    }

    /// Check if any Speaker Diarization service is registered
    public var hasSpeakerDiarization: Bool { !speakerDiarizationRegistrations.isEmpty }

    // MARK: - Availability

    /// List of registered service types
    public var registeredServices: [String] {
        var services: [String] = []
        if hasSTT { services.append("STT") }
        if hasLLM { services.append("LLM") }
        if hasTTS { services.append("TTS") }
        if hasVAD { services.append("VAD") }
        if hasSpeakerDiarization { services.append("SpeakerDiarization") }
        return services
    }

    // MARK: - Reset

    /// Reset all registrations
    public func reset() {
        sttRegistrations.removeAll()
        llmRegistrations.removeAll()
        ttsRegistrations.removeAll()
        vadRegistrations.removeAll()
        speakerDiarizationRegistrations.removeAll()
        logger.info("Service registry reset")
    }
}
