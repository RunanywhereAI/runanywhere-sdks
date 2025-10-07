# KMP Cross-Platform Database Implementation Plan

## Overview

This plan implements SQLDelight-based cross-platform database support for the Kotlin Multiplatform (KMP) SDK to achieve parity with the iOS implementation. The goal is to replace the current Android Room + in-memory storage approach with a unified SQLDelight solution that provides persistent storage across all platforms (JVM, Android, and Native).

## Current State Analysis

Based on the database comparison research, the current KMP implementation has:

**Strengths:**
- Good repository pattern architecture in `commonMain`
- Android Room implementation with proper DAOs
- Type-safe database access on Android
- Coroutine support for async operations

**Critical Gaps:**
- JVM and Native platforms only have in-memory storage (data loss on restart)
- No persistent storage outside of Android
- Missing real-time data observation
- Limited migration strategy (currently destructive)
- Type safety differences from iOS (URLs as strings, primitive date types)

## Implementation Plan

### Phase 1: SQLDelight Setup and Core Infrastructure

#### 1.1 Add SQLDelight Dependencies
- Add SQLDelight Gradle plugin to `build.gradle.kts`
- Add platform-specific driver dependencies:
  - JVM: SQLite JDBC driver
  - Android: Android SQLite driver
  - Native: Native SQLite driver (when native targets are re-enabled)
- Configure SQLDelight plugin with database name and package

#### 1.2 Create Database Schema
Create `.sq` files in `src/commonMain/sqldelight/com/runanywhere/sdk/database/`:

- `ModelInfo.sq` - Core model information table
- `Configuration.sq` - SDK configuration settings
- `Analytics.sq` - Analytics events and metrics
- `AuthToken.sq` - Authentication tokens
- `DeviceInfo.sq` - Device information
- `Telemetry.sq` - Telemetry data
- `Migration.sq` - Database migration history

#### 1.3 Define Database Schema Structure

**ModelInfo Table:**
```sql
CREATE TABLE ModelInfo (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    category TEXT NOT NULL,
    format TEXT NOT NULL,
    downloadURL TEXT,
    localPath TEXT,
    downloadSize INTEGER,
    memoryRequired INTEGER,
    compatibleFrameworks TEXT NOT NULL, -- JSON array
    preferredFramework TEXT,
    contextLength INTEGER,
    supportsThinking INTEGER NOT NULL DEFAULT 0, -- Boolean as INTEGER
    metadata TEXT, -- JSON object
    createdAt INTEGER NOT NULL, -- Timestamp
    updatedAt INTEGER NOT NULL, -- Timestamp
    lastUsedAt INTEGER,
    syncPending INTEGER NOT NULL DEFAULT 0, -- Boolean as INTEGER
    version INTEGER NOT NULL DEFAULT 1
);
```

**Configuration Table:**
```sql
CREATE TABLE Configuration (
    key TEXT PRIMARY KEY NOT NULL,
    value TEXT NOT NULL,
    valueType TEXT NOT NULL, -- STRING, INTEGER, BOOLEAN, JSON
    updatedAt INTEGER NOT NULL,
    syncPending INTEGER NOT NULL DEFAULT 0
);
```

**Analytics Table:**
```sql
CREATE TABLE Analytics (
    id TEXT PRIMARY KEY NOT NULL,
    eventType TEXT NOT NULL,
    eventData TEXT NOT NULL, -- JSON object
    timestamp INTEGER NOT NULL,
    sessionId TEXT,
    deviceId TEXT,
    processed INTEGER NOT NULL DEFAULT 0
);
```

#### 1.4 Platform-Specific Database Drivers

Create `expect/actual` implementations for database drivers:

**Common Interface (`commonMain`):**
```kotlin
expect class DatabaseDriverFactory {
    fun createDriver(): SqlDriver
}
```

**Platform Implementations:**
- `jvmMain`: SQLite JDBC driver
- `androidMain`: Android SQLite driver
- `nativeMain`: Native SQLite driver (future)

### Phase 2: Database Manager and Infrastructure

#### 2.1 Create DatabaseManager
- Replace Android Room database with SQLDelight database
- Implement database initialization and configuration
- Add connection pooling and performance optimizations
- Implement database health checks and maintenance

#### 2.2 Migration System
- Create migration framework similar to iOS DatabaseMigrator
- Implement version-based migration strategy
- Support non-destructive schema changes
- Add rollback capabilities for failed migrations

