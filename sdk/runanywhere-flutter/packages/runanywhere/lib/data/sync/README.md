# Sync Infrastructure

This module provides centralized sync coordination for synchronizing data between local storage and remote API.

## Overview

The sync infrastructure matches the iOS SDK's `SyncCoordinator` pattern, adapted for Flutter using Dart Streams for reactive state updates instead of iOS's AsyncSequence.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   SyncCoordinator                       │
│  - Manages sync operations                             │
│  - Tracks sync state                                   │
│  - Emits progress updates                              │
└───────────────────┬─────────────────────────────────────┘
                    │
        ┌───────────┴───────────┐
        ↓                       ↓
┌───────────────────┐   ┌──────────────────┐
│   Repository      │   │  RemoteDataSource│
│   - CRUD ops      │   │  - API calls     │
│   - Sync support  │   │  - Batch sync    │
└───────────────────┘   └──────────────────┘
        │
        ↓
┌───────────────────┐
│ RepositoryEntity  │
│ - markUpdated()   │
│ - markSynced()    │
└───────────────────┘
```

## Key Components

### SyncCoordinator
- **Purpose**: Centralized coordinator for all sync operations
- **Pattern**: Matches iOS actor pattern (thread-safe with async/await)
- **Features**:
  - Generic sync method for any repository
  - Batch processing (100 items per batch)
  - Auto-sync timer (5-minute intervals)
  - Progress tracking via Stream
  - Conflict resolution via remote data source

### Models

#### SyncState
- `idle` - Not currently syncing
- `syncing` - Sync in progress
- `synced` - Sync completed successfully
- `error` - Sync failed

#### SyncProgress
- Entity type being synced
- Current sync state
- Total/synced/failed item counts
- Error message (if applicable)
- Progress percentage

### Protocols

#### RepositoryEntity
- Base protocol for syncable entities
- Required fields: `id`, `createdAt`, `updatedAt`, `syncPending`
- Methods: `markUpdated()`, `markSynced()`

#### Repository
- CRUD operations
- Sync support methods
- Reference to RemoteDataSource

#### DataSource
- Base protocol for data sources
- LocalDataSource - local storage operations
- RemoteDataSource - API operations with batch sync

## Usage

### Basic Sync
```dart
final syncCoordinator = SyncCoordinator();
await syncCoordinator.sync(myRepository);
```

### With Progress Tracking
```dart
syncCoordinator.progressStream.listen((progress) {
  print('${progress.entityType}: ${progress.syncedItems}/${progress.totalItems}');
});

await syncCoordinator.sync(myRepository);
```

### Auto-Sync
```dart
final syncCoordinator = SyncCoordinator(enableAutoSync: true);
// Syncs automatically every 5 minutes
```

### Check Sync Status
```dart
if (syncCoordinator.isSyncing<MyEntity>()) {
  print('Sync in progress');
}
```

## Implementation Details

### Batch Processing
- Default batch size: 100 items
- Processes pending items in chunks
- Tracks success/failure per batch
- Continues on partial failures

### Progress Updates
- Emitted via broadcast Stream
- Real-time updates during sync
- Final state on completion
- Error state on failure

### Error Handling
- Failed items tracked separately
- Sync continues despite batch failures
- Errors logged via SDKLogger
- Can retry failed items later

## Comparison with iOS

| Feature | iOS | Flutter |
|---------|-----|---------|
| Concurrency | Actor | Async/Await |
| State Updates | N/A | Stream |
| Batch Size | 100 | 100 |
| Auto-Sync Interval | 5 min | 5 min |
| Type Safety | Generics | Generics |
| Error Tracking | Logs | Logs + Progress |

## Files

```
sync/
├── models/
│   ├── sync_state.dart          # Sync state enum
│   ├── sync_progress.dart       # Progress model
│   └── models.dart              # Barrel file
├── sync_coordinator.dart        # Main coordinator
├── sync.dart                    # Public exports
├── USAGE_EXAMPLE.md            # Detailed usage guide
└── README.md                    # This file
```

## Integration

The sync infrastructure integrates with existing repositories like `TelemetryRepository`:

```dart
// TelemetryRepository already implements Repository protocol
final telemetryRepo = TelemetryRepository.withShared(
  remoteDataSource: remoteTelemetryDataSource,
);

// Sync telemetry data
await syncCoordinator.sync(telemetryRepo);
```

## Next Steps

To implement sync for a new entity type:

1. Make entity implement `RepositoryEntity`
2. Create `RemoteDataSource` with `syncBatch()` method
3. Create `Repository` with local and remote data sources
4. Call `syncCoordinator.sync(repository)`

See `USAGE_EXAMPLE.md` for complete implementation examples.

## References

- iOS Implementation: `sdk/runanywhere-swift/Sources/RunAnywhere/Data/Sync/SyncCoordinator.swift`
- Example Repository: `lib/infrastructure/analytics/repositories/telemetry_repository.dart`
- Example Entity: `lib/infrastructure/analytics/models/domain/telemetry_data.dart`
