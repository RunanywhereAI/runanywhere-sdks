//
//  ModelCompatibilityMatrix.swift
//  RunAnywhereAI
//
//  Created by Assistant on 7/27/25.
//

import Foundation

/// Model compatibility matrix for determining which models work with which frameworks
class ModelCompatibilityMatrix: ObservableObject {
    static let shared = ModelCompatibilityMatrix()
    
    // MARK: - Compatibility Data
    
    /// Framework capabilities
    private let frameworkCapabilities: [LLMFramework: FrameworkCapability] = [
        .foundationModels: FrameworkCapability(
            supportedFormats: [.coreML],
            supportedQuantizations: [.int2, .int4],
            maxModelSize: 3_000_000_000,
            requiresSpecificModels: true,
            minimumOS: "18.0",
            supportedArchitectures: ["arm64e"]
        ),
        .coreML: FrameworkCapability(
            supportedFormats: [.coreML],
            supportedQuantizations: [.float16, .int8, .int4],
            maxModelSize: 15_000_000_000,
            requiresSpecificModels: false,
            minimumOS: "11.0",
            supportedArchitectures: ["arm64", "arm64e"]
        ),
        .mlx: FrameworkCapability(
            supportedFormats: [.mlx],
            supportedQuantizations: [.q4_0, .q4_1, .q8_0],
            maxModelSize: 30_000_000_000,
            requiresSpecificModels: false,
            minimumOS: "17.0",
            supportedArchitectures: ["arm64e"]
        ),
        .mlc: FrameworkCapability(
            supportedFormats: [.mlc],
            supportedQuantizations: [.q3f16_1, .q4f16_1],
            maxModelSize: 20_000_000_000,
            requiresSpecificModels: false,
            minimumOS: "14.0",
            supportedArchitectures: ["arm64", "arm64e"]
        ),
        .onnx: FrameworkCapability(
            supportedFormats: [.onnx],
            supportedQuantizations: [.float32, .float16, .int8],
            maxModelSize: 10_000_000_000,
            requiresSpecificModels: false,
            minimumOS: "11.0",
            supportedArchitectures: ["arm64", "arm64e", "x86_64"]
        ),
        .execuTorch: FrameworkCapability(
            supportedFormats: [.pte],
            supportedQuantizations: [.int4, .int8],
            maxModelSize: 15_000_000_000,
            requiresSpecificModels: false,
            minimumOS: "12.0",
            supportedArchitectures: ["arm64", "arm64e"]
        ),
        .llamaCpp: FrameworkCapability(
            supportedFormats: [.gguf],
            supportedQuantizations: [.q2_k, .q3_k_s, .q3_k_m, .q3_k_l, .q4_0, .q4_1, .q4_k_s, .q4_k_m, .q5_0, .q5_1, .q5_k_s, .q5_k_m, .q6_k, .q8_0],
            maxModelSize: 50_000_000_000,
            requiresSpecificModels: false,
            minimumOS: "10.0",
            supportedArchitectures: ["arm64", "arm64e", "x86_64"]
        ),
        .tfLite: FrameworkCapability(
            supportedFormats: [.tflite],
            supportedQuantizations: [.float32, .float16, .int8],
            maxModelSize: 5_000_000_000,
            requiresSpecificModels: false,
            minimumOS: "11.0",
            supportedArchitectures: ["arm64", "arm64e"]
        ),
        .picoLLM: FrameworkCapability(
            supportedFormats: [.picoLLM],
            supportedQuantizations: [.x1, .x2, .x4, .x8],
            maxModelSize: 2_000_000_000,
            requiresSpecificModels: true,
            minimumOS: "11.0",
            supportedArchitectures: ["arm64", "arm64e"]
        ),
        .swiftTransformers: FrameworkCapability(
            supportedFormats: [.coreML],
            supportedQuantizations: [.float16, .int8],
            maxModelSize: 10_000_000_000,
            requiresSpecificModels: false,
            minimumOS: "15.0",
            supportedArchitectures: ["arm64", "arm64e"]
        )
    ]
    
    /// Model architecture compatibility
    private let modelArchitectureSupport: [ModelArchitecture: Set<LLMFramework>] = [
        .llama: [.llamaCpp, .mlx, .mlc, .coreML, .onnx, .execuTorch, .tfLite],
        .mistral: [.llamaCpp, .mlx, .mlc, .coreML, .onnx],
        .phi: [.llamaCpp, .coreML, .mlx, .onnx],
        .qwen: [.llamaCpp, .mlx, .mlc],
        .gemma: [.tfLite, .coreML, .onnx],
        .gpt2: [.swiftTransformers, .coreML, .onnx],
        .bert: [.coreML, .onnx, .tfLite],
        .t5: [.onnx, .tfLite],
        .custom: [.coreML, .onnx]
    ]
    
    // MARK: - Public Methods
    
