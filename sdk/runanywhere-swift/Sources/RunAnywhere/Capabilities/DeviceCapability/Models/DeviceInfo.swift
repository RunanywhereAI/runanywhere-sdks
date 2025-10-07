//
//  DeviceInfo.swift
//  RunAnywhere SDK
//
//  Device information for compatibility checking
//

import Foundation

// Platform-specific imports
#if os(iOS) || os(tvOS)
import UIKit
#endif

/// Device information for compatibility checking
public struct DeviceInfo: Codable {
    public let model: String
    public let osVersion: String
    public let architecture: String
    public let totalMemory: Int64
    public let availableMemory: Int64
    public let hasNeuralEngine: Bool
    public let gpuFamily: String?

    public init(
        model: String,
        osVersion: String,
        architecture: String,
        totalMemory: Int64,
        availableMemory: Int64,
        hasNeuralEngine: Bool,
        gpuFamily: String? = nil
    ) {
        self.model = model
        self.osVersion = osVersion
        self.architecture = architecture
        self.totalMemory = totalMemory
        self.availableMemory = availableMemory
        self.hasNeuralEngine = hasNeuralEngine
        self.gpuFamily = gpuFamily
    }

    /// Get current device info
    public static var current: DeviceInfo {
        let processInfo = ProcessInfo.processInfo

        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "unknown"
        #endif

        // Use DeviceKitAdapter if available
        let deviceModel = getDetailedDeviceModel()
        let neuralEngineInfo = getDetailedNeuralEngineInfo()

        return DeviceInfo(
            model: deviceModel,
            osVersion: processInfo.operatingSystemVersionString,
            architecture: architecture,
            totalMemory: Int64(processInfo.physicalMemory),
            availableMemory: getAvailableMemory(),
            hasNeuralEngine: neuralEngineInfo.hasNeuralEngine,
            gpuFamily: getGPUFamily()
        )
    }

    private static func getDetailedDeviceModel() -> String {
        // Try to use DeviceKitAdapter for detailed model name
        let adapter = DeviceKitAdapter()
        let deviceInfo = adapter.getDeviceInfo()

        // Return detailed name if available, otherwise fall back to generic
        if !deviceInfo.name.isEmpty && deviceInfo.name != "Simulator" {
            return deviceInfo.name
        }

        // Fallback to generic model
        #if os(iOS) || os(tvOS)
        return UIDevice.current.model
        #else
        return "Mac"
        #endif
    }

    private static func getDetailedNeuralEngineInfo() -> (hasNeuralEngine: Bool, cores: Int) {
        // Use DeviceKitAdapter for accurate Neural Engine detection
        let adapter = DeviceKitAdapter()
        let processorInfo = adapter.getProcessorInfo()

        return (
            hasNeuralEngine: processorInfo.hasNeuralEngine,
            cores: processorInfo.neuralEngineCores
        )
    }

    private static func getAvailableMemory() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }

        let used = result == KERN_SUCCESS ? Int64(info.resident_size) : 0
        return Int64(ProcessInfo.processInfo.physicalMemory) - used
    }


    private static func getGPUFamily() -> String? {
        #if os(iOS) || os(tvOS)
        return "Apple GPU"
        #else
        return "Metal"
        #endif
    }
}
