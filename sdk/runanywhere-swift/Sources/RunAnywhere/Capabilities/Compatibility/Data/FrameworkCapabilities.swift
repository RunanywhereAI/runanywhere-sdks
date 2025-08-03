import Foundation

/// Framework capability definitions
struct FrameworkCapabilities {
    fileprivate static let capabilities: [LLMFramework: InternalFrameworkCapability] = [
        .foundationModels: InternalFrameworkCapability(
            supportedFormats: [.mlmodel, .mlpackage],
            supportedQuantizations: [.q4_0],
            maxModelSize: 3_000_000_000,
            requiresSpecificModels: true,
            minimumOS: "18.0",
            supportedArchitectures: ["arm64e"]
        ),
        .coreML: InternalFrameworkCapability(
            supportedFormats: [.mlmodel, .mlpackage],
            supportedQuantizations: [.f16, .q8_0, .q4_0],
            maxModelSize: 15_000_000_000,
            requiresSpecificModels: false,
            minimumOS: "11.0",
            supportedArchitectures: ["arm64", "arm64e"]
        ),
        .mlx: InternalFrameworkCapability(
            supportedFormats: [.safetensors, .weights],
            supportedQuantizations: [.q4_0, .q4_K_M, .q8_0],
            maxModelSize: 30_000_000_000,
            requiresSpecificModels: false,
            minimumOS: "14.0",
            supportedArchitectures: ["arm64e"]
        ),
        .mlc: InternalFrameworkCapability(
            supportedFormats: [.safetensors, .bin],
            supportedQuantizations: [.q3_K_M, .q4_K_M],
            maxModelSize: 20_000_000_000,
            requiresSpecificModels: false,
            minimumOS: "14.0",
            supportedArchitectures: ["arm64", "arm64e"]
        ),
        .onnx: InternalFrameworkCapability(
            supportedFormats: [.onnx, .ort],
            supportedQuantizations: [.f32, .f16, .q8_0],
            maxModelSize: 10_000_000_000,
            requiresSpecificModels: false,
            minimumOS: "11.0",
            supportedArchitectures: ["arm64", "arm64e", "x86_64"]
        ),
        .execuTorch: InternalFrameworkCapability(
            supportedFormats: [.pte],
            supportedQuantizations: [.q4_0, .q8_0],
            maxModelSize: 15_000_000_000,
            requiresSpecificModels: false,
            minimumOS: "12.0",
            supportedArchitectures: ["arm64", "arm64e"]
        ),
        .llamaCpp: InternalFrameworkCapability(
            supportedFormats: [.gguf, .ggml],
            supportedQuantizations: [.q2_K, .q3_K_S, .q3_K_M, .q3_K_L, .q4_0, .q4_K_S, .q4_K_M, .q5_0, .q5_K_S, .q5_K_M, .q6_K, .q8_0],
            maxModelSize: 50_000_000_000,
            requiresSpecificModels: false,
            minimumOS: "10.0",
            supportedArchitectures: ["arm64", "arm64e", "x86_64"]
        ),
        .tensorFlowLite: InternalFrameworkCapability(
            supportedFormats: [.tflite],
            supportedQuantizations: [.f32, .f16, .q8_0],
            maxModelSize: 5_000_000_000,
            requiresSpecificModels: false,
            minimumOS: "11.0",
            supportedArchitectures: ["arm64", "arm64e"]
        ),
        .picoLLM: InternalFrameworkCapability(
            supportedFormats: [.bin],
            supportedQuantizations: [.q4_0, .q8_0],
            maxModelSize: 2_000_000_000,
            requiresSpecificModels: true,
            minimumOS: "11.0",
            supportedArchitectures: ["arm64", "arm64e"]
        ),
        .swiftTransformers: InternalFrameworkCapability(
            supportedFormats: [.mlmodel, .mlpackage],
            supportedQuantizations: [.f16, .q8_0],
            maxModelSize: 10_000_000_000,
            requiresSpecificModels: false,
            minimumOS: "15.0",
            supportedArchitectures: ["arm64", "arm64e"]
        ),
        .mediaPipe: InternalFrameworkCapability(
            supportedFormats: [.tflite, .gguf],
            supportedQuantizations: [.f32, .f16, .q8_0],
            maxModelSize: 5_000_000_000,
            requiresSpecificModels: false,
            minimumOS: "12.0",
            supportedArchitectures: ["arm64", "arm64e"]
        )
    ]

    internal static func getCapability(for framework: LLMFramework) -> InternalFrameworkCapability? {
        return capabilities[framework]
    }

    static func getSupportedFrameworks(for format: ModelFormat) -> [LLMFramework] {
        return capabilities.compactMap { (framework, capability) in
            capability.supportedFormats.contains(format) ? framework : nil
        }
    }
}

/// Internal capability information for a framework
internal struct InternalFrameworkCapability {
    let supportedFormats: Set<ModelFormat>
    let supportedQuantizations: Set<QuantizationLevel>
    let maxModelSize: Int64
    let requiresSpecificModels: Bool
    let minimumOS: String
    let supportedArchitectures: [String]
}