#### 2.3 Transaction Management
- Implement transaction boundaries for complex operations
- Add retry logic for database conflicts
- Ensure ACID compliance across operations

### Phase 3: Repository Layer Refactoring

#### 3.1 Update Repository Implementations
- Migrate `ModelInfoRepositoryImpl` to use SQLDelight
- Update all repository implementations to use SQLDelight queries
- Maintain existing interfaces for backward compatibility
- Add Flow-based real-time data observation

#### 3.2 Type Safety Improvements
- Create proper URL wrapper types
- Implement structured datetime handling
- Add JSON serialization for complex objects
- Create structured metadata classes

#### 3.3 Query Optimization
- Add database indices for commonly queried fields
- Implement proper foreign key relationships
- Add query performance monitoring

### Phase 4: Advanced Features

#### 4.1 Real-Time Data Observation
- Implement Flow-based data streams similar to iOS ValueObservation
- Add reactive updates for UI components
- Support for filtered and transformed observations

#### 4.2 Backup and Restore
- Database export/import functionality
- Backup scheduling and management
- Data corruption recovery mechanisms

#### 4.3 Performance Optimization
- Query caching strategies
- Connection pooling optimization
- Memory usage monitoring

## Technical Specifications

### SQLDelight Configuration

```kotlin
// build.gradle.kts
sqldelight {
    databases {
        create("RunAnywhereDatabase") {
            packageName.set("com.runanywhere.sdk.database")
            generateAsync.set(true)
        }
    }
}
```

### Dependencies to Add

```kotlin
commonMain {
    dependencies {
        implementation("app.cash.sqldelight:runtime:2.0.1")
        implementation("app.cash.sqldelight:coroutines-extensions:2.0.1")
    }
}

jvmMain {
    dependencies {
        implementation("app.cash.sqldelight:sqlite-driver:2.0.1")
    }
}

androidMain {
    dependencies {
        implementation("app.cash.sqldelight:android-driver:2.0.1")
    }
}

// Native targets (when enabled)
nativeMain {
    dependencies {
        implementation("app.cash.sqldelight:native-driver:2.0.1")
    }
}
```

### Database Schema Evolution

**Migration Example:**
```sql
-- Migration 1 -> 2: Add new columns
ALTER TABLE ModelInfo ADD COLUMN downloadProgress REAL DEFAULT 0.0;
ALTER TABLE ModelInfo ADD COLUMN downloadStatus TEXT DEFAULT 'NOT_DOWNLOADED';

-- Create index for performance
CREATE INDEX idx_model_status ON ModelInfo(downloadStatus);
```

## Data Model Consistency

### URL Handling
```kotlin
// Common type-safe URL wrapper
@Serializable
data class DatabaseURL(val value: String) {
    fun toURL(): URL? = try { URL(value) } catch (e: Exception) { null }

    companion object {
        fun from(url: URL?): DatabaseURL? = url?.let { DatabaseURL(it.toString()) }
    }
}
```

### Datetime Handling
```kotlin
// Type-safe timestamp wrapper
@Serializable
data class DatabaseTimestamp(val value: Long) {
    fun toInstant(): Instant = Instant.fromEpochMilliseconds(value)

    companion object {
        fun now(): DatabaseTimestamp = DatabaseTimestamp(Clock.System.now().toEpochMilliseconds())
        fun from(instant: Instant): DatabaseTimestamp = DatabaseTimestamp(instant.toEpochMilliseconds())
    }
}
```

### JSON Serialization
```kotlin
// Type-safe JSON handling for complex objects
object DatabaseSerializers {
    fun serializeFrameworks(frameworks: List<LLMFramework>): String =
        Json.encodeToString(frameworks.map { it.name })

    fun deserializeFrameworks(json: String): List<LLMFramework> =
        Json.decodeFromString<List<String>>(json).mapNotNull { LLMFramework.valueOf(it) }

    fun serializeMetadata(metadata: ModelInfoMetadata?): String? =
        metadata?.let { Json.encodeToString(it) }

    fun deserializeMetadata(json: String?): ModelInfoMetadata? =
        json?.let { Json.decodeFromString(it) }
}
```

## Repository Pattern Updates

