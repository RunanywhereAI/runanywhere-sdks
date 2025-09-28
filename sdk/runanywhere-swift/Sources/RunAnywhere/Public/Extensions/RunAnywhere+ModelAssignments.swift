import Foundation

// MARK: - Model Assignments API

extension RunAnywhere {

    /// Fetch model assignments for the current device from the backend
    /// This method fetches models assigned to this device based on device type and platform
    /// - Parameter forceRefresh: Force refresh even if cached models are available
    /// - Returns: Array of ModelInfo objects assigned to this device
    /// - Throws: SDKError if fetching fails
    public static func fetchModelAssignments(forceRefresh: Bool = false) async throws -> [ModelInfo] {
        let logger = SDKLogger(category: "RunAnywhere.ModelAssignments")

        // Ensure SDK is initialized
        guard isSDKInitialized else {
            throw SDKError.notInitialized
        }

        // Ensure network services are initialized (lazy initialization)
        if let params = initParams {
            try await serviceContainer.initializeNetworkServices(with: params)
        }

        // Get or create the model assignment service
        let assignmentService: ModelAssignmentService
        if let existing = serviceContainer.getModelAssignmentService() as? ModelAssignmentService {
            assignmentService = existing
        } else {
            // Create new service
            guard let networkService = serviceContainer.networkService else {
                logger.error("Network service not available")
                throw SDKError.invalidState("Network service not initialized")
            }

            let modelInfoService = await serviceContainer.modelInfoService
            assignmentService = ModelAssignmentService(
                networkService: networkService,
                modelInfoService: modelInfoService
            )
            serviceContainer.setModelAssignmentService(assignmentService)
        }

        logger.info("Fetching model assignments...")

        do {
            let models = try await assignmentService.fetchModelAssignments(forceRefresh: forceRefresh)
            logger.info("Successfully fetched \(models.count) model assignments")

            // Publish event for model assignments fetched
            events.publish(ModelAssignmentsFetchedEvent(models: models))

            return models
        } catch {
            logger.error("Failed to fetch model assignments: \(error)")
            events.publish(ModelAssignmentsFetchFailedEvent(error: error))
            throw error
        }
    }

    /// Get available models for a specific framework
    /// - Parameter framework: The LLM framework to filter models for
    /// - Returns: Array of ModelInfo objects compatible with the specified framework
    public static func getModelsForFramework(_ framework: LLMFramework) async throws -> [ModelInfo] {
        let logger = SDKLogger(category: "RunAnywhere.ModelAssignments")

        // Try to get existing service first
        guard let assignmentService = serviceContainer.getModelAssignmentService() as? ModelAssignmentService else {
            // Service not initialized yet - fetch assignments first
            _ = try await fetchModelAssignments()

            // Now get the service
            guard let service = serviceContainer.getModelAssignmentService() as? ModelAssignmentService else {
                logger.error("Model assignment service not available")
                throw SDKError.invalidState("Model assignment service not initialized")
            }
            return try await service.getModelsForFramework(framework)
        }

        return try await assignmentService.getModelsForFramework(framework)
    }

    /// Get available models for a specific category
    /// - Parameter category: The model category to filter models for
    /// - Returns: Array of ModelInfo objects in the specified category
    public static func getModelsForCategory(_ category: ModelCategory) async throws -> [ModelInfo] {
        let logger = SDKLogger(category: "RunAnywhere.ModelAssignments")

        // Try to get existing service first
        guard let assignmentService = serviceContainer.getModelAssignmentService() as? ModelAssignmentService else {
            // Service not initialized yet - fetch assignments first
            _ = try await fetchModelAssignments()

            // Now get the service
            guard let service = serviceContainer.getModelAssignmentService() as? ModelAssignmentService else {
                logger.error("Model assignment service not available")
                throw SDKError.invalidState("Model assignment service not initialized")
            }
            return try await service.getModelsForCategory(category)
        }

        return try await assignmentService.getModelsForCategory(category)
    }

    /// Clear cached model assignments
    public static func clearModelAssignmentsCache() async {
        let logger = SDKLogger(category: "RunAnywhere.ModelAssignments")

        guard let assignmentService = serviceContainer.getModelAssignmentService() as? ModelAssignmentService else {
            logger.warning("Model assignment service not available to clear cache")
            return
        }

        await assignmentService.clearCache()
        logger.info("Model assignments cache cleared")
    }
}

// MARK: - Model Assignment Events

/// Event published when model assignments are successfully fetched
public struct ModelAssignmentsFetchedEvent: SDKEvent {
    public let timestamp = Date()
    public let eventType = SDKEventType.generation
    public let models: [ModelInfo]
    public var description: String {
        "Model assignments fetched: \(models.count) models"
    }
}

/// Event published when model assignments fetch fails
public struct ModelAssignmentsFetchFailedEvent: SDKEvent {
    public let timestamp = Date()
    public let eventType = SDKEventType.generation
    public let error: Error
    public var description: String {
        "Model assignments fetch failed: \(error.localizedDescription)"
    }
}
