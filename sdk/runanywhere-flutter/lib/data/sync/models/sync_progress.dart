//
//  sync_progress.dart
//  RunAnywhere SDK
//
//  Progress information for a sync operation
//

import 'package:runanywhere/data/sync/models/sync_state.dart';

/// Progress information for a sync operation
class SyncProgress {
  /// Entity type being synced
  final String entityType;

  /// Current sync state
  final SyncState state;

  /// Total number of items to sync
  final int totalItems;

  /// Number of items successfully synced
  final int syncedItems;

  /// Number of items that failed to sync
  final int failedItems;

  /// Error message if sync failed
  final String? errorMessage;

  const SyncProgress({
    required this.entityType,
    required this.state,
    required this.totalItems,
    required this.syncedItems,
    required this.failedItems,
    this.errorMessage,
  });

  /// Create an idle sync progress
  factory SyncProgress.idle(String entityType) {
    return SyncProgress(
      entityType: entityType,
      state: SyncState.idle,
      totalItems: 0,
      syncedItems: 0,
      failedItems: 0,
    );
  }

  /// Create a syncing progress
  factory SyncProgress.syncing(
    String entityType, {
    required int totalItems,
    int syncedItems = 0,
    int failedItems = 0,
  }) {
    return SyncProgress(
      entityType: entityType,
      state: SyncState.syncing,
      totalItems: totalItems,
      syncedItems: syncedItems,
      failedItems: failedItems,
    );
  }

  /// Create a completed sync progress
  factory SyncProgress.completed(
    String entityType, {
    required int totalItems,
    required int syncedItems,
    required int failedItems,
  }) {
    return SyncProgress(
      entityType: entityType,
      state: SyncState.synced,
      totalItems: totalItems,
      syncedItems: syncedItems,
      failedItems: failedItems,
    );
  }

  /// Create an error sync progress
  factory SyncProgress.error(
    String entityType, {
    required String errorMessage,
    int totalItems = 0,
    int syncedItems = 0,
    int failedItems = 0,
  }) {
    return SyncProgress(
      entityType: entityType,
      state: SyncState.error,
      totalItems: totalItems,
      syncedItems: syncedItems,
      failedItems: failedItems,
      errorMessage: errorMessage,
    );
  }

  /// Get sync progress as a percentage (0.0 to 1.0)
  double get progressPercentage {
    if (totalItems == 0) return 0.0;
    return syncedItems / totalItems;
  }

  /// Check if sync is complete
  bool get isComplete => syncedItems + failedItems >= totalItems;

  /// Copy with updated fields
  SyncProgress copyWith({
    String? entityType,
    SyncState? state,
    int? totalItems,
    int? syncedItems,
    int? failedItems,
    String? errorMessage,
  }) {
    return SyncProgress(
      entityType: entityType ?? this.entityType,
      state: state ?? this.state,
      totalItems: totalItems ?? this.totalItems,
      syncedItems: syncedItems ?? this.syncedItems,
      failedItems: failedItems ?? this.failedItems,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  String toString() {
    return 'SyncProgress(entityType: $entityType, state: $state, '
        'progress: $syncedItems/$totalItems, failed: $failedItems)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SyncProgress &&
        other.entityType == entityType &&
        other.state == state &&
        other.totalItems == totalItems &&
        other.syncedItems == syncedItems &&
        other.failedItems == failedItems &&
        other.errorMessage == errorMessage;
  }

  @override
  int get hashCode => Object.hash(
        entityType,
        state,
        totalItems,
        syncedItems,
        failedItems,
        errorMessage,
      );
}
