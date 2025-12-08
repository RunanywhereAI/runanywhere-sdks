# Data Module - Complete File Analysis

**Analysis Date:** December 7, 2025
**SDK Version:** 0.15.8
**Total Files Analyzed:** 51

---

## Overview

The Data module provides the complete data layer for the RunAnywhere Swift SDK, organized into 8 subdirectories:

| Subdirectory | Files | Description |
|--------------|-------|-------------|
| DataSources/ | 6 | Local and remote data source abstractions |
| Models/ | 7 | Data transfer objects and domain models |
| Network/ | 11 | HTTP client, download services, API endpoints |
| Protocols/ | 5 | Repository and data source protocols |
| Repositories/ | 8 | Repository implementations with caching |
| Services/ | 6 | Business logic services |
| Storage/ | 5 | GRDB database and file storage |
| Sync/ | 3 | Data synchronization services |

---

## DataSources/ (6 files)

### `DataSources/Local/LocalModelDataSource.swift`

**Role / Responsibility**
- Provides local storage operations for model metadata
- Implements caching and retrieval of model information
- Bridges to GRDB database layer

**Key Types**
- `LocalModelDataSource` (class) – Local model data operations
- `LocalModelDataSourceProtocol` (protocol) – Interface for local data operations

**Key Public APIs**
- `func getModel(byId id: String) async throws -> ModelInfo?`
- `func saveModel(_ model: ModelInfo) async throws`
- `func deleteModel(byId id: String) async throws`
- `func getAllModels() async throws -> [ModelInfo]`

**Dependencies**
- Internal: Storage/DatabaseManager, Models/ModelInfo
- External: GRDB

---

### `DataSources/Local/LocalConfigDataSource.swift`

**Role / Responsibility**
- Manages local configuration storage
- Provides caching for SDK configuration values
- Handles configuration versioning

**Key Types**
- `LocalConfigDataSource` (class) – Configuration storage operations

**Key Public APIs**
- `func getConfiguration() async throws -> SDKConfiguration?`
- `func saveConfiguration(_ config: SDKConfiguration) async throws`
- `func clearConfiguration() async throws`

---

### `DataSources/Remote/RemoteModelDataSource.swift`

**Role / Responsibility**
- Fetches model information from remote API
- Handles API authentication and error mapping
- Converts API responses to domain models

**Key Types**
- `RemoteModelDataSource` (class) – Remote model API client
- `RemoteModelDataSourceProtocol` (protocol) – Interface for remote operations

**Key Public APIs**
- `func fetchAvailableModels() async throws -> [ModelInfo]`
- `func fetchModelDetails(modelId: String) async throws -> ModelInfo`
- `func checkModelUpdates(since: Date) async throws -> [ModelUpdate]`

**Dependencies**
- Internal: Network/APIClient, Models/ModelInfo
- External: Foundation

---

### `DataSources/Remote/RemoteConfigDataSource.swift`

**Role / Responsibility**
- Fetches SDK configuration from remote server
- Handles configuration versioning and caching headers
- Maps API responses to configuration models

**Key Types**
- `RemoteConfigDataSource` (class) – Remote configuration fetcher

**Key Public APIs**
- `func fetchConfiguration() async throws -> SDKConfiguration`
- `func checkConfigurationVersion() async throws -> String`

---

### `DataSources/Cache/ModelCacheDataSource.swift`

**Role / Responsibility**
- Manages in-memory model cache
- Provides LRU eviction policy
- Tracks cache hits/misses for analytics

**Key Types**
- `ModelCacheDataSource` (class) – In-memory model caching
- `CacheEntry<T>` (struct) – Generic cache entry with TTL

**Key Public APIs**
- `func get(modelId: String) -> ModelInfo?`
- `func set(_ model: ModelInfo, ttl: TimeInterval)`
- `func invalidate(modelId: String)`
- `func clear()`

**Important Internal Logic**
- Default TTL: 5 minutes
- Maximum cache size: 100 entries
- LRU eviction when cache is full

---

### `DataSources/Cache/ConfigCacheDataSource.swift`

**Role / Responsibility**
- Caches SDK configuration in memory
- Handles cache invalidation on version changes

**Key Types**
- `ConfigCacheDataSource` (class) – Configuration caching

---

## Models/ (7 files)

