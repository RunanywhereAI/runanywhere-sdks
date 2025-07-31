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
    func getThermalState() -> ThermalState
    
    /// Get battery information
    /// - Returns: Battery information if available
    func getBatteryInfo() -> BatteryInfo?
}

/// Device capabilities structure
public struct DeviceCapabilities {
    public let totalMemory: Int64
    public let availableMemory: Int64
    public let hasNeuralEngine: Bool
    public let hasGPU: Bool
    public let processorCount: Int
    public let processorType: ProcessorType
    public let supportedAccelerators: [HardwareAcceleration]
    public let osVersion: OperatingSystemVersion
    public let modelIdentifier: String
    
    public enum ProcessorType {
        case a14Bionic
        case a15Bionic
        case a16Bionic
        case a17Pro
        case a18
        case a18Pro
        case m1
        case m1Pro
        case m1Max
        case m1Ultra
        case m2
        case m2Pro
        case m2Max
        case m2Ultra
        case m3
        case m3Pro
        case m3Max
        case m4
        case m4Pro
        case m4Max
        case intel
        case unknown
    }
    
    public init(
        totalMemory: Int64,
        availableMemory: Int64,
        hasNeuralEngine: Bool,
        hasGPU: Bool,
        processorCount: Int,
        processorType: ProcessorType = .unknown,
        supportedAccelerators: [HardwareAcceleration] = [],
        osVersion: OperatingSystemVersion,
        modelIdentifier: String = ""
    ) {
        self.totalMemory = totalMemory
        self.availableMemory = availableMemory
        self.hasNeuralEngine = hasNeuralEngine
        self.hasGPU = hasGPU
        self.processorCount = processorCount
        self.processorType = processorType
        self.supportedAccelerators = supportedAccelerators
        self.osVersion = osVersion
        self.modelIdentifier = modelIdentifier
    }
    
    /// Check if a hardware requirement is supported
    public func supports(_ requirement: HardwareRequirement) -> Bool {
        switch requirement {
        case .minimumMemory(let required):
            return totalMemory >= required
        case .requiresNeuralEngine:
            return hasNeuralEngine
        case .requiresGPU:
            return hasGPU
        case .minimumOSVersion(let version):
            return ProcessInfo.processInfo.isOperatingSystemAtLeast(
                OperatingSystemVersion(
                    majorVersion: Int(version.split(separator: ".")[0]) ?? 0,
                    minorVersion: Int(version.split(separator: ".")[1]) ?? 0,
                    patchVersion: 0
                )
            )
        case .specificChip(let chip):
            return modelIdentifier.contains(chip)
        case .minimumCompute(let compute):
            // Simplified check based on processor type
            switch processorType {
            case .a17Pro, .a18, .a18Pro, .m3, .m3Pro, .m3Max, .m4, .m4Pro, .m4Max:
                return compute <= "high"
            case .a15Bionic, .a16Bionic, .m1, .m1Pro, .m1Max, .m1Ultra, .m2, .m2Pro, .m2Max, .m2Ultra:
                return compute <= "medium"
            default:
                return compute <= "low"
            }
        }
    }
}

/// Processor information
public struct ProcessorInfo {
    public let name: String
    public let architecture: String
    public let coreCount: Int
    public let performanceCoreCount: Int
    public let efficiencyCoreCount: Int
    public let frequencyHz: Int64?
    public let hasARM64E: Bool
    
    public init(
        name: String,
        architecture: String,
        coreCount: Int,
        performanceCoreCount: Int = 0,
        efficiencyCoreCount: Int = 0,
        frequencyHz: Int64? = nil,
        hasARM64E: Bool = false
    ) {
        self.name = name
        self.architecture = architecture
        self.coreCount = coreCount
        self.performanceCoreCount = performanceCoreCount
        self.efficiencyCoreCount = efficiencyCoreCount
        self.frequencyHz = frequencyHz
        self.hasARM64E = hasARM64E
    }
}

/// Thermal state enumeration
public enum ThermalState {
    case nominal
    case fair
    case serious
    case critical
    case unknown
    
    #if canImport(Foundation)
    public init(from processInfoState: ProcessInfo.ThermalState) {
        switch processInfoState {
        case .nominal:
            self = .nominal
        case .fair:
            self = .fair
        case .serious:
            self = .serious
        case .critical:
            self = .critical
        @unknown default:
            self = .unknown
        }
    }
    #endif
}

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

/// Resource availability information
public struct ResourceAvailability {
    public let memoryAvailable: Int64
    public let storageAvailable: Int64
    public let acceleratorsAvailable: [HardwareAcceleration]
    public let thermalState: ThermalState
    public let batteryLevel: Float?
    public let isLowPowerMode: Bool
    
    public init(
        memoryAvailable: Int64,
        storageAvailable: Int64,
        acceleratorsAvailable: [HardwareAcceleration],
        thermalState: ThermalState,
        batteryLevel: Float? = nil,
        isLowPowerMode: Bool = false
    ) {
        self.memoryAvailable = memoryAvailable
        self.storageAvailable = storageAvailable
        self.acceleratorsAvailable = acceleratorsAvailable
        self.thermalState = thermalState
        self.batteryLevel = batteryLevel
        self.isLowPowerMode = isLowPowerMode
    }
    
    /// Check if resources are available to load a model
    public func canLoad(model: ModelInfo) -> (canLoad: Bool, reason: String?) {
        // Check memory
        if model.estimatedMemory > memoryAvailable {
            let needed = ByteCountFormatter.string(fromByteCount: model.estimatedMemory, countStyle: .memory)
            let available = ByteCountFormatter.string(fromByteCount: memoryAvailable, countStyle: .memory)
            return (false, "Insufficient memory: need \(needed), have \(available)")
        }
        
        // Check storage
        if let downloadSize = model.downloadSize, downloadSize > storageAvailable {
            let needed = ByteCountFormatter.string(fromByteCount: downloadSize, countStyle: .file)
            let available = ByteCountFormatter.string(fromByteCount: storageAvailable, countStyle: .file)
            return (false, "Insufficient storage: need \(needed), have \(available)")
        }
        
        // Check thermal state
        if thermalState == .critical {
            return (false, "Device is too hot, please wait for it to cool down")
        }
        
        // Check battery in low power mode
        if isLowPowerMode && batteryLevel != nil && batteryLevel! < 0.2 {
            return (false, "Battery too low for model loading in Low Power Mode")
        }
        
        return (true, nil)
    }
}
