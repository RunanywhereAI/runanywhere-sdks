//
//  sync_state.dart
//  RunAnywhere SDK
//
//  State of a sync operation
//

/// State of a sync operation
enum SyncState {
  /// Not currently syncing
  idle,

  /// Sync operation in progress
  syncing,

  /// Sync completed successfully
  synced,

  /// Sync failed with error
  error;

  /// Check if sync is in progress
  bool get isSyncing => this == SyncState.syncing;

  /// Check if sync is idle
  bool get isIdle => this == SyncState.idle;

  /// Check if sync completed successfully
  bool get isSynced => this == SyncState.synced;

  /// Check if sync failed
  bool get hasError => this == SyncState.error;
}
