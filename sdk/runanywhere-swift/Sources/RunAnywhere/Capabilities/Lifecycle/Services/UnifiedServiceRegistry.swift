import Foundation

/// Registry for managing multiple adapters per service type
public actor UnifiedServiceRegistry {

    /// Wrapper for adapters with priority and metadata
    private struct RegisteredAdapter {
        let adapter: FrameworkAdapter
        let priority: Int
        let registrationDate: Date
    }

    /// Storage: modality -> array of registered adapters
    private var adaptersByModality: [FrameworkModality: [RegisteredAdapter]] = [:]

    /// Legacy storage for backward compatibility: framework -> adapter
    private var adaptersByFramework: [LLMFramework: FrameworkAdapter] = [:]

    public init() {}

    /// Register an adapter with priority
    /// Higher priority = preferred selection (default: 100)
    public func register(_ adapter: FrameworkAdapter, priority: Int = 100) {
        // Store in legacy framework map for backward compatibility
        adaptersByFramework[adapter.framework] = adapter

        // Store by modality with priority
        for modality in adapter.supportedModalities {
            var adapters = adaptersByModality[modality] ?? []

            // Remove existing adapter with same framework to avoid duplicates
            adapters.removeAll { $0.adapter.framework == adapter.framework }

            // Add new adapter
            adapters.append(RegisteredAdapter(
                adapter: adapter,
                priority: priority,
                registrationDate: Date()
            ))

            // Sort by priority (higher first), then by registration date (earlier first)
            adapters.sort { lhs, rhs in
                if lhs.priority != rhs.priority {
                    return lhs.priority > rhs.priority
                }
                return lhs.registrationDate < rhs.registrationDate
            }

            adaptersByModality[modality] = adapters
        }
    }

    /// Get all adapters that can handle a model for a given modality
    public func findAdapters(for model: ModelInfo, modality: FrameworkModality) -> [FrameworkAdapter] {
        guard let registered = adaptersByModality[modality] else {
            return []
        }

        return registered
            .map(\.adapter)
            .filter { $0.canHandle(model: model) }
    }

    /// Find the best adapter for a model based on preferences
    public func findBestAdapter(for model: ModelInfo, modality: FrameworkModality) -> FrameworkAdapter? {
        let adapters = findAdapters(for: model, modality: modality)

        guard !adapters.isEmpty else {
            return nil
        }

        // Priority 1: Preferred framework specified in model
        if let preferred = model.preferredFramework {
            if let match = adapters.first(where: { $0.framework == preferred }) {
                return match
            }
        }

        // Priority 2: Compatible frameworks in order
        for framework in model.compatibleFrameworks {
            if let match = adapters.first(where: { $0.framework == framework }) {
                return match
            }
        }

        // Priority 3: First capable adapter (already sorted by priority)
        return adapters.first
    }

    /// Get adapter by framework (for backward compatibility)
    public func getAdapter(for framework: LLMFramework) -> FrameworkAdapter? {
        return adaptersByFramework[framework]
    }

    /// Get all registered frameworks for a modality
    public func getFrameworks(for modality: FrameworkModality) -> [LLMFramework] {
        guard let registered = adaptersByModality[modality] else {
            return []
        }
        return registered.map { $0.adapter.framework }
    }

    /// Get all registered adapters across all modalities
    public func getAllAdapters() -> [FrameworkAdapter] {
        return Array(adaptersByFramework.values)
    }
}