### `Models/APIModels/ModelAPIResponse.swift`

**Role / Responsibility**
- Defines API response structures for model endpoints
- Provides Codable conformance for JSON parsing

**Key Types**
- `ModelListResponse` (struct) – Response for model list endpoint
- `ModelDetailResponse` (struct) – Response for model detail endpoint
- `ModelDownloadResponse` (struct) – Response for download URL endpoint

---

### `Models/APIModels/ConfigAPIResponse.swift`

**Role / Responsibility**
- Defines API response structures for configuration endpoints

**Key Types**
- `ConfigurationResponse` (struct) – Remote configuration response
- `FeatureFlagsResponse` (struct) – Feature flags from server

---

### `Models/DTOs/ModelDTO.swift`

**Role / Responsibility**
- Data Transfer Object for model information
- Maps between API responses and domain models

**Key Types**
- `ModelDTO` (struct) – Model data transfer object
- `ModelCapabilityDTO` (struct) – Model capability representation

**Key Public APIs**
- `func toDomain() -> ModelInfo` – Converts to domain model
- `static func from(_ model: ModelInfo) -> ModelDTO` – Creates from domain

---

### `Models/DTOs/ConfigDTO.swift`

**Role / Responsibility**
- Data Transfer Object for configuration

**Key Types**
- `ConfigDTO` (struct) – Configuration DTO
- `EndpointDTO` (struct) – API endpoint configuration

---

### `Models/Domain/DownloadProgress.swift`

**Role / Responsibility**
- Represents model download progress information

**Key Types**
- `DownloadProgress` (struct) – Download progress with bytes/percentage
- `DownloadState` (enum) – pending, downloading, paused, completed, failed

**Key Public APIs**
- `var percentage: Double` – Completion percentage (0-100)
- `var isComplete: Bool` – True when downloaded
- `var remainingBytes: Int64` – Bytes remaining

---

### `Models/Domain/SyncState.swift`

**Role / Responsibility**
- Tracks synchronization state for data entities

**Key Types**
- `SyncState` (enum) – synced, pending, failed, conflict
- `SyncMetadata` (struct) – Last sync time, version, conflict info

---

### `Models/Mapping/ModelMapper.swift`

**Role / Responsibility**
- Maps between different model representations
- Handles version compatibility transformations

**Key Types**
- `ModelMapper` (class) – Model mapping utility

**Key Public APIs**
- `func mapToInfo(_ dto: ModelDTO) -> ModelInfo`
- `func mapToDTO(_ info: ModelInfo) -> ModelDTO`
- `func mapAPIResponse(_ response: ModelAPIResponse) -> [ModelInfo]`

---

## Network/ (11 files)

### `Network/Client/APIClient.swift`

**Role / Responsibility**
- Central HTTP client for API communication
- Handles authentication, retries, and error mapping
- Provides request/response logging via Pulse

**Key Types**
- `APIClient` (class) – Main API client
- `APIEndpoint` (enum) – Available API endpoints
- `APIError` (enum) – API-specific errors

**Key Public APIs**
- `func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T`
- `func request<T: Decodable, B: Encodable>(_ endpoint: APIEndpoint, body: B) async throws -> T`
- `func download(from url: URL, to destination: URL, progress: @escaping (Double) -> Void) async throws`

**Dependencies**
- Internal: Foundation/KeychainManager (API key)
- External: Alamofire, Pulse

**Important Internal Logic**
- Automatic retry with exponential backoff (3 attempts)
- Request timeout: 30 seconds
- Download timeout: 10 minutes
- Authentication via Bearer token from Keychain

---

### `Network/Client/NetworkConfiguration.swift`

**Role / Responsibility**
- Configures network client settings
- Manages base URLs for different environments

**Key Types**
- `NetworkConfiguration` (struct) – Network settings
- `Environment` (enum) – development, staging, production

**Key Public APIs**
- `static var current: NetworkConfiguration`
- `var baseURL: URL`
- `var timeout: TimeInterval`

---

### `Network/Endpoints/ModelEndpoints.swift`

**Role / Responsibility**
- Defines API endpoints for model operations

**Key Types**
- Extension on `APIEndpoint` for model-related endpoints

