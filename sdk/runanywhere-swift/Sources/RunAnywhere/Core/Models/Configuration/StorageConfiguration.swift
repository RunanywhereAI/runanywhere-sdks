import Foundation

/// Configuration for storage behavior
public struct StorageConfiguration: Codable {
    /// Maximum cache size in bytes
    public var maxCacheSize: Int64

    /// Cache eviction policy
    public var evictionPolicy: CacheEvictionPolicy

    /// Storage directory name
    public var directoryName: String

    /// Whether to enable automatic cleanup
    public var enableAutoCleanup: Bool

    /// Auto cleanup interval in seconds
    public var autoCleanupInterval: TimeInterval

    /// Minimum free space to maintain (in bytes)
    public var minimumFreeSpace: Int64

    /// Whether to compress stored models
    public var enableCompression: Bool

    public init(
        maxCacheSize: Int64 = 1_073_741_824, // 1GB
        evictionPolicy: CacheEvictionPolicy = .leastRecentlyUsed,
        directoryName: String = "RunAnywhere",
        enableAutoCleanup: Bool = true,
        autoCleanupInterval: TimeInterval = 86400, // 24 hours
        minimumFreeSpace: Int64 = 500_000_000, // 500MB
        enableCompression: Bool = false
    ) {
        self.maxCacheSize = maxCacheSize
        self.evictionPolicy = evictionPolicy
        self.directoryName = directoryName
        self.enableAutoCleanup = enableAutoCleanup
        self.autoCleanupInterval = autoCleanupInterval
        self.minimumFreeSpace = minimumFreeSpace
        self.enableCompression = enableCompression
    }
}

/// Cache eviction policy
public enum CacheEvictionPolicy: String, Codable, CaseIterable {
    /// Least recently used items are evicted first
    case leastRecentlyUsed = "lru"

    /// Least frequently used items are evicted first
    case leastFrequentlyUsed = "lfu"

    /// First in, first out
    case fifo = "fifo"

    /// Largest items are evicted first
    case largestFirst = "largest_first"

    public var description: String {
        switch self {
        case .leastRecentlyUsed:
            return "Least Recently Used"
        case .leastFrequentlyUsed:
            return "Least Frequently Used"
        case .fifo:
            return "First In, First Out"
        case .largestFirst:
            return "Largest First"
        }
    }
}
