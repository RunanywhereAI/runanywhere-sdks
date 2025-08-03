import Foundation

/// Core ML specific options for text generation
public struct CoreMLOptions {
    /// Use Neural Engine if available
    public let useNeuralEngine: Bool

    /// Compute units preference
    public let computeUnits: ComputeUnits

    /// Compute units available for Core ML
    public enum ComputeUnits {
        case all
        case cpuOnly
        case cpuAndGPU
        case cpuAndNeuralEngine
    }

    /// Initialize Core ML options
    /// - Parameters:
    ///   - useNeuralEngine: Use Neural Engine if available (default: true)
    ///   - computeUnits: Compute units preference (default: .all)
    public init(
        useNeuralEngine: Bool = true,
        computeUnits: ComputeUnits = .all
    ) {
        self.useNeuralEngine = useNeuralEngine
        self.computeUnits = computeUnits
    }
}
