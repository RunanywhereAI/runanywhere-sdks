//
//  ModelLifecycleEvent.swift
//  RunAnywhere SDK
//
//  Events published during model lifecycle changes
//

import Foundation

/// Events published when model lifecycle state changes
/// Subscribe to these events for real-time updates on model loading/unloading
public enum ModelLifecycleEvent: Sendable {

    // MARK: - Loading Events

    /// Model is about to start loading
    case willLoad(modelId: String, modality: Modality)

    /// Model loading progress update (0.0 to 1.0)
    case loadProgress(modelId: String, modality: Modality, progress: Double)

    /// Model finished loading successfully
    case didLoad(modelId: String, modality: Modality, framework: LLMFramework)

    /// Model loading failed with an error
    case loadFailed(modelId: String, modality: Modality, error: String)

    // MARK: - Unloading Events

    /// Model is about to start unloading
    case willUnload(modelId: String, modality: Modality)

    /// Model finished unloading
    case didUnload(modelId: String, modality: Modality)

    // MARK: - Memory Events

    /// Memory pressure detected, may need to unload models
    case memoryPressure(availableBytes: Int64)

    /// Model memory usage updated
    case memoryUsageUpdated(modelId: String, bytes: Int64)

    // MARK: - Convenience Properties

    /// Get the model ID from any event
    public var modelId: String {
        switch self {
        case .willLoad(let modelId, _),
             .loadProgress(let modelId, _, _),
             .didLoad(let modelId, _, _),
             .loadFailed(let modelId, _, _),
             .willUnload(let modelId, _),
             .didUnload(let modelId, _),
             .memoryUsageUpdated(let modelId, _):
            return modelId
        case .memoryPressure:
            return ""
        }
    }

    /// Get the modality from any event (if applicable)
    public var modality: Modality? {
        switch self {
        case .willLoad(_, let modality),
             .loadProgress(_, let modality, _),
             .didLoad(_, let modality, _),
             .loadFailed(_, let modality, _),
             .willUnload(_, let modality),
             .didUnload(_, let modality):
            return modality
        case .memoryPressure, .memoryUsageUpdated:
            return nil
        }
    }

    /// Check if this is a loading event
    public var isLoadingEvent: Bool {
        switch self {
        case .willLoad, .loadProgress, .didLoad, .loadFailed:
            return true
        default:
            return false
        }
    }

    /// Check if this is an unloading event
    public var isUnloadingEvent: Bool {
        switch self {
        case .willUnload, .didUnload:
            return true
        default:
            return false
        }
    }

    /// Check if this is a success event
    public var isSuccess: Bool {
        switch self {
        case .didLoad, .didUnload:
            return true
        default:
            return false
        }
    }

    /// Check if this is a failure event
    public var isFailure: Bool {
        switch self {
        case .loadFailed:
            return true
        default:
            return false
        }
    }

    /// Human-readable description of the event
    public var description: String {
        switch self {
        case .willLoad(let modelId, let modality):
            return "Model '\(modelId)' (\(modality.displayName)) will start loading"
        case .loadProgress(let modelId, let modality, let progress):
            return "Model '\(modelId)' (\(modality.displayName)) loading: \(Int(progress * 100))%"
        case .didLoad(let modelId, let modality, let framework):
            return "Model '\(modelId)' (\(modality.displayName)) loaded with \(framework.rawValue)"
        case .loadFailed(let modelId, let modality, let error):
            return "Model '\(modelId)' (\(modality.displayName)) failed to load: \(error)"
        case .willUnload(let modelId, let modality):
            return "Model '\(modelId)' (\(modality.displayName)) will start unloading"
        case .didUnload(let modelId, let modality):
            return "Model '\(modelId)' (\(modality.displayName)) unloaded"
        case .memoryPressure(let available):
            return "Memory pressure detected, \(ByteCountFormatter.string(fromByteCount: available, countStyle: .memory)) available"
        case .memoryUsageUpdated(let modelId, let bytes):
            return "Model '\(modelId)' memory usage: \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory))"
        }
    }
}
