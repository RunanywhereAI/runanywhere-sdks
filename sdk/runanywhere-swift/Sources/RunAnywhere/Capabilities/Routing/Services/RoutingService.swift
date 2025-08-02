import Foundation

/// Service for making routing decisions
public class RoutingService {
    private let costCalculator: CostCalculator
    private let resourceChecker: ResourceChecker

    public init(
        costCalculator: CostCalculator,
        resourceChecker: ResourceChecker
    ) {
        self.costCalculator = costCalculator
        self.resourceChecker = resourceChecker
    }

    /// Determine the optimal routing for a generation request
    public func determineRouting(
        prompt: String,
        context: Context,
        options: GenerationOptions
    ) async throws -> RoutingDecision {
        // Check user preference first
        if let userTarget = options.executionTarget {
            return try await handleUserPreference(userTarget, prompt: prompt, context: context, options: options)
        }

        // Check policy constraints
        if let policyDecision = try await checkPolicyConstraints(prompt: prompt, context: context, options: options) {
            return policyDecision
        }

        // Check resource availability
        let deviceResourcesAvailable = await resourceChecker.checkDeviceResources()
        if !deviceResourcesAvailable {
            return .cloud(
                provider: nil,
                reason: .insufficientResources("device memory or processing power")
            )
        }

        // Analyze complexity
        let complexity = analyzeComplexity(prompt: prompt, options: options)

        // Calculate costs for different options
        let onDeviceCost = await costCalculator.calculateOnDeviceCost(
            tokenCount: estimateTokenCount(prompt),
            options: options
        )

        let cloudCost = await costCalculator.calculateCloudCost(
            tokenCount: estimateTokenCount(prompt),
            options: options
        )

        // Make decision based on cost and complexity
        if complexity == .low && onDeviceCost < cloudCost {
            return .onDevice(
                framework: selectBestFramework(for: options),
                reason: .costOptimization(savedAmount: cloudCost - onDeviceCost)
            )
        } else if complexity == .high {
            return .cloud(
                provider: nil,
                reason: .highComplexity
            )
        } else {
            // Use hybrid approach for medium complexity
            return .hybrid(
                devicePortion: 0.5,
                framework: selectBestFramework(for: options),
                reason: .latencyOptimization(expectedMs: 500)
            )
        }
    }

    // MARK: - Private Methods

    private func handleUserPreference(
        _ target: ExecutionTarget,
        prompt: String,
        context: Context,
        options: GenerationOptions
    ) async throws -> RoutingDecision {
        switch target {
        case .onDevice:
            // Check if device execution is possible
            let resourcesAvailable = await resourceChecker.checkDeviceResources()
            if !resourcesAvailable {
                // Override user preference due to resource constraints
                return .cloud(
                    provider: nil,
                    reason: .insufficientResources("device resources")
                )
            }
            return .onDevice(
                framework: selectBestFramework(for: options),
                reason: .userPreference(target)
            )

        case .cloud:
            return .cloud(
                provider: nil,
                reason: .userPreference(target)
            )

        case .hybrid:
            return .hybrid(
                devicePortion: 0.5,
                framework: selectBestFramework(for: options),
                reason: .userPreference(target)
            )
        }
    }

    private func checkPolicyConstraints(
        prompt: String,
        context: Context,
        options: GenerationOptions
    ) async throws -> RoutingDecision? {
        // Check for privacy-sensitive content
        if detectPrivacySensitiveContent(prompt) {
            return .onDevice(
                framework: selectBestFramework(for: options),
                reason: .privacySensitive
            )
        }

        // No policy constraints found
        return nil
    }

    private func analyzeComplexity(prompt: String, options: GenerationOptions) -> TaskComplexity {
        let promptLength = prompt.count
        let maxTokens = options.maxTokens ?? 100

        // Simple heuristic for complexity
        if promptLength < 100 && maxTokens < 50 {
            return .low
        } else if promptLength > 500 || maxTokens > 200 {
            return .high
        } else {
            return .medium
        }
    }

    private func estimateTokenCount(_ prompt: String) -> Int {
        // Simple estimation: ~4 characters per token
        return prompt.count / 4
    }

    private func selectBestFramework(for options: GenerationOptions) -> LLMFramework? {
        // Prefer user's framework choice if available
        if let userFramework = getUserPreferredFramework(from: options) {
            return userFramework
        }

        // Default to CoreML on Apple platforms
        return .coreML
    }

    private func getUserPreferredFramework(from options: GenerationOptions) -> LLMFramework? {
        // Check if user has specified a framework preference
        // This is a simplified implementation
        return nil
    }

    private func detectPrivacySensitiveContent(_ prompt: String) -> Bool {
        // Simple keyword-based detection
        let sensitiveKeywords = ["password", "ssn", "credit card", "personal", "private"]
        let lowercasePrompt = prompt.lowercased()

        return sensitiveKeywords.contains { keyword in
            lowercasePrompt.contains(keyword)
        }
    }

    /// Check if service is healthy
    public func isHealthy() -> Bool {
        return true
    }
}

// MARK: - Supporting Types

private enum TaskComplexity {
    case low
    case medium
    case high
}

// MARK: - Supporting Services

/// Cost calculator for routing decisions
public class CostCalculator {
    public init() {}

    public func calculateOnDeviceCost(tokenCount: Int, options: GenerationOptions) async -> Double {
        // On-device is essentially free (just battery/processing)
        return 0.0
    }

    public func calculateCloudCost(tokenCount: Int, options: GenerationOptions) async -> Double {
        // Simple cost model: $0.001 per token
        return Double(tokenCount) * 0.001
    }
}

/// Resource checker for routing decisions
public class ResourceChecker {
    private let hardwareManager: HardwareCapabilityManager

    public init(hardwareManager: HardwareCapabilityManager) {
        self.hardwareManager = hardwareManager
    }

    public func checkDeviceResources() async -> Bool {
        // Check if device has sufficient resources
        let capabilities = hardwareManager.getDeviceCapabilities()

        // Simple check: ensure we have Neural Engine or GPU
        return capabilities.hasNeuralEngine || capabilities.hasGPU
    }
}
