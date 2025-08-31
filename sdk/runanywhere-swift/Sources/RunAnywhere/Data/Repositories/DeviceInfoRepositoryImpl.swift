import Foundation
import GRDB

/// Repository for managing device information data
/// Implements both Repository for basic CRUD and DeviceInfoRepository for device-specific operations
public actor DeviceInfoRepositoryImpl: Repository, DeviceInfoRepository {
    public typealias Entity = DeviceInfoData

    // Core dependencies
    private let databaseManager: DatabaseManager
    private let apiClient: APIClient?
    private let logger = SDKLogger(category: "DeviceInfoRepository")

    // Data sources for device-specific operations
    private let remoteDataSource: RemoteDeviceInfoDataSource
    private let localDataSource: LocalDeviceInfoDataSource

    // MARK: - Initialization

    public init(databaseManager: DatabaseManager, apiClient: APIClient?) {
        self.databaseManager = databaseManager
        self.apiClient = apiClient
        self.remoteDataSource = RemoteDeviceInfoDataSource(apiClient: apiClient)
        self.localDataSource = LocalDeviceInfoDataSource(databaseManager: databaseManager)
    }

    // MARK: - Repository Protocol Implementation

    public func save(_ entity: DeviceInfoData) async throws {
        try databaseManager.write { db in
            try entity.save(db)
        }
        logger.debug("Saved device info: \(entity.id)")
    }

    public func fetch(id: String) async throws -> DeviceInfoData? {
        return try databaseManager.read { db in
            try DeviceInfoData.fetchOne(db, key: id)
        }
    }

    public func fetchAll() async throws -> [DeviceInfoData] {
        return try databaseManager.read { db in
            try DeviceInfoData
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }
    }

    public func delete(id: String) async throws {
        try databaseManager.write { db in
            _ = try DeviceInfoData.deleteOne(db, key: id)
        }
        logger.debug("Deleted device info: \(id)")
    }

    // MARK: - Sync Support (for Repository protocol)

    public func fetchPendingSync() async throws -> [DeviceInfoData] {
        return try databaseManager.read { db in
            try DeviceInfoData
                .filter(Column("syncPending") == true)
                .fetchAll(db)
        }
    }

    public func markSynced(_ ids: [String]) async throws {
        try databaseManager.write { db in
            for id in ids {
                if var data = try DeviceInfoData.fetchOne(db, key: id) {
                    data.markSynced()
                    try data.update(db)
                }
            }
        }
    }

    // MARK: - DeviceInfoRepository Protocol Implementation

    public func fetchCurrentDeviceInfo() async throws -> DeviceInfoData {
        logger.debug("Fetching current device information")

        // First try to get stored device info
        if let storedInfo = try await getStoredDeviceInfo() {
            // Check if stored info is recent (within last day)
            let dayAgo = Date().addingTimeInterval(-24 * 60 * 60)
            if storedInfo.updatedAt > dayAgo {
                logger.debug("Using cached device info from \(storedInfo.updatedAt)")
                return storedInfo
            }
        }

        // Generate fresh device info and store it
        logger.info("Generating fresh device information")
        let currentDeviceInfo = DeviceInfoData.current()

        try await localDataSource.storeCurrentDeviceInfo(currentDeviceInfo)
        logger.info("Fresh device information generated and stored")

        return currentDeviceInfo
    }

    public func updateDeviceInfo(_ deviceInfo: DeviceInfoData) async throws {
        try await localDataSource.updateDeviceInfo(deviceInfo)
        logger.info("Device information updated: \(deviceInfo.id)")
    }

    public func getStoredDeviceInfo() async throws -> DeviceInfoData? {
        return try await localDataSource.loadCurrentDeviceInfo()
    }

    public func refreshDeviceInfo() async throws -> DeviceInfoData {
        logger.info("Refreshing device information from system")

        // Always generate fresh device info
        let currentDeviceInfo = DeviceInfoData.current()

        // Store the refreshed info
        try await localDataSource.storeCurrentDeviceInfo(currentDeviceInfo)

        logger.info("Device information refreshed successfully")
        return currentDeviceInfo
    }
}
