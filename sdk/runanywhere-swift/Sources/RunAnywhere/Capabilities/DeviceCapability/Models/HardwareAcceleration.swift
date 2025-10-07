import Foundation

/// Hardware acceleration options
public enum HardwareAcceleration: String, CaseIterable {
    case cpu = "CPU"
    case gpu = "GPU"
    case neuralEngine = "NeuralEngine"
    case metal = "Metal"
    case coreML = "CoreML"
    case auto = "Auto"
}
