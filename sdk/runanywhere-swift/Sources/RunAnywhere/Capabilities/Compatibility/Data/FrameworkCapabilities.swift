import Foundation

/// Framework capability definitions
struct FrameworkCapabilities {
    static let capabilities: [LLMFramework: FrameworkCapability] = [
        .foundationModels: FrameworkCapability(
            supportedFormats: [.mlmodel, .mlpackage],
            supportedQuantizations: [.q4_0],
            maxModelSize: 3_000_000_000,
            requiresSpecificModels: true,
            minimumOS: "18.0",
            supportedArchitectures: ["arm64e"]
        ),
        .coreML: FrameworkCapability(
            supportedFormats: [.mlmodel, .mlpackage],
            supportedQuantizations: [.f16, .q8_0, .q4_0],
            maxModelSize: 15_000_000_000,
            requiresSpecificModels: false,
            minimumOS: "11.0",
            supportedArchitectures: ["arm64", "arm64e"]
        ),
        .mlx: FrameworkCapability(
            supportedFormats: [.safetensors, .weights],
            supportedQuantizations: [.q4_0, .q4_K_M, .q8_0],
            maxModelSize: 30_000_000_000,
            requiresSpecificModels: false,
            minimumOS: "14.0",
            supportedArchitectures: ["arm64e"]
        ),
        .mlc: FrameworkCapability(
            supportedFormats: [.safetensors, .bin],
            supportedQuantizations: [.q3_K_M, .q4_K_M],
            maxModelSize: 20_000_000_000,
            requiresSpecificModels: false,
            minimumOS: "14.0",
            supportedArchitectures: ["arm64", "arm64e"]
        ),
        .onnx: FrameworkCapability(
            supportedFormats: [.onnx, .ort],
            supportedQuantizations: [.f32, .f16, .q8_0],
            maxModelSize: 10_000_000_000,
            requiresSpecificModels: false,
            minimumOS: "11.0",
            supportedArchitectures: ["arm64", "arm64e", "x86_64"]
        ),
        .execuTorch: FrameworkCapability(
            supportedFormats: [.pte],
            supportedQuantizations: [.q4_0, .q8_0],
            maxModelSize: 15_000_000_000,
            requiresSpecificModels: false,
            minimumOS: "12.0",
            supportedArchitectures: ["arm64", "arm64e"]
        ),
        .llamaCpp: FrameworkCapability(
            supportedFormats: [.gguf, .ggml],
            supportedQuantizations: [.q2_K, .q3_K_S, .q3_K_M, .q3_K_L, .q4_0, .q4_K_S, .q4_K_M, .q5_0, .q5_K_S, .q5_K_M, .q6_K, .q8_0],
            maxModelSize: 50_000_000_000,
            requiresSpecificModels: false,
            minimumOS: "10.0",
            supportedArchitectures: ["arm64", "arm64e", "x86_64"]
        ),
        .tensorFlowLite: FrameworkCapability(
            supportedFormats: [.tflite],
            supportedQuantizations: [.f32, .f16, .q8_0],
            maxModelSize: 5_000_000_000,
            requiresSpecificModels: false,
            minimumOS: "11.0",
            supportedArchitectures: ["arm64", "arm64e"]
        ),
        .picoLLM: FrameworkCapability(
            supportedFormats: [.bin],
            supportedQuantizations: [.q4_0, .q8_0],
            maxModelSize: 2_000_000_000,
            requiresSpecificModels: true,
            minimumOS: "11.0",
            supportedArchitectures: ["arm64", "arm64e"]
        ),
        .swiftTransformers: FrameworkCapability(
            supportedFormats: [.mlmodel, .mlpackage],
            supportedQuantizations: [.f16, .q8_0],
            maxModelSize: 10_000_000_000,
            requiresSpecificModels: false,
            minimumOS: "15.0",
            supportedArchitectures: ["arm64", "arm64e"]
        )
    ]

    static func getCapability(for framework: LLMFramework) -> FrameworkCapability? {
        return capabilities[framework]
    }

    static func getSupportedFrameworks(for format: ModelFormat) -> [LLMFramework] {
        return capabilities.compactMap { (framework, capability) in
            capability.supportedFormats.contains(format) ? framework : nil
        }
    }
}

/// Capability information for a framework
struct FrameworkCapability {
    let supportedFormats: Set<ModelFormat>
    let supportedQuantizations: Set<QuantizationLevel>
    let maxModelSize: Int64
    let requiresSpecificModels: Bool
    let minimumOS: String
    let supportedArchitectures: [String]
}