### Enhanced Repository Interface
```kotlin
interface Repository<T : Any> {
    suspend fun save(entity: T): T
    suspend fun findById(id: String): T?
    suspend fun findAll(): List<T>
    suspend fun delete(id: String): Boolean
    suspend fun deleteAll(): Boolean

    // Real-time observation
    fun observe(): Flow<List<T>>
    fun observeById(id: String): Flow<T?>

    // Batch operations
    suspend fun saveAll(entities: List<T>): List<T>
    suspend fun deleteAll(ids: List<String>): Int
}
```

### ModelInfo Repository Implementation
```kotlin
class ModelInfoRepositoryImpl(
    private val database: RunAnywhereDatabase
) : ModelInfoRepository {

    override suspend fun save(entity: ModelInfo): ModelInfo {
        database.transaction {
            database.modelInfoQueries.insertOrReplace(
                id = entity.id,
                name = entity.name,
                category = entity.category.name,
                format = entity.format.name,
                downloadURL = entity.downloadURL?.toString(),
                localPath = entity.localPath?.toString(),
                downloadSize = entity.downloadSize,
                memoryRequired = entity.memoryRequired,
                compatibleFrameworks = DatabaseSerializers.serializeFrameworks(entity.compatibleFrameworks),
                preferredFramework = entity.preferredFramework?.name,
                contextLength = entity.contextLength,
                supportsThinking = if (entity.supportsThinking) 1L else 0L,
                metadata = DatabaseSerializers.serializeMetadata(entity.metadata),
                createdAt = DatabaseTimestamp.now().value,
                updatedAt = DatabaseTimestamp.now().value,
                syncPending = if (entity.syncPending) 1L else 0L,
                version = entity.version
            )
        }
        return entity
    }

    override fun observe(): Flow<List<ModelInfo>> {
        return database.modelInfoQueries
            .selectAll()
            .asFlow()
            .mapToList(Dispatchers.IO)
            .map { entities -> entities.map { it.toDomainModel() } }
    }
}
```

## Testing Strategy

### Unit Tests
- Test database migrations
- Test repository implementations
- Test data consistency across platforms
- Test transaction handling

### Integration Tests
- Test cross-platform database compatibility
- Test performance under load
- Test concurrent access patterns
- Test data recovery scenarios

## Migration from Current Implementation

### Backward Compatibility
- Keep existing repository interfaces unchanged
- Gradual migration of implementations
- Support for data import from existing Room database
- Fallback mechanisms during transition

### Data Migration Script
```kotlin
suspend fun migrateFromRoom(
    roomDatabase: RunAnywhereRoomDatabase,
    sqlDelightDatabase: RunAnywhereDatabase
) {
    // Migrate ModelInfo data
    val roomModels = roomDatabase.modelInfoDao().getAllModels()
    roomModels.forEach { roomEntity ->
        val domainModel = roomEntity.toDomainModel()
        sqlDelightDatabase.modelInfoQueries.insertOrReplace(/* ... */)
    }

    // Migrate other entities...
    // Mark migration as complete
}
```

## Success Criteria

1. **Platform Parity**: All platforms (JVM, Android, Native) have persistent storage
2. **Data Consistency**: Same data models and behavior across all platforms
3. **Performance**: Database operations perform similarly to iOS GRDB implementation
4. **Real-time Updates**: Flow-based reactive data observation works across platforms
5. **Migration Support**: Non-destructive schema migrations work correctly
6. **Type Safety**: Proper type handling for URLs, dates, and complex objects
7. **Backward Compatibility**: Existing code continues to work during and after migration

## Timeline Estimate

- **Phase 1** (SQLDelight Setup): 2-3 days
- **Phase 2** (Database Manager): 2-3 days
- **Phase 3** (Repository Refactoring): 3-4 days
- **Phase 4** (Advanced Features): 2-3 days
- **Testing and Migration**: 2-3 days

**Total**: ~12-16 days

## Risk Mitigation

1. **Data Loss**: Implement robust backup/restore before migration
2. **Performance**: Benchmark against current implementation
3. **Platform Compatibility**: Test thoroughly on all target platforms
4. **Breaking Changes**: Maintain interface compatibility during transition
5. **Complex Migrations**: Start with simple schema changes, build up complexity

This implementation will bring the KMP SDK database capabilities to full parity with iOS, providing reliable persistent storage across all platforms while maintaining type safety and performance.