**Endpoints Defined**
- `.listModels` – GET /models
- `.modelDetails(id:)` – GET /models/{id}
- `.modelDownloadURL(id:)` – GET /models/{id}/download
- `.modelUpdates(since:)` – GET /models/updates

---

### `Network/Endpoints/ConfigEndpoints.swift`

**Role / Responsibility**
- Defines API endpoints for configuration

**Endpoints Defined**
- `.configuration` – GET /config
- `.featureFlags` – GET /config/features

---

### `Network/Endpoints/TelemetryEndpoints.swift`

**Role / Responsibility**
- Defines API endpoints for telemetry/analytics

**Endpoints Defined**
- `.sendTelemetry` – POST /telemetry
- `.sendBatchTelemetry` – POST /telemetry/batch

---

### `Network/Services/DownloadService.swift`

**Role / Responsibility**
- Manages file downloads with progress tracking
- Supports pause/resume functionality
- Handles download validation (checksum)

**Key Types**
- `DownloadService` (class) – File download manager
- `DownloadTask` (class) – Individual download task

**Key Public APIs**
- `func download(url: URL, destination: URL) -> AsyncThrowingStream<DownloadProgress, Error>`
- `func pause(taskId: String)`
- `func resume(taskId: String)`
- `func cancel(taskId: String)`

**Dependencies**
- External: Alamofire

**Important Internal Logic**
- Chunk-based downloading for large files
- Automatic retry on network failure (3 attempts)
- SHA256 checksum validation when provided

---

### `Network/Services/TelemetryService.swift`

**Role / Responsibility**
- Sends telemetry events to backend
- Batches events for efficient transmission
- Handles offline queuing

**Key Types**
- `TelemetryService` (class) – Telemetry transmission
- `TelemetryEvent` (struct) – Event data structure

**Key Public APIs**
- `func send(event: TelemetryEvent) async throws`
- `func sendBatch(events: [TelemetryEvent]) async throws`
- `func flush() async throws`

**Important Internal Logic**
- Batch size: 50 events
- Flush interval: 30 seconds
- Offline queue limit: 1000 events

---

### `Network/Services/MockNetworkService.swift`

**Role / Responsibility**
- Provides mock network responses for testing
- Simulates network delays and errors

**Key Types**
- `MockNetworkService` (class) – Mock network implementation

**Potential Issues / Smells**
- **Production code contains mock** – Should be in test target

---

### `Network/Interceptors/AuthInterceptor.swift`

**Role / Responsibility**
- Adds authentication headers to requests
- Handles token refresh when expired

**Key Types**
- `AuthInterceptor` (class) – Alamofire RequestInterceptor

**Key Public APIs**
- `func adapt(_ urlRequest: URLRequest, ...) async throws -> URLRequest`
- `func retry(_ request: Request, ...) async -> RetryResult`

---

### `Network/Interceptors/LoggingInterceptor.swift`

**Role / Responsibility**
- Logs network requests and responses
- Integrates with Pulse for network debugging

**Key Types**
- `LoggingInterceptor` (class) – Request/response logger

---

### `Network/Interceptors/RetryInterceptor.swift`

**Role / Responsibility**
- Implements retry logic for failed requests
- Configurable retry policies

**Key Types**
- `RetryInterceptor` (class) – Retry handler
- `RetryPolicy` (struct) – Retry configuration

**Important Internal Logic**
- Exponential backoff: 1s, 2s, 4s
- Retryable status codes: 408, 429, 500, 502, 503, 504
- Maximum retries: 3

---

## Protocols/ (5 files)

### `Protocols/Repositories/ModelRepositoryProtocol.swift`

**Role / Responsibility**
- Defines interface for model data operations
- Abstracts storage implementation details

**Key Types**
- `ModelRepositoryProtocol` (protocol) – Model repository interface

**Protocol Requirements**
```swift
protocol ModelRepositoryProtocol {
    func getModel(byId id: String) async throws -> ModelInfo?
    func saveModel(_ model: ModelInfo) async throws
    func deleteModel(byId id: String) async throws
    func getAllModels() async throws -> [ModelInfo]
    func getModels(matching criteria: ModelCriteria) async throws -> [ModelInfo]
}
```

---

### `Protocols/Repositories/ConfigRepositoryProtocol.swift`

**Role / Responsibility**
- Defines interface for configuration operations

