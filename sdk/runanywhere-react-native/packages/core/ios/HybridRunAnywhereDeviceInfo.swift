import Foundation
import NitroModules
import UIKit

/// Swift implementation of RunAnywhereDeviceInfo HybridObject
/// Mirrors: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Device/Models/Domain/DeviceInfo.swift
class HybridRunAnywhereDeviceInfo: HybridRunAnywhereDeviceInfoSpec {

    // MARK: - Model Lookup Tables (from Swift SDK)

    private static let deviceModels: [String: String] = [
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
        // iPhone 13 (2021)
        "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13",
        // iPhone 12 (2020)
        "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
        // iPhone SE
        "iPhone14,6": "iPhone SE (3rd gen)", "iPhone12,8": "iPhone SE (2nd gen)",
        // iPad Pro M4 (2024)
        "iPad16,3": "iPad Pro 11-inch (M4)", "iPad16,4": "iPad Pro 11-inch (M4)",
        "iPad16,5": "iPad Pro 13-inch (M4)", "iPad16,6": "iPad Pro 13-inch (M4)",
        // iPad Pro M2 (2022)
        "iPad14,3": "iPad Pro 11-inch (M2)", "iPad14,4": "iPad Pro 11-inch (M2)",
        "iPad14,5": "iPad Pro 12.9-inch (M2)", "iPad14,6": "iPad Pro 12.9-inch (M2)",
        // iPad Air
        "iPad14,8": "iPad Air (M2)", "iPad14,9": "iPad Air (M2)",
        "iPad13,16": "iPad Air (5th gen)", "iPad13,17": "iPad Air (5th gen)"
    ]

    // MARK: - Get Machine Identifier

    private static func getMachineIdentifier() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "Unknown"
            }
        }
    }

    // MARK: - Chip Name Lookup (from Swift SDK)

    private static func getChipNameForModel(_ identifier: String) -> String {
        if identifier.hasPrefix("iPhone18,") { return "A19 Pro" }
        if identifier.hasPrefix("iPhone17,1") || identifier.hasPrefix("iPhone17,2") { return "A18 Pro" }
        if identifier.hasPrefix("iPhone17,") { return "A18" }
        if identifier.hasPrefix("iPhone16,") { return "A17 Pro" }
        if identifier.hasPrefix("iPhone15,2") || identifier.hasPrefix("iPhone15,3") { return "A16 Bionic" }
        if identifier.hasPrefix("iPhone15,") { return "A16 Bionic" }
        if identifier.hasPrefix("iPhone14,") { return "A15 Bionic" }
        if identifier.hasPrefix("iPhone13,") { return "A14 Bionic" }
        if identifier.hasPrefix("iPhone12,") { return "A13 Bionic" }
        if identifier.hasPrefix("iPad16,") { return "M4" }
        if identifier.hasPrefix("iPad14,3") || identifier.hasPrefix("iPad14,4") ||
           identifier.hasPrefix("iPad14,5") || identifier.hasPrefix("iPad14,6") { return "M2" }
        if identifier.hasPrefix("iPad14,8") || identifier.hasPrefix("iPad14,9") { return "M2" }
        if identifier.hasPrefix("iPad13,") { return "M1" }

        #if arch(arm64)
        return "Apple Silicon"
        #else
        return "Intel"
        #endif
    }

    // MARK: - HybridObject Implementation

    func getDeviceModel() throws -> Promise<String> {
        return Promise.async {
            let machineId = Self.getMachineIdentifier()

            // Check simulator
            #if targetEnvironment(simulator)
            if let simModelId = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
                return Self.deviceModels[simModelId] ?? "iOS Simulator"
            }
            return "iOS Simulator"
            #else
            // Look up friendly model name
            return Self.deviceModels[machineId] ?? UIDevice.current.model
            #endif
        }
    }

    func getOSVersion() throws -> Promise<String> {
        return Promise.async {
            return UIDevice.current.systemVersion
        }
    }

    func getPlatform() throws -> Promise<String> {
        return Promise.async {
            return "ios"
        }
    }

    func getTotalRAM() throws -> Promise<Double> {
        return Promise.async {
            return Double(ProcessInfo.processInfo.physicalMemory)
        }
    }

    func getAvailableRAM() throws -> Promise<Double> {
        return Promise.async {
            var info = mach_task_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
            let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                    task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
                }
            }
            if kerr == KERN_SUCCESS {
                let usedMemory = Double(info.resident_size)
                let totalMemory = Double(ProcessInfo.processInfo.physicalMemory)
                return totalMemory - usedMemory
            }
            return Double(ProcessInfo.processInfo.physicalMemory) / 2
        }
    }

    func getCPUCores() throws -> Promise<Double> {
        return Promise.async {
            return Double(ProcessInfo.processInfo.processorCount)
        }
    }

    func hasGPU() throws -> Promise<Bool> {
        return Promise.async {
            // iOS devices always have GPU
            return true
        }
    }

    func hasNPU() throws -> Promise<Bool> {
        return Promise.async {
            // Check for Neural Engine (A11 Bionic and later = iPhone X and later)
            // All arm64 iOS devices since 2017 have Neural Engine
            #if arch(arm64)
            return true
            #else
            return false
            #endif
        }
    }

    func getChipName() throws -> Promise<String> {
        return Promise.async {
            let machineId = Self.getMachineIdentifier()

            #if targetEnvironment(simulator)
            if let simModelId = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
                return Self.getChipNameForModel(simModelId)
            }
            return "Simulated"
            #else
            return Self.getChipNameForModel(machineId)
            #endif
        }
    }

    func getThermalState() throws -> Promise<Double> {
        return Promise.async {
            let state = ProcessInfo.processInfo.thermalState
            switch state {
            case .nominal: return 0.0
            case .fair: return 1.0
            case .serious: return 2.0
            case .critical: return 3.0
            @unknown default: return 0.0
            }
        }
    }

    func getBatteryLevel() throws -> Promise<Double> {
        return Promise.async {
            await MainActor.run {
                UIDevice.current.isBatteryMonitoringEnabled = true
            }
            let level = UIDevice.current.batteryLevel
            // batteryLevel is -1.0 if monitoring not enabled or on simulator
            return level >= 0 ? Double(level) : -1.0
        }
    }

    func isCharging() throws -> Promise<Bool> {
        return Promise.async {
            await MainActor.run {
                UIDevice.current.isBatteryMonitoringEnabled = true
            }
            let state = UIDevice.current.batteryState
            return state == .charging || state == .full
        }
    }

    func isLowPowerMode() throws -> Promise<Bool> {
        return Promise.async {
            return ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
}
