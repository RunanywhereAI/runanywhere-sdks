import SwiftUI
import Combine

@MainActor
class FrameworkCapabilityExplorerViewModel: ObservableObject {
    func getCapabilities(for framework: LLMFramework) -> FrameworkCapabilities {
        switch framework {
        case .llamaCpp:
            return FrameworkCapabilities(
                supportsStreaming: true,
                supportsQuantization: true,
                supportsBatching: false,
                supportsMultiModal: false,
                supportsGPUAcceleration: true,
                supportsCustomModels: true,
                topFeatures: ["GGUF Support", "Metal Acceleration", "Low Memory"]
            )

        case .coreML:
            return FrameworkCapabilities(
                supportsStreaming: false,
                supportsQuantization: true,
                supportsBatching: true,
                supportsMultiModal: true,
                supportsGPUAcceleration: true,
                supportsCustomModels: true,
                topFeatures: ["Neural Engine", "Apple Integration", "Optimization"]
            )

        case .mlx:
            return FrameworkCapabilities(
                supportsStreaming: true,
                supportsQuantization: true,
                supportsBatching: true,
                supportsMultiModal: false,
                supportsGPUAcceleration: true,
                supportsCustomModels: true,
                topFeatures: ["Unified Memory", "NumPy-like", "Auto Differentiation"]
            )

        case .onnxRuntime:
            return FrameworkCapabilities(
                supportsStreaming: false,
                supportsQuantization: true,
                supportsBatching: true,
                supportsMultiModal: true,
                supportsGPUAcceleration: true,
                supportsCustomModels: true,
                topFeatures: ["Cross-platform", "Multiple Providers", "Industry Standard"]
            )

        case .execuTorch:
            return FrameworkCapabilities(
                supportsStreaming: false,
                supportsQuantization: true,
                supportsBatching: false,
                supportsMultiModal: false,
                supportsGPUAcceleration: true,
                supportsCustomModels: true,
                topFeatures: ["PyTorch Ecosystem", "4-bit Quantization", "Edge Optimized"]
            )

        case .tensorFlowLite:
            return FrameworkCapabilities(
                supportsStreaming: false,
                supportsQuantization: true,
                supportsBatching: true,
                supportsMultiModal: true,
                supportsGPUAcceleration: true,
                supportsCustomModels: true,
                topFeatures: ["TensorFlow Ecosystem", "Delegate System", "Model Toolkit"]
            )

        case .picoLLM:
            return FrameworkCapabilities(
                supportsStreaming: true,
                supportsQuantization: true,
                supportsBatching: false,
                supportsMultiModal: false,
                supportsGPUAcceleration: false,
                supportsCustomModels: false,
                topFeatures: ["Ultra Compression", "Voice Optimized", "Real-time"]
            )

        case .swiftTransformers:
            return FrameworkCapabilities(
                supportsStreaming: true,
                supportsQuantization: false,
                supportsBatching: true,
                supportsMultiModal: false,
                supportsGPUAcceleration: false,
                supportsCustomModels: true,
                topFeatures: ["Native Swift", "Hugging Face", "Type Safety"]
            )

        case .mlc:
            return FrameworkCapabilities(
                supportsStreaming: true,
                supportsQuantization: true,
                supportsBatching: true,
                supportsMultiModal: false,
                supportsGPUAcceleration: true,
                supportsCustomModels: true,
                topFeatures: ["TVM Compilation", "Hardware Agnostic", "OpenAI API"]
            )

        case .foundationModels:
            return FrameworkCapabilities(
                supportsStreaming: true,
                supportsQuantization: false,
                supportsBatching: false,
                supportsMultiModal: true,
                supportsGPUAcceleration: true,
                supportsCustomModels: false,
                topFeatures: ["Apple Silicon", "Privacy First", "System Integration"]
            )
        }
    }

    func getPerformanceProfile(for framework: LLMFramework) -> PerformanceProfile {
        switch framework {
        case .llamaCpp:
            return PerformanceProfile(speed: 0.8, memoryEfficiency: 0.9, modelSizeSupport: 0.95, easeOfUse: 0.7)
        case .coreML:
            return PerformanceProfile(speed: 0.95, memoryEfficiency: 0.8, modelSizeSupport: 0.7, easeOfUse: 0.85)
        case .mlx:
            return PerformanceProfile(speed: 0.9, memoryEfficiency: 0.95, modelSizeSupport: 0.8, easeOfUse: 0.75)
        case .onnxRuntime:
            return PerformanceProfile(speed: 0.85, memoryEfficiency: 0.75, modelSizeSupport: 0.9, easeOfUse: 0.8)
        case .execuTorch:
            return PerformanceProfile(speed: 0.7, memoryEfficiency: 0.85, modelSizeSupport: 0.6, easeOfUse: 0.65)
        case .tensorFlowLite:
            return PerformanceProfile(speed: 0.8, memoryEfficiency: 0.8, modelSizeSupport: 0.85, easeOfUse: 0.75)
        case .picoLLM:
            return PerformanceProfile(speed: 0.95, memoryEfficiency: 0.95, modelSizeSupport: 0.4, easeOfUse: 0.9)
        case .swiftTransformers:
            return PerformanceProfile(speed: 0.6, memoryEfficiency: 0.7, modelSizeSupport: 0.7, easeOfUse: 0.95)
        case .mlc:
            return PerformanceProfile(speed: 0.85, memoryEfficiency: 0.8, modelSizeSupport: 0.85, easeOfUse: 0.7)
        case .foundationModels:
            return PerformanceProfile(speed: 0.9, memoryEfficiency: 0.9, modelSizeSupport: 0.5, easeOfUse: 0.95)
        }
    }