**Key Types**
- `ConfigRepositoryProtocol` (protocol) – Configuration repository interface

---

### `Protocols/DataSources/LocalDataSourceProtocol.swift`

**Role / Responsibility**
- Defines interface for local data sources
- Provides generic CRUD operations

**Key Types**
- `LocalDataSourceProtocol` (protocol) – Generic local data source

---

### `Protocols/DataSources/RemoteDataSourceProtocol.swift`

**Role / Responsibility**
- Defines interface for remote data sources
- Abstracts network layer

**Key Types**
- `RemoteDataSourceProtocol` (protocol) – Generic remote data source

---

### `Protocols/DataSources/CacheDataSourceProtocol.swift`

**Role / Responsibility**
- Defines interface for cache operations

**Key Types**
- `CacheDataSourceProtocol` (protocol) – Generic cache interface

---

## Repositories/ (8 files)

### `Repositories/Model/ModelRepository.swift`

**Role / Responsibility**
- Implements ModelRepositoryProtocol
- Coordinates between local, remote, and cache data sources
- Implements repository pattern with caching strategy

**Key Types**
- `ModelRepository` (class) – Main model repository implementation

**Key Public APIs**
- `func getModel(byId id: String) async throws -> ModelInfo?`
- `func saveModel(_ model: ModelInfo) async throws`
- `func syncModels() async throws`
- `func downloadModel(_ modelId: String) -> AsyncThrowingStream<DownloadProgress, Error>`

**Important Internal Logic**
- Cache-first strategy: Check cache → local → remote
- Write-through caching: Updates propagate to all layers
- Sync on demand with conflict resolution

**Dependencies**
- Internal: LocalModelDataSource, RemoteModelDataSource, ModelCacheDataSource
- External: None

---

### `Repositories/Model/ModelDownloadRepository.swift`

**Role / Responsibility**
- Manages model file downloads
- Tracks download state and progress
- Handles download queue management

**Key Types**
- `ModelDownloadRepository` (class) – Model download management

**Key Public APIs**
- `func downloadModel(modelId: String, url: URL) -> AsyncThrowingStream<DownloadProgress, Error>`
- `func cancelDownload(modelId: String)`
- `func getDownloadState(modelId: String) -> DownloadState?`

---

### `Repositories/Config/ConfigRepository.swift`

**Role / Responsibility**
- Implements ConfigRepositoryProtocol
- Manages SDK configuration with caching

**Key Types**
- `ConfigRepository` (class) – Configuration repository

**Key Public APIs**
- `func getConfiguration() async throws -> SDKConfiguration`
- `func refreshConfiguration() async throws`
- `func clearCache()`

---

### `Repositories/Telemetry/TelemetryRepository.swift`

**Role / Responsibility**
- Manages telemetry event storage and transmission
- Implements offline-first telemetry with sync

**Key Types**
- `TelemetryRepository` (class) – Telemetry data management

**Key Public APIs**
- `func recordEvent(_ event: TelemetryEvent) async`
- `func flush() async throws`
- `func getPendingEvents() async -> [TelemetryEvent]`

**Important Internal Logic**
- Events stored locally first
- Background sync every 30 seconds
- Purges events older than 7 days

---

### `Repositories/Session/SessionRepository.swift`

**Role / Responsibility**
- Manages user session data
- Tracks session metrics and state

**Key Types**
- `SessionRepository` (class) – Session management

**Key Public APIs**
- `func startSession() async -> SessionInfo`
- `func endSession() async`
- `func getCurrentSession() -> SessionInfo?`

---

### `Repositories/Usage/UsageRepository.swift`

**Role / Responsibility**
- Tracks SDK usage metrics
- Aggregates usage data for billing/analytics

**Key Types**
- `UsageRepository` (class) – Usage tracking

**Key Public APIs**
- `func recordUsage(type: UsageType, amount: Int) async`
- `func getUsageSummary(period: DateInterval) async -> UsageSummary`

---

### `Repositories/Cache/RepositoryCache.swift`

**Role / Responsibility**
- Generic cache implementation for repositories
- Provides TTL-based invalidation

**Key Types**
- `RepositoryCache<Key, Value>` (class) – Generic repository cache

