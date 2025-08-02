import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Protocol for hardware detection
public protocol HardwareDetector {
    /// Detect current device capabilities
    /// - Returns: Device capabilities
    func detectCapabilities() -> DeviceCapabilities

    /// Get available memory
    /// - Returns: Available memory in bytes
    func getAvailableMemory() -> Int64

    /// Get total memory
    /// - Returns: Total memory in bytes
    func getTotalMemory() -> Int64

    /// Check if Neural Engine is available
    /// - Returns: Whether Neural Engine is available
    func hasNeuralEngine() -> Bool

    /// Check if GPU is available
    /// - Returns: Whether GPU is available
    func hasGPU() -> Bool

    /// Get processor information
    /// - Returns: Processor information
    func getProcessorInfo() -> ProcessorInfo

    /// Get thermal state
    /// - Returns: Current thermal state
    func getThermalState() -> ProcessInfo.ThermalState

    /// Get battery information
    /// - Returns: Battery information if available
    func getBatteryInfo() -> BatteryInfo?
}

// DeviceCapabilities and ProcessorInfo are now defined in:
// - Infrastructure/Hardware/Models/DeviceCapabilities.swift
// - Infrastructure/Hardware/Models/ProcessorInfo.swift
// The types are available in the same module scope

// Using ProcessInfo.ThermalState from Foundation

/// Battery information
public struct BatteryInfo {
    public let level: Float  // 0.0 to 1.0
    public let state: BatteryState
    public let isLowPowerModeEnabled: Bool

    public enum BatteryState {
        case unknown
        case unplugged
        case charging
        case full
    }

    public init(
        level: Float,
        state: BatteryState,
        isLowPowerModeEnabled: Bool = false
    ) {
        self.level = level
        self.state = state
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
    }
}

// ResourceAvailability is defined in Types.swift
