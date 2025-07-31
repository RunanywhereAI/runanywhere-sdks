import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

/// Manager for hardware capability detection and configuration
public class HardwareCapabilityManager {
    // MARK: - Properties
    
    /// Shared instance
    public static let shared: HardwareCapabilityManager = HardwareCapabilityManager()
    
    /// Registered hardware detector
    private var registeredHardwareDetector: HardwareDetector?
    private let detectorLock: NSLock = NSLock()
    
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
    
    private init() {}
    
    // MARK: - Public API
    
    /// Register a platform-specific hardware detector
    /// - Parameter detector: Hardware detector implementation
    public func registerHardwareDetector(_ detector: HardwareDetector) {
        detectorLock.lock()
        defer { detectorLock.unlock() }
        
        self.registeredHardwareDetector = detector
        self.cachedCapabilities = nil // Clear cache
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
        
        // Use registered detector or fallback
        if let detector = registeredHardwareDetector {
            let capabilities = detector.detectCapabilities()
            cachedCapabilities = capabilities
            cacheTimestamp = Date()
            return capabilities
        } else {
            // Return minimal defaults if no detector registered
            let defaultCapabilities = createDefaultCapabilities()
            cachedCapabilities = defaultCapabilities
            cacheTimestamp = Date()
            return defaultCapabilities
        }
    }
    
    /// Get optimal hardware configuration for a model
    /// - Parameter model: Model information
    /// - Returns: Optimal hardware configuration
    public func optimalConfiguration(for model: ModelInfo) -> HardwareConfiguration {
        var config = HardwareConfiguration()
        
        // Get current capabilities
        let capabilities = self.capabilities
        
        // Determine primary accelerator
        config.primaryAccelerator = selectPrimaryAccelerator(for: model, capabilities: capabilities)
        
        // Set fallback accelerator
        config.fallbackAccelerator = selectFallbackAccelerator(
            primary: config.primaryAccelerator,
            capabilities: capabilities
        )
        
        // Configure memory mode
        config.memoryMode = selectMemoryMode(for: model, capabilities: capabilities)
        
        // Set thread count
        config.threadCount = selectThreadCount(for: model, capabilities: capabilities)
        
        // Determine quantization settings
        let quantizationSettings = selectQuantizationSettings(for: model, capabilities: capabilities)
        config.useQuantization = quantizationSettings.use
        config.quantizationBits = quantizationSettings.bits
        
        return config
    }
    
