import Foundation

/// Quantization support data
struct QuantizationSupport {

    /// Framework to quantization level support mapping
    static let quantizationMatrix: [LLMFramework: Set<QuantizationLevel>] = [
        .foundationModels: [.q4_0],
        .coreML: [.f16, .q8_0, .q4_0],
        .mlx: [.q4_0, .q4_K_M, .q8_0],
        .mlc: [.q3_K_M, .q4_K_M],
        .onnx: [.f32, .f16, .q8_0],
        .execuTorch: [.q4_0, .q8_0],
        .llamaCpp: [
            .q2_K, .q3_K_S, .q3_K_M, .q3_K_L,
            .q4_0, .q4_K_S, .q4_K_M,
            .q5_0, .q5_K_S, .q5_K_M,
            .q6_K, .q8_0
        ],
        .tensorFlowLite: [.f32, .f16, .q8_0],
        .picoLLM: [.q4_0, .q8_0],
        .swiftTransformers: [.f16, .q8_0]
    ]

    /// Quality to performance ratio for different quantization levels
    static let quantizationQuality: [QuantizationLevel: QuantizationInfo] = [
        .f32: QuantizationInfo(quality: 1.0, speedup: 1.0, memoryReduction: 1.0),
        .f16: QuantizationInfo(quality: 0.99, speedup: 1.5, memoryReduction: 0.5),
        .q8_0: QuantizationInfo(quality: 0.95, speedup: 2.0, memoryReduction: 0.25),
        .q6_K: QuantizationInfo(quality: 0.92, speedup: 2.5, memoryReduction: 0.19),
        .q5_K_M: QuantizationInfo(quality: 0.88, speedup: 3.0, memoryReduction: 0.16),
        .q4_K_M: QuantizationInfo(quality: 0.85, speedup: 3.5, memoryReduction: 0.125),
        .q4_0: QuantizationInfo(quality: 0.80, speedup: 4.0, memoryReduction: 0.125),
        .q3_K_M: QuantizationInfo(quality: 0.75, speedup: 4.5, memoryReduction: 0.094),
        .q2_K: QuantizationInfo(quality: 0.65, speedup: 5.0, memoryReduction: 0.063)
    ]

    static func isSupported(quantization: QuantizationLevel, framework: LLMFramework) -> Bool {
        return quantizationMatrix[framework]?.contains(quantization) ?? false
    }

    static func getSupportedQuantizations(for framework: LLMFramework) -> Set<QuantizationLevel> {
        return quantizationMatrix[framework] ?? []
    }

    static func getSupportingFrameworks(for quantization: QuantizationLevel) -> [LLMFramework] {
        return quantizationMatrix.compactMap { (framework, levels) in
            levels.contains(quantization) ? framework : nil
        }
    }

    static func getQuantizationInfo(for level: QuantizationLevel) -> QuantizationInfo? {
        return quantizationQuality[level]
    }

    static func recommendQuantization(for framework: LLMFramework, prioritizing: QuantizationPriority) -> QuantizationLevel? {
        let supportedLevels = getSupportedQuantizations(for: framework)

        switch prioritizing {
        case .quality:
            return supportedLevels.max { level1, level2 in
                let info1 = quantizationQuality[level1] ?? QuantizationInfo.default
                let info2 = quantizationQuality[level2] ?? QuantizationInfo.default
                return info1.quality < info2.quality
            }
        case .speed:
            return supportedLevels.max { level1, level2 in
                let info1 = quantizationQuality[level1] ?? QuantizationInfo.default
                let info2 = quantizationQuality[level2] ?? QuantizationInfo.default
                return info1.speedup < info2.speedup
            }
        case .memory:
            return supportedLevels.max { level1, level2 in
                let info1 = quantizationQuality[level1] ?? QuantizationInfo.default
                let info2 = quantizationQuality[level2] ?? QuantizationInfo.default
                return info1.memoryReduction > info2.memoryReduction
            }
        case .balanced:
            return supportedLevels.max { level1, level2 in
                let info1 = quantizationQuality[level1] ?? QuantizationInfo.default
                let info2 = quantizationQuality[level2] ?? QuantizationInfo.default
                let score1 = info1.quality * info1.speedup * (1.0 / info1.memoryReduction)
                let score2 = info2.quality * info2.speedup * (1.0 / info2.memoryReduction)
                return score1 < score2
            }
        }
    }
}

/// Information about a quantization level
struct QuantizationInfo {
    let quality: Double        // 0.0 to 1.0, where 1.0 is best quality
    let speedup: Double        // Relative to f32, where 1.0 is no speedup
    let memoryReduction: Double // Fraction of original memory, where 1.0 is no reduction

    static let `default` = QuantizationInfo(quality: 0.5, speedup: 1.0, memoryReduction: 1.0)
}

/// Priority for quantization selection
enum QuantizationPriority {
    case quality
    case speed
    case memory
    case balanced
}
