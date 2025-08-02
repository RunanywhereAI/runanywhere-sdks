//
//  DeviceCapabilities.swift
//  RunAnywhere SDK
//
//  Device hardware capabilities information
//

import Foundation

/// Complete device hardware capabilities
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

    public init(
        totalMemory: Int64,
        availableMemory: Int64,
        hasNeuralEngine: Bool = false,
        hasGPU: Bool = false,
        processorCount: Int,
        processorType: ProcessorType = .unknown,
        supportedAccelerators: [HardwareAcceleration] = [.cpu],
        osVersion: OperatingSystemVersion,
        modelIdentifier: String = "Unknown"
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

    /// Memory pressure level based on available memory
    public var memoryPressureLevel: MemoryPressureLevel {
        let ratio = Double(availableMemory) / Double(totalMemory)

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

    /// Whether the device has sufficient resources for a given model
    public func canRun(model: ModelInfo) -> Bool {
        return availableMemory >= model.estimatedMemory
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

/// Memory pressure levels
public enum MemoryPressureLevel {
    case low
    case medium
    case high
    case critical
}

/// Processor type enumeration
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
