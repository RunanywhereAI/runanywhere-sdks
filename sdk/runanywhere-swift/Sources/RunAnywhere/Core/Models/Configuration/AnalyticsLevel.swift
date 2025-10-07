import Foundation

/// Defines the level of analytics data collection
public enum AnalyticsLevel: String, Codable, CaseIterable {
    /// No analytics collection
    case none = "none"

    /// Basic metrics only (counts, success/failure)
    case basic = "basic"

    /// Detailed performance metrics (latency, token counts, memory usage)
    case detailed = "detailed"

    /// Full debug-level analytics (includes internal state, detailed traces)
    case verbose = "verbose"

    /// Human-readable description of the analytics level
    public var description: String {
        switch self {
        case .none:
            return "No analytics collection"
        case .basic:
            return "Basic metrics only"
        case .detailed:
            return "Detailed performance metrics"
        case .verbose:
            return "Full debug-level analytics"
        }
    }

    /// Whether this level includes basic metrics
    public var includesBasicMetrics: Bool {
        self != .none
    }

    /// Whether this level includes performance metrics
    public var includesPerformanceMetrics: Bool {
        self == .detailed || self == .verbose
    }

    /// Whether this level includes debug information
    public var includesDebugInfo: Bool {
        self == .verbose
    }

    /// Whether this level includes generation metrics
    public var includesGenerationMetrics: Bool {
        self != .none
    }

    /// Whether this level includes memory tracking
    public var includesMemoryTracking: Bool {
        self == .detailed || self == .verbose
    }

    /// Whether this level includes cost tracking
    public var includesCostTracking: Bool {
        self != .none
    }
}
