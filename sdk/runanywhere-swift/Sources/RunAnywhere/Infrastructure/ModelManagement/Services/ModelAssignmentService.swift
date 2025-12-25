import Foundation

/// Service for fetching and managing model assignments from the backend
public actor ModelAssignmentService {
    private let logger = SDKLogger(category: "ModelAssignmentService")
    private let networkService: any NetworkService
    private let modelInfoService: ModelInfoService
    private var cachedAssignments: [ModelInfo]?
    private var lastFetchTime: Date?
    private let cacheTimeout: TimeInterval = 3600 // 1 hour cache

    // MARK: - Initialization

    public init(networkService: any NetworkService, modelInfoService: ModelInfoService) {
        self.networkService = networkService
        self.modelInfoService = modelInfoService
        logger.info("ModelAssignmentService initialized")
    }

    // MARK: - Public Methods

    /// Fetch model assignments for the current device from the backend
    /// - Parameters:
    ///   - forceRefresh: Force refresh even if cache is valid
    /// - Returns: Array of ModelInfo objects assigned to this device
    public func fetchModelAssignments(forceRefresh: Bool = false) async throws -> [ModelInfo] {
        // Check cache first
        if !forceRefresh,
           let cached = cachedAssignments,
           let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < cacheTimeout {
            logger.debug("Returning cached model assignments (\(cached.count) models)")
            return cached
        }

        logger.info("Fetching model assignments from backend...")

        // Use centralized device info
        let deviceInfo = DeviceInfo.current

        // Create the endpoint with parameters
        let endpoint = APIEndpoint.modelAssignments(
            deviceType: deviceInfo.deviceType,
            platform: deviceInfo.platform
        )

        do {
            // Fetch from network service (works with both mock and real)
            let response: ModelAssignmentResponse = try await networkService.get(
                endpoint,
                requiresAuth: true
            )

            logger.info("Received \(response.models.count) model assignments")

            // Convert API models to SDK ModelInfo objects
            let modelInfos = response.models.map { $0.toModelInfo() }

            // Cache the results
            cachedAssignments = modelInfos
            lastFetchTime = Date()

            // Save to local database for offline access
            for model in modelInfos {
                try await modelInfoService.saveModel(model)
            }

            logger.info("Model assignments cached and saved locally")
            return modelInfos

        } catch {
            logger.error("Failed to fetch model assignments: \(error)")

            // Fall back to locally stored models if network fails
            if let cached = cachedAssignments {
                logger.info("Using cached models as fallback")
                return cached
            }

            // Last resort: load from local database
            let localModels = try await modelInfoService.loadStoredModels()
            if !localModels.isEmpty {
                logger.info("Using \(localModels.count) locally stored models as fallback")
                cachedAssignments = localModels
                return localModels
            }

            throw error
        }
    }

    /// Get model assignments for a specific framework
    public func getModelsForFramework(_ framework: InferenceFramework) async throws -> [ModelInfo] {
        let allModels = try await fetchModelAssignments()
        return allModels.filter { $0.compatibleFrameworks.contains(framework) }
    }

    /// Get model assignments for a specific category
    public func getModelsForCategory(_ category: ModelCategory) async throws -> [ModelInfo] {
        let allModels = try await fetchModelAssignments()
        return allModels.filter { $0.category == category }
    }

    /// Clear cached assignments
    public func clearCache() {
        cachedAssignments = nil
        lastFetchTime = nil
        logger.debug("Model assignments cache cleared")
    }
}

// MARK: - Model Assignment Response Models

/// Response from the model assignments API
public struct ModelAssignmentResponse: Codable, Sendable {
    public let models: [ModelAssignment]
    public let deviceType: String
    public let platform: String
    public let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case models
        case deviceType = "device_type"
        case platform
        case timestamp
    }
}

/// Individual model assignment from the API
public struct ModelAssignment: Codable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let category: String
    public let format: String
    public let downloadUrl: String?
    public let size: Int64?
    public let memoryRequired: Int64?
    public let contextLength: Int?
    public let supportsThinking: Bool
    public let compatibleFrameworks: [String]
    public let framework: String?
    public let metadata: ModelAssignmentMetadata?
    public let isRequired: Bool
    public let priority: Int

    enum CodingKeys: String, CodingKey {
        case id, name, version, category, format
        case downloadUrl = "download_url"
        case size
        case memoryRequired = "memory_required"
        case contextLength = "context_length"
        case supportsThinking = "supports_thinking"
        case compatibleFrameworks = "compatible_frameworks"
        case framework = "preferred_framework"
        case metadata
        case isRequired = "is_required"
        case priority
    }
}

/// Metadata for model assignments
public struct ModelAssignmentMetadata: Codable, Sendable {
    public let description: String?
    public let author: String?
    public let license: String?
    public let tags: [String]?
    public let capabilities: [String]?
    public let limitations: [String]?

    enum CodingKeys: String, CodingKey {
        case description, author, license, tags
        case capabilities, limitations
    }
}

// MARK: - Conversion Extension

extension ModelAssignment {
    /// Convert API model assignment to SDK ModelInfo
    public func toModelInfo() -> ModelInfo {
        // Convert string category to ModelCategory enum
        let modelCategory = ModelCategory(rawValue: category.lowercased()) ?? .language

        // Convert string format to ModelFormat enum
        let modelFormat = ModelFormat(rawValue: format.lowercased()) ?? .gguf

        // Convert string frameworks to InferenceFramework enum
        let frameworks = compatibleFrameworks.compactMap { InferenceFramework(rawValue: $0.lowercased()) }
        let preferred = framework.flatMap { InferenceFramework(rawValue: $0.lowercased()) }

        // Extract tags and description from metadata
        let modelTags = metadata?.tags ?? []
        let modelDescription = metadata?.description

        // Create download URL if provided
        let downloadURL = downloadUrl.flatMap { URL(string: $0) }

        return ModelInfo(
            id: id,
            name: name,
            category: modelCategory,
            format: modelFormat,
            downloadURL: downloadURL,
            localPath: nil,
            downloadSize: size,
            memoryRequired: memoryRequired,
            compatibleFrameworks: frameworks,
            framework: preferred,
            contextLength: contextLength,
            supportsThinking: supportsThinking,
            tags: modelTags,
            description: modelDescription,
            source: .remote,
            createdAt: Date(),
            updatedAt: Date(),
            syncPending: false,
            lastUsed: nil,
            usageCount: 0
        )
    }
}