    /// Check if a model is compatible with a framework
    func isCompatible(
        model: ModelInfo,
        framework: LLMFramework,
        device: DeviceInfo? = nil
    ) -> CompatibilityResult {
        
        guard let capability = frameworkCapabilities[framework] else {
            return CompatibilityResult(
                isCompatible: false,
                reason: "Framework not supported",
                warnings: []
            )
        }
        
        // Check format support
        if !capability.supportedFormats.contains(model.format) {
            return CompatibilityResult(
                isCompatible: false,
                reason: "Model format \(model.format.rawValue) not supported by \(framework.displayName)",
                warnings: []
            )
        }
        
        // Check quantization support
        if !capability.supportedQuantizations.contains(model.quantization) {
            return CompatibilityResult(
                isCompatible: false,
                reason: "Quantization \(model.quantization.rawValue) not supported by \(framework.displayName)",
                warnings: []
            )
        }
        
        // Check model size
        if model.size > capability.maxModelSize {
            return CompatibilityResult(
                isCompatible: false,
                reason: "Model too large for \(framework.displayName)",
                warnings: []
            )
        }
        
        // Check device requirements
        if let device = device {
            let osVersion = ProcessInfo.processInfo.operatingSystemVersion
            let currentOSString = "\(osVersion.majorVersion).\(osVersion.minorVersion)"
            
            if currentOSString.compare(capability.minimumOS, options: .numeric) == .orderedAscending {
                return CompatibilityResult(
                    isCompatible: false,
                    reason: "Requires iOS \(capability.minimumOS) or later",
                    warnings: []
                )
            }
            
            if !device.requirements.isSatisfied() {
                return CompatibilityResult(
                    isCompatible: false,
                    reason: "Device doesn't meet memory requirements",
                    warnings: []
                )
            }
        }
        
        // Check architecture support
        if let architecture = getModelArchitecture(from: model.id),
           let supportedFrameworks = modelArchitectureSupport[architecture],
           !supportedFrameworks.contains(framework) {
            return CompatibilityResult(
                isCompatible: false,
                reason: "\(architecture.rawValue) architecture not supported by \(framework.displayName)",
                warnings: []
            )
        }
        
        // Generate warnings
        var warnings: [String] = []
        
        if model.size > capability.maxModelSize / 2 {
            warnings.append("Model uses over 50% of maximum supported size")
        }
        
        if capability.requiresSpecificModels {
            warnings.append("Framework requires specifically optimized models")
        }
        
        return CompatibilityResult(
            isCompatible: true,
            reason: "Compatible",
            warnings: warnings
        )
    }
    
    /// Get all compatible frameworks for a model
    func getCompatibleFrameworks(for model: ModelInfo) -> [FrameworkCompatibility] {
        var compatibilities: [FrameworkCompatibility] = []
        
        for framework in LLMFramework.allCases {
            let result = isCompatible(model: model, framework: framework)
            compatibilities.append(
                FrameworkCompatibility(
                    framework: framework,
                    result: result,
                    performance: estimatePerformance(model: model, framework: framework)
                )
            )
        }
        
        return compatibilities.sorted { $0.performance.score > $1.performance.score }
    }
    
    /// Get recommended framework for a model
    func getRecommendedFramework(
        for model: ModelInfo,
        preferences: FrameworkPreferences = .default
    ) -> LLMFramework? {
        
        let compatibleFrameworks = getCompatibleFrameworks(for: model)
            .filter { $0.result.isCompatible }
        
        guard !compatibleFrameworks.isEmpty else { return nil }
        
        // Apply preferences
        let scored = compatibleFrameworks.map { compatibility -> (FrameworkCompatibility, Double) in
            var score = compatibility.performance.score
            
            // Adjust score based on preferences
            if preferences.preferNative && isNativeFramework(compatibility.framework) {
                score *= 1.5
            }
            
            if preferences.preferFastestInference {
                score *= compatibility.performance.estimatedTokensPerSecond / 50.0
            }
            
            if preferences.preferLowestMemory {
                score *= 1.0 / (compatibility.performance.estimatedMemoryUsage / 1_000_000_000.0)
            }
            
            return (compatibility, score)
        }
        
        return scored.max { $0.1 < $1.1 }?.0.framework
    }
    
    /// Create compatibility report
    func generateCompatibilityReport(for models: [ModelInfo]) -> CompatibilityReport {
        var matrix: [[Bool]] = []
        var details: [String: [CompatibilityResult]] = [:]
        
        for model in models {
            var row: [Bool] = []
            var modelDetails: [CompatibilityResult] = []
            
            for framework in LLMFramework.allCases {
                let result = isCompatible(model: model, framework: framework)
                row.append(result.isCompatible)
                modelDetails.append(result)
            }
            
            matrix.append(row)
            details[model.id] = modelDetails
        }
        
        return CompatibilityReport(
            models: models,
            frameworks: LLMFramework.allCases,
            compatibilityMatrix: matrix,
            details: details,
            generatedAt: Date()
        )
    }
    
