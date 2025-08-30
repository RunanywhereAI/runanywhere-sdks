import Foundation

/// Simple LRU cache for extracted metadata
public class MetadataCache {

    // MARK: - Properties

    private var cache: [URL: (metadata: ModelMetadata, timestamp: Date)] = [:]
    private let cacheTimeout: TimeInterval = 3600 // 1 hour
    private let maxCacheSize = 100
    private let lock = NSLock()
    private let logger = SDKLogger(category: "MetadataCache")

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Gets cached metadata for a URL
    /// - Parameter url: The URL to get metadata for
    /// - Returns: The cached metadata, or nil if not found or expired
    public func get(for url: URL) -> ModelMetadata? {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = cache[url] else {
            logger.debug("Cache miss for: \(url.lastPathComponent)")
            return nil
        }

        // Check if cache is still valid
        if Date().timeIntervalSince(entry.timestamp) > cacheTimeout {
            logger.debug("Cache expired for: \(url.lastPathComponent)")
            cache.removeValue(forKey: url)
            return nil
        }

        logger.debug("Cache hit for: \(url.lastPathComponent)")
        return entry.metadata
    }

    /// Stores metadata in the cache
    /// - Parameters:
    ///   - metadata: The metadata to cache
    ///   - url: The URL to associate with the metadata
    public func store(_ metadata: ModelMetadata, for url: URL) {
        lock.lock()
        defer { lock.unlock() }

        // Implement simple LRU eviction if cache is full
        if cache.count >= maxCacheSize {
            evictOldestEntry()
        }

        cache[url] = (metadata, Date())
        logger.debug("Cached metadata for: \(url.lastPathComponent)")
    }

    /// Clears all cached metadata
    public func clear() {
        lock.lock()
        defer { lock.unlock() }

        let count = cache.count
        cache.removeAll()
        logger.info("Cleared \(count) cached entries")
    }

    /// Removes expired entries from the cache
    public func cleanupExpired() {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        var expiredKeys: [URL] = []

        for (key, entry) in cache {
            if now.timeIntervalSince(entry.timestamp) > cacheTimeout {
                expiredKeys.append(key)
            }
        }

        for key in expiredKeys {
            cache.removeValue(forKey: key)
        }

        if !expiredKeys.isEmpty {
            logger.info("Removed \(expiredKeys.count) expired entries")
        }
    }

    // MARK: - Private Methods

    private func evictOldestEntry() {
        guard let oldestEntry = cache.min(by: { $0.value.timestamp < $1.value.timestamp }) else {
            return
        }

        cache.removeValue(forKey: oldestEntry.key)
        logger.debug("Evicted oldest entry: \(oldestEntry.key.lastPathComponent)")
    }
}
