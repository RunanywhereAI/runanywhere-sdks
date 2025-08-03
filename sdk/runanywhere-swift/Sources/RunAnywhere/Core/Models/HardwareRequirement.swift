import Foundation

/// Hardware requirements for models
public enum HardwareRequirement {
    case minimumMemory(Int64)
    case minimumCompute(String)
    case requiresNeuralEngine
    case requiresGPU
    case minimumOSVersion(String)
    case specificChip(String)
}
