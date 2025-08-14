import Foundation

/// Service for recommending the best framework for a given model
class FrameworkRecommender {
    private let compatibilityService: CompatibilityService
    private let requirementChecker: RequirementChecker
    private let logger = SDKLogger(category: "FrameworkRecommender")

    init(
        compatibilityService: CompatibilityService = CompatibilityService(),
        requirementChecker: RequirementChecker = RequirementChecker()
    ) {
        self.compatibilityService = compatibilityService
        self.requirementChecker = requirementChecker
    }

    func recommendFramework(for model: ModelInfo, preferences: RecommendationPreferences = .default) -> FrameworkRecommendation? {
        let compatibleFrameworks = compatibilityService.getCompatibleFrameworks(for: model)

        guard !compatibleFrameworks.isEmpty else {
            logger.warning("No compatible frameworks found for model \(model.name)")
            return nil
        }

        // Score each compatible framework
        let scoredFrameworks = compatibleFrameworks.compactMap { framework -> ScoredFramework? in
            let score = calculateScore(framework: framework, model: model, preferences: preferences)
            let deviceSupport = requirementChecker.checkDeviceSupport(for: framework)

            guard deviceSupport.isSupported else {
                return nil
            }

            return ScoredFramework(
                framework: framework,
                score: score,
                compatibilityResult: compatibilityService.checkCompatibility(model: model, framework: framework),
                deviceSupport: deviceSupport
            )
        }

        // Sort by score (highest first)
        let sortedFrameworks = scoredFrameworks.sorted { $0.score > $1.score }

        guard let bestFramework = sortedFrameworks.first else {
            return nil
        }

        return FrameworkRecommendation(
            primaryFramework: bestFramework.framework,
            primaryScore: bestFramework.score,
            alternatives: Array(sortedFrameworks.dropFirst().prefix(2)),
            reasoning: generateReasoning(for: bestFramework, model: model, preferences: preferences)
        )
    }

    func recommendFrameworks(for models: [ModelInfo], preferences: RecommendationPreferences = .default) -> [ModelFrameworkRecommendation] {
        return models.compactMap { model in
            guard let recommendation = recommendFramework(for: model, preferences: preferences) else {
                return nil
            }
            return ModelFrameworkRecommendation(model: model, recommendation: recommendation)
        }
    }

    func getBestFrameworkForFormat(_ format: ModelFormat, preferences: RecommendationPreferences = .default) -> LLMFramework? {
        let supportedFrameworks = FrameworkCapabilities.getSupportedFrameworks(for: format)

        let scoredFrameworks = supportedFrameworks.map { framework in
            (framework, calculateFormatScore(framework: framework, format: format, preferences: preferences))
        }

        return scoredFrameworks.max { $0.1 < $1.1 }?.0
    }

    private func calculateScore(framework: LLMFramework, model: ModelInfo, preferences: RecommendationPreferences) -> Double {
        var score: Double = 0.0

        // Base compatibility score
        let compatibilityResult = compatibilityService.checkCompatibility(model: model, framework: framework)
        let compatibilityScore = compatibilityResult.isCompatible ?
            (compatibilityResult.confidence == .high ? 1.0 :
             compatibilityResult.confidence == .medium ? 0.8 :
             compatibilityResult.confidence == .low ? 0.6 : 0.4) : 0.0
        score += compatibilityScore * 0.4

        // Performance preference
        let performanceScore = getPerformanceScore(framework: framework, model: model)
        score += performanceScore * preferences.performanceWeight

        // Memory efficiency preference
        let memoryScore = getMemoryScore(framework: framework, model: model)
        score += memoryScore * preferences.memoryWeight

        // Ease of use preference
        let easeOfUseScore = getEaseOfUseScore(framework: framework)
        score += easeOfUseScore * preferences.easeOfUseWeight

        // Stability preference
        let stabilityScore = getStabilityScore(framework: framework)
        score += stabilityScore * preferences.stabilityWeight

        return min(score, 1.0)
    }

    private func calculateFormatScore(framework: LLMFramework, format: ModelFormat, preferences: RecommendationPreferences) -> Double {
        guard let capability = FrameworkCapabilities.getCapability(for: framework) else {
            return 0.0
        }

        guard capability.supportedFormats.contains(format) else {
            return 0.0
        }

        var score: Double = 0.5 // Base score for supporting the format

        // Add framework-specific bonuses
        switch (framework, format) {
        case (.coreML, .mlmodel), (.coreML, .mlpackage):
            score += 0.3 // Native format
        case (.llamaCpp, .gguf), (.llamaCpp, .ggml):
            score += 0.3 // Native format
        case (.mlx, .safetensors):
            score += 0.2 // Optimized for Apple Silicon
        default:
            break
        }

        return score
    }

    private func getPerformanceScore(framework: LLMFramework, model: ModelInfo) -> Double {
        // Performance rankings based on typical performance characteristics
        switch framework {
        case .foundationModels:
            return 0.95 // Highly optimized by Apple
        case .coreML:
            return 0.90 // Native Apple framework
        case .mlx:
            return 0.85 // Optimized for Apple Silicon
        case .llamaCpp:
            return 0.80 // Well-optimized C++ implementation
        case .mlc:
            return 0.75 // Good optimization
        case .onnx:
            return 0.70 // General purpose
        case .execuTorch:
            return 0.65 // Mobile-optimized
        case .tensorFlowLite:
            return 0.60 // Mobile-optimized but older
        case .swiftTransformers:
            return 0.55 // Swift implementation
        case .picoLLM:
            return 0.50 // Small models only
        case .mediaPipe:
            return 0.60 // Optimized for specific model types
        case .whisperKit:
            return 0.85 // Optimized for speech recognition on Apple devices
        case .openAIWhisper:
            return 0.70 // Cloud-based, excellent accuracy
        }
    }

