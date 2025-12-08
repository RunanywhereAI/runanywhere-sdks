import Foundation

/// Service for managing device information collection and sync
public actor DeviceInfoService {
    private let logger = SDKLogger(category: "DeviceInfoService")
    private let deviceInfoRepository: DeviceInfoRepositoryImpl
    private let syncCoordinator: SyncCoordinator?

    private var currentDeviceInfo: DeviceInfoData?

    // MARK: - Initialization

    public init(deviceInfoRepository: DeviceInfoRepositoryImpl, syncCoordinator: SyncCoordinator?) {
        self.deviceInfoRepository = deviceInfoRepository
        self.syncCoordinator = syncCoordinator
        logger.info("DeviceInfoService created")
    }

    // MARK: - Public Methods

    /// Get current device information (cached or fresh)
    public func getCurrentDeviceInfo() async -> DeviceInfoData? {
        if let cached = currentDeviceInfo {
            // Check if cached info is recent (within last hour)
            let hourAgo = Date().addingTimeInterval(-60 * 60)
            if cached.updatedAt > hourAgo {
                return cached
            }
        }

        // Load fresh device info
        return await loadCurrentDeviceInfo()
    }

    /// Load device information on app launch
    /// This collects fresh device info and stores it locally
    public func loadCurrentDeviceInfo() async -> DeviceInfoData? {
        do {
            let deviceInfo = try await deviceInfoRepository.fetchCurrentDeviceInfo()
            currentDeviceInfo = deviceInfo
            logger.info("Device information loaded successfully")

            // Trigger background sync if available
            await triggerBackgroundSync()

            return deviceInfo
        } catch {
            logger.error("Failed to load device information: \(error)")
            return nil
        }
    }

    /// Force refresh device information from system
    public func refreshDeviceInfo() async -> DeviceInfoData? {
        do {
            let deviceInfo = try await deviceInfoRepository.refreshDeviceInfo()
            currentDeviceInfo = deviceInfo
            logger.info("Device information refreshed successfully")

            // Trigger background sync
            await triggerBackgroundSync()

            return deviceInfo
        } catch {
            logger.error("Failed to refresh device information: \(error)")
            return nil
        }
    }

    /// Update device information with changes
    public func updateDeviceInfo(_ updates: (DeviceInfoData) -> DeviceInfoData) async throws {
        guard let deviceInfo = currentDeviceInfo else {
            logger.warning("No device information loaded")
            return
        }

        var updated = updates(deviceInfo)

        // Mark as updated and pending sync
        _ = updated.markUpdated()

        try await deviceInfoRepository.updateDeviceInfo(updated)
        currentDeviceInfo = updated

        logger.info("Device information updated and queued for sync")

        // Trigger sync in background
        await triggerBackgroundSync()
    }

    /// Sync device information to cloud
    public func syncToCloud() async throws {
        guard let coordinator = syncCoordinator else {
            logger.debug("No sync coordinator available")
            return
        }

        try await coordinator.sync(deviceInfoRepository)
        logger.info("Device information sync completed")
    }

    /// Get stored device information from database
    public func getStoredDeviceInfo() async -> DeviceInfoData? {
        do {
            return try await deviceInfoRepository.getStoredDeviceInfo()
        } catch {
            logger.error("Failed to get stored device info: \(error)")
            return nil
        }
    }

    // MARK: - Private Methods

    /// Trigger background sync if coordinator is available
    private func triggerBackgroundSync() async {
        guard let syncCoordinator = syncCoordinator else {
            logger.debug("No sync coordinator for background sync")
            return
        }

        Task {
            do {
                try await syncCoordinator.sync(deviceInfoRepository)
                logger.debug("Background device info sync completed")
            } catch {
                logger.debug("Background device info sync failed: \(error)")
            }
        }
    }
}

// MARK: - Device Information Summary

extension DeviceInfoService {

    /// Get the persistent device UUID
    /// This UUID will remain the same across app reinstalls
    public func getPersistentDeviceUUID() -> String {
        return PersistentDeviceIdentity.getPersistentDeviceUUID()
    }

    /// Get device fingerprint for additional validation
    public func getDeviceFingerprint() -> String {
        return PersistentDeviceIdentity.getDeviceFingerprint()
    }

    /// Get a summary of device information for logging/debugging
    public func getDeviceInfoSummary() async -> String {
        guard let deviceInfo = await getCurrentDeviceInfo() else {
            return "Device information not available"
        }

        let batteryInfo = deviceInfo.batteryLevel.map { "Battery: \(Int($0 * 100))%" } ?? "No battery"
        let totalMemoryGB = deviceInfo.totalMemory / 1024 / 1024 / 1024
        let availableMemoryGB = deviceInfo.availableMemory / 1024 / 1024 / 1024
        let memoryInfo = "Memory: \(totalMemoryGB)GB total, \(availableMemoryGB)GB available"
        let neuralEngineInfo = deviceInfo.hasNeuralEngine ?
            "Neural Engine: \(deviceInfo.neuralEngineCores) cores" : "No Neural Engine"

        return """
        Device: \(deviceInfo.deviceModel) (\(deviceInfo.deviceName))
        UUID: \(deviceInfo.id)
        OS: \(deviceInfo.osVersion)
        Chip: \(deviceInfo.chipName)
        Cores: \(deviceInfo.performanceCores)P + \(deviceInfo.efficiencyCores)E = \(deviceInfo.coreCount) total
        \(memoryInfo)
        \(neuralEngineInfo)
        \(batteryInfo)
        Fingerprint: \(deviceInfo.deviceFingerprint)
        """
    }
}
