import Foundation

/// Registry for voice framework adapters
internal protocol VoiceAdapterRegistry {
    func register(_ adapter: VoiceFrameworkAdapter)
    func getAdapter(for framework: LLMFramework) -> VoiceFrameworkAdapter?
    func findBestAdapter(for model: ModelInfo) -> VoiceFrameworkAdapter?
    func getAvailableVoiceFrameworks() -> [LLMFramework]
}

/// Implementation of voice adapter registry
internal class VoiceAdapterRegistryImpl: VoiceAdapterRegistry {

    // MARK: - Properties

    private var adapters: [LLMFramework: VoiceFrameworkAdapter] = [:]
    private let queue = DispatchQueue(label: "com.runanywhere.voice.adapter.registry", attributes: .concurrent)

    // MARK: - VoiceAdapterRegistry Implementation

    func register(_ adapter: VoiceFrameworkAdapter) {
        queue.async(flags: .barrier) {
            self.adapters[adapter.framework] = adapter
        }
    }

    func getAdapter(for framework: LLMFramework) -> VoiceFrameworkAdapter? {
        return queue.sync {
            return adapters[framework]
        }
    }

    func findBestAdapter(for model: ModelInfo) -> VoiceFrameworkAdapter? {
        return queue.sync {
            // Try to find adapter based on compatible frameworks
            for framework in model.compatibleFrameworks {
                if let adapter = adapters[framework], adapter.canHandle(model: model) {
                    return adapter
                }
            }

            // Try to find adapter based on architecture
            if model.architecture == .whisper {
                // Find any adapter that supports whisper models
                for adapter in adapters.values {
                    if adapter.canHandle(model: model) {
                        return adapter
                    }
                }
            }

            return nil
        }
    }

    func getAvailableVoiceFrameworks() -> [LLMFramework] {
        return queue.sync {
            return Array(adapters.keys)
        }
    }
}
