import Foundation
import os

/// Thread-safe cache for model information
/// Providers check model metadata when determining if they can handle a model
/// Uses OSAllocatedUnfairLock for efficient synchronous access from any thread
public final class ModelInfoCache: Sendable {
    public static let shared = ModelInfoCache()

    private let state: OSAllocatedUnfairLock<[String: ModelInfo]>

    private init() {
        state = OSAllocatedUnfairLock(initialState: [:])
    }

    public func cacheModels(_ models: [ModelInfo]) {
        state.withLock { cache in
            for model in models {
                cache[model.id] = model
            }
        }
    }

    public func modelInfo(for modelId: String) -> ModelInfo? {
        state.withLock { $0[modelId] }
    }

    public func clear() {
        state.withLock { $0.removeAll() }
    }

    public func contains(_ modelId: String) -> Bool {
        state.withLock { $0[modelId] != nil }
    }
}
