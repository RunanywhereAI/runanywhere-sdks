//
//  ModelLifecycleManager.swift
//  RunAnywhere SDK
//
//  Generic model lifecycle manager for capability services.
//

import Foundation

// MARK: - Loading State

/// State of a capability's model loading
public enum CapabilityLoadingState: Sendable {
    case idle
    case loading(modelId: String)
    case loaded(modelId: String)
    case error(Error)

    public var isLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }
}

// MARK: - Model Lifecycle Manager

/// Generic actor for managing model lifecycle with type-safe service instances.
///
/// This provides common lifecycle operations for capabilities:
/// - Load/unload models
/// - Track current state
/// - Provide access to active service instances
public actor ModelLifecycleManager<ServiceType> {

    // MARK: - Properties

    private var _state: CapabilityLoadingState = .idle
    private var _currentService: ServiceType?
    private var _currentResourceId: String?
    private var _configuration: (any ComponentConfiguration)?
    private let serviceFactory: (String) async throws -> ServiceType
    private let serviceCleanup: (ServiceType) async -> Void

    // MARK: - Initialization

    public init(
        serviceFactory: @escaping (String) async throws -> ServiceType,
        serviceCleanup: @escaping (ServiceType) async -> Void = { _ in }
    ) {
        self.serviceFactory = serviceFactory
        self.serviceCleanup = serviceCleanup
    }

    // MARK: - State Accessors

    public var state: CapabilityLoadingState {
        _state
    }

    public var isLoaded: Bool {
        _state.isLoaded
    }

    public var currentResourceId: String? {
        _currentResourceId
    }

    public var currentService: ServiceType? {
        _currentService
    }

    // MARK: - Configuration

    public func configure(_ config: (any ComponentConfiguration)?) {
        _configuration = config
    }

    // MARK: - Lifecycle Operations

    /// Load a model and create its service instance
    @discardableResult
    public func load(_ resourceId: String) async throws -> ServiceType {
        // Already loaded with same ID?
        if _currentResourceId == resourceId, let service = _currentService {
            return service
        }

        // Unload previous
        if _currentService != nil {
            await unload()
        }

        _state = .loading(modelId: resourceId)

        do {
            let service = try await serviceFactory(resourceId)
            _currentService = service
            _currentResourceId = resourceId
            _state = .loaded(modelId: resourceId)
            return service
        } catch {
            _state = .error(error)
            throw error
        }
    }

    /// Unload the current model
    public func unload() async {
        if let service = _currentService {
            await serviceCleanup(service)
        }
        _currentService = nil
        _currentResourceId = nil
        _state = .idle
    }

    /// Reset the manager
    public func reset() async {
        await unload()
        _configuration = nil
    }

    /// Track an operation error
    public func trackOperationError(_ error: Error, operation: String) {
        // Could log or track the error here
        // For now, just update state
        _state = .error(error)
    }

    /// Get service or throw if not loaded
    public func requireService() throws -> ServiceType {
        guard let service = _currentService else {
            throw SDKError.general(.notInitialized, "No service is currently loaded")
        }
        return service
    }
}

// MARK: - Factory Methods

@MainActor
extension ModelLifecycleManager where ServiceType == LLMService {
    /// Create a lifecycle manager for LLM services
    public static func forLLM() -> ModelLifecycleManager<LLMService> {
        ModelLifecycleManager<LLMService>(
            serviceFactory: { modelId in
                let config = LLMConfiguration(modelId: modelId)
                return try await ServiceRegistry.shared.createLLM(config: config)
            },
            serviceCleanup: { service in
                await service.cleanup()
            }
        )
    }
}

@MainActor
extension ModelLifecycleManager where ServiceType == STTService {
    /// Create a lifecycle manager for STT services
    public static func forSTT() -> ModelLifecycleManager<STTService> {
        ModelLifecycleManager<STTService>(
            serviceFactory: { modelId in
                let config = STTConfiguration(modelId: modelId)
                return try await ServiceRegistry.shared.createSTT(config: config)
            },
            serviceCleanup: { service in
                await service.cleanup()
            }
        )
    }
}

@MainActor
extension ModelLifecycleManager where ServiceType == TTSService {
    /// Create a lifecycle manager for TTS services
    public static func forTTS() -> ModelLifecycleManager<TTSService> {
        ModelLifecycleManager<TTSService>(
            serviceFactory: { voiceId in
                let config = TTSConfiguration(voice: voiceId)
                return try await ServiceRegistry.shared.createTTS(config: config)
            },
            serviceCleanup: { service in
                await service.cleanup()
            }
        )
    }
}
