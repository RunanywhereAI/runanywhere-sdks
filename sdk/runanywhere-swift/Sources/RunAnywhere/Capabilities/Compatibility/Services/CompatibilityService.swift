import Foundation

/// Main compatibility service for checking model-framework compatibility
public class CompatibilityService {
    private let logger = SDKLogger(category: "Compatibility")

    public init() {}

    func checkCompatibility(model: ModelInfo, framework: LLMFramework) -> CompatibilityResult {
        var warnings: [String] = []
        var recommendations: [String] = []

        // Check format compatibility
        if !isFormatSupported(model.format, framework: framework) {
            return CompatibilityResult(
                isCompatible: false,
                reason: "Format \(model.format.rawValue) is not supported by \(framework.rawValue)",
                confidence: .high
            )
        }

        // Check size limits
        if let capability = FrameworkCapabilities.getCapability(for: framework) {
            if model.estimatedMemory > capability.maxModelSize {
                return CompatibilityResult(
                    isCompatible: false,
                    reason: "Model size (\(model.estimatedMemory)) exceeds maximum (\(capability.maxModelSize))",
                    confidence: .high
                )
            }
        }

        // Check quantization compatibility (warning only)
        if let quantization = model.metadata?.quantizationLevel {
            if !isQuantizationSupported(quantization, framework: framework) {
                warnings.append("Quantization \(quantization.rawValue) may not be supported by \(framework.rawValue)")
                recommendations.append("Consider using a different quantization method")
            }
        }

        return CompatibilityResult(
            isCompatible: true,
            warnings: warnings,
            recommendations: recommendations,
            confidence: warnings.isEmpty ? .high : .medium
        )
    }

    func checkCompatibility(models: [ModelInfo], framework: LLMFramework) -> [CompatibilityResult] {
        return models.map { checkCompatibility(model: $0, framework: framework) }
    }

    func getCompatibleFrameworks(for model: ModelInfo) -> [LLMFramework] {
        let allFrameworks = LLMFramework.allCases

        return allFrameworks.filter { framework in
            let result = checkCompatibility(model: model, framework: framework)
            return result.isCompatible
        }
    }

    func detectCompatibleFrameworks(format: ModelFormat, metadata: ModelMetadata) -> [LLMFramework] {
        return FrameworkCapabilities.getSupportedFrameworks(for: format)
    }

    // MARK: - Health Check

    /// Check if the compatibility service is healthy and operational
    public func isHealthy() -> Bool {
        // Basic health check - ensure essential components are available
        return true // Simple implementation for now
    }

    func detectHardwareRequirements(format: ModelFormat, metadata: ModelMetadata) -> [HardwareRequirement] {
        var requirements: [HardwareRequirement] = []

        // Memory requirements
        if let minMemory = metadata.requirements?.minMemory {
            requirements.append(.minimumMemory(minMemory))
        }

        // Accelerator requirements based on format
        switch format {
        case .mlmodel, .mlpackage:
            requirements.append(.requiresNeuralEngine)
        case .tflite:
            requirements.append(.requiresGPU)
        case .safetensors:
            requirements.append(.specificChip("A17"))
        default:
            break
        }

        return requirements
    }

    private func isFormatSupported(_ format: ModelFormat, framework: LLMFramework) -> Bool {
        guard let capability = FrameworkCapabilities.getCapability(for: framework) else {
            return false
        }
        return capability.supportedFormats.contains(format)
    }

    private func isQuantizationSupported(_ quantization: QuantizationLevel, framework: LLMFramework) -> Bool {
        return QuantizationSupport.isSupported(quantization: quantization, framework: framework)
    }
}
