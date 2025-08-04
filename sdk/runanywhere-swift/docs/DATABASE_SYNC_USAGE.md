# Database & Sync Integration Usage Guide

This guide shows how to use the new database and sync integration in the RunAnywhere Swift SDK.

## Overview

The new database sync integration provides:
- Local SQLite storage for all SDK data
- Automatic background sync with the cloud
- Repository pattern for clean data access
- Support for offline operation

## Basic Usage

### Accessing the Data Sync Service

```swift
// Get the data sync service from the SDK
if let dataSyncService = await ServiceContainer.shared.dataSyncService {
    // Use the service
}
```

### Saving Configuration

```swift
// Save configuration settings
let settings = [
    "model_id": "gpt-4",
    "temperature": "0.7",
    "max_tokens": "1000"
]

try await dataSyncService.saveConfiguration(settings)
```

### Tracking Telemetry Events

```swift
// Track an event
try await dataSyncService.trackEvent(
    "model_loaded",
    properties: [
        "model_id": "gpt-4",
        "load_time": "1.2"
    ]
)
```

### Manual Sync

```swift
// Manually trigger sync
try await dataSyncService.syncAll()
```

## Architecture

### Repository Pattern

Each data type has its own repository:
- `ConfigurationRepository` - SDK configuration
- `TelemetryRepository` - Usage telemetry
- More repositories can be added following the same pattern

### Database Layer

- Uses SQLite for local storage
- All data is stored as JSON in a simple schema
- Automatic table creation on first use

### Sync Layer

- Automatic sync every 5 minutes
- Batch sync for telemetry (50 events at a time)
- Immediate sync for configuration changes
- Graceful handling of offline scenarios

## Adding New Data Types

To add a new data type:

1. Create a model conforming to `RepositoryEntity`:
```swift
struct MyData: RepositoryEntity {
    let id: String
    let value: String
    let updatedAt: Date
    let syncPending: Bool
}
```

2. Create a repository:
```swift
actor MyDataRepository: Repository {
    typealias Entity = MyData
    // Implement required methods
}
```

3. Add to DataSyncService:
```swift
private let myDataRepository: MyDataRepository

public func saveMyData(_ data: MyData) async throws {
    try await myDataRepository.save(data)
}
```

## Available Operations

### Model Metadata Operations

```swift
// Save model metadata
try await dataSyncService.saveModelMetadata(model)

// Update last used date
try await dataSyncService.updateModelLastUsed(for: modelId)

// Update thinking support
try await dataSyncService.updateThinkingSupport(
    for: modelId,
    supportsThinking: true,
    thinkingTagPattern: pattern
)

// Load stored models
let models = try await dataSyncService.loadStoredModels()

// Remove model metadata
try await dataSyncService.removeModelMetadata(modelId)
```

## Best Practices

1. **Always handle errors** - Database operations can fail
2. **Use async/await** - All operations are asynchronous
3. **Don't rely on immediate sync** - Data may be synced later
4. **Keep data models simple** - Complex nested objects increase complexity

## Troubleshooting

### Database Not Initialized
- Ensure the SDK is properly initialized
- Check file system permissions

### Sync Not Working
- Verify API key is configured
- Check network connectivity
- Look for sync errors in logs

### Data Not Persisting
- Ensure you're awaiting async operations
- Check for save errors
- Verify database file exists
