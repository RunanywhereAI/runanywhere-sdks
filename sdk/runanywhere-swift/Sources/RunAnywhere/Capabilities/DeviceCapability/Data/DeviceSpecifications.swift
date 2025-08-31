//
//  DeviceSpecifications.swift
//  RunAnywhere SDK
//
//  Detailed hardware specifications for ML workloads
//

import Foundation

/// Processor specification for ML workloads
public struct ProcessorSpec {
    public let name: String
    public let coreCount: Int
    public let performanceCores: Int
    public let efficiencyCores: Int
    public let neuralEngineCores: Int
    public let estimatedTops: Float
    public let maxMemoryBandwidth: Int // GB/s
    public let supportedFrameworks: [LLMFramework]
    public let thermalDesignPower: Float // Watts
    public let estimatedClockSpeed: Double // GHz
}

/// Device specifications database
public enum DeviceSpecifications {

    /// Get processor specification for a given CPU type and variant
    public static func getSpec(for cpu: CPUType, variant: ProcessorVariant = .standard) -> ProcessorSpec {
        switch cpu {
        // MARK: - A-Series Chips
        case .a14Bionic:
            return ProcessorSpec(
                name: "A14 Bionic",
                coreCount: 6,
                performanceCores: 2,
                efficiencyCores: 4,
                neuralEngineCores: 16,
                estimatedTops: 11,
                maxMemoryBandwidth: 60,
                supportedFrameworks: [.coreML, .tensorFlowLite],
                thermalDesignPower: 6,
                estimatedClockSpeed: 3.0
            )

        case .a15Bionic:
            return ProcessorSpec(
                name: "A15 Bionic",
                coreCount: 6,
                performanceCores: 2,
                efficiencyCores: 4,
                neuralEngineCores: 16,
                estimatedTops: 15.8,
                maxMemoryBandwidth: 70,
                supportedFrameworks: [.coreML, .tensorFlowLite],
                thermalDesignPower: 6.5,
                estimatedClockSpeed: 3.23
            )

        case .a16Bionic:
            return ProcessorSpec(
                name: "A16 Bionic",
                coreCount: 6,
                performanceCores: 2,
                efficiencyCores: 4,
                neuralEngineCores: 16,
                estimatedTops: 17,
                maxMemoryBandwidth: 80,
                supportedFrameworks: [.coreML, .tensorFlowLite],
                thermalDesignPower: 7,
                estimatedClockSpeed: 3.46
            )

        case .a17Pro:
            return ProcessorSpec(
                name: "A17 Pro",
                coreCount: 6,
                performanceCores: 2,
                efficiencyCores: 4,
                neuralEngineCores: 16,
                estimatedTops: 35,
                maxMemoryBandwidth: 90,
                supportedFrameworks: [.coreML, .onnx, .tensorFlowLite],
                thermalDesignPower: 8.5,
                estimatedClockSpeed: 3.78
            )

        case .a18:
            return ProcessorSpec(
                name: "A18",
                coreCount: 6,
                performanceCores: 2,
                efficiencyCores: 4,
                neuralEngineCores: 16,
                estimatedTops: 38,
                maxMemoryBandwidth: 100,
                supportedFrameworks: [.coreML, .onnx, .tensorFlowLite],
                thermalDesignPower: 9,
                estimatedClockSpeed: 4.0
            )

        case .a18Pro:
            return ProcessorSpec(
                name: "A18 Pro",
                coreCount: 6,
                performanceCores: 2,
                efficiencyCores: 4,
                neuralEngineCores: 16,
                estimatedTops: 45,
                maxMemoryBandwidth: 110,
                supportedFrameworks: [.coreML, .onnx, .tensorFlowLite],
                thermalDesignPower: 10,
                estimatedClockSpeed: 4.05
            )

        // MARK: - M1 Series
        case .m1:
            switch variant {
            case .standard:
                return ProcessorSpec(
                    name: "M1",
                    coreCount: 8,
                    performanceCores: 4,
                    efficiencyCores: 4,
                    neuralEngineCores: 16,
                    estimatedTops: 11,
                    maxMemoryBandwidth: 68,
                    supportedFrameworks: [.coreML, .onnx, .mlx, .tensorFlowLite],
                    thermalDesignPower: 15,
                    estimatedClockSpeed: 3.2
                )
            case .pro:
                return ProcessorSpec(
                    name: "M1 Pro",
                    coreCount: 10,
                    performanceCores: 8,
                    efficiencyCores: 2,
                    neuralEngineCores: 16,
                    estimatedTops: 11,
                    maxMemoryBandwidth: 200,
                    supportedFrameworks: [.coreML, .onnx, .mlx, .tensorFlowLite],
                    thermalDesignPower: 30,
                    estimatedClockSpeed: 3.2
                )
            case .max:
                return ProcessorSpec(
                    name: "M1 Max",
                    coreCount: 10,
                    performanceCores: 8,
                    efficiencyCores: 2,
                    neuralEngineCores: 16,
                    estimatedTops: 11,
                    maxMemoryBandwidth: 400,
                    supportedFrameworks: [.coreML, .onnx, .mlx, .tensorFlowLite],
                    thermalDesignPower: 40,
                    estimatedClockSpeed: 3.2
                )
            case .ultra:
                return ProcessorSpec(
                    name: "M1 Ultra",
                    coreCount: 20,
                    performanceCores: 16,
                    efficiencyCores: 4,
                    neuralEngineCores: 32,
                    estimatedTops: 22,
                    maxMemoryBandwidth: 800,
                    supportedFrameworks: [.coreML, .onnx, .mlx, .tensorFlowLite],
                    thermalDesignPower: 60,
                    estimatedClockSpeed: 3.2
                )
            }

        // MARK: - M2 Series
        case .m2:
            switch variant {
            case .standard:
                return ProcessorSpec(
                    name: "M2",
                    coreCount: 8,
                    performanceCores: 4,
                    efficiencyCores: 4,
                    neuralEngineCores: 16,
                    estimatedTops: 15.8,
                    maxMemoryBandwidth: 100,
                    supportedFrameworks: [.coreML, .onnx, .mlx, .tensorFlowLite],
                    thermalDesignPower: 15,
                    estimatedClockSpeed: 3.5
                )
            case .pro:
                return ProcessorSpec(
                    name: "M2 Pro",
                    coreCount: 12,
                    performanceCores: 8,
                    efficiencyCores: 4,
                    neuralEngineCores: 16,
                    estimatedTops: 15.8,
                    maxMemoryBandwidth: 200,
                    supportedFrameworks: [.coreML, .onnx, .mlx, .tensorFlowLite],
                    thermalDesignPower: 30,
                    estimatedClockSpeed: 3.5
                )
            case .max:
                return ProcessorSpec(
                    name: "M2 Max",
                    coreCount: 12,
                    performanceCores: 8,
                    efficiencyCores: 4,
                    neuralEngineCores: 16,
                    estimatedTops: 15.8,
                    maxMemoryBandwidth: 400,
                    supportedFrameworks: [.coreML, .onnx, .mlx, .tensorFlowLite],
                    thermalDesignPower: 40,
                    estimatedClockSpeed: 3.5
                )
            case .ultra:
                return ProcessorSpec(
                    name: "M2 Ultra",
                    coreCount: 24,
                    performanceCores: 16,
                    efficiencyCores: 8,
                    neuralEngineCores: 32,
                    estimatedTops: 31.6,
                    maxMemoryBandwidth: 800,
                    supportedFrameworks: [.coreML, .onnx, .mlx, .tensorFlowLite],
                    thermalDesignPower: 60,
                    estimatedClockSpeed: 3.5
                )
            }

        // MARK: - M3 Series
        case .m3:
            switch variant {
            case .standard:
                return ProcessorSpec(
                    name: "M3",
                    coreCount: 8,
                    performanceCores: 4,
                    efficiencyCores: 4,
                    neuralEngineCores: 16,
                    estimatedTops: 18,
                    maxMemoryBandwidth: 100,
                    supportedFrameworks: [.coreML, .onnx, .mlx, .tensorFlowLite],
                    thermalDesignPower: 20,
                    estimatedClockSpeed: 4.0
                )
            case .pro:
                return ProcessorSpec(
                    name: "M3 Pro",
                    coreCount: 12,
                    performanceCores: 6,
                    efficiencyCores: 6,
                    neuralEngineCores: 16,
                    estimatedTops: 18,
                    maxMemoryBandwidth: 150,
                    supportedFrameworks: [.coreML, .onnx, .mlx, .tensorFlowLite],
                    thermalDesignPower: 30,
                    estimatedClockSpeed: 4.0
                )
            case .max:
                return ProcessorSpec(
                    name: "M3 Max",
                    coreCount: 16,
                    performanceCores: 12,
                    efficiencyCores: 4,
                    neuralEngineCores: 16,
                    estimatedTops: 18,
                    maxMemoryBandwidth: 400,
                    supportedFrameworks: [.coreML, .onnx, .mlx, .tensorFlowLite],
                    thermalDesignPower: 40,
                    estimatedClockSpeed: 4.0
                )
            case .ultra:
                // M3 Ultra not released yet, using estimated specs
                return ProcessorSpec(
                    name: "M3 Ultra",
                    coreCount: 32,
                    performanceCores: 24,
                    efficiencyCores: 8,
                    neuralEngineCores: 32,
                    estimatedTops: 36,
                    maxMemoryBandwidth: 800,
                    supportedFrameworks: [.coreML, .onnx, .mlx, .tensorFlowLite],
                    thermalDesignPower: 60,
                    estimatedClockSpeed: 4.0
                )
            }

        // MARK: - M4 Series
        case .m4:
            switch variant {
            case .standard:
                return ProcessorSpec(
                    name: "M4",
                    coreCount: 10,
                    performanceCores: 4,
                    efficiencyCores: 6,
                    neuralEngineCores: 16,
                    estimatedTops: 38,
                    maxMemoryBandwidth: 120,
                    supportedFrameworks: [.coreML, .onnx, .mlx, .tensorFlowLite],
                    thermalDesignPower: 20,
                    estimatedClockSpeed: 4.4
                )
            case .pro:
                return ProcessorSpec(
                    name: "M4 Pro",
                    coreCount: 14,
                    performanceCores: 10,
                    efficiencyCores: 4,
                    neuralEngineCores: 16,
                    estimatedTops: 38,
                    maxMemoryBandwidth: 273,
                    supportedFrameworks: [.coreML, .onnx, .mlx, .tensorFlowLite],
                    thermalDesignPower: 30,
                    estimatedClockSpeed: 4.5
                )
            case .max:
                return ProcessorSpec(
                    name: "M4 Max",
                    coreCount: 16,
                    performanceCores: 12,
                    efficiencyCores: 4,
                    neuralEngineCores: 16,
                    estimatedTops: 38,
                    maxMemoryBandwidth: 546,
                    supportedFrameworks: [.coreML, .onnx, .mlx, .tensorFlowLite],
                    thermalDesignPower: 40,
                    estimatedClockSpeed: 4.5
                )
            case .ultra:
                // M4 Ultra not released yet, using estimated specs
                return ProcessorSpec(
                    name: "M4 Ultra",
                    coreCount: 32,
                    performanceCores: 24,
                    efficiencyCores: 8,
                    neuralEngineCores: 32,
                    estimatedTops: 76,
                    maxMemoryBandwidth: 1092,
                    supportedFrameworks: [.coreML, .onnx, .mlx, .tensorFlowLite],
                    thermalDesignPower: 60,
                    estimatedClockSpeed: 4.5
                )
            }

        // MARK: - Intel
        case .intel:
            return ProcessorSpec(
                name: "Intel x86_64",
                coreCount: ProcessInfo.processInfo.processorCount,
                performanceCores: ProcessInfo.processInfo.processorCount,
                efficiencyCores: 0,
                neuralEngineCores: 0,
                estimatedTops: 0,
                maxMemoryBandwidth: 50,
                supportedFrameworks: [.coreML, .tensorFlowLite],
                thermalDesignPower: 45,
                estimatedClockSpeed: 2.5
            )

        // MARK: - Unknown
        case .unknown:
            return ProcessorSpec(
                name: "Unknown",
                coreCount: ProcessInfo.processInfo.processorCount,
                performanceCores: 2,
                efficiencyCores: ProcessInfo.processInfo.processorCount - 2,
                neuralEngineCores: 0,
                estimatedTops: 0,
                maxMemoryBandwidth: 50,
                supportedFrameworks: [.coreML],
                thermalDesignPower: 10,
                estimatedClockSpeed: 2.0
            )
        }
    }

