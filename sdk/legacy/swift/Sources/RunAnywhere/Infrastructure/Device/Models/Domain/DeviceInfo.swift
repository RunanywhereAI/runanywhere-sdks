//
//  DeviceInfo.swift
//  RunAnywhere SDK
//
//  Core device hardware information for telemetry and API requests
//  Matches backend schemas/device.py DeviceInfo schema
//

import Foundation

#if os(iOS) || os(tvOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#endif

/// Core device hardware information
/// Matches backend schemas/device.py DeviceInfo schema
public struct DeviceInfo: Codable, Sendable, Equatable {

    // MARK: - Required Fields (backend schema)

    public let deviceModel: String
    public let deviceName: String
    public let platform: String
    public let osVersion: String
    public let formFactor: String
    public let architecture: String
    public let chipName: String
    public let totalMemory: Int
    public let availableMemory: Int
    public let hasNeuralEngine: Bool
    public let neuralEngineCores: Int
    public let gpuFamily: String
    public let batteryLevel: Double?
    public let batteryState: String?
    public let isLowPowerMode: Bool
    public let coreCount: Int
    public let performanceCores: Int
    public let efficiencyCores: Int
    public let deviceFingerprint: String?

    // MARK: - Coding Keys (snake_case for backend)

    enum CodingKeys: String, CodingKey {
        case deviceModel = "device_model"
        case deviceName = "device_name"
        case platform
        case osVersion = "os_version"
        case formFactor = "form_factor"
        case architecture
        case chipName = "chip_name"
        case totalMemory = "total_memory"
        case availableMemory = "available_memory"
        case hasNeuralEngine = "has_neural_engine"
        case neuralEngineCores = "neural_engine_cores"
        case gpuFamily = "gpu_family"
        case batteryLevel = "battery_level"
        case batteryState = "battery_state"
        case isLowPowerMode = "is_low_power_mode"
        case coreCount = "core_count"
        case performanceCores = "performance_cores"
        case efficiencyCores = "efficiency_cores"
        case deviceFingerprint = "device_fingerprint"
    }

    // MARK: - Computed Properties

    public var cleanOSVersion: String {
        // Extract version number from "Version 17.2 (Build 21C52)" -> "17.2"
        if let match = osVersion.range(of: #"\d+\.\d+(\.\d+)?"#, options: .regularExpression) {
            return String(osVersion[match])
        }
        return osVersion
    }

    /// Device type derived from form factor (for API compatibility)
    public var deviceType: String {
        switch formFactor {
        case "phone": return "mobile"
        case "tablet": return "tablet"
        case "laptop", "desktop": return "desktop"
        case "tv": return "tv"
        case "watch": return "watch"
        case "headset": return "vr"
        default: return "mobile"
        }
    }

    /// Alias for backwards compatibility
    public var modelName: String { deviceModel }

    /// Alias for backwards compatibility
    public var deviceId: String { deviceFingerprint ?? "" }

    // MARK: - Current Device Info

    public static var current: DeviceInfo {
        let processInfo = ProcessInfo.processInfo
        let coreCount = processInfo.processorCount

        // Get architecture
        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "unknown"
        #endif

        // Get model identifier for chip/model lookup
        let modelId = getModelIdentifier()
        let chipName = getChipName(for: modelId)
        let (perfCores, effCores) = getCoreDistribution(totalCores: coreCount, modelId: modelId)

        // Platform-specific values
        #if os(iOS)
        let device = UIDevice.current
        let resolvedModel = getDeviceModelName(for: modelId)
        let deviceModel = resolvedModel ?? device.model
        let deviceName = device.name
        let platform = "ios"
        let formFactor = device.userInterfaceIdiom == .pad ? "tablet" : "phone"

        // Battery info
        device.isBatteryMonitoringEnabled = true
        let batteryLevel: Double? = device.batteryLevel >= 0 ? Double(device.batteryLevel) : nil
        let batteryState: String? = {
            switch device.batteryState {
            case .charging: return "charging"
            case .full: return "full"
            case .unplugged: return "unplugged"
            default: return nil
            }
        }()
        #elseif os(macOS)
        let deviceModel = getDeviceModelName(for: modelId) ?? Host.current().localizedName ?? "Mac"
        let deviceName = Host.current().localizedName ?? "Mac"
        let platform = "macos"
        let formFactor = modelId.contains("MacBook") ? "laptop" : "desktop"
        let batteryLevel: Double? = nil
        let batteryState: String? = nil
        #elseif os(tvOS)
        let device = UIDevice.current
        let deviceModel = getDeviceModelName(for: modelId) ?? device.model
        let deviceName = device.name
        let platform = "ios"
        let formFactor = "tv"
        let batteryLevel: Double? = nil
        let batteryState: String? = nil
        #elseif os(watchOS)
        let device = WKInterfaceDevice.current()
        let deviceModel = getDeviceModelName(for: modelId) ?? device.model
        let deviceName = device.name
        let platform = "ios"
        let formFactor = "watch"
        let batteryLevel: Double? = nil
        let batteryState: String? = nil
        #elseif os(visionOS)
        let deviceModel = "Apple Vision Pro"
        let deviceName = "Vision Pro"
        let platform = "ios"
        let formFactor = "headset"
        let batteryLevel: Double? = nil
        let batteryState: String? = nil
        #else
        let deviceModel = "Unknown"
        let deviceName = "Unknown"
        let platform = "web"
        let formFactor = "unknown"
        let batteryLevel: Double? = nil
        let batteryState: String? = nil
        #endif

        // Get available memory and clean OS version
        let availableMemory = getAvailableMemory()
        let osVersion = cleanVersion(processInfo.operatingSystemVersionString)

        return DeviceInfo(
            deviceModel: deviceModel,
            deviceName: deviceName,
            platform: platform,
            osVersion: osVersion,
            formFactor: formFactor,
            architecture: architecture,
            chipName: chipName,
            totalMemory: Int(processInfo.physicalMemory),
            availableMemory: availableMemory,
            hasNeuralEngine: architecture == "arm64",
            neuralEngineCores: architecture == "arm64" ? 16 : 0,
            gpuFamily: "apple",
            batteryLevel: batteryLevel,
            batteryState: batteryState,
            isLowPowerMode: processInfo.isLowPowerModeEnabled,
            coreCount: coreCount,
            performanceCores: perfCores,
            efficiencyCores: effCores,
            deviceFingerprint: DeviceIdentity.persistentUUID
        )
    }

