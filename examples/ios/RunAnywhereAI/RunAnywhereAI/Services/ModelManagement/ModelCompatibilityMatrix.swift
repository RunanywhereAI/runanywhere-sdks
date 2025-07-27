//
//  ModelCompatibilityMatrix.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/27/25.
//

import Foundation

/// Model compatibility matrix for determining which models work with which frameworks
class ModelCompatibilityMatrix: ObservableObject {
    static let shared = ModelCompatibilityMatrix()
    
    // MARK: - Compatibility Data
    
    /// Framework capabilities
    private let frameworkCapabilities: [LLMFramework: FrameworkCapability] = [
        .foundationModels: FrameworkCapability(
            supportedFormats: [ModelFormat.coreML],
            supportedQuantizations: [QuantizationType.q4_0],
            maxModelSize: 3_000_000_000,
            requiresSpecificModels: true,
            minimumOS: "18.0",
            supportedArchitectures: ["arm64e"]
        ),
        .coreML: FrameworkCapability(
            supportedFormats: [ModelFormat.coreML],
            supportedQuantizations: [QuantizationType.f16, QuantizationType.q8_0, QuantizationType.q4_0],
            maxModelSize: 15_000_000_000,
            requiresSpecificModels: false,
            minimumOS: "11.0",
            supportedArchitectures: ["arm64", "arm64e"]
        ),
        .mlx: FrameworkCapability(
            supportedFormats: [ModelFormat.mlx],
            supportedQuantizations: [QuantizationType.q4_0, QuantizationType.q4_K_M, QuantizationType.q8_0],
            maxModelSize: 30_000_000_000,
            requiresSpecificModels: false,
            minimumOS: "17.0",
            supportedArchitectures: ["arm64e"]
        ),
        .mlc: FrameworkCapability(
            supportedFormats: [ModelFormat.mlc],
            supportedQuantizations: [QuantizationType.q3_K_M, QuantizationType.q4_K_M],
            maxModelSize: 20_000_000_000,
            requiresSpecificModels: false,
            minimumOS: "14.0",
            supportedArchitectures: ["arm64", "arm64e"]
        ),
        .onnxRuntime: FrameworkCapability(
            supportedFormats: [ModelFormat.onnx],
            supportedQuantizations: [QuantizationType.f32, QuantizationType.f16, QuantizationType.q8_0],
            maxModelSize: 10_000_000_000,
            requiresSpecificModels: false,
            minimumOS: "11.0",
            supportedArchitectures: ["arm64", "arm64e", "x86_64"]
        ),
        .execuTorch: FrameworkCapability(
            supportedFormats: [ModelFormat.pte],
            supportedQuantizations: [QuantizationType.q4_0, QuantizationType.q8_0],
            maxModelSize: 15_000_000_000,
            requiresSpecificModels: false,
            minimumOS: "12.0",
            supportedArchitectures: ["arm64", "arm64e"]
        ),
        .llamaCpp: FrameworkCapability(
            supportedFormats: [ModelFormat.gguf],
            supportedQuantizations: [QuantizationType.q2_K, QuantizationType.q3_K_S, QuantizationType.q3_K_M, QuantizationType.q3_K_L, QuantizationType.q4_0, QuantizationType.q4_K_S, QuantizationType.q4_K_M, QuantizationType.q5_0, QuantizationType.q5_K_S, QuantizationType.q5_K_M, QuantizationType.q6_K, QuantizationType.q8_0],
            maxModelSize: 50_000_000_000,
            requiresSpecificModels: false,
            minimumOS: "10.0",
            supportedArchitectures: ["arm64", "arm64e", "x86_64"]
        ),
        .tensorFlowLite: FrameworkCapability(
            supportedFormats: [ModelFormat.tflite],
            supportedQuantizations: [QuantizationType.f32, QuantizationType.f16, QuantizationType.q8_0],
            maxModelSize: 5_000_000_000,
            requiresSpecificModels: false,
            minimumOS: "11.0",
            supportedArchitectures: ["arm64", "arm64e"]
        ),
        .picoLLM: FrameworkCapability(
            supportedFormats: [ModelFormat.picoLLM],
            supportedQuantizations: [QuantizationType.q4_0, QuantizationType.q8_0],
            maxModelSize: 2_000_000_000,
            requiresSpecificModels: true,
            minimumOS: "11.0",
            supportedArchitectures: ["arm64", "arm64e"]
        ),
        .swiftTransformers: FrameworkCapability(
            supportedFormats: [ModelFormat.coreML],
            supportedQuantizations: [QuantizationType.f16, QuantizationType.q8_0],
            maxModelSize: 10_000_000_000,
            requiresSpecificModels: false,
            minimumOS: "15.0",
            supportedArchitectures: ["arm64", "arm64e"]
        )
    ]
    
