//
//  RequirementMatcher.swift
//  RunAnywhere SDK
//
//  Matches model requirements with device capabilities
//

import Foundation

/// Matches model requirements against device capabilities
public class RequirementMatcher {

    // MARK: - Properties

    private let logger = SDKLogger(category: "RequirementMatcher")

    // MARK: - Public Methods

    /// Check if device meets model requirements
    public func checkCompatibility(
        model: ModelInfo,
        capabilities: DeviceCapabilities
    ) -> CompatibilityResult {

        logger.debug("Checking compatibility for model: \(model.name)")

        var isCompatible = true
        var warnings: [String] = []
        var recommendations: [String] = []
        var reason: String?

        // Check memory requirements
        let memoryCheck = checkMemoryRequirements(model: model, capabilities: capabilities)
        if !memoryCheck.passes {
            isCompatible = false
            reason = memoryCheck.reason
        } else if !memoryCheck.warnings.isEmpty {
            warnings.append(contentsOf: memoryCheck.warnings)
        }

        // Check accelerator compatibility
        let acceleratorCheck = checkAcceleratorCompatibility(model: model, capabilities: capabilities)
        if !acceleratorCheck.warnings.isEmpty {
            warnings.append(contentsOf: acceleratorCheck.warnings)
        }

        // Check format compatibility
        let formatCheck = checkFormatCompatibility(model: model, capabilities: capabilities)
        if !formatCheck.passes {
            warnings.append(formatCheck.reason ?? "Format compatibility issue")
        }

        // Generate recommendations
        recommendations.append(contentsOf: generateRecommendations(
            model: model,
            capabilities: capabilities,
            memoryCheck: memoryCheck,
            acceleratorCheck: acceleratorCheck
        ))

        let confidence = calculateConfidence(
            isCompatible: isCompatible,
            warningCount: warnings.count
        )

        return CompatibilityResult(
            isCompatible: isCompatible,
            reason: reason,
            warnings: warnings,
            recommendations: recommendations,
            confidence: confidence
        )
    }

    /// Get resource requirements for a model
    public func getResourceRequirements(for model: ModelInfo) -> ModelResourceRequirements {
        return ModelResourceRequirements(
            minimumMemory: model.estimatedMemory,
            recommendedMemory: model.estimatedMemory * 2,
            minimumStorage: estimateStorageRequirement(for: model),
            recommendedAccelerators: getRecommendedAccelerators(for: model),
            supportedFormats: getSupportedFormats(for: model)
        )
    }

    /// Check if specific accelerator is suitable for model
    public func isAcceleratorSuitable(
        _ accelerator: HardwareAcceleration,
        for model: ModelInfo,
        capabilities: DeviceCapabilities
    ) -> Bool {

        switch accelerator {
        case .neuralEngine:
            return capabilities.hasNeuralEngine &&
                   (model.format == .mlmodel || model.format == .mlpackage)

        case .gpu, .metal:
            return capabilities.hasGPU && model.estimatedMemory <= capabilities.availableMemory

        case .coreML:
            return capabilities.hasNeuralEngine || capabilities.hasGPU

        case .cpu:
            return true // CPU is always available

        case .auto:
            return true // Auto selection is always possible
        }
    }

    // MARK: - Private Methods

    private func checkMemoryRequirements(
        model: ModelInfo,
        capabilities: DeviceCapabilities
    ) -> RequirementCheck {

        let required = model.estimatedMemory
        let available = capabilities.availableMemory

        if available < required {
            return RequirementCheck(
                passes: false,
                reason: "Insufficient memory: need \(formatBytes(required)), have \(formatBytes(available))",
                warnings: []
            )
        }

        var warnings: [String] = []

        // Warn if memory is tight
        if available < required * 2 {
            warnings.append("Memory may be tight - consider using a smaller model")
        }

        // Warn based on memory pressure
        switch capabilities.memoryPressureLevel {
        case .high, .critical:
            warnings.append("High memory pressure detected - performance may be affected")
        case .medium:
            warnings.append("Moderate memory pressure - monitor performance")
        case .low:
            break
        }

        return RequirementCheck(passes: true, warnings: warnings)
    }

