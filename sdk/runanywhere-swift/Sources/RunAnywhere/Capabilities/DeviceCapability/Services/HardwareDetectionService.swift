//
//  HardwareCapabilityManager.swift
//  RunAnywhere SDK
//
//  This file has been refactored. The hardware detection functionality has been moved to:
//  - Infrastructure/Hardware/Detectors/ProcessorDetector.swift
//  - Infrastructure/Hardware/Detectors/NeuralEngineDetector.swift
//  - Infrastructure/Hardware/Detectors/GPUDetector.swift
//  - Infrastructure/Hardware/Capability/CapabilityAnalyzer.swift
//  - Infrastructure/Hardware/Models/DeviceCapabilities.swift
//  - Infrastructure/Hardware/Models/ProcessorInfo.swift
//
//  This file provides a compatibility facade and the main manager.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

/// Manager for hardware capability detection and configuration
public final class HardwareCapabilityManager: @unchecked Sendable {

    // MARK: - Properties

    /// Shared instance
    public static let shared: HardwareCapabilityManager = HardwareCapabilityManager()

    /// Capability analyzer
    private let capabilityAnalyzer: CapabilityAnalyzer


    /// Registered hardware detector (for backward compatibility)
    private var registeredHardwareDetector: HardwareDetector?
    private let detectorLock = NSLock()

    /// Cached capabilities
    private var cachedCapabilities: DeviceCapabilities?
    private var cacheTimestamp: Date?
    private let cacheValidityDuration: TimeInterval = 60 // 1 minute

    /// Device identifier for compilation cache
    public var deviceIdentifier: String {
        #if os(iOS) || os(tvOS)
        return UIDevice.current.model + "-" + ProcessInfo.processInfo.operatingSystemVersionString
        #elseif os(macOS)
        return "Mac-" + ProcessInfo.processInfo.operatingSystemVersionString
        #else
        return "Unknown-" + ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }

    // MARK: - Initialization

    private init() {
        self.capabilityAnalyzer = CapabilityAnalyzer()
    }

    // MARK: - Public API

    /// Register a platform-specific hardware detector (backward compatibility)
    public func registerHardwareDetector(_ detector: HardwareDetector) {
        detectorLock.lock()
        defer { detectorLock.unlock() }

        self.registeredHardwareDetector = detector
        self.cachedCapabilities = nil
        self.cacheTimestamp = nil
    }

    /// Get current device capabilities
    public var capabilities: DeviceCapabilities {
        detectorLock.lock()
        defer { detectorLock.unlock() }

        // Check cache validity
        if let cached = cachedCapabilities,
           let timestamp = cacheTimestamp,
           Date().timeIntervalSince(timestamp) < cacheValidityDuration {
            return cached
        }

        // Use capability analyzer for fresh detection
        let capabilities = capabilityAnalyzer.analyzeCapabilities()
        cachedCapabilities = capabilities
        cacheTimestamp = Date()

        return capabilities
    }

    /// Get optimal hardware configuration for a model
    public func optimalConfiguration(for model: ModelInfo) -> HardwareConfiguration {
        return capabilityAnalyzer.getOptimalConfiguration(for: model)
    }

    /// Check resource availability
    public func checkResourceAvailability() -> ResourceAvailability {
        let capabilities = self.capabilities

        let storageAvailable = getAvailableStorage()
        let accelerators = capabilities.supportedAccelerators
        let thermalState = getThermalState()
        let batteryInfo = getBatteryInfo()

        return ResourceAvailability(
            memoryAvailable: capabilities.availableMemory,
            storageAvailable: storageAvailable,
            acceleratorsAvailable: accelerators,
            thermalState: thermalState,
            batteryLevel: batteryInfo?.level,
            isLowPowerMode: batteryInfo?.isLowPowerModeEnabled ?? false
        )
    }


    /// Refresh cached capabilities
    public func refreshCapabilities() {
        detectorLock.lock()
        defer { detectorLock.unlock() }

        cachedCapabilities = nil
        cacheTimestamp = nil
    }

    // MARK: - Private Methods

    private func getAvailableStorage() -> Int64 {
        do {
            let fileURL = URL(fileURLWithPath: NSHomeDirectory())
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values.volumeAvailableCapacityForImportantUsage ?? 0
        } catch {
            return 0
        }
    }

    private func getThermalState() -> ProcessInfo.ThermalState {
        return ProcessInfo.processInfo.thermalState
    }

    private func getBatteryInfo() -> BatteryInfo? {
        #if os(iOS) || os(watchOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        return BatteryInfo(
            level: UIDevice.current.batteryLevel,
            state: {
                switch UIDevice.current.batteryState {
                case .unknown:
                    return .unknown
                case .unplugged:
                    return .unplugged
                case .charging:
                    return .charging
                case .full:
                    return .full
                @unknown default:
                    return .unknown
                }
            }(),
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
        #else
        return nil
        #endif
    }
}

// MARK: - Extensions

public extension HardwareCapabilityManager {
    /// Check if a specific accelerator is available
    func isAcceleratorAvailable(_ accelerator: HardwareAcceleration) -> Bool {
        let capabilities = self.capabilities
        return capabilities.supportedAccelerators.contains(accelerator)
    }

    /// Get memory pressure level
    var memoryPressureLevel: MemoryPressureLevel {
        return capabilities.memoryPressureLevel
    }
}

// MARK: - Backward Compatibility

/// Basic fallback hardware detector for backward compatibility
private class DefaultHardwareDetector: HardwareDetector {
    private let capabilityAnalyzer = CapabilityAnalyzer()

    func detectCapabilities() -> DeviceCapabilities {
        return capabilityAnalyzer.analyzeCapabilities()
    }

    func getAvailableMemory() -> Int64 {
        return capabilityAnalyzer.analyzeCapabilities().availableMemory
    }

    func getTotalMemory() -> Int64 {
        return capabilityAnalyzer.analyzeCapabilities().totalMemory
    }

    func hasNeuralEngine() -> Bool {
        return capabilityAnalyzer.analyzeCapabilities().hasNeuralEngine
    }

    func hasGPU() -> Bool {
        return capabilityAnalyzer.analyzeCapabilities().hasGPU
    }

    func getProcessorInfo() -> ProcessorInfo {
        let detector = ProcessorDetector()
        return detector.detectProcessorInfo()
    }

    func getThermalState() -> ProcessInfo.ThermalState {
        return ProcessInfo.processInfo.thermalState
    }

    func getBatteryInfo() -> BatteryInfo? {
        #if os(iOS) || os(watchOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        return BatteryInfo(
            level: UIDevice.current.batteryLevel,
            state: {
                switch UIDevice.current.batteryState {
                case .unknown: return .unknown
                case .unplugged: return .unplugged
                case .charging: return .charging
                case .full: return .full
                @unknown default: return .unknown
                }
            }(),
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
        #else
        return nil
        #endif
    }
}
