import Foundation

/// Main compatibility service for checking model-framework compatibility
class CompatibilityService {
    private let logger = SDKLogger(category: "Compatibility")

    func checkCompatibility(model: ModelInfo, framework: LLMFramework) -> CompatibilityResult {
        var issues: [CompatibilityIssue] = []
        var score: Double = 1.0

        // Check format compatibility
        if !isFormatSupported(model.format, framework: framework) {
            issues.append(.formatNotSupported(model.format, framework))
            return CompatibilityResult(compatible: false, score: 0.0, issues: issues)
        }

        // Check quantization compatibility
        if let quantization = model.metadata?.quantizationLevel {
            if !isQuantizationSupported(quantization, framework: framework) {
                issues.append(.quantizationNotSupported(quantization, framework))
                score *= 0.7
            }
        }

        // Check size limits
        if let capability = FrameworkCapabilities.getCapability(for: framework) {
            if model.estimatedMemory > capability.maxModelSize {
                issues.append(.modelTooLarge(model.estimatedMemory, capability.maxModelSize))
                score *= 0.5
            }
        }

        // Check architecture compatibility
        if let architecture = model.metadata?.description {
            let archCompatibility = ArchitectureSupport.getCompatibility(architecture: architecture, framework: framework)
            switch archCompatibility {
            case .notSupported:
                issues.append(.architectureNotSupported(architecture, framework))
                score *= 0.3
            case .partiallySupported:
                issues.append(.architecturePartiallySupported(architecture, framework))
                score *= 0.8
            case .supported:
                break
            }
        }

        let compatible = score > 0.5 && !issues.contains { $0.severity == .error }

        return CompatibilityResult(
            compatible: compatible,
            score: score,
            issues: issues
        )
    }

    func checkCompatibility(models: [ModelInfo], framework: LLMFramework) -> [CompatibilityResult] {
        return models.map { checkCompatibility(model: $0, framework: framework) }
    }

    func getCompatibleFrameworks(for model: ModelInfo) -> [LLMFramework] {
        let allFrameworks = LLMFramework.allCases

        return allFrameworks.filter { framework in
            let result = checkCompatibility(model: model, framework: framework)
            return result.compatible
        }
    }

    func detectCompatibleFrameworks(format: ModelFormat, metadata: ModelMetadata) -> [LLMFramework] {
        return FrameworkCapabilities.getSupportedFrameworks(for: format)
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

/// Result of compatibility check with scoring
struct CompatibilityCheckResult {
    let compatible: Bool
    let score: Double // 0.0 to 1.0
    let issues: [CompatibilityIssue]

    var hasErrors: Bool {
        return issues.contains { $0.severity == .error }
    }

    var hasWarnings: Bool {
        return issues.contains { $0.severity == .warning }
    }
}

/// Compatibility issue
enum CompatibilityIssue {
    case formatNotSupported(ModelFormat, LLMFramework)
    case quantizationNotSupported(QuantizationLevel, LLMFramework)
    case modelTooLarge(Int64, Int64)
    case architectureNotSupported(String, LLMFramework)
    case architecturePartiallySupported(String, LLMFramework)
    case osVersionTooOld(String, String)
    case hardwareNotSupported(String)

    var severity: IssueSeverity {
        switch self {
        case .formatNotSupported, .osVersionTooOld, .hardwareNotSupported:
            return .error
        case .quantizationNotSupported, .modelTooLarge, .architectureNotSupported:
            return .error
        case .architecturePartiallySupported:
            return .warning
        }
    }

    var description: String {
        switch self {
        case .formatNotSupported(let format, let framework):
            return "Format \(format.rawValue) is not supported by \(framework.rawValue)"
        case .quantizationNotSupported(let quant, let framework):
            return "Quantization \(quant.rawValue) is not supported by \(framework.rawValue)"
        case .modelTooLarge(let size, let maxSize):
            return "Model size (\(size)) exceeds maximum (\(maxSize))"
        case .architectureNotSupported(let arch, let framework):
            return "Architecture \(arch) is not supported by \(framework.rawValue)"
        case .architecturePartiallySupported(let arch, let framework):
            return "Architecture \(arch) is only partially supported by \(framework.rawValue)"
        case .osVersionTooOld(let current, let required):
            return "OS version \(current) is older than required \(required)"
        case .hardwareNotSupported(let hardware):
            return "Hardware \(hardware) is not supported"
        }
    }

    // MARK: - Health Check

    /// Check if the compatibility service is healthy and operational
    public func isHealthy() -> Bool {
        // Basic health check - ensure essential components are available
        return true // Simple implementation for now
    }
}

enum IssueSeverity {
    case error
    case warning
    case info
}
