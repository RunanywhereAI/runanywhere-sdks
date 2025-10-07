import Foundation

/// Architecture support matrix
struct ArchitectureSupport {

    /// Model architecture to framework compatibility
    static let architectureMatrix: [String: [LLMFramework: ArchitectureCompatibility]] = [
        "llama": [
            .coreML: .supported,
            .mlx: .supported,
            .llamaCpp: .supported,
            .onnx: .supported,
            .mlc: .supported,
            .swiftTransformers: .partiallySupported
        ],
        "gpt": [
            .coreML: .supported,
            .mlx: .supported,
            .onnx: .supported,
            .swiftTransformers: .supported,
            .tensorFlowLite: .partiallySupported
        ],
        "bert": [
            .coreML: .supported,
            .onnx: .supported,
            .tensorFlowLite: .supported,
            .swiftTransformers: .supported
        ],
        "t5": [
            .coreML: .supported,
            .onnx: .supported,
            .tensorFlowLite: .supported,
            .swiftTransformers: .supported
        ],
        "whisper": [
            .coreML: .supported,
            .onnx: .supported,
            .mlx: .supported
        ],
        "stable-diffusion": [
            .coreML: .supported,
            .onnx: .supported,
            .mlx: .supported
        ]
    ]

    static func getCompatibility(architecture: String, framework: LLMFramework) -> ArchitectureCompatibility {
        return architectureMatrix[architecture.lowercased()]?[framework] ?? .notSupported
    }

    static func getSupportedFrameworks(for architecture: String) -> [LLMFramework] {
        guard let frameworkMap = architectureMatrix[architecture.lowercased()] else {
            return []
        }

        return frameworkMap.compactMap { (framework, compatibility) in
            compatibility != .notSupported ? framework : nil
        }
    }

    static func getSupportedArchitectures(for framework: LLMFramework) -> [String] {
        return architectureMatrix.compactMap { (architecture, frameworkMap) in
            let compatibility = frameworkMap[framework] ?? .notSupported
            return compatibility != .notSupported ? architecture : nil
        }
    }
}

/// Architecture compatibility levels
enum ArchitectureCompatibility {
    case supported
    case partiallySupported
    case notSupported

    var description: String {
        switch self {
        case .supported:
            return "Fully Supported"
        case .partiallySupported:
            return "Partially Supported"
        case .notSupported:
            return "Not Supported"
        }
    }
}
