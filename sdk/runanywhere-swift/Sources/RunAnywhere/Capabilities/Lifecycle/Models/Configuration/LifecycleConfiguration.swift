//
//  LifecycleConfiguration.swift
//  RunAnywhere SDK
//
//  Configuration for all lifecycle operations (model, service, component)
//

import Foundation

/// Configuration for lifecycle management across all SDK components
public struct LifecycleConfiguration: Sendable {

    // MARK: - Model Lifecycle Configuration

    /// Maximum total memory to allocate for loaded models (in bytes)
    /// Default: 0 (unlimited)
    public var maxTotalMemory: Int64

    /// Memory threshold at which to start unloading unused models (in bytes)
    /// Default: 0 (never auto-unload)
    public var memoryPressureThreshold: Int64

    /// Whether to automatically unload models when memory pressure is detected
    public var autoUnloadOnMemoryPressure: Bool

    /// Whether to allow concurrent model loading
    public var allowConcurrentLoading: Bool

    /// Maximum number of models to keep loaded per modality
    /// Default: 1 (single model per modality)
    public var maxModelsPerModality: Int

    /// Whether to cache service instances for reuse
    public var cacheServices: Bool

    /// Timeout for model loading operations (in seconds)
    /// Default: 300 (5 minutes)
    public var loadTimeout: TimeInterval

    /// Timeout for model unloading operations (in seconds)
    /// Default: 60 (1 minute)
    public var unloadTimeout: TimeInterval

    // MARK: - Service Lifecycle Configuration

    /// Whether to start services automatically on registration
    public var autoStartServices: Bool

    /// Timeout for service startup (in seconds)
    /// Default: 30 seconds
    public var serviceStartTimeout: TimeInterval

    /// Timeout for service shutdown (in seconds)
    /// Default: 30 seconds
    public var serviceStopTimeout: TimeInterval

    /// Whether to restart services on failure
    public var restartOnFailure: Bool

    /// Maximum number of restart attempts
    /// Default: 3
    public var maxRestartAttempts: Int

    // MARK: - Component Lifecycle Configuration

    /// Whether to initialize components in parallel where possible
    public var parallelComponentInitialization: Bool

    /// Timeout for component initialization (in seconds)
    /// Default: 60 seconds
    public var componentInitTimeout: TimeInterval

    /// Whether to cleanup components on shutdown
    public var cleanupOnShutdown: Bool

    /// Priority for component initialization (higher = earlier)
    public var componentInitPriority: Int

    // MARK: - Logging Configuration

    /// Enable detailed lifecycle logging
    public var enableDetailedLogging: Bool

    /// Log lifecycle events to EventBus
    public var logToEventBus: Bool

    // MARK: - Initialization

    public init(
        // Model lifecycle
        maxTotalMemory: Int64 = 0,
        memoryPressureThreshold: Int64 = 0,
        autoUnloadOnMemoryPressure: Bool = false,
        allowConcurrentLoading: Bool = false,
        maxModelsPerModality: Int = 1,
        cacheServices: Bool = true,
        loadTimeout: TimeInterval = 300,
        unloadTimeout: TimeInterval = 60,
        // Service lifecycle
        autoStartServices: Bool = false,
        serviceStartTimeout: TimeInterval = 30,
        serviceStopTimeout: TimeInterval = 30,
        restartOnFailure: Bool = false,
        maxRestartAttempts: Int = 3,
        // Component lifecycle
        parallelComponentInitialization: Bool = true,
        componentInitTimeout: TimeInterval = 60,
        cleanupOnShutdown: Bool = true,
        componentInitPriority: Int = 0,
        // Logging
        enableDetailedLogging: Bool = false,
        logToEventBus: Bool = true
    ) {
        self.maxTotalMemory = maxTotalMemory
        self.memoryPressureThreshold = memoryPressureThreshold
        self.autoUnloadOnMemoryPressure = autoUnloadOnMemoryPressure
        self.allowConcurrentLoading = allowConcurrentLoading
        self.maxModelsPerModality = maxModelsPerModality
        self.cacheServices = cacheServices
        self.loadTimeout = loadTimeout
        self.unloadTimeout = unloadTimeout
        self.autoStartServices = autoStartServices
        self.serviceStartTimeout = serviceStartTimeout
        self.serviceStopTimeout = serviceStopTimeout
        self.restartOnFailure = restartOnFailure
        self.maxRestartAttempts = maxRestartAttempts
        self.parallelComponentInitialization = parallelComponentInitialization
        self.componentInitTimeout = componentInitTimeout
        self.cleanupOnShutdown = cleanupOnShutdown
        self.componentInitPriority = componentInitPriority
        self.enableDetailedLogging = enableDetailedLogging
        self.logToEventBus = logToEventBus
    }

    // MARK: - Presets

    /// Default configuration for standard usage
    public static let `default` = LifecycleConfiguration()