    // MARK: - System Helpers

    private static func getModelIdentifier() -> String {
        var size = 0
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
        #elseif os(macOS)
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
        #else
        return "Unknown"
        #endif
    }

    private static func cleanVersion(_ version: String) -> String {
        // Extract "17.2" from "Version 17.2 (Build 21C52)"
        if let match = version.range(of: #"\d+\.\d+(\.\d+)?"#, options: .regularExpression) {
            return String(version[match])
        }
        return version
    }

    private static func getAvailableMemory() -> Int {
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        let totalMemory = Int(ProcessInfo.processInfo.physicalMemory)
        if result == KERN_SUCCESS {
            return max(0, totalMemory - Int(taskInfo.resident_size))
        }
        return totalMemory / 2
    }

    // MARK: - Device Model Lookup (minimal, common devices only)

    private static func getDeviceModelName(for identifier: String) -> String? {
        // iPhone 14-17 series (2022-2025)
        let models: [String: String] = [
            // iPhone 17 (2025)
            "iPhone18,1": "iPhone 17 Pro", "iPhone18,2": "iPhone 17 Pro Max",
            "iPhone18,3": "iPhone 17", "iPhone18,4": "iPhone 17 Plus",
            // iPhone 16 (2024)
            "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max",
            "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus",
            // iPhone 15 (2023)
            "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
            // iPhone 14 (2022)
            "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus",
            // iPad Pro M4 (2024)
            "iPad16,3": "iPad Pro 11-inch (M4)", "iPad16,4": "iPad Pro 11-inch (M4)",
            "iPad16,5": "iPad Pro 13-inch (M4)", "iPad16,6": "iPad Pro 13-inch (M4)",
            // Mac M4 (2024)
            "Mac16,1": "MacBook Pro 14-inch (M4)", "Mac16,6": "MacBook Pro 16-inch (M4)",
            "Mac16,10": "iMac (M4)", "Mac16,15": "Mac mini (M4)"
        ]
        return models[identifier]
    }

    private static func getChipName(for identifier: String) -> String {
        // Map model prefix to chip
        if identifier.hasPrefix("iPhone18,") { return "A19 Pro" }
        if identifier.hasPrefix("iPhone17,1") || identifier.hasPrefix("iPhone17,2") { return "A18 Pro" }
        if identifier.hasPrefix("iPhone17,") { return "A18" }
        if identifier.hasPrefix("iPhone16,") { return "A17 Pro" }
        if identifier.hasPrefix("iPhone15,2") || identifier.hasPrefix("iPhone15,3") { return "A16 Bionic" }
        if identifier.hasPrefix("iPhone15,") { return "A16 Bionic" }
        if identifier.hasPrefix("iPhone14,") { return "A15 Bionic" }
        if identifier.hasPrefix("iPad16,") || identifier.hasPrefix("Mac16,") { return "M4" }
        if identifier.hasPrefix("iPad15,") || identifier.hasPrefix("Mac15,") { return "M3" }
        if identifier.hasPrefix("Mac14,") { return "M2" }

        #if arch(arm64)
        return "Apple Silicon"
        #else
        return "Intel"
        #endif
    }

    private static func getCoreDistribution(totalCores: Int, modelId: String) -> (perf: Int, eff: Int) {
        // iPhone: typically 2P + 4E = 6 cores
        if modelId.hasPrefix("iPhone") {
            return (2, totalCores - 2)
        }
        // iPad/Mac M-series: typically ~40% performance cores
        if modelId.hasPrefix("iPad") || modelId.hasPrefix("Mac") {
            let perf = max(2, totalCores * 2 / 5)
            return (perf, totalCores - perf)
        }
        // Default split
        return (max(1, totalCores / 3), totalCores - max(1, totalCores / 3))
    }
}
