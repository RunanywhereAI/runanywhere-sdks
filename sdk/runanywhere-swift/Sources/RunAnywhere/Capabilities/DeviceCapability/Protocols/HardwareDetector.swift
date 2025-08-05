import Foundation

/// Protocol for hardware detection services
public protocol HardwareDetector {
    /// Detect current device capabilities
    func detectCapabilities() -> DeviceCapabilities

    /// Get available memory
    func getAvailableMemory() -> Int64

    /// Check if Neural Engine is available
    func hasNeuralEngine() -> Bool

    /// Check if GPU is available
    func hasGPU() -> Bool

    /// Get thermal state
    func getThermalState() -> ThermalState

    /// Get battery information (if applicable)
    func getBatteryInfo() -> BatteryInfo?
}
