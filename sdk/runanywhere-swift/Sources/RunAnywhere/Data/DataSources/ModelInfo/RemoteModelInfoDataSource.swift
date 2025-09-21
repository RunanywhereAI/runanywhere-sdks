import Foundation
import Alamofire

/// Remote data source for fetching model information from API
public actor RemoteModelInfoDataSource: RemoteDataSource {
    public typealias Entity = ModelInfo

    private let apiClient: APIClient?
    private let logger = SDKLogger(category: "RemoteModelInfoDataSource")
    private let operationHelper = RemoteOperationHelper(timeout: 10.0)

    public init(apiClient: APIClient?) {
        self.apiClient = apiClient
    }

    // MARK: - DataSource Protocol

    public func isAvailable() async -> Bool {
        return apiClient != nil
    }

    public func validateConfiguration() async throws {
        guard apiClient != nil else {
            throw DataSourceError.networkUnavailable
        }
    }

    // MARK: - RemoteDataSource Protocol

    public func fetch(id: String) async throws -> ModelInfo? {
        guard let apiClient = apiClient else {
            throw DataSourceError.networkUnavailable
        }

        logger.debug("Fetching model from remote: \(id)")

        return try await operationHelper.withTimeout {
            do {
                // Ensure device is registered first
                // Ensure device is registered first
                do {
                    try await RunAnywhere.ensureDeviceRegistered()
                } catch {
                    self.logger.warning("Device registration failed, continuing: \(error)")
                }

                // Fetch single model by ID using getRaw
                let data = try await apiClient.getRaw(
                    .fetchModel(id: id),
                    requiresAuth: true
                )

                // Decode the response
                let decoder = JSONDecoder()
                let apiModel = try decoder.decode(APIModelInfo.self, from: data)

                let modelInfo = apiModel.toModelInfo()
                self.logger.info("Successfully fetched model: \(modelInfo.name)")
                return modelInfo
            } catch {
                self.logger.error("Failed to fetch model \(id): \(error.localizedDescription)")
                // Return nil if not found instead of throwing
                if error is DataSourceError, case DataSourceError.notFound = error {
                    return nil
                }
                throw DataSourceError.fetchFailed(error.localizedDescription)
            }
        }
    }

    public func fetchAll(filter: [String: Any]? = nil) async throws -> [ModelInfo] {
        guard let apiClient = apiClient else {
            throw DataSourceError.networkUnavailable
        }

        logger.debug("Fetching all models from backend API")

        return try await operationHelper.withTimeout { () async throws -> [ModelInfo] in
            do {
                // Ensure device is registered first (lazy registration)
                // Ensure device is registered first
                do {
                    try await RunAnywhere.ensureDeviceRegistered()
                } catch {
                    self.logger.warning("Device registration failed, continuing: \(error)")
                }

                // Determine device type and platform
                let deviceType = self.getDeviceType()
                let platform = "ios"

                print("📱 RemoteDataSource: Fetching models for deviceType: \(deviceType), platform: \(platform)")

                // Call the model-assignments endpoint with device parameters
                let data = try await apiClient.getRaw(
                    .modelAssignments(deviceType: deviceType, platform: platform),
                    requiresAuth: true
                )

                // Debug: Print raw response
                print("🔍 RemoteDataSource: Raw API response size: \(data.count) bytes")
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("📄 RemoteDataSource: Raw JSON response: \(jsonString.prefix(500))...")
                }

                // Try to decode the response - can be direct array or wrapped in response object
                let decoder = JSONDecoder()
                var models: [ModelInfo] = []

                // First try as direct array of ModelAssignment (model-assignments endpoint returns array directly)
                if let modelAssignments = try? decoder.decode([ModelAssignment].self, from: data) {
                    print("✅ RemoteDataSource: Decoded direct ModelAssignment array - \(modelAssignments.count) models")

                    // Try to fetch download URLs for each model
                    var enhancedModels: [ModelInfo] = []
                    for assignment in modelAssignments {
                        var apiModelInfo = assignment.toAPIModelInfo()

                        // Try to fetch download URL for this model
                        do {
                            print("🔍 RemoteDataSource: Fetching download URL for model ID: \(assignment.id)")
                            let downloadData = try await apiClient.getRaw(
                                .downloadModel(id: assignment.id),
                                requiresAuth: true
                            )

                            // Log the raw response
                            if let jsonString = String(data: downloadData, encoding: .utf8) {
                                print("📥 RemoteDataSource: Download endpoint response: \(jsonString)")
                            } else {
                                print("📥 RemoteDataSource: Download endpoint returned \(downloadData.count) bytes (non-text)")
                            }

                            // Try to decode the response
                            do {
                                let downloadResponse = try decoder.decode(ModelDownloadResponse.self, from: downloadData)

                                // Update the API model info with download URL
                                apiModelInfo = APIModelInfo(
                                    id: apiModelInfo.id,
                                    name: apiModelInfo.name,
                                    description: apiModelInfo.description,
                                    version: apiModelInfo.version,
                                    size: downloadResponse.size ?? apiModelInfo.size,
                                    format: apiModelInfo.format,
                                    downloadUrl: downloadResponse.downloadUrl,
                                    checksum: downloadResponse.checksum ?? apiModelInfo.checksum,
                                    compatibleFrameworks: apiModelInfo.compatibleFrameworks,
                                    requirements: apiModelInfo.requirements,
                                    metadata: apiModelInfo.metadata,
                                    createdAt: apiModelInfo.createdAt,
                                    updatedAt: apiModelInfo.updatedAt
                                )
                                print("🔗 RemoteDataSource: Got download URL for model \(assignment.name): \(downloadResponse.downloadUrl)")
                            } catch let decodeError {
                                print("❌ RemoteDataSource: Failed to decode download response: \(decodeError)")
                                if let errorDict = try? JSONSerialization.jsonObject(with: downloadData) as? [String: Any] {
                                    print("📄 Error response: \(errorDict)")
                                }
                            }
                        } catch {
                            // If download endpoint fails, continue without download URL
                            print("⚠️ RemoteDataSource: Could not fetch download URL for \(assignment.name): \(error)")

                            // Try to extract more details from the error
                            if let apiError = error as? RepositoryError {
                                print("📝 API Error details: \(apiError)")
                            }
                        }

                        enhancedModels.append(apiModelInfo.toModelInfo())
                    }
                    models = enhancedModels
                }
                // Try as direct array of APIModelInfo
                else if let apiModels = try? decoder.decode([APIModelInfo].self, from: data) {
                    print("✅ RemoteDataSource: Decoded direct APIModelInfo array - \(apiModels.count) models")
                    models = apiModels.map { $0.toModelInfo() }
                }
                // Try the model-assignments response format
                else if let assignmentResponse = try? decoder.decode(ModelAssignmentResponse.self, from: data) {
                    print("✅ RemoteDataSource: Decoded ModelAssignmentResponse - \(assignmentResponse.models.count) models")
                    models = assignmentResponse.models.map { $0.toModelInfo() }
                }
                // Fall back to the regular models response format
                else if let response = try? decoder.decode(AvailableModelsResponse.self, from: data) {
                    print("✅ RemoteDataSource: Decoded AvailableModelsResponse - success: \(response.success), model count: \(response.models.count)")
                    if let message = response.message {
                        print("📝 RemoteDataSource: API message: \(message)")
                    }
                    models = response.models.map { $0.toModelInfo() }
                } else {
                    print("❌ RemoteDataSource: Failed to decode response as any known format")
                    // Try to get more details about the decoding failure
                    do {
                        _ = try decoder.decode([ModelAssignment].self, from: data)
                    } catch {
                        print("🔍 ModelAssignment decode error: \(error)")
                    }
                    throw DataSourceError.fetchFailed("Unable to decode model response")
                }

                print("🎯 RemoteDataSource: Converted \(models.count) models to SDK format")
                self.logger.info("Successfully fetched \(models.count) models from backend")
                return models
            } catch {
                self.logger.error("Failed to fetch models from backend: \(error.localizedDescription)")
                throw DataSourceError.fetchFailed(error.localizedDescription)
            }
        }
    }

    public func save(_ entity: ModelInfo) async throws -> ModelInfo {
        guard apiClient != nil else {
            throw DataSourceError.networkUnavailable
        }

        logger.debug("Pushing model to remote: \(entity.id)")

        // Placeholder for actual API implementation
        return try await operationHelper.withTimeout {
            self.logger.debug("Remote model save not yet implemented")
            return entity
        }
    }

    public func delete(id: String) async throws {
        guard apiClient != nil else {
            throw DataSourceError.networkUnavailable
        }

        logger.debug("Deleting model from remote: \(id)")

        // Placeholder for actual API implementation
        try await operationHelper.withTimeout {
            self.logger.debug("Remote model delete not yet implemented")
        }
    }

    // MARK: - Private Helpers

    private func getDeviceType() -> String {
        #if os(iOS)
        return "mobile"  // iPhone
        #elseif os(macOS)
        return "desktop"
        #elseif os(tvOS)
        return "tv"
        #elseif os(watchOS)
        return "watch"
        #else
        return "unknown"
        #endif
    }

    // MARK: - Sync Support

    public func syncBatch(_ batch: [ModelInfo]) async throws -> [String] {
        guard let apiClient = apiClient else {
            throw DataSourceError.notAvailable
        }

        logger.info("Syncing \(batch.count) model info items")

        var syncedIds: [String] = []

        // For model info, we typically sync one at a time using POST to the regular endpoint
        for modelInfo in batch {
            do {
                // Use regular POST to models endpoint
                let _: ModelInfo = try await apiClient.post(
                    .models,
                    modelInfo,
                    requiresAuth: true
                )
                syncedIds.append(modelInfo.id)
                logger.debug("Synced model info: \(modelInfo.id)")
            } catch {
                logger.error("Failed to sync model info \(modelInfo.id): \(error)")
                // Continue with next item
            }
        }

        logger.info("Successfully synced \(syncedIds.count) of \(batch.count) model info items")
        return syncedIds
    }

    public func testConnection() async throws -> Bool {
        guard apiClient != nil else {
            return false
        }

        return try await operationHelper.withTimeout {
            self.logger.debug("Remote model service connection test skipped (not implemented)")
            return false
        }
    }

}
