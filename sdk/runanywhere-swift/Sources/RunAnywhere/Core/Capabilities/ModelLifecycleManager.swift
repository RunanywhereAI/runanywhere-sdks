//
//  ModelLifecycleManager.swift
//  RunAnywhere SDK
//
//  Unified model lifecycle management for all capabilities
//  Handles loading, unloading, and downloading of models/resources
//

import Foundation

// MARK: - Model Lifecycle Manager

/// Unified actor for managing model/resource lifecycle across all capabilities
/// Handles loading, unloading, state tracking, and concurrent access
public actor ModelLifecycleManager<ServiceType> {
    // MARK: - State

    /// The currently loaded service
    private var service: ServiceType?

    /// The ID of the currently loaded resource
    private var loadedResourceId: String?

    /// In-flight loading task
    private var inflightTask: Task<ServiceType, Error>?

    /// Configuration for loading
    private var configuration: (any ComponentConfiguration)?

    // MARK: - Dependencies

    private let logger: SDKLogger
    private let loadResource: @Sendable (String, (any ComponentConfiguration)?) async throws -> ServiceType
    private let unloadResource: @Sendable (ServiceType) async -> Void

    // MARK: - Initialization

    /// Initialize with resource loading closures
    /// - Parameters:
    ///   - category: Logger category
    ///   - loadResource: Closure to load a resource
    ///   - unloadResource: Closure to unload a resource
    public init(
        category: String,
        loadResource: @escaping @Sendable (String, (any ComponentConfiguration)?) async throws -> ServiceType,
        unloadResource: @escaping @Sendable (ServiceType) async -> Void
    ) {
        self.logger = SDKLogger(category: category)
        self.loadResource = loadResource
        self.unloadResource = unloadResource
    }

    // MARK: - State Properties

    /// Whether a resource is currently loaded
    public var isLoaded: Bool {
        service != nil
    }

    /// The currently loaded resource ID
    public var currentResourceId: String? {
        loadedResourceId
    }

    /// The currently loaded service
    public var currentService: ServiceType? {
        service
    }

    /// Current loading state
    public var state: CapabilityLoadingState {
        if let resourceId = loadedResourceId {
            return .loaded(resourceId: resourceId)
        }
        if inflightTask != nil {
            return .loading(resourceId: "")
        }
        return .idle
    }

    // MARK: - Configuration

    /// Set configuration for loading
    public func configure(_ config: (any ComponentConfiguration)?) {
        self.configuration = config
    }

    // MARK: - Lifecycle Operations

    /// Load a resource by ID
    /// - Parameter resourceId: The resource identifier
    /// - Returns: The loaded service
    @discardableResult
    public func load(_ resourceId: String) async throws -> ServiceType {
        // Check if already loaded with same ID
        if loadedResourceId == resourceId, let service = service {
            logger.info("Resource already loaded: \(resourceId)")
            return service
        }

        // Wait for existing load to complete
        if let existingTask = inflightTask {
            logger.info("Load in progress, waiting...")
            let result = try await existingTask.value

            // Check if the completed load was for our resource
            if loadedResourceId == resourceId {
                return result
            }
        }

        // Unload current if different
        if let currentService = service, loadedResourceId != resourceId {
            logger.info("Unloading current resource before loading new one")
            await unloadResource(currentService)
            service = nil
            loadedResourceId = nil
        }

        // Create loading task
        let config = configuration
        let loadTask = Task<ServiceType, Error> {
            try await loadResource(resourceId, config)
        }

        inflightTask = loadTask

        do {
            let loadedService = try await loadTask.value
            service = loadedService
            loadedResourceId = resourceId
            inflightTask = nil
            logger.info("Resource loaded successfully: \(resourceId)")
            return loadedService
        } catch {
            inflightTask = nil
            logger.error("Failed to load resource: \(error)")
            throw CapabilityError.loadFailed(resourceId, error)
        }
    }

    /// Unload the currently loaded resource
    public func unload() async {
        guard let currentService = service else { return }

        logger.info("Unloading resource: \(loadedResourceId ?? "unknown")")
        await unloadResource(currentService)
        service = nil
        loadedResourceId = nil
        logger.info("Resource unloaded successfully")
    }

    /// Reset all state
    public func reset() async {
        inflightTask?.cancel()
        inflightTask = nil

        if let currentService = service {
            await unloadResource(currentService)
        }

        service = nil
        loadedResourceId = nil
        configuration = nil
    }

    /// Get service or throw if not loaded
    public func requireService() throws -> ServiceType {
        guard let service = service else {
            throw CapabilityError.resourceNotLoaded("resource")
        }
        return service
    }
}

// MARK: - Factory Methods

extension ModelLifecycleManager where ServiceType == LLMService {
    /// Create a lifecycle manager for LLM capabilities
    public static func forLLM() -> ModelLifecycleManager<LLMService> {
        ModelLifecycleManager<LLMService>(
            category: "LLM.Lifecycle",
            loadResource: { resourceId, config in
                let logger = SDKLogger(category: "LLM.Loader")
                logger.info("Loading LLM model: \(resourceId)")

                let llmConfig = config as? LLMConfiguration ?? LLMConfiguration(modelId: resourceId)

                let service = try await MainActor.run {
                    Task {
                        try await ServiceRegistry.shared.createLLM(for: resourceId, config: llmConfig)
                    }
                }.value

                logger.info("LLM model loaded successfully: \(resourceId)")
                return service
            },
            unloadResource: { service in
                await service.cleanup()
            }
        )
    }
}

extension ModelLifecycleManager where ServiceType == STTService {
    /// Create a lifecycle manager for STT capabilities
    public static func forSTT() -> ModelLifecycleManager<STTService> {
        ModelLifecycleManager<STTService>(
            category: "STT.Lifecycle",
            loadResource: { resourceId, config in
                let logger = SDKLogger(category: "STT.Loader")
                logger.info("Loading STT model: \(resourceId)")

                let sttConfig = config as? STTConfiguration ?? STTConfiguration(modelId: resourceId)

                let service = try await MainActor.run {
                    Task {
                        try await ServiceRegistry.shared.createSTT(for: resourceId, config: sttConfig)
                    }
                }.value

                logger.info("STT model loaded successfully: \(resourceId)")
                return service
            },
            unloadResource: { service in
                await service.cleanup()
            }
        )
    }
}

extension ModelLifecycleManager where ServiceType == TTSService {
    /// Create a lifecycle manager for TTS capabilities
    public static func forTTS() -> ModelLifecycleManager<TTSService> {
        ModelLifecycleManager<TTSService>(
            category: "TTS.Lifecycle",
            loadResource: { resourceId, config in
                let logger = SDKLogger(category: "TTS.Loader")
                logger.info("Loading TTS voice: \(resourceId)")

                let ttsConfig = config as? TTSConfiguration ?? TTSConfiguration(voice: resourceId)

                let service = try await MainActor.run {
                    Task {
                        try await ServiceRegistry.shared.createTTS(for: resourceId, config: ttsConfig)
                    }
                }.value

                logger.info("TTS voice loaded successfully: \(resourceId)")
                return service
            },
            unloadResource: { service in
                await service.cleanup()
            }
        )
    }
}