    func getUseCases(for framework: LLMFramework) -> [String] {
        switch framework {
        case .llamaCpp:
            return ["Large model inference", "Resource-constrained devices", "GGUF model deployment"]
        case .coreML:
            return ["Apple ecosystem apps", "Neural Engine optimization", "Production iOS apps"]
        case .mlx:
            return ["Research and experimentation", "Apple Silicon optimization", "Custom model training"]
        case .onnxRuntime:
            return ["Cross-platform deployment", "Enterprise applications", "Model interoperability"]
        case .execuTorch:
            return ["PyTorch model deployment", "Edge computing", "Mobile AI applications"]
        case .tensorFlowLite:
            return ["TensorFlow ecosystem", "Multi-platform deployment", "Production mobile apps"]
        case .picoLLM:
            return ["Voice applications", "Ultra-low latency", "Real-time processing"]
        case .swiftTransformers:
            return ["Native Swift development", "Hugging Face models", "Type-safe inference"]
        case .mlc:
            return ["Universal deployment", "Hardware optimization", "OpenAI-compatible API"]
        case .foundationModels:
            return ["iOS 18+ applications", "Privacy-focused apps", "System-integrated AI"]
        }
    }

    func getCodeExample(for framework: LLMFramework) -> String {
        switch framework {
        case .llamaCpp:
            return """
            let service = LlamaCppService()
            try await service.loadModel("model.gguf")
            let result = try await service.generate(prompt: "Hello")
            """
        case .coreML:
            return """
            let service = CoreMLService()
            try await service.loadModel("model.mlmodel")
            let result = try await service.generate(prompt: "Hello")
            """
        case .mlx:
            return """
            let service = MLXService()
            try await service.loadModel("model.npz")
            let result = try await service.generate(prompt: "Hello")
            """
        case .onnxRuntime:
            return """
            let service = ONNXService()
            try await service.loadModel("model.onnx")
            let result = try await service.generate(prompt: "Hello")
            """
        case .execuTorch:
            return """
            let service = ExecuTorchService()
            try await service.loadModel("model.pte")
            let result = try await service.generate(prompt: "Hello")
            """
        case .tensorFlowLite:
            return """
            let service = TFLiteService()
            try await service.loadModel("model.tflite")
            let result = try await service.generate(prompt: "Hello")
            """
        case .picoLLM:
            return """
            let service = PicoLLMService()
            try await service.loadModel("model.pv")
            let result = try await service.generate(prompt: "Hello")
            """
        case .swiftTransformers:
            return """
            let service = SwiftTransformersService()
            try await service.loadModel("gpt2")
            let result = try await service.generate(prompt: "Hello")
            """
        case .mlc:
            return """
            let service = MLCService()
            try await service.loadModel("model.so")
            let result = try await service.generate(prompt: "Hello")
            """
        case .foundationModels:
            return """
            if #available(iOS 18.0, *) {
                let service = FoundationModelsService()
                let result = try await service.generate(prompt: "Hello")
            }
            """
        }
    }
}

struct FrameworkCapabilities {
    let supportsStreaming: Bool
    let supportsQuantization: Bool
    let supportsBatching: Bool
    let supportsMultiModal: Bool
    let supportsGPUAcceleration: Bool
    let supportsCustomModels: Bool
    let topFeatures: [String]
}

struct PerformanceProfile {
    let speed: Double
    let memoryEfficiency: Double
    let modelSizeSupport: Double
    let easeOfUse: Double
}

extension LLMFramework {
    var iconName: String {
        switch self {
        case .llamaCpp: return "cube.fill"
        case .coreML: return "brain.head.profile"
        case .mlx: return "memorychip.fill"
        case .onnxRuntime: return "network"
        case .execuTorch: return "flame.fill"
        case .tensorFlowLite: return "cpu.fill"
        case .picoLLM: return "mic.fill"
        case .swiftTransformers: return "swift"
        case .mlc: return "gearshape.fill"
        case .foundationModels: return "apple.logo"
        }
    }

    var description: String {
        switch self {
        case .llamaCpp: return "C++ implementation for GGUF models"
        case .coreML: return "Apple's machine learning framework"
        case .mlx: return "Apple Silicon optimized framework"
        case .onnxRuntime: return "Open Neural Network Exchange"
        case .execuTorch: return "PyTorch on-device inference"
        case .tensorFlowLite: return "TensorFlow mobile framework"
        case .picoLLM: return "Ultra-compressed voice-optimized LLM"
        case .swiftTransformers: return "Native Swift transformer implementation"
        case .mlc: return "Machine Learning Compilation for LLMs"
        case .foundationModels: return "Apple Foundation Models (iOS 18+)"
        }
    }
}