    /// Model architecture compatibility
    private let modelArchitectureSupport: [ModelArchitecture: Set<LLMFramework>] = [
        .llama: [.llamaCpp, .mlx, .mlc, .coreML, .onnxRuntime, .execuTorch, .tensorFlowLite],
        .mistral: [.llamaCpp, .mlx, .mlc, .coreML, .onnxRuntime],
        .phi: [.llamaCpp, .coreML, .mlx, .onnxRuntime],
        .qwen: [.llamaCpp, .mlx, .mlc],
        .gemma: [.tensorFlowLite, .coreML, .onnxRuntime],
        .gpt2: [.swiftTransformers, .coreML, .onnxRuntime],
        .bert: [.coreML, .onnxRuntime, .tensorFlowLite],
        .t5: [.onnxRuntime, .tensorFlowLite],
        .custom: [.coreML, .onnxRuntime]
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
        if let quantization = model.quantization {
            if let quantType = QuantizationType(rawValue: quantization),
               !capability.supportedQuantizations.contains(quantType) {
                return CompatibilityResult(
                    isCompatible: false,
                    reason: "Quantization \(quantization) not supported by \(framework.displayName)",
                    warnings: []
                )
            }
        }
        
        // Check model size
        let sizeInBytes = parseSizeString(model.size)
        if sizeInBytes > capability.maxModelSize {
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
            
            if !device.isSatisfied() {
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
        
        if sizeInBytes > capability.maxModelSize / 2 {
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
                score *= 1.0 / (Double(compatibility.performance.estimatedMemoryUsage) / 1_000_000_000.0)
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
            .onnxRuntime: 35,
            .execuTorch: 38,
            .tensorFlowLite: 30,
            .picoLLM: 25,
            .swiftTransformers: 40
        ]
        
        let base = basePerformance[framework] ?? 30
        
        // Adjust for model size
        let sizeInBytes = parseSizeString(model.size)
        let sizeMultiplier = 3_000_000_000.0 / Double(sizeInBytes)
        
        // Adjust for quantization
        let quantizationMultiplier: Double
        if let quantizationString = model.quantization {
            // Parse quantization string to determine multiplier
            if quantizationString.lowercased().contains("q2") || quantizationString.contains("int2") {
                quantizationMultiplier = 2.0
            } else if quantizationString.lowercased().contains("q4") || quantizationString.contains("int4") {
                quantizationMultiplier = 1.5
            } else if quantizationString.lowercased().contains("q8") || quantizationString.contains("int8") {
                quantizationMultiplier = 1.2
            } else {
                quantizationMultiplier = 1.0
            }
        } else {
            quantizationMultiplier = 1.0
        }
        
        let estimatedSpeed = base * sizeMultiplier * quantizationMultiplier
        
        // Parse size string is already done above
        let estimatedMemory = Int64(Double(sizeInBytes) / quantizationMultiplier)
        
        return PerformanceEstimate(
            estimatedTokensPerSecond: estimatedSpeed,
            estimatedMemoryUsage: estimatedMemory,
            estimatedLoadTime: Double(sizeInBytes) / 500_000_000, // 500MB/s
            score: estimatedSpeed / 100.0
        )
    }
    
    private func isNativeFramework(_ framework: LLMFramework) -> Bool {
        [.foundationModels, .coreML, .mlx].contains(framework)
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
    let minimumMemory: Int64
    let recommendedMemory: Int64
    
    func isSatisfied() -> Bool {
        let availableMemory = ProcessInfo.processInfo.physicalMemory
        return availableMemory >= minimumMemory
    }
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

// ModelFormat extensions removed - already defined in ModelInfo.swift
