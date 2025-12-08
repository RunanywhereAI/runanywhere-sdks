import Foundation

/// Remote data source for syncing device information with API server
public actor RemoteDeviceInfoDataSource: RemoteDataSource {
    public typealias Entity = DeviceInfoData

    private let apiClient: APIClient?
    private let logger = SDKLogger(category: "RemoteDeviceInfoDataSource")
    private let operationHelper = RemoteOperationHelper(timeout: 15.0) // Longer timeout for device info

    public init(apiClient: APIClient?) {
        self.apiClient = apiClient
    }

    // MARK: - DataSource Protocol

    public func isAvailable() async -> Bool {
        guard apiClient != nil else {
            logger.debug("API client not configured")
            return false
        }

        do {
            return try await testConnection()
        } catch {
            logger.debug("Connection test failed: \(error)")
            return false
        }
    }

    public func validateConfiguration() async throws {
        guard apiClient != nil else {
            throw DataSourceError.configurationInvalid("API client not configured")
        }
    }

    // MARK: - RemoteDataSource Protocol

    public func fetch(id: String) async throws -> DeviceInfoData? {
        guard apiClient != nil else {
            throw DataSourceError.notAvailable
        }

        logger.debug("Fetching device info from remote: \(id)")

        return try await operationHelper.withTimeout {
            // In a real implementation, this would fetch device info from the server
            self.logger.debug("Remote device info fetch not yet implemented")
            return nil
        }
    }

    // swiftlint:disable:next prefer_concrete_types avoid_any_type
    public func fetchAll(filter: [String: Any]?) async throws -> [DeviceInfoData] {
        // Not typically used for device info - each device has its own info
        return []
    }

    public func save(_ entity: DeviceInfoData) async throws -> DeviceInfoData {
        guard apiClient != nil else {
            throw DataSourceError.notAvailable
        }

        logger.debug("Syncing device info to remote: \(entity.id)")

        return try await operationHelper.withTimeout {
            // In a real implementation, this would sync device info to the server
            self.logger.debug("Remote device info sync not yet implemented")

            // For now, return the entity with updated sync status
            var syncedEntity = entity
            syncedEntity.syncPending = false
            syncedEntity.updatedAt = Date()
            return syncedEntity
        }
    }

    public func delete(id: String) async throws {
        guard apiClient != nil else {
            throw DataSourceError.notAvailable
        }

        logger.debug("Deleting device info from remote: \(id)")

        try await operationHelper.withTimeout {
            // In a real implementation, this would remove device info from the server
            self.logger.debug("Remote device info deletion not yet implemented")
        }
    }

    // MARK: - Sync Support

    public func syncBatch(_ batch: [DeviceInfoData]) async throws -> [String] {
        guard let apiClient = apiClient else {
            throw DataSourceError.notAvailable
        }

        logger.info("Syncing \(batch.count) device info items")

        var syncedIds: [String] = []

        // For device info, we typically sync one at a time using POST to the regular endpoint
        for deviceInfo in batch {
            do {
                // Use regular POST to deviceInfo endpoint
                let _: DeviceInfoData = try await apiClient.post(
                    .deviceInfo,
                    deviceInfo,
                    requiresAuth: true
                )
                syncedIds.append(deviceInfo.id)
                logger.debug("Synced device info: \(deviceInfo.id)")
            } catch {
                logger.error("Failed to sync device info \(deviceInfo.id): \(error)")
                // Continue with next item
            }
        }

        logger.info("Successfully synced \(syncedIds.count) of \(batch.count) device info items")
        return syncedIds
    }

    public func testConnection() async throws -> Bool {
        guard apiClient != nil else {
            return false
        }

        return try await operationHelper.withTimeout {
            // Test with a simple health check
            self.logger.debug("Remote device info service connection test skipped (not implemented)")
            return false
        }
    }

    // MARK: - DeviceInfo-specific methods

    /// Sync device information to server
    public func syncDeviceInfo(_ deviceInfo: DeviceInfoData) async throws -> DeviceInfoData {
        logger.info("Syncing device information to server...")

        return try await save(deviceInfo)
    }

    /// Register device with server (first-time sync)
    public func registerDevice(_ deviceInfo: DeviceInfoData) async throws -> DeviceInfoData {
        logger.info("Registering new device with server...")

        // For now, treat registration the same as sync
        return try await syncDeviceInfo(deviceInfo)
    }
}
