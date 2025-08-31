import Foundation
import GRDB
#if os(iOS) || os(tvOS)
import UIKit
#endif
#if os(watchOS)
import WatchKit
#endif

/// Device information data structure for sync and storage
/// Leverages existing DeviceKitAdapter for comprehensive device detection
public struct DeviceInfoData: Codable, Syncable, RepositoryEntity, FetchableRecord, PersistableRecord {
    /// Unique identifier for this device (persistent UUID)
    public let id: String

    /// Device model (e.g., "iPhone 16 Pro", "MacBook Pro M4")
    public var deviceModel: String

    /// Device name (user-assigned name like "John's iPhone")
    public var deviceName: String

    /// Operating system version
    public var osVersion: String

    /// Processor architecture (e.g., "arm64", "x86_64")
    public var architecture: String

    /// Chip name (e.g., "A18 Pro", "M4")
    public var chipName: String

    /// Total memory in bytes
    public var totalMemory: Int64

    /// Available memory in bytes (at collection time)
    public var availableMemory: Int64

    /// Whether device has Neural Engine
    public var hasNeuralEngine: Bool

    /// Number of Neural Engine cores
    public var neuralEngineCores: Int

    /// GPU family identifier
    public var gpuFamily: String?

    /// Battery level (0.0-1.0, nil for devices without battery)
    public var batteryLevel: Float?

    /// Battery charging state
    public var batteryState: String?

    /// Low power mode enabled
    public var isLowPowerMode: Bool

    /// Core count (total CPU cores)
    public var coreCount: Int

    /// Performance cores count
    public var performanceCores: Int

    /// Efficiency cores count
    public var efficiencyCores: Int

    /// Metadata
    public let createdAt: Date
    public var updatedAt: Date
    public var syncPending: Bool

    public init(
        id: String,
        deviceModel: String,
        deviceName: String,
        osVersion: String,
        architecture: String,
        chipName: String,
        totalMemory: Int64,
        availableMemory: Int64,
        hasNeuralEngine: Bool,
        neuralEngineCores: Int,
        gpuFamily: String? = nil,
        batteryLevel: Float? = nil,
        batteryState: String? = nil,
        isLowPowerMode: Bool = false,
        coreCount: Int,
        performanceCores: Int,
        efficiencyCores: Int,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        syncPending: Bool = false
    ) {
        self.id = id
        self.deviceModel = deviceModel
        self.deviceName = deviceName
        self.osVersion = osVersion
        self.architecture = architecture
        self.chipName = chipName
        self.totalMemory = totalMemory
        self.availableMemory = availableMemory
        self.hasNeuralEngine = hasNeuralEngine
        self.neuralEngineCores = neuralEngineCores
        self.gpuFamily = gpuFamily
        self.batteryLevel = batteryLevel
        self.batteryState = batteryState
        self.isLowPowerMode = isLowPowerMode
        self.coreCount = coreCount
        self.performanceCores = performanceCores
        self.efficiencyCores = efficiencyCores
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncPending = syncPending
    }

    /// Create DeviceInfoData from current device using DeviceKitAdapter
    public static func current() -> DeviceInfoData {
        let adapter = DeviceKitAdapter()
        let deviceInfo = adapter.getDeviceInfo()
        let processorInfo = adapter.getProcessorInfo()
        let batteryInfo = adapter.getBatteryInfo()
        let capabilities = adapter.getDeviceCapabilities()

        // Get persistent device UUID that survives app reinstalls
        let deviceUUID = PersistentDeviceIdentity.getPersistentDeviceUUID()

        // Determine device name
        let deviceName = getDeviceName()

        return DeviceInfoData(
            id: deviceUUID,
            deviceModel: deviceInfo.name,
            deviceName: deviceName,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: capabilities.modelIdentifier,
            chipName: processorInfo.chipName,
            totalMemory: capabilities.totalMemory,
            availableMemory: capabilities.availableMemory,
            hasNeuralEngine: capabilities.hasNeuralEngine,
            neuralEngineCores: processorInfo.neuralEngineCores,
            gpuFamily: "Apple GPU", // All modern Apple devices have Apple GPU
            batteryLevel: batteryInfo?.level,
            batteryState: batteryInfo?.state.rawValue,
            isLowPowerMode: batteryInfo?.isLowPowerModeEnabled ?? false,
            coreCount: processorInfo.coreCount,
            performanceCores: processorInfo.performanceCores,
            efficiencyCores: processorInfo.efficiencyCores,
            syncPending: true // Mark for sync when created
        )
    }

    /// Get user-assigned device name
    private static func getDeviceName() -> String {
        #if os(iOS) || os(tvOS)
        return UIDevice.current.name
        #elseif os(macOS)
        // Get Mac computer name
        let host = Host.current()
        return host.localizedName ?? "Mac"
        #elseif os(watchOS)
        return WKInterfaceDevice.current().name
        #else
        return "Unknown Device"
        #endif
    }
}

// MARK: - GRDB Configuration

extension DeviceInfoData: TableRecord {
    /// The table name for DeviceInfoData in the database
    public static let databaseTableName = "device_info"

    /// Define how to handle conflicts during persistence
    public static let persistenceConflictPolicy = PersistenceConflictPolicy(
        insert: .replace,
        update: .replace
    )
}

// MARK: - Column Names for Type-Safe Queries

extension DeviceInfoData {
    public enum Columns: String, ColumnExpression {
        case id
        case deviceModel
        case deviceName
        case osVersion
        case architecture
        case chipName
        case totalMemory
        case availableMemory
        case hasNeuralEngine
        case neuralEngineCores
        case gpuFamily
        case batteryLevel
        case batteryState
        case isLowPowerMode
        case coreCount
        case performanceCores
        case efficiencyCores
        case createdAt
        case updatedAt
        case syncPending
    }
}

// MARK: - Battery State Extension

extension BatteryState: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .unknown: return "unknown"
        case .unplugged: return "unplugged"
        case .charging: return "charging"
        case .full: return "full"
        }
    }

    public init?(rawValue: String) {
        switch rawValue {
        case "unknown": self = .unknown
        case "unplugged": self = .unplugged
        case "charging": self = .charging
        case "full": self = .full
        default: return nil
        }
    }
}

// MARK: - Device Identity Extensions

extension DeviceInfoData {
    /// Get device fingerprint for additional validation
    public var deviceFingerprint: String {
        return PersistentDeviceIdentity.getDeviceFingerprint()
    }

    /// Validate that this device info represents the same physical device
    public var isValidDeviceUUID: Bool {
        return PersistentDeviceIdentity.validateDeviceUUID(self.id)
    }
}
