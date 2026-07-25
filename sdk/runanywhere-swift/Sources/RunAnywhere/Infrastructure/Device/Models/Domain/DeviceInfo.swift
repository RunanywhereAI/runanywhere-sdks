//
//  DeviceInfo.swift
//  RunAnywhere SDK
//
//  Apple-platform factory that populates the generated, cross-SDK
//  `RADeviceInfo` telemetry schema from sysctl / UIKit / ProcessInfo.
//

import CryptoKit
import Foundation

#if canImport(Metal)
import Metal
#endif

#if os(iOS) || os(tvOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#elseif os(macOS)
import IOKit.ps
#endif

/// Builds the canonical `RADeviceInfo` (generated proto) for the current
/// Apple device. The proto is the wire-canonical shape shared with
/// Kotlin / Dart / TS; this enum is just the Apple-specific population.
public enum DeviceInfoFactory {

    // MARK: - Current Device Info

    public static var current: RADeviceInfo {
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
        let chipSpec = getChipSpec(for: modelId)
        let (perfCores, effCores) = getCoreDistribution(totalCores: coreCount, modelId: modelId)

        // Platform-specific values
        #if os(iOS)
        let device = UIDevice.current
        let resolvedModel = getDeviceModelName(for: modelId)
        let deviceModel = resolvedModel ?? device.model
        let deviceName = device.name
        let platform = "ios"
        let formFactor = device.userInterfaceIdiom == .pad ? "tablet" : "phone"

        // Battery info (monitoring must be enabled before reading)
        device.isBatteryMonitoringEnabled = true
        let batteryLevel: Float? = device.batteryLevel >= 0 ? Float(device.batteryLevel) : nil
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
        let (batteryLevel, batteryState) = getMacBatteryInfo()
        #elseif os(tvOS)
        let device = UIDevice.current
        let deviceModel = getDeviceModelName(for: modelId) ?? device.model
        let deviceName = device.name
        let platform = "ios"
        let formFactor = "tv"
        let batteryLevel: Float? = nil
        let batteryState: String? = nil
        #elseif os(watchOS)
        let device = WKInterfaceDevice.current()
        let deviceModel = getDeviceModelName(for: modelId) ?? device.model
        let deviceName = device.name
        let platform = "ios"
        let formFactor = "watch"
        let batteryLevel: Float? = nil
        let batteryState: String? = nil
        #elseif os(visionOS)
        let deviceModel = "Apple Vision Pro"
        let deviceName = "Vision Pro"
        let platform = "ios"
        let formFactor = "headset"
        let batteryLevel: Float? = nil
        let batteryState: String? = nil
        #else
        let deviceModel = "Unknown"
        let deviceName = "Unknown"
        let platform = "web"
        let formFactor = "unknown"
        let batteryLevel: Float? = nil
        let batteryState: String? = nil
        #endif

        // Get available memory and clean OS version
        let availableMemory = getAvailableMemory()
        let osVersion = cleanVersion(processInfo.operatingSystemVersionString)

        var info = RADeviceInfo()
        info.deviceModel = deviceModel
        info.deviceName = deviceName
        info.platform = platform
        info.osVersion = osVersion
        info.formFactor = formFactor
        info.architecture = architecture
        info.chipName = chipSpec.name
        info.totalMemory = Int64(processInfo.physicalMemory)
        info.availableMemory = Int64(availableMemory)
        info.hasNeuralEngine_p = chipSpec.hasNeuralEngine
        info.neuralEngineCores = chipSpec.neuralEngineCores
        info.gpuFamily = cachedGPUFamily
        if let batteryLevel { info.batteryLevel = batteryLevel }
        if let batteryState { info.batteryState = batteryState }
        info.isLowPowerMode = processInfo.isLowPowerModeEnabled
        info.coreCount = Int32(coreCount)
        info.performanceCores = Int32(perfCores)
        info.efficiencyCores = Int32(effCores)
        return info
    }

    /// Stable hardware fingerprint: deterministic per physical device,
    /// survives reinstalls (derived only from hardware attributes).
    static let hardwareFingerprint: String = {
        let modelId = getModelIdentifier()
        let chipName = getChipSpec(for: modelId).name
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let coreCount = ProcessInfo.processInfo.processorCount
        let composite = "\(modelId)|\(chipName)|\(totalMemory)|\(coreCount)"
        let digest = SHA256.hash(data: Data(composite.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }()

    // MARK: - GPU Family

    private static let cachedGPUFamily: String = computeGPUFamily()

    private static func computeGPUFamily() -> String {
        #if canImport(Metal)
        guard let device = MTLCreateSystemDefaultDevice() else {
            #if arch(arm64)
            return "apple"
            #else
            return "intel"
            #endif
        }
        let families: [(MTLGPUFamily, String)] = [
            (.apple9, "apple9"), (.apple8, "apple8"), (.apple7, "apple7"),
            (.apple6, "apple6"), (.apple5, "apple5"), (.apple4, "apple4"),
            (.apple3, "apple3"), (.apple2, "apple2"), (.apple1, "apple1")
        ]
        for (family, name) in families where device.supportsFamily(family) {
            return name
        }
        #if os(macOS)
        if device.supportsFamily(.mac2) {
            return device.name.lowercased().contains("intel") ? "intel" : device.name.lowercased()
        }
        #endif
        return "apple"
        #else
        return "apple"
        #endif
    }

    // MARK: - System Helpers

    private static func getModelIdentifier() -> String {
        var size = 0
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return decodeCStringBuffer(machine)
        #elseif os(macOS)
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return decodeCStringBuffer(model)
        #else
        return "Unknown"
        #endif
    }

    private static func decodeCStringBuffer(_ buffer: [CChar]) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(bytes: bytes, encoding: .utf8) ?? ""
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

    #if os(macOS)
    private static func getMacBatteryInfo() -> (level: Float?, state: String?) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return (nil, nil)
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else {
                continue
            }
            var level: Float?
            if let current = description[kIOPSCurrentCapacityKey] as? Int,
               let maxCapacity = description[kIOPSMaxCapacityKey] as? Int,
               maxCapacity > 0 {
                level = Float(current) / Float(maxCapacity)
            }
            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            let state: String?
            if isCharging {
                state = "charging"
            } else if let level, level >= 1.0 {
                state = "full"
            } else if level != nil {
                state = "unplugged"
            } else {
                state = nil
            }
            return (level, state)
        }
        // Desktop Mac: no internal battery is legitimate
        return (nil, nil)
    }
    #endif

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

