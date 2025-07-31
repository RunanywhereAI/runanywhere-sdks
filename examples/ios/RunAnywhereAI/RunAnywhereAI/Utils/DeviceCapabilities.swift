//
//  DeviceCapabilities.swift
//  RunAnywhereAI
//
//  Hardware capability detection for optimal delegate selection
//

import Foundation
import UIKit

struct DeviceCapabilities {

    // MARK: - Neural Engine Detection

    /// Check if device has Neural Engine (A12 Bionic or newer)
    static var hasNeuralEngine: Bool {
        // Get device model identifier
        var systemInfo = utsname()
        uname(&systemInfo)
        let modelCode = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                ptr in String(validatingUTF8: ptr)
            }
        } ?? "Unknown"

        // Neural Engine available on A12 and newer
        // iPhone XS/XR and newer (iPhone11,x and above)
        // iPad Pro 2018 and newer
        // iPad Air 2019 and newer
        // iPad Mini 2019 and newer
        let neuralEngineDevices = [
            "iPhone11", "iPhone12", "iPhone13", "iPhone14", "iPhone15", "iPhone16", "iPhone17",
            "iPad8", "iPad11", "iPad12", "iPad13", "iPad14",
            "iPad7,11", "iPad7,12", // iPad 7th gen
            "iPad11,6", "iPad11,7", // iPad 8th gen
            "iPad12,1", "iPad12,2", // iPad 9th gen
            "iPad13,1", "iPad13,2", // iPad Air 4th gen
            "iPad13,4", "iPad13,5", "iPad13,6", "iPad13,7", // iPad Pro 11" 3rd gen
            "iPad13,8", "iPad13,9", "iPad13,10", "iPad13,11", // iPad Pro 12.9" 5th gen
        ]

        return neuralEngineDevices.contains { modelCode.contains($0) }
    }

    // MARK: - GPU Performance Detection

    /// Check if device has high-performance GPU (A14 or newer)
    static var hasHighPerformanceGPU: Bool {
        // A14 and newer have significantly better GPU performance
        let modelCode = getModelCode()

        let highPerfDevices = [
            "iPhone13", "iPhone14", "iPhone15", "iPhone16", "iPhone17", // iPhone 12 and newer
            "iPad13,4", "iPad13,5", "iPad13,6", "iPad13,7", // iPad Pro 11" 3rd gen
            "iPad13,8", "iPad13,9", "iPad13,10", "iPad13,11", // iPad Pro 12.9" 5th gen
            "iPad13,16", "iPad13,17", // iPad Air 5th gen
            "iPad14", // Newer iPads
        ]

        return highPerfDevices.contains { modelCode.contains($0) }
    }

    // MARK: - Memory Detection

    /// Get device RAM in bytes
    static var totalMemory: Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }

        return result == KERN_SUCCESS ? Int64(info.resident_size) : Int64(ProcessInfo.processInfo.physicalMemory)
    }

    /// Check if device has sufficient memory for large models (>= 6GB RAM)
    static var hasHighMemory: Bool {
        ProcessInfo.processInfo.physicalMemory >= 6 * 1024 * 1024 * 1024
    }

    // MARK: - Processor Detection

    /// Number of processor cores
    static var processorCount: Int {
        ProcessInfo.processInfo.processorCount
    }

    /// Check if running on simulator
    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Acceleration Mode Selection

    enum AccelerationMode {
        case cpu
        case metal
        case coreML
        case auto
    }

    /// Determine best acceleration mode for current device
    static func recommendedAccelerationMode() -> AccelerationMode {
        // Simulator only supports CPU
        if isSimulator {
            return .cpu
        }

        // Neural Engine is fastest for supported devices
        if hasNeuralEngine {
            return .coreML
        }

        // High-performance GPU is next best option
        if hasHighPerformanceGPU {
            return .metal
        }

        // Fallback to CPU for older devices
        return .cpu
    }

    // MARK: - Device Info

    /// Get human-readable device name
    static var deviceName: String {
        UIDevice.current.name
    }

    /// Get device model
    static var deviceModel: String {
        UIDevice.current.model
    }

    /// Get iOS version
    static var systemVersion: String {
        UIDevice.current.systemVersion
    }

    /// Get detailed device info for logging
    static var deviceInfo: String {
        """
        Device: \(deviceName) (\(deviceModel))
        iOS: \(systemVersion)
        Processor Cores: \(processorCount)
        Memory: \(ByteCountFormatter.string(fromByteCount: totalMemory, countStyle: .memory))
        Neural Engine: \(hasNeuralEngine ? "Yes" : "No")
        High-Perf GPU: \(hasHighPerformanceGPU ? "Yes" : "No")
        Recommended Acceleration: \(recommendedAccelerationMode())
        """
    }

    // MARK: - Private Helpers

    private static func getModelCode() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                ptr in String(validatingUTF8: ptr)
            }
        } ?? "Unknown"
    }
}

// MARK: - TensorFlow Lite Specific Extensions

extension DeviceCapabilities {

    /// Check if Metal delegate is supported
    static var supportsMetalDelegate: Bool {
        !isSimulator && hasHighPerformanceGPU
    }

    /// Check if Core ML delegate is supported
    static var supportsCoreMLDelegate: Bool {
        !isSimulator && hasNeuralEngine
    }

    /// Get recommended thread count for CPU inference
    static var recommendedThreadCount: Int {
        // Use half the cores for better thermal management
        max(1, processorCount / 2)
    }

    /// Get recommended options based on device capabilities
    static func recommendedTFLiteOptions() -> String {
        var options: [String] = []

        if supportsCoreMLDelegate {
            options.append("Core ML Delegate (Neural Engine)")
        } else if supportsMetalDelegate {
            options.append("Metal Delegate (GPU)")
        } else {
            options.append("CPU (\(recommendedThreadCount) threads)")
        }

        if hasHighMemory {
            options.append("High Memory Mode")
        }

        return options.joined(separator: ", ")
    }
}
