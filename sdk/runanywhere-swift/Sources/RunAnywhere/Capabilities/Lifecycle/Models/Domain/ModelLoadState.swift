//
//  ModelLoadState.swift
//  RunAnywhere SDK
//
//  Represents the current loading state of a model
//

import Foundation

/// Represents the current state of a model in the lifecycle
public enum ModelLoadState: Equatable, Sendable {
    /// Model is not loaded
    case notLoaded

    /// Model is currently loading with progress (0.0 to 1.0)
    case loading(progress: Double)

    /// Model is fully loaded and ready for use
    case loaded

    /// Model is currently being unloaded
    case unloading

    /// Model failed to load with an error message
    case error(String)

    // MARK: - Convenience Properties

    /// Check if the model is fully loaded
    public var isLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }

    /// Check if the model is currently loading
    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    /// Check if the model is currently unloading
    public var isUnloading: Bool {
        if case .unloading = self { return true }
        return false
    }

    /// Check if the model is in an error state
    public var hasError: Bool {
        if case .error = self { return true }
        return false
    }

    /// Get the loading progress (0.0 to 1.0), or nil if not loading
    public var loadingProgress: Double? {
        if case .loading(let progress) = self {
            return progress
        }
        return nil
    }

    /// Get the error message if in error state
    public var errorMessage: String? {
        if case .error(let message) = self {
            return message
        }
        return nil
    }

    /// Human-readable description of the state
    public var displayName: String {
        switch self {
        case .notLoaded:
            return "Not Loaded"
        case .loading(let progress):
            return "Loading (\(Int(progress * 100))%)"
        case .loaded:
            return "Loaded"
        case .unloading:
            return "Unloading"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    // MARK: - Equatable

    public static func == (lhs: ModelLoadState, rhs: ModelLoadState) -> Bool {
        switch (lhs, rhs) {
        case (.notLoaded, .notLoaded): return true
        case (.loading(let p1), .loading(let p2)): return p1 == p2
        case (.loaded, .loaded): return true
        case (.unloading, .unloading): return true
        case (.error(let e1), .error(let e2)): return e1 == e2
        default: return false
        }
    }
}