    /// Check resource availability
    /// - Returns: Current resource availability
    public func checkResourceAvailability() -> ResourceAvailability {
        let detector = registeredHardwareDetector ?? DefaultHardwareDetector()
        
        let memoryAvailable = detector.getAvailableMemory()
        let storageAvailable = getAvailableStorage()
        let accelerators = getAvailableAccelerators(from: detector)
        let thermalState = detector.getThermalState()
        let batteryInfo = detector.getBatteryInfo()
        
        return ResourceAvailability(
            memoryAvailable: memoryAvailable,
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
    
    private func createDefaultCapabilities() -> DeviceCapabilities {
        DeviceCapabilities(
            totalMemory: 2_000_000_000, // 2GB default
            availableMemory: 1_000_000_000, // 1GB default
            hasNeuralEngine: false,
            hasGPU: false,
            processorCount: ProcessInfo.processInfo.processorCount,
            processorType: .unknown,
            supportedAccelerators: [.cpu],
            osVersion: ProcessInfo.processInfo.operatingSystemVersion,
            modelIdentifier: deviceIdentifier
        )
    }
    
    private func selectPrimaryAccelerator(
        for model: ModelInfo,
        capabilities: DeviceCapabilities
    ) -> HardwareAcceleration {
        // Large models with Neural Engine support
        if model.estimatedMemory > 3_000_000_000 && capabilities.hasNeuralEngine {
            // Check if model format supports Neural Engine
            if model.format == .mlmodel || model.format == .mlpackage {
                return .neuralEngine
            }
        }
        
        // GPU for medium to large models
        if capabilities.hasGPU && model.estimatedMemory > 1_000_000_000 {
            return .gpu
        }
        
        // Check framework preferences
        if let preferred = model.preferredFramework {
            switch preferred {
            case .coreML where capabilities.hasNeuralEngine:
                return .neuralEngine
            case .tensorFlowLite where capabilities.hasGPU:
                return .gpu
            case .mlx where capabilities.hasGPU:
                return .metal
            default:
                break
            }
        }
        
        // Default to auto selection
        return .auto
    }
    
    private func selectFallbackAccelerator(
        primary: HardwareAcceleration,
        capabilities: DeviceCapabilities
    ) -> HardwareAcceleration {
        switch primary {
        case .neuralEngine:
            return capabilities.hasGPU ? .gpu : .cpu
        case .gpu, .metal:
            return .cpu
        case .coreML:
            return .cpu
        case .cpu:
            return .cpu
        case .auto:
            return .cpu
        }
    }
    
    private func selectMemoryMode(
        for model: ModelInfo,
        capabilities: DeviceCapabilities
    ) -> HardwareConfiguration.MemoryMode {
        let availableMemory = capabilities.availableMemory
        let modelMemory = model.estimatedMemory
        
        // Conservative mode for low memory
        if availableMemory < modelMemory * 2 {
            return .conservative
        }
        
        // Aggressive mode for plenty of memory
        if availableMemory > modelMemory * 4 && capabilities.totalMemory > 8_000_000_000 {
            return .aggressive
        }
        
        // Default to balanced
        return .balanced
    }
    
    private func selectThreadCount(
        for model: ModelInfo,
        capabilities: DeviceCapabilities
    ) -> Int {
        let processorCount = capabilities.processorCount
        
        // Use all cores for large models
        if model.estimatedMemory > 2_000_000_000 {
            return processorCount
        }
        
        // Use half cores for small models to save power
        if model.estimatedMemory < 500_000_000 {
            return max(1, processorCount / 2)
        }
        
        // Default to 75% of cores
        return max(1, Int(Double(processorCount) * 0.75))
    }
    
    private func selectQuantizationSettings(
        for model: ModelInfo,
        capabilities: DeviceCapabilities
    ) -> (use: Bool, bits: Int) {
        // Check if model already quantized
        if let quantLevel = model.metadata?.quantizationLevel {
            // Extract bits from quantization level
            switch quantLevel {
            case .int4:
                return (true, 4)
            case .int8:
                return (true, 8)
            case .half:
                return (true, 16)
            case .full:
                return (false, 32)
            case .int2:
                return (true, 2)
            case .mixed:
                return (true, 8) // Default for mixed
            }
        }
        
        // Enable quantization for low memory devices
        if capabilities.totalMemory < 4_000_000_000 {
            return (true, 4)
        }
        
        // Enable 8-bit quantization for medium memory
        if capabilities.totalMemory < 8_000_000_000 && model.estimatedMemory > 1_000_000_000 {
            return (true, 8)
        }
        
        // No quantization for high-end devices
        return (false, 8)
    }
    
    private func getAvailableStorage() -> Int64 {
        do {
            let fileURL = URL(fileURLWithPath: NSHomeDirectory())
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values.volumeAvailableCapacityForImportantUsage ?? 0
        } catch {
            return 0
        }
    }
    
    private func getAvailableAccelerators(from detector: HardwareDetector) -> [HardwareAcceleration] {
        var accelerators: [HardwareAcceleration] = [.cpu]
        
        if detector.hasGPU() {
            accelerators.append(.gpu)
            accelerators.append(.metal)
        }
        
        if detector.hasNeuralEngine() {
            accelerators.append(.neuralEngine)
            accelerators.append(.coreML)
        }
        
        return accelerators
    }
}

// MARK: - Default Hardware Detector

/// Basic fallback hardware detector
private class DefaultHardwareDetector: HardwareDetector {
    func detectCapabilities() -> DeviceCapabilities {
        DeviceCapabilities(
            totalMemory: Int64(ProcessInfo.processInfo.physicalMemory),
            availableMemory: getAvailableMemory(),
            hasNeuralEngine: false,
            hasGPU: false,
            processorCount: ProcessInfo.processInfo.processorCount,
            osVersion: ProcessInfo.processInfo.operatingSystemVersion
        )
    }
    
    func getAvailableMemory() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<natural_t>.size)
        
        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPtr, &count)
            }
        }
        
        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }
    
    func getTotalMemory() -> Int64 {
        Int64(ProcessInfo.processInfo.physicalMemory)
    }
    
    func hasNeuralEngine() -> Bool {
        false
    }
    
    func hasGPU() -> Bool {
        false
    }
    
    func getProcessorInfo() -> ProcessorInfo {
        ProcessorInfo(
            name: "Unknown",
            architecture: "Unknown",
            coreCount: ProcessInfo.processInfo.processorCount
        )
    }
    
    func getThermalState() -> ProcessInfo.ThermalState {
        #if canImport(Foundation)
        return ProcessInfo.processInfo.thermalState
        #else
        return .unknown
        #endif
    }
    
    func getBatteryInfo() -> BatteryInfo? {
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
    /// - Parameter accelerator: The accelerator to check
    /// - Returns: Whether the accelerator is available
    func isAcceleratorAvailable(_ accelerator: HardwareAcceleration) -> Bool {
        let resources = checkResourceAvailability()
        return resources.acceleratorsAvailable.contains(accelerator)
    }
    
    /// Get memory pressure level
    var memoryPressureLevel: MemoryPressureLevel {
        let capabilities = self.capabilities
        let ratio = Double(capabilities.availableMemory) / Double(capabilities.totalMemory)
        
        if ratio < 0.1 {
            return .critical
        } else if ratio < 0.2 {
            return .high
        } else if ratio < 0.4 {
            return .medium
        } else {
            return .low
        }
    }
    
    /// Memory pressure levels
    enum MemoryPressureLevel {
        case low
        case medium
        case high
        case critical
    }
}

// MARK: - macOS Support

#if os(macOS)
import IOKit

extension HardwareCapabilityManager {
    /// Get macOS-specific hardware information
    private func getMacHardwareInfo() -> [String: Any]? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            service,
            &properties,
            kCFAllocatorDefault,
            0
        ) == KERN_SUCCESS,
        let dict = properties?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        
        return dict
    }
}
#endif