    /// Configuration optimized for low memory devices
    public static let lowMemory = LifecycleConfiguration(
        maxTotalMemory: 1024 * 1024 * 1024, // 1GB
        memoryPressureThreshold: 512 * 1024 * 1024, // 512MB
        autoUnloadOnMemoryPressure: true,
        maxModelsPerModality: 1,
        cacheServices: false,
        parallelComponentInitialization: false
    )

    /// Configuration for high-performance usage
    public static let highPerformance = LifecycleConfiguration(
        maxTotalMemory: 0, // Unlimited
        autoUnloadOnMemoryPressure: false,
        allowConcurrentLoading: true,
        maxModelsPerModality: 3,
        cacheServices: true,
        parallelComponentInitialization: true
    )

    /// Configuration for development/debugging
    public static let debug = LifecycleConfiguration(
        enableDetailedLogging: true,
        logToEventBus: true
    )

    // MARK: - Validation

    /// Validate the configuration
    public func validate() throws {
        if maxModelsPerModality < 1 {
            throw LifecycleError.invalidConfiguration(
                reason: "maxModelsPerModality must be at least 1"
            )
        }
        if loadTimeout <= 0 {
            throw LifecycleError.invalidConfiguration(
                reason: "loadTimeout must be positive"
            )
        }
        if unloadTimeout <= 0 {
            throw LifecycleError.invalidConfiguration(
                reason: "unloadTimeout must be positive"
            )
        }
        if serviceStartTimeout <= 0 {
            throw LifecycleError.invalidConfiguration(
                reason: "serviceStartTimeout must be positive"
            )
        }
        if serviceStopTimeout <= 0 {
            throw LifecycleError.invalidConfiguration(
                reason: "serviceStopTimeout must be positive"
            )
        }
        if componentInitTimeout <= 0 {
            throw LifecycleError.invalidConfiguration(
                reason: "componentInitTimeout must be positive"
            )
        }
        if maxRestartAttempts < 0 {
            throw LifecycleError.invalidConfiguration(
                reason: "maxRestartAttempts must be non-negative"
            )
        }
    }
}

// MARK: - Builder Pattern

extension LifecycleConfiguration {
    /// Create a configuration builder
    public static func builder() -> Builder {
        Builder()
    }

    public class Builder {
        private var config = LifecycleConfiguration()

        // Model lifecycle
        public func maxTotalMemory(_ bytes: Int64) -> Builder {
            config.maxTotalMemory = bytes
            return self
        }

        public func memoryPressureThreshold(_ bytes: Int64) -> Builder {
            config.memoryPressureThreshold = bytes
            return self
        }

        public func autoUnloadOnMemoryPressure(_ enabled: Bool) -> Builder {
            config.autoUnloadOnMemoryPressure = enabled
            return self
        }

        public func allowConcurrentLoading(_ enabled: Bool) -> Builder {
            config.allowConcurrentLoading = enabled
            return self
        }

        public func maxModelsPerModality(_ count: Int) -> Builder {
            config.maxModelsPerModality = count
            return self
        }

        public func cacheServices(_ enabled: Bool) -> Builder {
            config.cacheServices = enabled
            return self
        }

        public func loadTimeout(_ seconds: TimeInterval) -> Builder {
            config.loadTimeout = seconds
            return self
        }

        public func unloadTimeout(_ seconds: TimeInterval) -> Builder {
            config.unloadTimeout = seconds
            return self
        }

        // Service lifecycle
        public func autoStartServices(_ enabled: Bool) -> Builder {
            config.autoStartServices = enabled
            return self
        }

        public func serviceStartTimeout(_ seconds: TimeInterval) -> Builder {
            config.serviceStartTimeout = seconds
            return self
        }

        public func serviceStopTimeout(_ seconds: TimeInterval) -> Builder {
            config.serviceStopTimeout = seconds
            return self
        }

        public func restartOnFailure(_ enabled: Bool) -> Builder {
            config.restartOnFailure = enabled
            return self
        }

        public func maxRestartAttempts(_ count: Int) -> Builder {
            config.maxRestartAttempts = count
            return self
        }

        // Component lifecycle
        public func parallelComponentInitialization(_ enabled: Bool) -> Builder {
            config.parallelComponentInitialization = enabled
            return self
        }

        public func componentInitTimeout(_ seconds: TimeInterval) -> Builder {
            config.componentInitTimeout = seconds
            return self
        }

        public func cleanupOnShutdown(_ enabled: Bool) -> Builder {
            config.cleanupOnShutdown = enabled
            return self
        }

        public func componentInitPriority(_ priority: Int) -> Builder {
            config.componentInitPriority = priority
            return self
        }

        // Logging
        public func enableDetailedLogging(_ enabled: Bool) -> Builder {
            config.enableDetailedLogging = enabled
            return self
        }

        public func logToEventBus(_ enabled: Bool) -> Builder {
            config.logToEventBus = enabled
            return self
        }

        public func build() -> LifecycleConfiguration {
            config
        }
    }
}
