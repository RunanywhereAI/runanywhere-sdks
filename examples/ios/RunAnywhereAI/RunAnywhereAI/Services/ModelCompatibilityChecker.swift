import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Model Compatibility Checker

struct ModelCompatibilityChecker {
    // MARK: - Compatibility Result

    struct CompatibilityResult {
        let isCompatible: Bool
        let warnings: [String]
        let errors: [String]
        let recommendations: [String]

        var hasIssues: Bool {
            !warnings.isEmpty || !errors.isEmpty
        }
    }

    // MARK: - Check Compatibility

    @MainActor
    static func checkCompatibility(model: ModelInfo, framework: LLMFramework) -> CompatibilityResult {
        var warnings: [String] = []
        var errors: [String] = []
        var recommendations: [String] = []

        // Check format compatibility
        let formatCheck = checkFormatCompatibility(model.format, framework: framework)
        if !formatCheck.isCompatible {
            errors.append(formatCheck.message)
        }

        // Check memory requirements
        let memoryCheck = checkMemoryRequirements(model: model)
        if !memoryCheck.isCompatible {
            errors.append(memoryCheck.message)
        } else if memoryCheck.hasWarning {
            warnings.append(memoryCheck.message)
        }

        // Check quantization compatibility
        if let quantization = model.quantization {
            let quantCheck = checkQuantizationSupport(quantization, framework: framework)
            if !quantCheck.isCompatible {
                warnings.append(quantCheck.message)
            }
        }

        // Check context length
        if let contextLength = model.contextLength {
            let contextCheck = checkContextLength(contextLength, framework: framework)
            if contextCheck.hasWarning {
                warnings.append(contextCheck.message)
            }
        }

        // Add framework-specific checks
        let frameworkChecks = performFrameworkSpecificChecks(model: model, framework: framework)
        warnings.append(contentsOf: frameworkChecks.warnings)
        errors.append(contentsOf: frameworkChecks.errors)
        recommendations.append(contentsOf: frameworkChecks.recommendations)

        // Generate recommendations
        recommendations.append(contentsOf: generateRecommendations(model: model, framework: framework))

        let isCompatible = errors.isEmpty

        return CompatibilityResult(
            isCompatible: isCompatible,
            warnings: warnings,
            errors: errors,
            recommendations: recommendations
        )
    }

    // MARK: - Format Compatibility

    private static func checkFormatCompatibility(_ format: ModelFormat, framework: LLMFramework) -> (isCompatible: Bool, message: String) {
        let compatibleFormats: [LLMFramework: [ModelFormat]] = [
            .llamaCpp: [.gguf],
            .coreML: [.coreML],
            .mlx: [.mlx],
            .mlc: [.mlc],
            .onnxRuntime: [.onnxRuntime],
            .execuTorch: [.pte],
            .tensorFlowLite: [.tflite],
            .picoLLM: [.gguf, .onnxRuntime],
            .swiftTransformers: [.coreML, .onnxRuntime]
        ]

        guard let supportedFormats = compatibleFormats[framework] else {
            return (false, "Unknown framework: \(framework.rawValue)")
        }

        if supportedFormats.contains(format) {
            return (true, "")
        } else {
            let supportedList = supportedFormats.map { $0.displayName }.joined(separator: ", ")
            return (false, "\(framework.displayName) requires \(supportedList) format, but model is \(format.displayName)")
        }
    }

    // MARK: - Memory Requirements

    @MainActor
    private static func checkMemoryRequirements(model: ModelInfo) -> (isCompatible: Bool, hasWarning: Bool, message: String) {
        let availableMemory = ProcessInfo.processInfo.physicalMemory
        let usedMemory = MemoryManager.shared.getMemoryStats().used
        let freeMemory = Int64(availableMemory) - usedMemory

        // Parse model size to bytes
        let modelSizeBytes = parseSizeToBytes(model.size)

        // Models typically need 2-3x their size in memory during loading
        let requiredMemory = modelSizeBytes * 3

        if freeMemory < modelSizeBytes {
            return (false, false, "Insufficient memory: need \(ByteCountFormatter.string(fromByteCount: modelSizeBytes, countStyle: .memory)) but only \(ByteCountFormatter.string(fromByteCount: freeMemory, countStyle: .memory)) available")
        } else if freeMemory < requiredMemory {
            return (true, true, "Low memory warning: Model may load slowly or fail during peak usage")
        }

        return (true, false, "")
    }

    // MARK: - Quantization Support

    private static func checkQuantizationSupport(_ quantization: String, framework: LLMFramework) -> (isCompatible: Bool, message: String) {
        let supportedQuantizations: [LLMFramework: [String]] = [
            .llamaCpp: ["Q4_0", "Q4_1", "Q4_K_S", "Q4_K_M", "Q5_0", "Q5_1", "Q5_K_S", "Q5_K_M", "Q8_0", "F16", "F32"],
            .coreML: ["FP16", "FP32", "INT8", "INT4"],
            .mlx: ["INT4", "INT8", "FP16"],
            .onnxRuntime: ["INT8", "UINT8", "FP16", "FP32"],
            .tensorFlowLite: ["INT8", "FP16", "FP32"],
            .picoLLM: ["INT4", "INT8"],
            .execuTorch: ["INT8", "FP16"],
            .mlc: ["Q4", "Q8", "FP16"],
            .swiftTransformers: ["FP16", "FP32"]
        ]

        guard let supported = supportedQuantizations[framework] else {
            return (true, "") // Unknown framework, assume compatible
        }

        if supported.isEmpty || supported.contains(where: { quantization.contains($0) }) {
            return (true, "")
        }

        return (false, "\(framework.displayName) may not fully support \(quantization) quantization")
    }

