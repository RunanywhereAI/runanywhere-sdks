import Foundation
import os

/// The main entry point for the RunAnywhere SDK
public class RunAnywhereSDK {
    /// Shared instance of the SDK
    public static let shared: RunAnywhereSDK = RunAnywhereSDK()

    /// Current configuration
    private var configuration: Configuration?
    internal var _isInitialized = false

    /// Task that tracks SDK initialization - allows other code to await completion
    private var initializationTask: Task<Void, Error>?

    /// Check if SDK is fully initialized
    public var isInitialized: Bool {
        return _isInitialized
    }

    /// Wait for SDK to be initialized - safe to call from any thread
    public func waitForInitialization() async throws {
        if let initTask = initializationTask {
            try await initTask.value
        } else if !_isInitialized {
            throw SDKError.notInitialized
        }
    }

    /// Private helper to ensure SDK is initialized before proceeding
    internal func ensureInitialized() async throws {
        if _isInitialized {
            return // Fast path - already initialized
        }

        if let initTask = initializationTask {
            // Initialization in progress, wait for it
            try await initTask.value
            return
        }

        // Not initialized and no initialization in progress
        throw SDKError.notInitialized
    }

    /// Service container for dependency injection
    internal let serviceContainer: ServiceContainer

    /// Currently loaded model
    internal var currentModel: ModelInfo?
    internal var currentService: LLMService?

    /// Logger for debugging
    internal let logger = SDKLogger(category: "RunAnywhereSDK")

    /// Private initializer to enforce singleton pattern
    private init() {
        self.serviceContainer = ServiceContainer.shared  // Use the shared instance!
        setupServices()
        logger.info("🏗️ RunAnywhereSDK singleton created")
    }

    // MARK: - Public API

    /// Initialize the SDK with the provided configuration
    /// - Parameter config: The configuration to use
    public func initialize(configuration: Configuration) async throws {
        // If already initialized or initializing, return/wait
        if _isInitialized {
            logger.info("✅ SDK already initialized")
            return
        }

        if let existingTask = initializationTask {
            logger.info("⏳ SDK initialization in progress, waiting...")
            try await existingTask.value
            return
        }

        logger.info("🚀 Starting SDK initialization with configuration")

        // Create initialization task
        let initTask = Task<Void, Error> { @MainActor in
            do {
                self.configuration = configuration

                // Validate configuration
                try await serviceContainer.configurationValidator.validate(configuration)
                logger.info("✅ Configuration validated")

                // Bootstrap all services with configuration
                try await serviceContainer.bootstrap(with: configuration)
                logger.info("✅ Services bootstrapped")

                // Start monitoring services if enabled
                if configuration.enableRealTimeDashboard {
                    serviceContainer.performanceMonitor.startMonitoring()
                    logger.info("📊 Performance monitoring started")
                }

                // Mark as initialized
                _isInitialized = true

                // Log successful initialization
                logger.info("✅ RunAnywhereSDK initialized successfully - configuration loaded")
            } catch {
                logger.error("❌ SDK initialization failed: \(error)")
                _isInitialized = false
                self.configuration = nil
                self.initializationTask = nil // Clear failed task
                throw error
            }
        }

        self.initializationTask = initTask
        try await initTask.value
    }

    // MARK: - Private Methods

    private func setupServices() {
        // Services will be registered in the ServiceContainer
    }
}

// MARK: - Download Strategy Registration

extension RunAnywhereSDK {
    /// Register a custom download strategy for handling special model downloads
    /// - Parameter strategy: The download strategy to register
    /// - Note: Custom strategies have priority over default download behavior
    public func registerDownloadStrategy(_ strategy: DownloadStrategy) {
        serviceContainer.downloadService.registerStrategy(strategy)
        logger.info("✅ Registered custom download strategy")
    }
}

// MARK: - Performance and Testing Access

extension RunAnywhereSDK {
    /// Access to performance monitoring
    public var performanceMonitor: PerformanceMonitor {
        serviceContainer.performanceMonitor
    }

    /// Access to benchmarking
    public var benchmarkSuite: BenchmarkRunner {
        serviceContainer.benchmarkRunner
    }

    /// Access to A/B testing
    public var abTesting: ABTestRunner {
        serviceContainer.abTestRunner
    }
}