    // MARK: - Chip Lookup

    private struct ChipSpec {
        let name: String
        let neuralEngineCores: Int32
        let hasNeuralEngine: Bool
    }

    private static func getChipSpec(for identifier: String) -> ChipSpec {
        // Ordered prefix table: most specific entries first.
        let table: [(prefix: String, name: String, aneCores: Int32)] = [
            // iPhone
            ("iPhone18,", "A19 Pro", 16),
            ("iPhone17,1", "A18 Pro", 16), ("iPhone17,2", "A18 Pro", 16),
            ("iPhone17,", "A18", 16),
            ("iPhone16,", "A17 Pro", 16),
            ("iPhone15,", "A16 Bionic", 16),
            ("iPhone14,", "A15 Bionic", 16),
            ("iPhone13,", "A14 Bionic", 16),
            ("iPhone12,", "A13 Bionic", 8),
            ("iPhone11,", "A12 Bionic", 8),
            ("iPhone10,", "A11 Bionic", 2),
            // iPad
            ("iPad16,", "M4", 16),
            ("iPad15,", "M3", 16),
            ("iPad14,1", "A15 Bionic", 16), ("iPad14,2", "A15 Bionic", 16),
            ("iPad14,", "M2", 16),
            ("iPad13,1", "A14 Bionic", 16), ("iPad13,2", "A14 Bionic", 16),
            ("iPad13,", "M1", 16),
            // Mac
            ("Mac16,", "M4", 16),
            ("Mac15,14", "M3 Ultra", 32),
            ("Mac15,", "M3", 16),
            ("Mac14,8", "M2 Ultra", 32), ("Mac14,14", "M2 Ultra", 32),
            ("Mac14,13", "M2 Max", 16),
            ("Mac14,", "M2", 16),
            ("Mac13,2", "M1 Ultra", 32),
            ("Mac13,1", "M1 Max", 16),
            ("MacBookPro18,", "M1 Pro/Max", 16),
            ("MacBookPro17,1", "M1", 16),
            ("MacBookAir10,1", "M1", 16),
            ("Macmini9,1", "M1", 16),
            ("iMac21,", "M1", 16),
            // Vision Pro
            ("RealityDevice14,", "M2", 16)
        ]
        for entry in table where identifier.hasPrefix(entry.prefix) {
            return ChipSpec(
                name: entry.name,
                neuralEngineCores: entry.aneCores,
                hasNeuralEngine: true
            )
        }

        #if arch(arm64)
        // Unknown Apple Silicon: report the raw identifier so telemetry stays
        // informative; ANE presence is a safe assumption, core count is not.
        let name = identifier.isEmpty ? "Apple Silicon" : identifier
        return ChipSpec(name: name, neuralEngineCores: 0, hasNeuralEngine: true)
        #else
        return ChipSpec(name: "Intel", neuralEngineCores: 0, hasNeuralEngine: false)
        #endif
    }

    // MARK: - Core Distribution

    private static func sysctlInt32(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0, value > 0 else { return nil }
        return Int(value)
    }

    private static func getCoreDistribution(totalCores: Int, modelId: String) -> (perf: Int, eff: Int) {
        // Real values from the kernel (iOS 15+ / macOS 12+)
        if let perf = sysctlInt32("hw.perflevel0.logicalcpu") {
            let eff = sysctlInt32("hw.perflevel1.logicalcpu") ?? 0
            if perf + eff == totalCores {
                return (perf, eff)
            }
            return (min(perf, totalCores), max(0, totalCores - min(perf, totalCores)))
        }

        // Heuristic fallback
        if modelId.hasPrefix("iPhone") {
            return (2, totalCores - 2)
        }
        if modelId.hasPrefix("iPad") || modelId.hasPrefix("Mac") {
            let perf = max(2, totalCores * 2 / 5)
            return (perf, totalCores - perf)
        }
        return (max(1, totalCores / 3), totalCores - max(1, totalCores / 3))
    }
}
