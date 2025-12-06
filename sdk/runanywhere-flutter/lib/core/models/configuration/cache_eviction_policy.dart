/// Cache eviction policy.
/// Matches iOS CacheEvictionPolicy from Configuration/StorageConfiguration.swift
enum CacheEvictionPolicy {
  /// Least recently used items are evicted first
  leastRecentlyUsed('lru', 'Least Recently Used'),

  /// Least frequently used items are evicted first
  leastFrequentlyUsed('lfu', 'Least Frequently Used'),

  /// First in, first out
  fifo('fifo', 'First In, First Out'),

  /// Largest items are evicted first
  largestFirst('largest_first', 'Largest First');

  final String rawValue;
  final String description;

  const CacheEvictionPolicy(this.rawValue, this.description);

  /// Create from raw string value
  static CacheEvictionPolicy? fromRawValue(String value) {
    return CacheEvictionPolicy.values.cast<CacheEvictionPolicy?>().firstWhere(
          (p) => p?.rawValue == value,
          orElse: () => null,
        );
  }
}
