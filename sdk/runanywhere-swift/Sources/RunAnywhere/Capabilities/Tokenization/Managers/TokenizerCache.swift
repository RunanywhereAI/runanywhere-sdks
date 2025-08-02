import Foundation

/// Cache for tokenizer instances with LRU eviction and memory management
class TokenizerCache {
    private struct CacheEntry {
        let tokenizer: UnifiedTokenizer
        var accessCount: Int
        var lastAccessed: Date
        let createdAt: Date
        let estimatedMemoryUsage: Int64

        init(tokenizer: UnifiedTokenizer, estimatedMemoryUsage: Int64 = 10_000_000) {
            self.tokenizer = tokenizer
            self.accessCount = 0
            self.lastAccessed = Date()
            self.createdAt = Date()
            self.estimatedMemoryUsage = estimatedMemoryUsage
        }
    }

    private var cache: [String: CacheEntry] = [:]
    private let lock = NSLock()
    private let logger = SDKLogger(category: "TokenizerCache")

    // Cache configuration
    private var maxCacheSize: Int = 10
    private var maxMemoryUsage: Int64 = 100_000_000 // 100MB
    private var evictionPolicy: EvictionPolicy = .lru

    // Statistics
    private var totalHits: Int = 0
    private var totalMisses: Int = 0
    private var totalEvictions: Int = 0

    enum EvictionPolicy {
        case lru           // Least Recently Used
        case lfu           // Least Frequently Used
        case fifo          // First In, First Out
        case size          // Largest items first
    }

    // MARK: - Configuration

    func configure(maxSize: Int, maxMemory: Int64, policy: EvictionPolicy) {
        lock.lock()
        defer { lock.unlock() }

        maxCacheSize = maxSize
        maxMemoryUsage = maxMemory
        evictionPolicy = policy

        logger.info("Cache configured: max size \(maxSize), max memory \(ByteCountFormatter.string(fromByteCount: maxMemory, countStyle: .memory)), policy \(policy)")

        // Evict if current cache exceeds new limits
        enforceMemoryLimits()
    }

    // MARK: - Cache Operations

    func getTokenizer(for modelId: String) -> UnifiedTokenizer? {
        lock.lock()
        defer { lock.unlock() }

        guard var entry = cache[modelId] else {
            totalMisses += 1
            logger.debug("Cache miss for model: \(modelId)")
            return nil
        }

        // Update access statistics
        entry.accessCount += 1
        entry.lastAccessed = Date()
        cache[modelId] = entry

        totalHits += 1
        logger.debug("Cache hit for model: \(modelId) (access count: \(entry.accessCount))")

        return entry.tokenizer
    }

    func setTokenizer(_ tokenizer: UnifiedTokenizer, for modelId: String) {
        lock.lock()
        defer { lock.unlock() }

        let estimatedMemory = estimateTokenizerMemoryUsage(tokenizer)
        let entry = CacheEntry(tokenizer: tokenizer, estimatedMemoryUsage: estimatedMemory)

        cache[modelId] = entry
        logger.debug("Cached tokenizer for model: \(modelId) (estimated memory: \(ByteCountFormatter.string(fromByteCount: estimatedMemory, countStyle: .memory)))")

        // Evict if necessary
        enforceMemoryLimits()
    }

    func removeTokenizer(for modelId: String) {
        lock.lock()
        defer { lock.unlock() }

        if let _ = cache.removeValue(forKey: modelId) {
            logger.debug("Removed tokenizer from cache: \(modelId)")
        }
    }

    func clearAll() {
        lock.lock()
        defer { lock.unlock() }

        let count = cache.count
        cache.removeAll()
        logger.info("Cleared all \(count) tokenizers from cache")
    }

    // MARK: - Cache Maintenance

