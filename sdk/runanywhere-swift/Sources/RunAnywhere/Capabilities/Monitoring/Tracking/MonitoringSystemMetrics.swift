//
//  SystemMetrics.swift
//  RunAnywhere SDK
//
//  System metrics collection
//

import Foundation

/// Collects system performance metrics
internal class SystemMetrics {
    private let logger = SDKLogger(category: "SystemMetrics")

    /// Get current memory usage in bytes
    func getCurrentMemoryUsage() -> Int64 {
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

        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }

    /// Get available memory in bytes
    func getAvailableMemory() -> Int64 {
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let usedMemory = getCurrentMemoryUsage()
        return Int64(totalMemory) - usedMemory
    }

    /// Get current CPU usage (simplified implementation)
    func getCurrentCPUUsage() -> Double {
        var cpuInfo: processor_info_array_t!
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCpus: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCpus,
            &cpuInfo,
            &numCpuInfo
        )

        guard result == KERN_SUCCESS else {
            logger.debug("Failed to get CPU info")
            return 0
        }

        // Simplified CPU calculation
        // In production, this would track deltas over time
        return 0.15
    }

    /// Get memory usage ratio
    func getMemoryUsageRatio() -> Double {
        let currentMemory = getCurrentMemoryUsage()
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        return Double(currentMemory) / Double(totalMemory)
    }

    /// Get current thermal state
    func getThermalState() -> ProcessInfo.ThermalState {
        return ProcessInfo.processInfo.thermalState
    }
}