    private func getMemoryScore(framework: LLMFramework, model: ModelInfo) -> Double {
        // Memory efficiency rankings
        switch framework {
        case .llamaCpp:
            return 0.95 // Excellent quantization support
        case .mlx:
            return 0.90 // Efficient memory usage
        case .coreML:
            return 0.85 // Good optimization
        case .mlc:
            return 0.80 // Good memory management
        case .execuTorch:
            return 0.75 // Mobile-optimized
        case .tensorFlowLite:
            return 0.70 // Compact models
        case .onnx:
            return 0.65 // General purpose
        case .picoLLM:
            return 0.90 // Very small models
        case .foundationModels:
            return 0.60 // Apple handles optimization
        case .swiftTransformers:
            return 0.55 // Less optimized
        case .mediaPipe:
            return 0.70 // Efficient for specific models
        case .whisperKit:
            return 0.80 // Efficient on-device speech models
        case .openAIWhisper:
            return 0.50 // Cloud-based, no local memory usage
        }
    }

    private func getEaseOfUseScore(framework: LLMFramework) -> Double {
        switch framework {
        case .foundationModels:
            return 0.95 // Easiest, built into iOS
        case .coreML:
            return 0.90 // Well-documented Apple framework
        case .swiftTransformers:
            return 0.85 // Swift-native
        case .mlx:
            return 0.75 // Good documentation
        case .tensorFlowLite:
            return 0.70 // Established framework
        case .onnx:
            return 0.65 // Good tooling
        case .execuTorch:
            return 0.60 // PyTorch ecosystem
        case .llamaCpp:
            return 0.55 // C++ integration needed
        case .mlc:
            return 0.50 // More complex setup
        case .picoLLM:
            return 0.80 // Simple for small models
        case .mediaPipe:
            return 0.75 // Good integration with Google tools
        case .whisperKit:
            return 0.80 // Simple API for speech recognition
        case .openAIWhisper:
            return 0.85 // Very simple API, cloud-based
        }
    }

    private func getStabilityScore(framework: LLMFramework) -> Double {
        switch framework {
        case .foundationModels:
            return 0.95 // Apple-maintained
        case .coreML:
            return 0.95 // Mature Apple framework
        case .tensorFlowLite:
            return 0.90 // Mature Google framework
        case .onnx:
            return 0.85 // Established standard
        case .llamaCpp:
            return 0.80 // Stable community project
        case .mlx:
            return 0.75 // Newer but Apple-backed
        case .swiftTransformers:
            return 0.70 // Community project
        case .execuTorch:
            return 0.65 // Newer framework
        case .mlc:
            return 0.60 // Research project
        case .picoLLM:
            return 0.70 // Simple and stable
        case .mediaPipe:
            return 0.85 // Google-maintained, stable
        case .whisperKit:
            return 0.75 // Active community project
        case .openAIWhisper:
            return 0.90 // OpenAI-maintained, very stable
        }
    }

    private func generateReasoning(for scoredFramework: ScoredFramework, model: ModelInfo, preferences: RecommendationPreferences) -> String {
        var reasons: [String] = []

        // Format compatibility
        reasons.append("Supports \(model.format.rawValue) format")

        // Performance characteristics
        let performanceScore = getPerformanceScore(framework: scoredFramework.framework, model: model)
        if performanceScore > 0.8 {
            reasons.append("High performance on this platform")
        }

        // Memory efficiency
        let memoryScore = getMemoryScore(framework: scoredFramework.framework, model: model)
        if memoryScore > 0.8 {
            reasons.append("Efficient memory usage")
        }

        // Quantization support
        if let quantization = model.metadata?.quantizationLevel {
            if QuantizationSupport.isSupported(quantization: quantization, framework: scoredFramework.framework) {
                reasons.append("Supports \(quantization.rawValue) quantization")
            }
        }

        return reasons.joined(separator: ", ")
    }
}

/// Preferences for framework recommendation
struct RecommendationPreferences {
    let performanceWeight: Double
    let memoryWeight: Double
    let easeOfUseWeight: Double
    let stabilityWeight: Double

    static let `default` = RecommendationPreferences(
        performanceWeight: 0.3,
        memoryWeight: 0.25,
        easeOfUseWeight: 0.25,
        stabilityWeight: 0.2
    )

    static let performance = RecommendationPreferences(
        performanceWeight: 0.5,
        memoryWeight: 0.2,
        easeOfUseWeight: 0.15,
        stabilityWeight: 0.15
    )

    static let memory = RecommendationPreferences(
        performanceWeight: 0.2,
        memoryWeight: 0.5,
        easeOfUseWeight: 0.15,
        stabilityWeight: 0.15
    )

    static let easeOfUse = RecommendationPreferences(
        performanceWeight: 0.15,
        memoryWeight: 0.15,
        easeOfUseWeight: 0.5,
        stabilityWeight: 0.2
    )
}

/// Framework recommendation result
struct FrameworkRecommendation {
    let primaryFramework: LLMFramework
    let primaryScore: Double
    let alternatives: [ScoredFramework]
    let reasoning: String
}

/// Scored framework with additional context
struct ScoredFramework {
    let framework: LLMFramework
    let score: Double
    let compatibilityResult: CompatibilityResult
    let deviceSupport: DeviceSupport
}

/// Model with framework recommendation
struct ModelFrameworkRecommendation {
    let model: ModelInfo
    let recommendation: FrameworkRecommendation
}