    private func checkAcceleratorCompatibility(
        model: ModelInfo,
        capabilities: DeviceCapabilities
    ) -> RequirementCheck {

        var warnings: [String] = []

        // Check if preferred framework is supported
        if let preferred = model.preferredFramework {
            switch preferred {
            case .coreML:
                if !capabilities.hasNeuralEngine && !capabilities.hasGPU {
                    warnings.append("CoreML may run slowly without Neural Engine or GPU")
                }
            case .tensorFlowLite:
                if !capabilities.hasGPU {
                    warnings.append("TensorFlow Lite may run slowly without GPU acceleration")
                }
            case .mlx:
                if !capabilities.hasGPU {
                    warnings.append("MLX requires GPU acceleration for optimal performance")
                }
            default:
                break
            }
        }

        return RequirementCheck(passes: true, warnings: warnings)
    }

    private func checkFormatCompatibility(
        model: ModelInfo,
        capabilities: DeviceCapabilities
    ) -> RequirementCheck {

        // All formats are technically supported, but some perform better
        switch model.format {
        case .mlmodel, .mlpackage:
            if !capabilities.hasNeuralEngine {
                return RequirementCheck(
                    passes: true,
                    reason: "CoreML models perform best with Neural Engine"
                )
            }

        case .tflite:
            if !capabilities.hasGPU {
                return RequirementCheck(
                    passes: true,
                    reason: "TensorFlow Lite models perform best with GPU"
                )
            }

        default:
            break
        }

        return RequirementCheck(passes: true)
    }

    private func generateRecommendations(
        model: ModelInfo,
        capabilities: DeviceCapabilities,
        memoryCheck: RequirementCheck,
        acceleratorCheck: RequirementCheck
    ) -> [String] {

        var recommendations: [String] = []

        // Memory recommendations
        if !memoryCheck.passes {
            recommendations.append("Consider using a quantized version of the model")
            recommendations.append("Close other applications to free memory")

            if capabilities.totalMemory < 4_000_000_000 {
                recommendations.append("Consider upgrading to a device with more memory")
            }
        }

        // Accelerator recommendations
        if capabilities.hasNeuralEngine && model.format != .mlmodel && model.format != .mlpackage {
            recommendations.append("Convert model to Core ML format for Neural Engine acceleration")
        }

        if capabilities.hasGPU && model.estimatedMemory > 1_000_000_000 {
            recommendations.append("Use GPU acceleration for better performance")
        }

        // Format recommendations
        if model.format == .gguf && capabilities.hasNeuralEngine {
            recommendations.append("Consider using Core ML format instead of GGUF for better performance")
        }

        return recommendations
    }

    private func calculateConfidence(isCompatible: Bool, warningCount: Int) -> CompatibilityConfidence {
        if !isCompatible {
            return .low
        }

        switch warningCount {
        case 0:
            return .high
        case 1...2:
            return .medium
        default:
            return .low
        }
    }

    private func estimateStorageRequirement(for model: ModelInfo) -> Int64 {
        // Estimate 2x model size for temporary files during loading
        let modelSize = model.downloadSize ?? model.estimatedMemory
        return modelSize * 2
    }

    private func getRecommendedAccelerators(for model: ModelInfo) -> [HardwareAcceleration] {
        var accelerators: [HardwareAcceleration] = []

        switch model.format {
        case .mlmodel, .mlpackage:
            accelerators.append(.neuralEngine)
            accelerators.append(.coreML)
        case .tflite:
            accelerators.append(.gpu)
        case .gguf:
            accelerators.append(.cpu)
        default:
            accelerators.append(.auto)
        }

        return accelerators
    }

    private func getSupportedFormats(for model: ModelInfo) -> [ModelFormat] {
        // In practice, this would be based on available frameworks
        return [.mlmodel, .mlpackage, .tflite, .gguf, .onnx]
    }

    private func formatBytes(_ bytes: Int64) -> String {
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }
}

// MARK: - Supporting Types

private struct RequirementCheck {
    let passes: Bool
    let reason: String?
    let warnings: [String]

    init(passes: Bool, reason: String? = nil, warnings: [String] = []) {
        self.passes = passes
        self.reason = reason
        self.warnings = warnings
    }
}

/// Model resource requirements
public struct ModelResourceRequirements {
    public let minimumMemory: Int64
    public let recommendedMemory: Int64
    public let minimumStorage: Int64
    public let recommendedAccelerators: [HardwareAcceleration]
    public let supportedFormats: [ModelFormat]
}