    /// Get optimization recommendations for a processor
    public static func getOptimizationRecommendations(for cpu: CPUType, variant: ProcessorVariant = .standard) -> OptimizationRecommendations {
        let spec = getSpec(for: cpu, variant: variant)

        // Determine recommendations based on TOPS performance
        let maxBatchSize: Int
        let maxContextLength: Int
        let recommendedQuantization: QuantizationLevel
        let maxTokensPerSecond: Int

        switch spec.estimatedTops {
        case 35...:
            // High-performance chips (A17 Pro, A18, M4)
            maxBatchSize = 8
            maxContextLength = 4096
            recommendedQuantization = .full
            maxTokensPerSecond = 50

        case 15...:
            // Mid-range chips (A15, A16, M2, M3)
            maxBatchSize = 4
            maxContextLength = 2048
            recommendedQuantization = .q8_0
            maxTokensPerSecond = 25

        case 10...:
            // Entry-level ML chips (A14, M1)
            maxBatchSize = 2
            maxContextLength = 1024
            recommendedQuantization = .q8_0
            maxTokensPerSecond = 15

        default:
            // Low-end or unknown chips
            maxBatchSize = 1
            maxContextLength = 512
            recommendedQuantization = .q4_K_M
            maxTokensPerSecond = 10
        }

        return OptimizationRecommendations(
            maxBatchSize: maxBatchSize,
            maxContextLength: maxContextLength,
            recommendedQuantization: recommendedQuantization,
            maxTokensPerSecond: maxTokensPerSecond,
            useNeuralEngine: spec.neuralEngineCores > 0,
            useGPU: true,
            preferredFramework: determinePreferredFramework(for: cpu)
        )
    }

    private static func determinePreferredFramework(for cpu: CPUType) -> LLMFramework {
        switch cpu {
        case .m1, .m2, .m3, .m4:
            return .mlx // MLX optimized for Apple Silicon Macs
        case .a14Bionic, .a15Bionic, .a16Bionic, .a17Pro, .a18, .a18Pro:
            return .coreML // Core ML for iOS devices
        case .intel:
            return .tensorFlowLite // TensorFlow Lite for Intel Macs
        default:
            return .coreML // Default to Core ML
        }
    }
}

// MARK: - Supporting Types

public struct OptimizationRecommendations {
    public let maxBatchSize: Int
    public let maxContextLength: Int
    public let recommendedQuantization: QuantizationLevel
    public let maxTokensPerSecond: Int
    public let useNeuralEngine: Bool
    public let useGPU: Bool
    public let preferredFramework: LLMFramework
}
