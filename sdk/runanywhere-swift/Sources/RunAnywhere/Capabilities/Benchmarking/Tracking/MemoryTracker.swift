//
//  MemoryTracker.swift
//  RunAnywhere SDK
//
//  Tracks memory usage during benchmarks
//

import Foundation

/// Tracks memory usage for benchmarking
public class MemoryTracker {
    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Get current memory usage in bytes
    public func getCurrentMemoryUsage() -> Int64 {
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

    /// Get memory delta between two measurements
    public func getMemoryDelta(from startMemory: Int64) -> Int64 {
        getCurrentMemoryUsage() - startMemory
    }

    /// Get formatted memory string
    public func formatMemory(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }
}