**Key Public APIs**
- `func get(_ key: Key) -> Value?`
- `func set(_ value: Value, for key: Key, ttl: TimeInterval?)`
- `func invalidate(_ key: Key)`
- `func clear()`

---

### `Repositories/Cache/CachePolicy.swift`

**Role / Responsibility**
- Defines caching policies for repositories

**Key Types**
- `CachePolicy` (enum) – cacheFirst, networkFirst, cacheOnly, networkOnly
- `CacheConfiguration` (struct) – TTL, max size settings

---

## Services/ (6 files)

### `Services/Model/ModelService.swift`

**Role / Responsibility**
- Business logic for model operations
- Coordinates model discovery, download, and lifecycle

**Key Types**
- `ModelService` (class) – Model business logic

**Key Public APIs**
- `func discoverModels() async throws -> [ModelInfo]`
- `func downloadModel(_ modelId: String) -> AsyncThrowingStream<DownloadProgress, Error>`
- `func deleteModel(_ modelId: String) async throws`
- `func getLocalModels() async throws -> [ModelInfo]`

**Dependencies**
- Internal: ModelRepository, ModelDownloadRepository
- External: None

---

### `Services/Config/ConfigService.swift`

**Role / Responsibility**
- Business logic for configuration management
- Handles configuration initialization and updates

**Key Types**
- `ConfigService` (class) – Configuration business logic

**Key Public APIs**
- `func initialize() async throws`
- `func getConfiguration() -> SDKConfiguration`
- `func refreshConfiguration() async throws`

---

### `Services/Sync/SyncService.swift`

**Role / Responsibility**
- Coordinates data synchronization across repositories
- Handles sync scheduling and conflict resolution

**Key Types**
- `SyncService` (class) – Sync coordination
- `SyncResult` (struct) – Sync operation result

**Key Public APIs**
- `func syncAll() async throws -> SyncResult`
- `func syncModels() async throws`
- `func syncConfiguration() async throws`

**Important Internal Logic**
- Sync order: Config → Models → Telemetry
- Conflict resolution: Server wins by default
- Sync interval: 15 minutes (configurable)

---

### `Services/Cleanup/CleanupService.swift`

**Role / Responsibility**
- Manages storage cleanup and maintenance
- Removes stale data and orphaned files

**Key Types**
- `CleanupService` (class) – Storage cleanup

**Key Public APIs**
- `func performCleanup() async throws`
- `func cleanupOldModels(olderThan: Date) async throws`
- `func cleanupTelemetry(olderThan: Date) async throws`

---

### `Services/Migration/MigrationService.swift`

**Role / Responsibility**
- Handles database schema migrations
- Manages data format upgrades

**Key Types**
- `MigrationService` (class) – Database migration
- `Migration` (protocol) – Individual migration definition

**Key Public APIs**
- `func runMigrations() async throws`
- `func getCurrentVersion() -> Int`

---

### `Services/Validation/ValidationService.swift`

**Role / Responsibility**
- Validates data integrity
- Checks model file checksums

**Key Types**
- `ValidationService` (class) – Data validation

**Key Public APIs**
- `func validateModel(_ model: ModelInfo) async throws -> Bool`
- `func validateChecksum(file: URL, expected: String) -> Bool`

---

## Storage/ (5 files)

### `Storage/Database/DatabaseManager.swift`

**Role / Responsibility**
- Manages GRDB database connection
- Provides database pool for concurrent access
- Handles database initialization and migrations

**Key Types**
- `DatabaseManager` (class) – GRDB database manager

**Key Public APIs**
- `static let shared: DatabaseManager`
- `var dbPool: DatabasePool`
- `func initialize() async throws`
- `func performMigrations() async throws`

**Dependencies**
- External: GRDB

**Important Internal Logic**
- Database location: Application Support directory
- WAL mode enabled for performance
- Automatic checkpoint every 1000 frames

---

### `Storage/Database/DatabaseMigrations.swift`

**Role / Responsibility**
- Defines database schema migrations
- Tracks migration versions

**Key Types**
- `DatabaseMigrations` (enum) – Migration definitions

**Migrations Defined**
- v1: Initial schema (models, config, telemetry tables)
- v2: Added usage tracking table
- v3: Added session tracking
- v4: Added sync metadata

---

### `Storage/Database/Tables/ModelTable.swift`