    func performCleanup() {
        lock.lock()
        defer { lock.unlock() }

        let initialCount = cache.count
        let cutoffTime = Date().addingTimeInterval(-3600) // 1 hour ago

        // Remove old unused entries
        cache = cache.filter { _, entry in
            entry.lastAccessed > cutoffTime || entry.accessCount > 1
        }

        let removedCount = initialCount - cache.count
        if removedCount > 0 {
            logger.info("Cleanup removed \(removedCount) old tokenizers")
        }

        // Enforce limits after cleanup
        enforceMemoryLimits()
    }

    func evictLeastUsed(count: Int) {
        lock.lock()
        defer { lock.unlock() }

        let sortedEntries = cache.sorted { lhs, rhs in
            switch evictionPolicy {
            case .lru:
                return lhs.value.lastAccessed < rhs.value.lastAccessed
            case .lfu:
                return lhs.value.accessCount < rhs.value.accessCount
            case .fifo:
                return lhs.value.createdAt < rhs.value.createdAt
            case .size:
                return lhs.value.estimatedMemoryUsage > rhs.value.estimatedMemoryUsage
            }
        }

        let toEvict = min(count, sortedEntries.count)
        for i in 0..<toEvict {
            let modelId = sortedEntries[i].key
            cache.removeValue(forKey: modelId)
            totalEvictions += 1
            logger.debug("Evicted tokenizer: \(modelId)")
        }

        if toEvict > 0 {
            logger.info("Evicted \(toEvict) tokenizers based on policy: \(evictionPolicy)")
        }
    }

    // MARK: - Statistics

    func getStatistics() -> TokenizerCacheStatistics {
        lock.lock()
        defer { lock.unlock() }

        let totalMemory = cache.values.reduce(0) { $0 + $1.estimatedMemoryUsage }
        let totalRequests = totalHits + totalMisses
        let hitRate = totalRequests > 0 ? Double(totalHits) / Double(totalRequests) : 0.0

        return TokenizerCacheStatistics(
            count: cache.count,
            estimatedMemoryUsage: totalMemory,
            hitRate: hitRate,
            totalHits: totalHits,
            totalMisses: totalMisses,
            totalEvictions: totalEvictions,
            averageAccessCount: calculateAverageAccessCount(),
            oldestEntry: cache.values.map { $0.createdAt }.min() ?? Date()
        )
    }

    func getCacheEntryInfo() -> [CacheEntryInfo] {
        lock.lock()
        defer { lock.unlock() }

        return cache.map { modelId, entry in
            CacheEntryInfo(
                modelId: modelId,
                accessCount: entry.accessCount,
                lastAccessed: entry.lastAccessed,
                createdAt: entry.createdAt,
                estimatedMemoryUsage: entry.estimatedMemoryUsage,
                tokenizerType: String(describing: type(of: entry.tokenizer))
            )
        }
    }

    // MARK: - Memory Management

    private func enforceMemoryLimits() {
        // Enforce size limit
        while cache.count > maxCacheSize {
            evictOneEntry()
        }

        // Enforce memory limit
        let currentMemory = cache.values.reduce(0) { $0 + $1.estimatedMemoryUsage }
        while currentMemory > maxMemoryUsage && !cache.isEmpty {
            evictOneEntry()
        }
    }

    private func evictOneEntry() {
        let sortedEntries = cache.sorted { lhs, rhs in
            switch evictionPolicy {
            case .lru:
                return lhs.value.lastAccessed < rhs.value.lastAccessed
            case .lfu:
                return lhs.value.accessCount < rhs.value.accessCount
            case .fifo:
                return lhs.value.createdAt < rhs.value.createdAt
            case .size:
                return lhs.value.estimatedMemoryUsage > rhs.value.estimatedMemoryUsage
            }
        }

        if let entryToEvict = sortedEntries.first {
            cache.removeValue(forKey: entryToEvict.key)
            totalEvictions += 1
            logger.debug("Evicted tokenizer due to limits: \(entryToEvict.key)")
        }
    }

