import Foundation

// MARK: - Frameworks Extensions (Event-Based)

public extension RunAnywhere {

    /// Register a framework adapter with event reporting
    /// - Parameter adapter: The framework adapter to register
    static func registerFrameworkAdapter(_ adapter: UnifiedFrameworkAdapter) {
        // Access service container directly
        RunAnywhere.serviceContainer.adapterRegistry.register(adapter)

        Task {
            events.publish(SDKFrameworkEvent.adapterRegistered(
                framework: adapter.framework,
                name: String(describing: adapter)
            ))
        }
    }

    /// Register a framework adapter with custom models
    /// - Parameters:
    ///   - adapter: The framework adapter to register
    ///   - models: Array of custom models to register with this adapter
    ///   - options: Registration options (defaults based on environment)
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    static func registerFrameworkAdapter(
        _ adapter: UnifiedFrameworkAdapter,
        models: [ModelRegistration] = [],
        options: AdapterRegistrationOptions? = nil
    ) async throws {
        let logger = SDKLogger(category: "RunAnywhere.Frameworks")

        // Determine options based on environment
        let registrationOptions = options ?? (currentEnvironment == .development ? .development : .production)

        // Register the adapter first
        RunAnywhere.serviceContainer.adapterRegistry.register(adapter)

        // Publish adapter registration event
        events.publish(SDKFrameworkEvent.adapterRegistered(
            framework: adapter.framework,
            name: String(describing: adapter)
        ))

        logger.info("Registered adapter for \(adapter.framework) with \(models.count) custom models")

        // Register custom models if provided
        for modelReg in models {
            let modelInfo = modelReg.toModelInfo()

            // Validate model if needed
            if registrationOptions.validateModels {
                // Check if adapter can handle this model
                guard adapter.canHandle(model: modelInfo) else {
                    logger.error("Adapter \(adapter.framework) cannot handle model \(modelInfo.id)")
                    if !registrationOptions.fallbackToMockModels {
                        throw SDKError.invalidConfiguration("Model \(modelInfo.id) is not compatible with \(adapter.framework)")
                    }
                    continue
                }
            }

            // Register the model persistently (both in memory and database)
            if let registryService = RunAnywhere.serviceContainer.modelRegistry as? RegistryService {
                await registryService.registerModelPersistently(modelInfo)
                logger.info("Registered and saved model: \(modelInfo.id) for framework: \(modelReg.framework)")
            } else {
                // Fallback to memory-only registration
                RunAnywhere.serviceContainer.modelRegistry.registerModel(modelInfo)
                logger.warning("Model \(modelInfo.id) registered in memory only (persistence not available)")
            }

            // Auto-download in development mode if enabled
            if currentEnvironment == .development && registrationOptions.autoDownloadInDev {
                logger.info("Auto-downloading model \(modelInfo.id) in development mode")

                do {
                    if registrationOptions.showProgress {
                        // Download with progress
                        let progressStream = try await RunAnywhere.downloadModelWithProgress(modelInfo.id)

                        // Consume the progress stream (in real app, this would update UI)
                        for try await progress in progressStream {
                            logger.debug("Download progress for \(modelInfo.id): \(Int(progress.percentage * 100))%")

                            // Publish download progress event
                            events.publish(SDKModelEvent.downloadProgress(
                                modelId: modelInfo.id,
                                progress: progress.percentage
                            ))
                        }
                    } else {
                        // Silent download
                        try await RunAnywhere.downloadModel(modelInfo.id)
                    }

                    logger.info("Successfully downloaded model: \(modelInfo.id)")
                } catch {
                    logger.error("Failed to auto-download model \(modelInfo.id): \(error)")

                    if !registrationOptions.fallbackToMockModels {
                        throw error
                    }
                }
            }
        }

        logger.info("Framework adapter registration complete for \(adapter.framework)")
    }

    /// Get registered adapters with event reporting
    /// - Returns: Dictionary of registered adapters
    static func getRegisteredAdapters() -> [LLMFramework: UnifiedFrameworkAdapter] {
        Task {
            events.publish(SDKFrameworkEvent.adaptersRequested)
        }

        let adapters = RunAnywhere.serviceContainer.adapterRegistry.getRegisteredAdapters()

        Task {
            events.publish(SDKFrameworkEvent.adaptersRetrieved(count: adapters.count))
        }

        return adapters
    }

    /// Get available frameworks
    /// - Returns: Array of available frameworks
    static func getAvailableFrameworks() -> [LLMFramework] {
        Task {
            events.publish(SDKFrameworkEvent.frameworksRequested)
        }

        let frameworks = RunAnywhere.serviceContainer.adapterRegistry.getAvailableFrameworks()

        Task {
            events.publish(SDKFrameworkEvent.frameworksRetrieved(frameworks: frameworks))
        }

        return frameworks
    }

    /// Get framework availability information
    /// - Returns: Array of framework availability info
    static func getFrameworkAvailability() -> [FrameworkAvailability] {
        Task {
            events.publish(SDKFrameworkEvent.availabilityRequested)
        }

        let availability = RunAnywhere.serviceContainer.adapterRegistry.getFrameworkAvailability()

        Task {
            events.publish(SDKFrameworkEvent.availabilityRetrieved(availability: availability))
        }

        return availability
    }

    /// Get models for a specific framework
    /// - Parameter framework: The framework to query
    /// - Returns: Array of models for the framework
    static func getModelsForFramework(_ framework: LLMFramework) -> [ModelInfo] {
        Task {
            events.publish(SDKFrameworkEvent.modelsForFrameworkRequested(framework: framework))
        }

        let models = RunAnywhere.serviceContainer.modelRegistry.filterModels(by: ModelCriteria(framework: framework))

        Task {
            events.publish(SDKFrameworkEvent.modelsForFrameworkRetrieved(
                framework: framework,
                models: models
            ))
        }

        return models
    }

    /// Get frameworks for a specific modality
    /// - Parameter modality: The modality to query
    /// - Returns: Array of frameworks supporting the modality
    static func getFrameworks(for modality: FrameworkModality) -> [LLMFramework] {
        Task {
            events.publish(SDKFrameworkEvent.frameworksForModalityRequested(modality: modality))
        }

        let frameworks = RunAnywhere.serviceContainer.adapterRegistry.getFrameworks(for: modality)

        Task {
            events.publish(SDKFrameworkEvent.frameworksForModalityRetrieved(
                modality: modality,
                frameworks: frameworks
            ))
        }

        return frameworks
    }

    /// Get primary modality for a framework
    /// - Parameter framework: The framework to query
    /// - Returns: Primary modality of the framework
    static func getPrimaryModality(for framework: LLMFramework) -> FrameworkModality? {
        guard let adapter = RunAnywhere.serviceContainer.adapterRegistry.getAdapter(for: framework) else {
            return nil
        }
        return adapter.supportedModalities.first
    }

    /// Check if framework supports a specific modality
    /// - Parameters:
    ///   - framework: The framework to check
    ///   - modality: The modality to check
    /// - Returns: True if framework supports the modality
    static func frameworkSupports(_ framework: LLMFramework, modality: FrameworkModality) -> Bool {
        guard let adapter = RunAnywhere.serviceContainer.adapterRegistry.getAdapter(for: framework) else {
            return false
        }
        return adapter.supportedModalities.contains(modality)
    }
}
