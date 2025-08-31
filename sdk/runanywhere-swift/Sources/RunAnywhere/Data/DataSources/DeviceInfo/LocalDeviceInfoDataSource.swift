import Foundation
import GRDB

/// Local data source for managing device information in database
public actor LocalDeviceInfoDataSource: LocalDataSource {
    public typealias Entity = DeviceInfoData

    private let databaseManager: DatabaseManager
    private let logger = SDKLogger(category: "LocalDeviceInfoDataSource")

    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    // MARK: - DataSource Protocol

    public func isAvailable() async -> Bool {
        do {
            _ = try databaseManager.read { db in
                try db.tableExists("device_info")
            }
            return true
        } catch {
            logger.debug("Database table 'device_info' not available: \(error)")
            return false
        }
    }

    public func validateConfiguration() async throws {
        guard await isAvailable() else {
            throw DataSourceError.storageUnavailable
        }
    }

    // MARK: - LocalDataSource Protocol

    public func load(id: String) async throws -> DeviceInfoData? {
        logger.debug("Loading device info: \(id)")

        let deviceInfo = try databaseManager.read { db in
            try DeviceInfoData.fetchOne(db, key: id)
        }

        if deviceInfo == nil {
            logger.debug("Device info not found: \(id)")
        }

        return deviceInfo
    }

    public func loadAll() async throws -> [DeviceInfoData] {
        logger.debug("Loading all device info records")

        return try databaseManager.read { db in
            try DeviceInfoData
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }
    }

    public func store(_ entity: DeviceInfoData) async throws {
        logger.debug("Storing device info: \(entity.id)")

        try databaseManager.write { db in
            try entity.save(db)
        }

        logger.debug("Device info stored successfully: \(entity.id)")
    }

    public func remove(id: String) async throws {
        logger.debug("Removing device info: \(id)")

        let deleted = try databaseManager.write { db in
            try DeviceInfoData.deleteOne(db, key: id)
        }

        if deleted {
            logger.debug("Device info removed successfully: \(id)")
        } else {
            logger.debug("Device info not found for removal: \(id)")
        }
    }

    public func clear() async throws {
        logger.debug("Clearing all device info records")

        let deletedCount = try databaseManager.write { db in
            try DeviceInfoData.deleteAll(db)
        }

        logger.info("Cleared \(deletedCount) device info records")
    }

    public func getStorageInfo() async throws -> DataSourceStorageInfo {
        let entityCount = try databaseManager.read { db in
            try DeviceInfoData.fetchCount(db)
        }

        return DataSourceStorageInfo(
            totalSpace: nil,
            availableSpace: nil,
            usedSpace: nil,
            entityCount: entityCount,
            lastUpdated: Date()
        )
    }

    // MARK: - DeviceInfo-specific methods

    /// Load the current device's stored information
    public func loadCurrentDeviceInfo() async throws -> DeviceInfoData? {
        return try databaseManager.read { db in
            try DeviceInfoData
                .order(Column("updatedAt").desc)
                .fetchOne(db)
        }
    }

    /// Store current device info, replacing any existing record
    public func storeCurrentDeviceInfo(_ deviceInfo: DeviceInfoData) async throws {
        try databaseManager.write { db in
            // Clear any existing device info (only one device record should exist)
            try DeviceInfoData.deleteAll(db)

            // Store new device info
            try deviceInfo.save(db)
        }

        logger.info("Current device info stored successfully")
    }

    /// Update existing device info with new data
    public func updateDeviceInfo(_ deviceInfo: DeviceInfoData) async throws {
        var updatedInfo = deviceInfo
        updatedInfo.updatedAt = Date()
        updatedInfo.syncPending = true

        try databaseManager.write { db in
            try updatedInfo.update(db)
        }

        logger.debug("Device info updated: \(deviceInfo.id)")
    }
}
