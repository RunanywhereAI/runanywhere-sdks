//
//  FrameworkSwitchStrategy.swift
//  RunAnywhere SDK
//
//  Strategy for switching to alternative ML frameworks
//

import Foundation

/// Strategy for switching between ML frameworks
public class FrameworkSwitchStrategy: ErrorRecoveryStrategy {

    // MARK: - Properties

    private let logger = SDKLogger(category: "FrameworkSwitchStrategy")

    // Framework fallback order
    private let frameworkFallbackOrder: [LLMFramework: [LLMFramework]] = [
        .coreML: [.tensorFlowLite, .llamaCpp, .onnx],
        .tensorFlowLite: [.coreML, .llamaCpp, .onnx],
        .llamaCpp: [.mlx, .coreML, .tensorFlowLite],
        .mlx: [.llamaCpp, .coreML, .tensorFlowLite],
        .onnx: [.tensorFlowLite, .coreML]
    ]

    // MARK: - ErrorRecoveryStrategy

    public func canRecover(from error: Error) -> Bool {
        // Can switch frameworks for framework and memory errors
        let errorType = ErrorType(from: error)

        switch errorType {
        case .framework, .memory, .hardware:
            return true
        default:
            // Check if error mentions framework issues
            if case UnifiedModelError.retryWithFramework = error {
                return true
            }
            return false
        }
    }

    public func recover(from error: Error, context: RecoveryContext) async throws {
        logger.info("Attempting framework switch recovery")

        // Check if framework switching is allowed
        guard context.options.allowFrameworkSwitch else {
            logger.warning("Framework switching not allowed by options")
            throw UnifiedModelError.unrecoverable(error)
        }

        // Get current framework
        let currentFramework = context.model.preferredFramework ?? .coreML

        // Get alternative frameworks
        let alternatives = getAlternativeFrameworks(
            for: currentFramework,
            model: context.model,
            resources: context.availableResources
        )

        guard !alternatives.isEmpty else {
            logger.error("No alternative frameworks available")
            throw UnifiedModelError.noAlternativeFramework
        }

        // Try first alternative
        let targetFramework = alternatives.first!
        logger.info("Switching from \(currentFramework.rawValue) to \(targetFramework.rawValue)")

        throw UnifiedModelError.retryWithFramework(targetFramework)
    }

    public func getRecoverySuggestions(for error: Error) -> [RecoverySuggestion] {
        var suggestions: [RecoverySuggestion] = []

        // For framework errors, suggest alternatives
        if case let UnifiedModelError.framework(frameworkError) = error {
            // Get framework from error if possible
            suggestions.append(RecoverySuggestion(
                action: .switchFramework(.tensorFlowLite),
                description: "Try TensorFlow Lite framework",
                priority: .high,
                estimatedDuration: 10.0
            ))

            suggestions.append(RecoverySuggestion(
                action: .switchFramework(.llamaCpp),
                description: "Try LlamaCpp format",
                priority: .medium,
                estimatedDuration: 15.0
            ))
        }

        // For memory errors, suggest lighter frameworks
        let errorType = ErrorType(from: error)
        if errorType == .memory {
            suggestions.append(RecoverySuggestion(
                action: .switchFramework(.llamaCpp),
                description: "Switch to memory-efficient LlamaCpp format",
                priority: .high,
                estimatedDuration: 10.0
            ))

            suggestions.append(RecoverySuggestion(
                action: .reduceQuality,
                description: "Use quantized model version",
                priority: .medium,
                estimatedDuration: 5.0
            ))
        }

        return suggestions
    }

    // MARK: - Private Methods

    private func getAlternativeFrameworks(
        for current: LLMFramework,
        model: ModelInfo,
        resources: ResourceAvailability
    ) -> [LLMFramework] {

        // Get fallback order
        var alternatives = frameworkFallbackOrder[current] ?? []

        // Filter based on model support
        alternatives = alternatives.filter { framework in
            // Check if model supports this framework
            // This is simplified - in real implementation would check model metadata
            return true
        }

        // Filter based on available resources
        if resources.memoryAvailable < 2_000_000_000 { // Less than 2GB
            // Prefer memory-efficient frameworks
            alternatives = alternatives.filter { framework in
                switch framework {
                case .llamaCpp:
                    return true // These are memory efficient
                default:
                    return false
                }
            }
        }

        // Filter based on hardware
        if !resources.acceleratorsAvailable.contains(.neuralEngine) {
            // Remove CoreML if no Neural Engine
            alternatives = alternatives.filter { $0 != .coreML }
        }

        return alternatives
    }
}
