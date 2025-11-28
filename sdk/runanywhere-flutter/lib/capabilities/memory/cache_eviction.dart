import 'allocation_manager.dart';
import 'memory_service.dart';

/// Selects models to evict based on memory pressure
class CacheEviction {
  /// Select models to evict to free up target memory
  List<String> selectModelsToEvict({
    required int targetMemory,
    required AllocationManager allocationManager,
  }) {
    // Access allocations through a public method
    final allocations = allocationManager.getAllocations();
    final sorted = allocations.entries.toList()
      ..sort((a, b) {
        // Sort by priority first, then by last access
        final priorityCompare = a.value.priority.index.compareTo(b.value.priority.index);
        if (priorityCompare != 0) return priorityCompare;
        return a.value.lastAccess.compareTo(b.value.lastAccess);
      });

    final evictable = <String>[];
    int freed = 0;

    for (final entry in sorted) {
      if (entry.value.priority == MemoryPriority.low || freed < targetMemory) {
        evictable.add(entry.key);
        freed += entry.value.size;
        if (freed >= targetMemory) break;
      }
    }

    return evictable;
  }
}