    private func estimateTokenizerMemoryUsage(_ tokenizer: UnifiedTokenizer) -> Int64 {
        // Rough estimation based on vocabulary size
        let vocabSize = tokenizer.vocabularySize
        let estimatedBytesPerToken = 50 // Average bytes per token (word + id + metadata)
        return Int64(vocabSize * estimatedBytesPerToken) + 1_000_000 // Base overhead
    }

    private func calculateAverageAccessCount() -> Double {
        guard !cache.isEmpty else { return 0.0 }

        let totalAccesses = cache.values.reduce(0) { $0 + $1.accessCount }
        return Double(totalAccesses) / Double(cache.count)
    }

    // MARK: - Cache Analysis

    func analyzeUsagePatterns() -> CacheUsageAnalysis {
        lock.lock()
        defer { lock.unlock() }

        let entries = Array(cache.values)

        let accessCounts = entries.map { $0.accessCount }
        let lastAccessTimes = entries.map { Date().timeIntervalSince($0.lastAccessed) }

        return CacheUsageAnalysis(
            totalEntries: entries.count,
            averageAccessCount: accessCounts.isEmpty ? 0 : Double(accessCounts.reduce(0, +)) / Double(accessCounts.count),
            maxAccessCount: accessCounts.max() ?? 0,
            averageIdleTime: lastAccessTimes.isEmpty ? 0 : lastAccessTimes.reduce(0, +) / Double(lastAccessTimes.count),
            memorySavings: calculateMemorySavings(),
            recommendations: generateRecommendations()
        )
    }

    private func calculateMemorySavings() -> Int64 {
        // Estimate memory saved by caching vs. recreating tokenizers
        let totalAccesses = cache.values.reduce(0) { $0 + $1.accessCount }
        let totalMemory = cache.values.reduce(0) { $0 + $1.estimatedMemoryUsage }

        // Assume each recreation would cost the full memory amount
        let potentialMemoryUse = Int64(totalAccesses) * (totalMemory / Int64(max(cache.count, 1)))
        return max(0, potentialMemoryUse - totalMemory)
    }

    private func generateRecommendations() -> [String] {
        var recommendations: [String] = []

        let stats = getStatistics()

        if stats.hitRate < 0.5 {
            recommendations.append("Consider increasing cache size - low hit rate (\(String(format: "%.1f%%", stats.hitRate * 100)))")
        }

        if stats.estimatedMemoryUsage > maxMemoryUsage * 8 / 10 {
            recommendations.append("Cache is using \(String(format: "%.1f%%", Double(stats.estimatedMemoryUsage) / Double(maxMemoryUsage) * 100)) of memory limit")
        }

        if stats.count == maxCacheSize {
            recommendations.append("Cache is at maximum size limit")
        }

        return recommendations
    }
}

// MARK: - Data Structures

struct TokenizerCacheStatistics {
    let count: Int
    let estimatedMemoryUsage: Int64
    let hitRate: Double
    let totalHits: Int
    let totalMisses: Int
    let totalEvictions: Int
    let averageAccessCount: Double
    let oldestEntry: Date

    var memoryUsageString: String {
        ByteCountFormatter.string(fromByteCount: estimatedMemoryUsage, countStyle: .memory)
    }

    var hitRatePercentage: String {
        String(format: "%.1f%%", hitRate * 100)
    }
}

struct CacheEntryInfo {
    let modelId: String
    let accessCount: Int
    let lastAccessed: Date
    let createdAt: Date
    let estimatedMemoryUsage: Int64
    let tokenizerType: String

    var age: TimeInterval {
        Date().timeIntervalSince(createdAt)
    }

    var idleTime: TimeInterval {
        Date().timeIntervalSince(lastAccessed)
    }
}

struct CacheUsageAnalysis {
    let totalEntries: Int
    let averageAccessCount: Double
    let maxAccessCount: Int
    let averageIdleTime: TimeInterval
    let memorySavings: Int64
    let recommendations: [String]
}
