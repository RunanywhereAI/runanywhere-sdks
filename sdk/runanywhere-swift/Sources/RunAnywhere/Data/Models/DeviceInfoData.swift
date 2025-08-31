import Foundation
import GRDB
#if os(iOS) || os(tvOS)
import UIKit
#endif
#if os(watchOS)
import WatchKit
#endif

// MARK: - Strongly Typed Enums

/// Device architecture types
public enum DeviceArchitecture: String, Codable, CaseIterable, Sendable {
    case arm64 = "arm64"
    case x86_64 = "x86_64"
    case unknown = "unknown"

    public var displayName: String {
        switch self {
        case .arm64: return "ARM64"
        case .x86_64: return "Intel x86_64"
        case .unknown: return "Unknown"
        }
    }
}

/// GPU family types for Apple devices
public enum GPUFamily: String, Codable, CaseIterable, Sendable {
    case appleGPU = "apple_gpu"
    case intel = "intel"
    case amd = "amd"
    case unknown = "unknown"

    public var displayName: String {
        switch self {
        case .appleGPU: return "Apple GPU"
        case .intel: return "Intel Graphics"
        case .amd: return "AMD Graphics"
        case .unknown: return "Unknown GPU"
        }
    }
}

// BatteryState is already defined in DeviceCapability/Models/BatteryInfo.swift
// We'll extend it with display names for consistency
extension BatteryState {
    public var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .unplugged: return "Not Charging"
        case .charging: return "Charging"
        case .full: return "Fully Charged"
        }
    }
}

/// Device form factor types
public enum DeviceFormFactor: String, Codable, CaseIterable, Sendable {
    case phone = "phone"
    case tablet = "tablet"
    case desktop = "desktop"
    case laptop = "laptop"
    case watch = "watch"
    case tv = "tv"
    case unknown = "unknown"

    public var displayName: String {
        switch self {
        case .phone: return "Phone"
        case .tablet: return "Tablet"
        case .desktop: return "Desktop"
        case .laptop: return "Laptop"
        case .watch: return "Watch"
        case .tv: return "TV"
        case .unknown: return "Unknown"
        }
    }
}

/// Device information data structure for sync and storage
/// Leverages existing DeviceKitAdapter for comprehensive device detection
public struct DeviceInfoData: Codable, RepositoryEntity, FetchableRecord, PersistableRecord, Sendable {
    /// Unique identifier for this device (persistent UUID)
    public let id: String

    /// Device model (e.g., "iPhone 16 Pro", "MacBook Pro M4")
    public var deviceModel: String

    /// Device name (user-assigned name like "John's iPhone")
    public var deviceName: String

    /// Operating system version
    public var osVersion: String

    /// Device form factor
    public var formFactor: DeviceFormFactor

    /// Processor architecture
    public var architecture: DeviceArchitecture

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

    /// GPU family
    public var gpuFamily: GPUFamily

    /// Battery level (0.0-1.0, nil for devices without battery)
    public var batteryLevel: Float?

    /// Battery charging state
    public var batteryState: BatteryState?

    /// Low power mode enabled
    public var isLowPowerMode: Bool

    /// Core count (total CPU cores)
    public var coreCount: Int

    /// Performance cores count
    public var performanceCores: Int

    /// Efficiency cores count
    public var efficiencyCores: Int

    // MARK: - RepositoryEntity Protocol Requirements
    public let createdAt: Date
    public var updatedAt: Date
    public var syncPending: Bool

    public init(
        id: String,
        deviceModel: String,
        deviceName: String,
        osVersion: String,
        formFactor: DeviceFormFactor = .unknown,
        architecture: DeviceArchitecture,
        chipName: String,
        totalMemory: Int64,
        availableMemory: Int64,
        hasNeuralEngine: Bool,
        neuralEngineCores: Int,
        gpuFamily: GPUFamily = .unknown,
        batteryLevel: Float? = nil,
        batteryState: BatteryState? = nil,
        isLowPowerMode: Bool = false,
        coreCount: Int,
        performanceCores: Int,
        efficiencyCores: Int,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        syncPending: Bool = true
    ) {
        self.id = id
        self.deviceModel = deviceModel
        self.deviceName = deviceName
        self.osVersion = osVersion
        self.formFactor = formFactor
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

        // Determine form factor based on platform and device type
        let formFactor = determineFormFactor(deviceName: deviceInfo.name)

        // Determine architecture
        let architecture = determineArchitecture()

        // Determine GPU family
        let gpuFamily: GPUFamily = .appleGPU // All modern Apple devices have Apple GPU

        // Battery state is already strongly typed from DeviceKitAdapter
        let batteryState = batteryInfo?.state

        return DeviceInfoData(
            id: deviceUUID,
            deviceModel: deviceInfo.name,
            deviceName: deviceName,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            formFactor: formFactor,
            architecture: architecture,
            chipName: processorInfo.chipName,
            totalMemory: capabilities.totalMemory,
            availableMemory: capabilities.availableMemory,
            hasNeuralEngine: capabilities.hasNeuralEngine,
            neuralEngineCores: processorInfo.neuralEngineCores,
            gpuFamily: gpuFamily,
            batteryLevel: batteryInfo?.level,
            batteryState: batteryState,
            isLowPowerMode: batteryInfo?.isLowPowerModeEnabled ?? false,
            coreCount: processorInfo.coreCount,
            performanceCores: processorInfo.performanceCores,
            efficiencyCores: processorInfo.efficiencyCores
        )
    }

    /// Determine device form factor based on platform and device information
    private static func determineFormFactor(deviceName: String) -> DeviceFormFactor {
        #if os(iOS)
        if deviceName.contains("iPad") {
            return .tablet
        } else {
            return .phone
        }
        #elseif os(macOS)
        if deviceName.contains("MacBook") {
            return .laptop
        } else {
            return .desktop
        }
        #elseif os(tvOS)
        return .tv
        #elseif os(watchOS)
        return .watch
        #else
        return .unknown
        #endif
    }

    /// Determine device architecture
    private static func determineArchitecture() -> DeviceArchitecture {
        #if arch(arm64)
        return .arm64
        #elseif arch(x86_64)
        return .x86_64
        #else
        return .unknown
        #endif
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
        case formFactor
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
