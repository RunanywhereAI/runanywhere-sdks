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
            throw RunAnywhereError.notInitialized
        }

        // Ensure network services are initialized (lazy initialization via device registration)
        try await ensureDeviceRegistered()

        logger.info("Fetching model assignments...")

        do {
            // Delegate to service container's model assignment service
            let models = try await serviceContainer.modelAssignmentService.fetchModelAssignments(forceRefresh: forceRefresh)
            logger.info("Successfully fetched \(models.count) model assignments")

            // Publish event for model assignments fetched
            events.publish(SDKModelEvent.assignmentsFetched(models: models))

            return models
        } catch {
            logger.error("Failed to fetch model assignments: \(error)")
            events.publish(SDKModelEvent.assignmentsFetchFailed(error: error))
            throw error
        }
    }

    /// Get available models for a specific framework
    /// - Parameter framework: The LLM framework to filter models for
    /// - Returns: Array of ModelInfo objects compatible with the specified framework
    public static func getModelsForFramework(_ framework: InferenceFramework) async throws -> [ModelInfo] {
        // Ensure SDK is initialized
        guard isSDKInitialized else {
            throw RunAnywhereError.notInitialized
        }

        // Ensure network services are initialized (lazy initialization via device registration)
        try await ensureDeviceRegistered()

        // Delegate to service container's model assignment service
        return try await serviceContainer.modelAssignmentService.getModelsForFramework(framework)
    }

    /// Get available models for a specific category
    /// - Parameter category: The model category to filter models for
    /// - Returns: Array of ModelInfo objects in the specified category
    public static func getModelsForCategory(_ category: ModelCategory) async throws -> [ModelInfo] {
        // Ensure SDK is initialized
        guard isSDKInitialized else {
            throw RunAnywhereError.notInitialized
        }

        // Ensure network services are initialized (lazy initialization via device registration)
        try await ensureDeviceRegistered()

        // Delegate to service container's model assignment service
        return try await serviceContainer.modelAssignmentService.getModelsForCategory(category)
    }

    /// Clear cached model assignments
    public static func clearModelAssignmentsCache() async {
        // Ensure SDK is initialized
        guard isSDKInitialized else {
            return
        }

        // Clear cache on the service container's model assignment service
        await serviceContainer.modelAssignmentService.clearCache()
    }
}