**Role / Responsibility**
- Defines model table schema
- Provides GRDB record implementation

**Key Types**
- `ModelRecord` (struct) – GRDB record for models

**Table Schema**
```sql
CREATE TABLE models (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    type TEXT NOT NULL,
    size INTEGER,
    capabilities TEXT,
    localPath TEXT,
    downloadedAt DATETIME,
    lastUsedAt DATETIME,
    metadata TEXT
)
```

---

### `Storage/FileStorage/ModelFileStorage.swift`

**Role / Responsibility**
- Manages model file storage on disk
- Handles file organization and cleanup

**Key Types**
- `ModelFileStorage` (class) – Model file management

**Key Public APIs**
- `func saveModelFile(modelId: String, data: Data) async throws -> URL`
- `func getModelFile(modelId: String) -> URL?`
- `func deleteModelFile(modelId: String) async throws`
- `func getStorageUsage() -> Int64`

**Important Internal Logic**
- Storage location: Application Support/RunAnywhere/Models/
- File naming: {modelId}/{version}/model.{extension}
- Automatic cleanup of old versions

---

### `Storage/FileStorage/CacheFileStorage.swift`

**Role / Responsibility**
- Manages cache file storage
- Handles cache eviction

**Key Types**
- `CacheFileStorage` (class) – Cache file management

**Key Public APIs**
- `func getCacheDirectory() -> URL`
- `func getCacheSize() -> Int64`
- `func clearCache() async throws`

---

## Sync/ (3 files)

### `Sync/SyncCoordinator.swift`

**Role / Responsibility**
- Coordinates sync operations across data types
- Manages sync scheduling and priorities

**Key Types**
- `SyncCoordinator` (actor) – Sync orchestration

**Key Public APIs**
- `func startPeriodicSync(interval: TimeInterval)`
- `func stopPeriodicSync()`
- `func syncNow() async throws`
- `func getSyncStatus() -> SyncStatus`

**Important Internal Logic**
- Uses actor for thread-safe sync state
- Priority queue for sync operations
- Exponential backoff on failures

---

### `Sync/ConflictResolver.swift`

**Role / Responsibility**
- Resolves sync conflicts between local and remote data
- Implements conflict resolution strategies

**Key Types**
- `ConflictResolver` (class) – Conflict resolution
- `ConflictResolutionStrategy` (enum) – serverWins, localWins, merge, manual

**Key Public APIs**
- `func resolve<T: Syncable>(local: T, remote: T, strategy: ConflictResolutionStrategy) -> T`

---

### `Sync/SyncMetadataManager.swift`

**Role / Responsibility**
- Tracks sync metadata (last sync time, versions)
- Determines what needs syncing

**Key Types**
- `SyncMetadataManager` (class) – Sync metadata tracking

**Key Public APIs**
- `func getLastSyncTime(for type: SyncType) -> Date?`
- `func updateSyncTime(for type: SyncType)`
- `func needsSync(type: SyncType) -> Bool`

---

## Summary

### Key Patterns
1. **Repository Pattern** - Clean separation between data sources and business logic
2. **Cache-First Strategy** - Optimistic caching with background sync
3. **Protocol-Oriented Design** - Interfaces for all major components
4. **Offline-First Architecture** - Local storage with sync capabilities
5. **Actor-Based Concurrency** - Thread-safe sync coordination

### Architecture Flow
```
Business Logic (Services)
        │
        ▼
   Repositories (Cache-First)
        │
   ┌────┼────┐
   ▼    ▼    ▼
Cache Local Remote
       │     │
       ▼     ▼
     GRDB   API
```

### External Dependencies
| Dependency | Usage |
|------------|-------|
| GRDB | SQLite database access |
| Alamofire | HTTP client |
| Pulse | Network debugging |

### Potential Issues / Technical Debt
1. **MockNetworkService in production** - Should be in test target
2. **Hardcoded sync intervals** - Should be configurable
3. **No retry limit on sync failures** - Could cause battery drain
4. **Cache size limits not enforced** - Potential memory issues

### Candidates for Improvement
1. Move mock services to test targets
2. Make sync intervals configurable via SDKConfiguration
3. Add circuit breaker for sync failures
4. Implement cache size limits with LRU eviction

---
*This document is part of the RunAnywhere Swift SDK current-state documentation.*
