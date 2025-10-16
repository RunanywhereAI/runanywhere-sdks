import Foundation

/// Strategy for selecting the best adapter from multiple candidates
public protocol AdapterSelectionStrategy {
    func selectAdapter(
        from candidates: [UnifiedFrameworkAdapter],
        for model: ModelInfo,
        modality: FrameworkModality
    ) -> UnifiedFrameworkAdapter?
}

/// Default strategy: Prefer model's preferredFramework, then compatible frameworks
public struct DefaultAdapterSelectionStrategy: AdapterSelectionStrategy {

    public init() {}

    public func selectAdapter(
        from candidates: [UnifiedFrameworkAdapter],
        for model: ModelInfo,
        modality: FrameworkModality
    ) -> UnifiedFrameworkAdapter? {

        guard !candidates.isEmpty else {
            return nil
        }

        // Priority 1: Preferred framework from model
        if let preferred = model.preferredFramework {
            if let match = candidates.first(where: { $0.framework == preferred }) {
                return match
            }
        }

        // Priority 2: Compatible frameworks in order
        for framework in model.compatibleFrameworks {
            if let match = candidates.first(where: { $0.framework == framework }) {
                return match
            }
        }

        // Priority 3: First capable adapter
        return candidates.first
    }
}

/// Pattern-based strategy: Select adapter based on model ID patterns
public struct PatternBasedAdapterSelectionStrategy: AdapterSelectionStrategy {

    private let patterns: [String: LLMFramework]

    /// Initialize with patterns mapping model ID substrings to frameworks
    /// Example: ["whisper": .whisperKit, "moonshine": .moonshine]
    public init(patterns: [String: LLMFramework]) {
        self.patterns = patterns
    }

    public func selectAdapter(
        from candidates: [UnifiedFrameworkAdapter],
        for model: ModelInfo,
        modality: FrameworkModality
    ) -> UnifiedFrameworkAdapter? {

        guard !candidates.isEmpty else {
            return nil
        }

        // Check patterns in model ID
        let modelIdLower = model.id.lowercased()
        for (pattern, framework) in patterns {
            if modelIdLower.contains(pattern.lowercased()) {
                if let match = candidates.first(where: { $0.framework == framework }) {
                    return match
                }
            }
        }

        // Fallback to default strategy
        return DefaultAdapterSelectionStrategy().selectAdapter(
            from: candidates,
            for: model,
            modality: modality
        )
    }
}

/// Explicit framework strategy: Always prefer a specific framework
public struct ExplicitFrameworkStrategy: AdapterSelectionStrategy {

    private let preferredFramework: LLMFramework

    public init(preferredFramework: LLMFramework) {
        self.preferredFramework = preferredFramework
    }

    public func selectAdapter(
        from candidates: [UnifiedFrameworkAdapter],
        for model: ModelInfo,
        modality: FrameworkModality
    ) -> UnifiedFrameworkAdapter? {

        // Try to find preferred framework
        if let match = candidates.first(where: { $0.framework == preferredFramework }) {
            return match
        }

        // Fallback to first available
        return candidates.first
    }
}