    // MARK: - Context Length

    private static func checkContextLength(_ contextLength: Int, framework: LLMFramework) -> (hasWarning: Bool, message: String) {
        let maxContextLengths: [LLMFramework: Int] = [
            .llamaCpp: 8192,
            .coreML: 2048,
            .mlx: 4096,
            .onnxRuntime: 2048,
            .tensorFlowLite: 1024,
            .picoLLM: 512,
            .execuTorch: 2048,
            .mlc: 4096,
            .swiftTransformers: 2048
        ]

        guard let maxLength = maxContextLengths[framework] else {
            return (false, "")
        }

        if contextLength > maxLength {
            return (true, "Model context length (\(contextLength)) exceeds \(framework.displayName)'s typical limit (\(maxLength))")
        }

        return (false, "")
    }

    // MARK: - Framework-Specific Checks

    private static func performFrameworkSpecificChecks(model: ModelInfo, framework: LLMFramework) -> (warnings: [String], errors: [String], recommendations: [String]) {
        var warnings: [String] = []
        var errors: [String] = []
        var recommendations: [String] = []

        switch framework {
        case .coreML:
            // Core ML specific checks
            if model.format == .coreML {
                recommendations.append("Ensure Core ML model is optimized for your target devices")
            }
            let size = parseSizeToBytes(model.size)
            if size > 1_000_000_000 { // > 1GB
                warnings.append("Large Core ML models may have slower initial load times")
            }

        case .llamaCpp:
            // llama.cpp specific checks
            if model.format != .gguf {
                errors.append("llama.cpp requires GGUF format models")
            }
            recommendations.append("Consider using Q4_K_M or Q5_K_M quantization for best performance/quality balance")

        case .mlx:
            // MLX specific checks
            if ProcessInfo.processInfo.processorCount < 8 {
                warnings.append("MLX performs best on Apple Silicon with 8+ cores")
            }
            recommendations.append("MLX works best with INT4 or INT8 quantization on Apple Silicon")

        case .onnxRuntime:
            // ONNX Runtime checks
            recommendations.append("Enable CoreML execution provider for best performance on iOS")

        case .tensorFlowLite:
            // TensorFlow Lite checks
            let size = parseSizeToBytes(model.size)
            if size > 500_000_000 { // > 500MB
                warnings.append("Large TFLite models may have memory issues on older devices")
            }

        case .picoLLM:
            // picoLLM checks
            if let contextLength = model.contextLength, contextLength > 512 {
                warnings.append("picoLLM is optimized for shorter contexts")
            }
            recommendations.append("picoLLM works best with highly compressed models")

        default:
            break
        }

        return (warnings, errors, recommendations)
    }

    // MARK: - Recommendations

    private static func generateRecommendations(model: ModelInfo, framework: LLMFramework) -> [String] {
        var recommendations: [String] = []

        // Memory-based recommendations
        let modelSizeBytes = parseSizeToBytes(model.size)
        let availableMemory = ProcessInfo.processInfo.physicalMemory

        if modelSizeBytes > availableMemory / 4 {
            recommendations.append("Consider using a smaller or more quantized model for better performance")
        }

        // Device-specific recommendations
        #if canImport(UIKit)
        let deviceModel = UIDevice.current.model
        if deviceModel.contains("iPad") {
            recommendations.append("iPad's larger memory allows for bigger models and longer contexts")
        } else if deviceModel.contains("iPhone") {
            if ProcessInfo.processInfo.processorCount >= 6 {
                recommendations.append("Your device supports efficient on-device inference")
            } else {
                recommendations.append("Consider using smaller models for optimal performance")
            }
        }
        #else
        if ProcessInfo.processInfo.processorCount >= 6 {
            recommendations.append("Your device supports efficient on-device inference")
        } else {
            recommendations.append("Consider using smaller models for optimal performance")
        }
        #endif

        // Framework optimization tips
        if framework == .coreML || framework == .mlx {
            recommendations.append("These frameworks are optimized for Apple Silicon")
        }

        return recommendations
    }

    // MARK: - Utility Functions

    private static func parseSizeToBytes(_ sizeString: String) -> Int64 {
        let components = sizeString.components(separatedBy: " ")
        guard components.count >= 2,
              let value = Double(components[0]) else {
            return 0
        }

        let unit = components[1].uppercased()
        let multiplier: Double

        switch unit {
        case "B", "BYTES":
            multiplier = 1
        case "KB":
            multiplier = 1_000
        case "MB":
            multiplier = 1_000_000
        case "GB":
            multiplier = 1_000_000_000
        case "TB":
            multiplier = 1_000_000_000_000
        default:
            multiplier = 1
        }

        return Int64(value * multiplier)
    }
}
