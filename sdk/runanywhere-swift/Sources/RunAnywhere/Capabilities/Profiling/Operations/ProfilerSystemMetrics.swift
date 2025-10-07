//
//  SystemMetrics.swift
//  RunAnywhere SDK
//
//  System memory metrics utilities
//

import Foundation

/// Utilities for gathering system memory metrics
class ProfilerSystemMetrics {
    /// Get current memory usage in bytes
    static func getCurrentMemoryUsage() -> Int64 {
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
    static func getAvailableMemory() -> Int64 {
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let usedMemory = getCurrentMemoryUsage()
        return Int64(totalMemory) - usedMemory
    }

    /// Get memory pressure level
    static func getMemoryPressure() -> MemoryPressure {
        let usageRatio = Double(getCurrentMemoryUsage()) / Double(ProcessInfo.processInfo.physicalMemory)

        switch usageRatio {
        case 0..<0.5:
            return .normal
        case 0.5..<0.75:
            return .warning
        case 0.75..<0.9:
            return .urgent
        default:
            return .critical
        }
    }

    /// Get VM statistics
    static func getVMStatistics() -> vm_statistics64? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(
                    mach_host_self(),
                    HOST_VM_INFO64,
                    $0,
                    &count
                )
            }
        }

        return result == KERN_SUCCESS ? info : nil
    }

    /// Calculate memory fragmentation ratio
    static func calculateFragmentation() -> Double? {
        guard let vmStats = getVMStatistics() else { return nil }

        let pageSize = vm_kernel_page_size
        let totalPages = Double(vmStats.free_count + vmStats.active_count + vmStats.inactive_count + vmStats.wire_count)
        let freePages = Double(vmStats.free_count)

        guard totalPages > 0 else { return nil }

        // Simple fragmentation estimate based on free vs total pages
        let fragmentation = 1.0 - (freePages / totalPages)
        return fragmentation
    }
}
