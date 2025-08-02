//
//  ModelCompatibilityMatrix.swift
//  RunAnywhere SDK
//
//  Model compatibility checking infrastructure
//

import Foundation

/// Model compatibility matrix for determining which models work with which frameworks
public class ModelCompatibilityMatrix {
    public static let shared = ModelCompatibilityMatrix()

    private let logger = SDKLogger(category: "Compatibility")

    // MARK: - Compatibility Data

    /// Framework capabilities
    public let frameworkCapabilities: [LLMFramework: FrameworkCapability] = [
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

    /// Model architecture support
    public let modelArchitectureSupport: [ModelArchitecture: Set<LLMFramework>] = [
        .llama: [.llamaCpp, .mlx, .mlc, .coreML, .onnx, .execuTorch, .tensorFlowLite],
        .mistral: [.llamaCpp, .mlx, .mlc, .coreML, .onnx],
        .phi: [.llamaCpp, .coreML, .mlx, .onnx],
        .qwen: [.llamaCpp, .mlx, .mlc],
        .gemma: [.tensorFlowLite, .coreML, .onnx],
        .gpt2: [.swiftTransformers, .coreML, .onnx],
        .bert: [.coreML, .onnx, .tensorFlowLite],
        .t5: [.onnx, .tensorFlowLite],
        .falcon: [.llamaCpp, .mlx],
        .starcoder: [.llamaCpp, .mlx, .coreML],
        .codegen: [.llamaCpp, .mlx],
        .custom: [.coreML, .onnx]
    ]

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Check if a model is compatible with a framework
    public func checkCompatibility(
        model: ModelInfo,
        framework: LLMFramework,
        device: DeviceInfo? = nil
    ) -> CompatibilityResult {
        let deviceInfo = device ?? DeviceInfo.current

        guard let capability = frameworkCapabilities[framework] else {
            return CompatibilityResult(
                isCompatible: false,
                reason: "Framework \(framework.displayName) not supported",
                confidence: .high
            )
        }

        var warnings: [String] = []
        var recommendations: [String] = []

        // Check format support
        if !capability.supportedFormats.contains(model.format) {
            return CompatibilityResult(
                isCompatible: false,
                reason: "Model format \(model.format.rawValue) not supported by \(framework.displayName)",
                recommendations: ["Convert model to one of: \(capability.supportedFormats.map { $0.rawValue }.joined(separator: ", "))"],
                confidence: .high
            )
        }

        // Check quantization support
        if let quantization = extractQuantization(from: model) {
            if !capability.supportedQuantizations.contains(quantization) {
                return CompatibilityResult(
                    isCompatible: false,
                    reason: "Quantization \(quantization.displayName) not supported by \(framework.displayName)",
                    recommendations: ["Use one of: \(capability.supportedQuantizations.map { $0.displayName }.joined(separator: ", "))"],
                    confidence: .high
                )
            }
        }

        // Check model size
        let estimatedSize = model.estimatedMemory
        if estimatedSize > capability.maxModelSize {
            return CompatibilityResult(
                isCompatible: false,
                reason: "Model size (\(ByteCountFormatter.string(fromByteCount: estimatedSize, countStyle: .memory))) exceeds framework limit (\(ByteCountFormatter.string(fromByteCount: capability.maxModelSize, countStyle: .memory)))",
                recommendations: ["Use a smaller model variant", "Try quantization to reduce size"],
                confidence: .high
            )
        }

        // Check memory availability
        if estimatedSize > deviceInfo.availableMemory {
            warnings.append("Model may not fit in available memory (\(ByteCountFormatter.string(fromByteCount: deviceInfo.availableMemory, countStyle: .memory)))")
            recommendations.append("Close other apps to free memory")
        }

        // Check OS version
        if let currentOS = Double(ProcessInfo.processInfo.operatingSystemVersionString.components(separatedBy: " ").first ?? ""),
           let minOS = Double(capability.minimumOS),
           currentOS < minOS {
            return CompatibilityResult(
                isCompatible: false,
                reason: "Requires OS version \(capability.minimumOS) or later",
                confidence: .high
            )
        }

        // Check architecture
        if !capability.supportedArchitectures.contains(deviceInfo.architecture) {
            return CompatibilityResult(
                isCompatible: false,
                reason: "Architecture \(deviceInfo.architecture) not supported",
                confidence: .high
            )
        }

        // Check architecture support
        if let architecture = extractArchitecture(from: model) {
            if let supportedFrameworks = modelArchitectureSupport[architecture],
               !supportedFrameworks.contains(framework) {
                warnings.append("\(architecture.displayName) models may have limited support on \(framework.displayName)")
            }
        }

        // Hardware-specific checks
        if framework == .coreML && !deviceInfo.hasNeuralEngine {
            warnings.append("No Neural Engine detected - performance may be limited")
        }

        // Context length warnings
        if model.contextLength > 4096 {
            warnings.append("Large context length (\(model.contextLength)) may impact performance")
        }

        let confidence = determineConfidence(
            framework: framework,
            model: model,
            warnings: warnings
        )

        return CompatibilityResult(
            isCompatible: true,
            warnings: warnings,
            recommendations: recommendations,
            confidence: confidence
        )
    }

    /// Get recommended frameworks for a model
    public func getRecommendedFrameworks(
        for model: ModelInfo,
        device: DeviceInfo? = nil
    ) -> [FrameworkRecommendation] {
        let deviceInfo = device ?? DeviceInfo.current
        var recommendations: [FrameworkRecommendation] = []

        for framework in LLMFramework.allCases {
            let compatibility = checkCompatibility(
                model: model,
                framework: framework,
                device: deviceInfo
            )

            if compatibility.isCompatible {
                let score = calculateFrameworkScore(
                    framework: framework,
                    model: model,
                    device: deviceInfo,
                    compatibility: compatibility
                )

                recommendations.append(
                    FrameworkRecommendation(
                        framework: framework,
                        score: score,
                        reason: determineRecommendationReason(
                            framework: framework,
                            score: score,
                            model: model
                        ),
                        warnings: compatibility.warnings
                    )
                )
            }
        }

        return recommendations.sorted { $0.score > $1.score }
    }

    /// Check if device meets requirements for a model/framework combination
    public func checkDeviceRequirements(
        model: ModelInfo,
        framework: LLMFramework,
        device: DeviceInfo? = nil
    ) -> DeviceRequirementResult {
        let deviceInfo = device ?? DeviceInfo.current
        var requirements: [DeviceRequirement] = []
        var satisfied: [DeviceRequirement] = []
        var unsatisfied: [DeviceRequirement] = []

        // Memory requirement
        let memoryReq = DeviceRequirement(
            type: .memory,
            minimumValue: Double(model.estimatedMemory),
            currentValue: Double(deviceInfo.totalMemory),
            isSatisfied: deviceInfo.totalMemory >= model.estimatedMemory
        )
        requirements.append(memoryReq)

        if memoryReq.isSatisfied {
            satisfied.append(memoryReq)
        } else {
            unsatisfied.append(memoryReq)
        }

        // Neural Engine requirement
        if framework == .coreML && model.estimatedMemory > 1_000_000_000 {
            let neuralReq = DeviceRequirement(
                type: .neuralEngine,
                minimumValue: 1,
                currentValue: deviceInfo.hasNeuralEngine ? 1 : 0,
                isSatisfied: deviceInfo.hasNeuralEngine
            )
            requirements.append(neuralReq)

            if neuralReq.isSatisfied {
                satisfied.append(neuralReq)
            } else {
                unsatisfied.append(neuralReq)
            }
        }

        // OS version requirement
        if let capability = frameworkCapabilities[framework] {
            let currentOSVersion = ProcessInfo.processInfo.operatingSystemVersion
            let osVersionString = "\(currentOSVersion.majorVersion).\(currentOSVersion.minorVersion)"
            let osReq = DeviceRequirement(
                type: .osVersion,
                minimumValue: Double(capability.minimumOS) ?? 0,
                currentValue: Double(osVersionString) ?? 0,
                isSatisfied: osVersionString >= capability.minimumOS
            )
            requirements.append(osReq)

            if osReq.isSatisfied {
                satisfied.append(osReq)
            } else {
                unsatisfied.append(osReq)
            }
        }

        return DeviceRequirementResult(
            allRequirements: requirements,
            satisfiedRequirements: satisfied,
            unsatisfiedRequirements: unsatisfied,
            meetsAllRequirements: unsatisfied.isEmpty
        )
    }

    // MARK: - Private Methods

    private func extractQuantization(from model: ModelInfo) -> QuantizationType? {
        // Check metadata first
        if let quantLevel = model.metadata?.quantizationLevel {
            return QuantizationType(rawValue: quantLevel.rawValue) ?? QuantizationType.none
        }

        // Try to extract from model name
        let name = model.name.lowercased()
        for quant in QuantizationType.allCases {
            if name.contains(quant.rawValue.lowercased()) {
                return quant
            }
        }

        return nil
    }

    private func extractArchitecture(from model: ModelInfo) -> ModelArchitecture? {
        let name = model.name.lowercased()

        for arch in ModelArchitecture.allCases {
            if name.contains(arch.rawValue.lowercased()) {
                return arch
            }
        }

        // Check base model in metadata
        if let baseModel = model.metadata?.baseModel?.lowercased() {
            for arch in ModelArchitecture.allCases {
                if baseModel.contains(arch.rawValue.lowercased()) {
                    return arch
                }
            }
        }

        return nil
    }

    private func determineConfidence(
        framework: LLMFramework,
        model: ModelInfo,
        warnings: [String]
    ) -> CompatibilityConfidence {
        // High confidence for well-known combinations
        if let arch = extractArchitecture(from: model),
           let supported = modelArchitectureSupport[arch],
           supported.contains(framework) && warnings.isEmpty {
            return .high
        }

        // Medium confidence if there are warnings
        if !warnings.isEmpty {
            return .medium
        }

        // Low confidence for custom models
        if extractArchitecture(from: model) == .custom {
            return .low
        }

        return .medium
    }

    private func calculateFrameworkScore(
        framework: LLMFramework,
        model: ModelInfo,
        device: DeviceInfo,
        compatibility: CompatibilityResult
    ) -> Double {
        var score = 100.0

        // Deduct points for warnings
        score -= Double(compatibility.warnings.count) * 10

        // Bonus for Neural Engine support
        if framework == .coreML && device.hasNeuralEngine {
            score += 20
        }

        // Bonus for native formats
        if (framework == .coreML && (model.format == .mlmodel || model.format == .mlpackage)) ||
           (framework == .llamaCpp && model.format == .gguf) {
            score += 15
        }

        // Penalty for high memory usage
        let memoryRatio = Double(model.estimatedMemory) / Double(device.totalMemory)
        if memoryRatio > 0.5 {
            score -= 20
        }

        // Confidence multiplier
        switch compatibility.confidence {
        case .high:
            score *= 1.0
        case .medium:
            score *= 0.8
        case .low:
            score *= 0.6
        case .unknown:
            score *= 0.4
        }

        return max(0, min(100, score))
    }

    private func determineRecommendationReason(
        framework: LLMFramework,
        score: Double,
        model: ModelInfo
    ) -> String {
        if score >= 90 {
            return "Excellent compatibility and performance"
        } else if score >= 70 {
            return "Good compatibility with minor limitations"
        } else if score >= 50 {
            return "Acceptable but consider alternatives"
        } else {
            return "Limited compatibility"
        }
    }
}

// MARK: - Supporting Types

/// Framework recommendation
public struct FrameworkRecommendation {
    public let framework: LLMFramework
    public let score: Double // 0-100
    public let reason: String
    public let warnings: [String]
}

/// Device requirement
public struct DeviceRequirement {
    public let type: RequirementType
    public let minimumValue: Double
    public let currentValue: Double
    public let isSatisfied: Bool

    public enum RequirementType {
        case memory
        case storage
        case osVersion
        case neuralEngine
        case gpu
    }
}

/// Device requirement result
public struct DeviceRequirementResult {
    public let allRequirements: [DeviceRequirement]
    public let satisfiedRequirements: [DeviceRequirement]
    public let unsatisfiedRequirements: [DeviceRequirement]
    public let meetsAllRequirements: Bool
}