    // MARK: - Private Methods
    
    private func getModelArchitecture(from modelId: String) -> ModelArchitecture? {
        for architecture in ModelArchitecture.allCases {
            if modelId.lowercased().contains(architecture.rawValue.lowercased()) {
                return architecture
            }
        }
        return nil
    }
    
    private func estimatePerformance(model: ModelInfo, framework: LLMFramework) -> PerformanceEstimate {
        // Base performance scores (tokens/second)
        let basePerformance: [LLMFramework: Double] = [
            .foundationModels: 50,
            .mlx: 65,
            .llamaCpp: 40,
            .coreML: 45,
            .mlc: 55,
            .onnx: 35,
            .execuTorch: 38,
            .tfLite: 30,
            .picoLLM: 25,
            .swiftTransformers: 40
        ]
        
        let base = basePerformance[framework] ?? 30
        
        // Adjust for model size
        let sizeMultiplier = 3_000_000_000.0 / Double(model.size)
        
        // Adjust for quantization
        let quantizationMultiplier: Double
        switch model.quantization {
        case .int2, .q2_k, .x1, .x2:
            quantizationMultiplier = 2.0
        case .int4, .q4_0, .q4_1, .q4_k_s, .q4_k_m, .x4:
            quantizationMultiplier = 1.5
        case .int8, .q8_0, .x8:
            quantizationMultiplier = 1.2
        default:
            quantizationMultiplier = 1.0
        }
        
        let estimatedSpeed = base * sizeMultiplier * quantizationMultiplier
        
        // Parse size string to get numeric value in bytes
        let sizeInBytes = parseSizeString(model.size)
        let estimatedMemory = Int64(Double(sizeInBytes) / quantizationMultiplier)
        
        return PerformanceEstimate(
            estimatedTokensPerSecond: estimatedSpeed,
            estimatedMemoryUsage: estimatedMemory,
            estimatedLoadTime: Double(sizeInBytes) / 500_000_000, // 500MB/s
            score: estimatedSpeed / 100.0
        )
    }
    
    private func isNativeFramework(_ framework: LLMFramework) -> Bool {
        return [.foundationModels, .coreML, .mlx].contains(framework)
    }
    
    private func parseSizeString(_ sizeString: String) -> Int64 {
        // Parse size strings like "1.7GB", "3.5G", "500MB", etc.
        let cleanString = sizeString.uppercased().replacingOccurrences(of: " ", with: "")
        
        // Extract numeric value
        let scanner = Scanner(string: cleanString)
        var value: Double = 0
        scanner.scanDouble(&value)
        
        // Check for unit suffix
        let remaining = cleanString.dropFirst(scanner.currentIndex.utf16Offset(in: cleanString))
        
        var multiplier: Double = 1
        if remaining.hasPrefix("GB") || remaining.hasPrefix("G") {
            multiplier = 1_000_000_000
        } else if remaining.hasPrefix("MB") || remaining.hasPrefix("M") {
            multiplier = 1_000_000
        } else if remaining.hasPrefix("KB") || remaining.hasPrefix("K") {
            multiplier = 1_000
        }
        
        return Int64(value * multiplier)
    }
}

// MARK: - Supporting Types

struct FrameworkCapability {
    let supportedFormats: Set<ModelFormat>
    let supportedQuantizations: Set<QuantizationType>
    let maxModelSize: Int64
    let requiresSpecificModels: Bool
    let minimumOS: String
    let supportedArchitectures: [String]
}

struct CompatibilityResult {
    let isCompatible: Bool
    let reason: String
    let warnings: [String]
}

struct FrameworkCompatibility {
    let framework: LLMFramework
    let result: CompatibilityResult
    let performance: PerformanceEstimate
}

struct PerformanceEstimate {
    let estimatedTokensPerSecond: Double
    let estimatedMemoryUsage: Int64
    let estimatedLoadTime: Double
    let score: Double
}

struct FrameworkPreferences {
    let preferNative: Bool
    let preferFastestInference: Bool
    let preferLowestMemory: Bool
    let preferCrossplatform: Bool
    
    static let `default` = FrameworkPreferences(
        preferNative: true,
        preferFastestInference: true,
        preferLowestMemory: false,
        preferCrossplatform: false
    )
}

struct CompatibilityReport {
    let models: [ModelInfo]
    let frameworks: [LLMFramework]
    let compatibilityMatrix: [[Bool]]
    let details: [String: [CompatibilityResult]]
    let generatedAt: Date
}

struct DeviceInfo {
    let model: String
    let memory: Int64
    let requirements: DeviceRequirement
}

enum ModelArchitecture: String, CaseIterable {
    case llama
    case mistral
    case phi
    case qwen
    case gemma
    case gpt2
    case bert
    case t5
    case custom
}

extension ModelFormat {
    static let mlc = ModelFormat(rawValue: "mlc")!
    static let picoLLM = ModelFormat(rawValue: "picoLLM")!
}