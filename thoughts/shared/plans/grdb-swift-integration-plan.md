# GRDB.swift Integration Plan for RunAnywhere SDK

## Executive Summary

This plan outlines the integration of GRDB.swift to replace the current disabled SQLite database implementation in the RunAnywhere SDK. The integration will fix JSON corruption issues, provide type-safe database operations, and enable robust data persistence.

**Current State**: Database completely disabled due to JSON corruption when storing complex nested structures
**Target State**: Fully functional GRDB.swift database with relational schema, type safety, and migration support

---

## Integration Architecture

### 1. Database Structure Transformation

**From**: JSON blobs in TEXT columns → **To**: Normalized relational schema

#### New Schema Design

```
┌─────────────────────────┐
│     configuration       │
├─────────────────────────┤
│ id: String (PK)         │
│ api_key: String?        │
│ base_url: String        │
│ model_cache_size: Int   │
│ created_at: Date        │
│ updated_at: Date        │
└─────────────────────────┘
         │
         ├──── routing_policies (1:N)
         ├──── analytics_config (1:1)
         └──── storage_config (1:1)

┌─────────────────────────┐
│    model_metadata       │
├─────────────────────────┤
│ id: String (PK)         │
│ name: String            │
│ format: String          │
│ size_bytes: Int64       │
│ framework: String       │
│ quantization: String?   │
│ capabilities: JSON      │
│ created_at: Date        │
│ updated_at: Date        │
└─────────────────────────┘
         │
         └──── model_usage_stats (1:N)

┌─────────────────────────┐
│  generation_sessions    │
├─────────────────────────┤
│ id: String (PK)         │
│ model_id: String (FK)   │
│ session_type: String    │
│ total_tokens: Int       │
│ total_cost: Double      │
│ created_at: Date        │
│ updated_at: Date        │
└─────────────────────────┘
         │
         └──── generations (1:N)

┌─────────────────────────┐
│     generations         │
├─────────────────────────┤
│ id: String (PK)         │
│ session_id: String (FK) │
│ sequence_number: Int    │
│ prompt_tokens: Int      │
│ completion_tokens: Int  │
│ latency_ms: Double      │
│ cost: Double            │
│ execution_target: String│
│ created_at: Date        │
└─────────────────────────┘
```

### 2. Corrected Architecture - Repository Pattern

```
┌────────────────────────────────────────┐
│          Public API Layer              │
│    (Repository Protocols)              │
│  ConfigurationRepository, etc.         │
└────────────────────────────────────────┘
                    │
┌────────────────────────────────────────┐
│     Repository Implementations         │
│  ConfigurationRepositoryImpl, etc.     │
│  (Handles BOTH local DB + remote API)  │
└────────────────────────────────────────┘
                    │
            ┌───────┴───────┐
            │               │
┌───────────▼──────┐ ┌─────▼──────────┐
│  Local Storage   │ │  Remote API    │
│  (GRDB inside)   │ │  (APIClient)   │
├──────────────────┤ ├────────────────┤
│ • DatabaseManager│ │ • Sync logic   │
│ • GRDB Records   │ │ • DTOs         │
│ • Migrations     │ │ • Endpoints    │
└──────────────────┘ └────────────────┘
```

**Key Architecture Principles:**
1. **Repository hides implementation** - No "GRDB" in public names
2. **Single source of truth** - Repository manages both local cache and remote sync
3. **Implementation agnostic** - Could switch from GRDB to Core Data without changing public API
4. **Existing structure preserved** - Update internals, not the architecture

---

## Implementation Approach

### What We're Actually Doing:
1. **Replacing the database engine** - SQLite → GRDB (internal change only)
2. **Keeping the same architecture** - Repository pattern remains unchanged
3. **Updating existing files** - Not creating parallel implementations
4. **Hiding implementation details** - GRDB is an internal detail, not exposed

### What We're NOT Doing:
- ❌ Creating new "GRDB" repositories
- ❌ Changing the repository protocols
- ❌ Exposing GRDB in public APIs
- ❌ Breaking the repository pattern

## Implementation Plan

### Phase 1A: GRDB Foundation (Days 1-2)

#### 1.1 Add GRDB Dependency
- Add to Package.swift: `.package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0")`
- Update target dependencies
- Verify compilation and resolve any conflicts

#### 1.2 Create Database Manager
```
GRDBDatabaseManager/
├── DatabaseManager.swift          // Main database coordinator
├── DatabaseConfiguration.swift    // GRDB configuration
├── DatabaseMigrator.swift        // Migration coordinator
└── DatabaseError.swift           // GRDB-specific errors
```

**Key Features:**
- Singleton pattern with shared instance
- DatabaseQueue for main operations
- Configurable database location
- Automatic migration on startup
- Error recovery mechanisms

#### 1.3 Define Migration Strategy
```
Migrations/
├── Migration001_InitialSchema.swift
├── Migration002_AddIndexes.swift
└── MigrationRegistry.swift
```

### Phase 1B: Core Data Models (Days 3-4)

#### 1.4 Create GRDB Record Types
```
GRDBModels/
├── ConfigurationRecord.swift
├── ModelMetadataRecord.swift
├── GenerationSessionRecord.swift
├── GenerationRecord.swift
├── TelemetryRecord.swift
└── Associations.swift
```

**Record Implementation Pattern:**
- Conform to FetchableRecord, PersistableRecord, TableRecord
- Define table name and columns
- Implement Codable for automatic encoding/decoding
- Add computed properties for derived values
- Define associations between records

#### 1.5 Implement Type Converters
- JSON column support for flexible data (capabilities, metadata)
- Date formatters for consistent timestamp handling
- Enum converters for type-safe status fields
- Custom UUID handling

### Phase 1C: Repository Migration (Days 5-7) 🚧 NEEDS FIXES

#### Issues Found:
1. **ConfigurationRepositoryImpl.swift is partially migrated** - Has mixed old and new code
2. **ServiceContainer still references old DatabaseCore** - Uses GRDBDatabaseAdapter as bridge
3. **Repository constructor signatures are inconsistent** - Some expect DatabaseCore, others DatabaseManager
4. **Missing mapping functions** - Need mapToRecord() and mapToEntity() implementations

#### 1.6 Update Existing Repository Implementations
```
Updated Files (not new):
├── Data/Repositories/ConfigurationRepositoryImpl.swift
├── Data/Repositories/ModelMetadataRepositoryImpl.swift
├── Data/Repositories/GenerationAnalyticsRepositoryImpl.swift
└── Data/Repositories/TelemetryRepositoryImpl.swift
```

**Fixed Implementation Strategy:**
1. **Fix ConfigurationRepositoryImpl.swift** first:
   - Remove mixed old database code (lines 50-100 have old JSON blob pattern)
   - Implement proper mapToRecord() and mapToEntity() functions
   - Use DatabaseManager instead of DatabaseCore
   - Keep apiClient for remote sync

2. **Update remaining repositories** following same pattern:
   - Replace `database: DatabaseCore` with `databaseManager: DatabaseManager`
   - Replace JSON blob storage with GRDB record operations
   - Implement record mapping functions for each repository
   - Keep all sync() logic with APIClient unchanged

3. **Fix ServiceContainer initialization**:
   - Update repository constructors to use DatabaseManager directly
   - Remove GRDBDatabaseAdapter bridge after all repositories updated
   - Fix async initialization issues

#### 1.7 Repository Implementation Details

**Each repository needs:**
```swift
// 1. Updated constructor
public init(databaseManager: DatabaseManager, apiClient: APIClient?)

// 2. Mapping functions
private func mapToRecord(_ entity: EntityType) -> RecordType
private func mapToEntity(_ record: RecordType) throws -> EntityType

// 3. GRDB operations replacing JSON blobs
try databaseManager.write { db in
    try record.save(db)
}

// 4. Proper associations for related data
let records = try ModelMetadataRecord
    .including(all: ModelMetadataRecord.usageStats)
    .fetchAll(db)
```

#### 1.8 Query Optimization
- Indexes already added in Migration002_AddIndexes.swift ✅
- Implement filtered queries using GRDB's query interface
- Add pagination using `.limit()` and `.offset()`
- Use GRDB's request builders for complex queries

### Phase 1C Implementation Order:

1. **ConfigurationRepositoryImpl.swift** (FIRST - it's already partially done)
   - Remove lines 50-100 (old JSON blob code)
   - Add proper mapToRecord() and mapToEntity() functions
   - Fix fetch, fetchAll, delete methods to use GRDB
   - Keep sync() method with APIClient

2. **ModelMetadataRepositoryImpl.swift**
   - Change constructor to use DatabaseManager
   - Implement record mapping for ModelMetadataRecord
   - Handle JSON blobs for capabilities and requirements
   - Include associations for usage stats

3. **GenerationAnalyticsRepositoryImpl.swift**
   - Map to GenerationSessionRecord and GenerationRecord
   - Handle parent-child relationship between sessions and generations
   - Implement aggregation queries for analytics

4. **TelemetryRepositoryImpl.swift**
   - Simple mapping to TelemetryRecord
   - Implement batch insert for performance
   - Add cleanup for old telemetry data

5. **ServiceContainer Updates**
   - Update all repository initializations
   - Remove DatabaseCore and GRDBDatabaseAdapter references
   - Simplify async initialization

### Phase 1D: Advanced Features (Days 8-9)

#### 1.8 Implement Database Observations
```
GRDBObservations/
├── ConfigurationObserver.swift
├── ModelMetadataObserver.swift
└── GenerationStatsObserver.swift
```

**Features:**
- Real-time configuration updates
- Model usage tracking
- Generation performance monitoring
- Memory-efficient observation

#### 1.9 Add Backup and Recovery
- Automatic database backups
- Point-in-time recovery
- Export/import functionality
- Data validation and repair

### Phase 1E: Legacy Cleanup (Days 10-11)

#### 1.13 Remove Legacy SQLite Code
```
Files to Delete:
├── Data/Storage/Database/
│   ├── Protocols/DatabaseCore.swift     (Keep - used as bridge)
│   └── Services/SQLiteDatabase.swift    (DELETE)
├── Data/Repositories/
│   ├── ConfigurationRepositoryImpl.swift    (DELETE after GRDB version)
│   ├── GenerationAnalyticsRepositoryImpl.swift (DELETE after GRDB version)
│   ├── ModelMetadataRepositoryImpl.swift    (DELETE after GRDB version)
│   └── TelemetryRepositoryImpl.swift        (DELETE after GRDB version)
```

#### 1.14 Remove JSON Blob Storage Pattern
- Remove all JSON encoding/decoding from repositories
- Remove `RepositoryEntity` protocol's JSON requirements
- Simplify data models to use proper types instead of JSON strings

#### 1.15 Clean Up ServiceContainer
- Remove fallback to InMemoryConfigurationService
- Remove NoOpGenerationAnalyticsService
- Ensure all services use GRDB database

### Phase 1F: Integration and Testing (Days 12-14)

#### 1.10 ServiceContainer Integration
```swift
// Progressive rollout strategy
if FeatureFlags.useGRDBDatabase {
    // New GRDB implementation
    return GRDBDatabaseManager.shared
} else {
    // Legacy implementation (currently nil)
    return nil
}
```

#### 1.11 Data Migration Tools
- Legacy data importer (if any existing data)
- JSON to relational converter
- Validation and verification tools
- Rollback mechanisms

#### 1.12 Comprehensive Testing
```
GRDBTests/
├── DatabaseManagerTests.swift
├── MigrationTests.swift
├── RepositoryTests.swift
├── PerformanceTests.swift
└── ConcurrencyTests.swift
```

---

## Migration Strategy

### Gradual Rollout Plan

1. **Alpha Phase** (Week 1)
   - Deploy with feature flag disabled
   - Internal testing with test data
   - Performance benchmarking

2. **Beta Phase** (Week 2)
   - Enable for internal builds
   - Monitor for errors and performance
   - Gather metrics on database operations

3. **Production Rollout** (Week 3)
   - Gradual percentage rollout
   - Monitor error rates and performance
   - Full rollout when stable

### Backward Compatibility

1. **Dual Implementation Period**
   - Keep both implementations available
   - Feature flag controls active implementation
   - Ability to switch back if issues arise

2. **Data Preservation**
   - Export existing in-memory data before migration
   - Import into new GRDB database
   - Verify data integrity

---

## Technical Considerations

### 1. Performance Optimizations
- WAL mode for better concurrency
- Connection pooling for heavy workloads
- Prepared statement caching
- Batch operations for bulk inserts

### 2. Error Handling
- Comprehensive error types for all database operations
- Automatic retry for transient errors
- Corruption detection and recovery
- Detailed logging for debugging

### 3. Security
- Encrypted database support (SQLCipher integration)
- Parameterized queries to prevent SQL injection
- Access control for sensitive data
- Audit logging for compliance

### 4. Monitoring
- Database operation metrics
- Query performance tracking
- Storage usage monitoring
- Error rate tracking

---

## Success Metrics

### Functional Requirements
- [ ] All database operations working without corruption
- [ ] JSON data properly stored and retrieved
- [ ] All repositories functioning with GRDB
- [ ] Migration system operational
- [ ] No data loss during migration

### Performance Requirements
- [ ] Query response time < 10ms for simple queries
- [ ] Batch insert > 1000 records/second
- [ ] Database size < 50MB for typical usage
- [ ] Memory usage stable under load

### Quality Requirements
- [ ] 95%+ test coverage for database layer
- [ ] Zero critical bugs in production
- [ ] Successful migration for 100% of users
- [ ] No increase in crash rate

---

## Risk Mitigation

### Identified Risks

1. **Data Loss Risk**
   - Mitigation: Comprehensive backup before migration
   - Rollback plan with data export/import

2. **Performance Regression**
   - Mitigation: Extensive benchmarking before rollout
   - Query optimization and indexing

3. **Compatibility Issues**
   - Mitigation: Thorough testing on all iOS versions
   - Gradual rollout with monitoring

4. **Migration Failure**
   - Mitigation: Atomic migrations with rollback
   - Validation checks at each step

---

## Timeline Summary

**Week 1**: Foundation and Core Models
- Days 1-2: GRDB setup and database manager
- Days 3-4: Record types and models
- Days 5-7: Repository implementations

**Week 2**: Advanced Features and Integration
- Days 8-9: Observations and backup
- Days 10-12: ServiceContainer integration
- Days 13-14: Testing and validation

**Week 3**: Rollout and Stabilization
- Gradual production rollout
- Monitoring and optimization
- Documentation and knowledge transfer

---

## Next Steps

1. **Immediate Actions**
   - Review and approve this plan
   - Set up development branch
   - Begin GRDB dependency integration

2. **Team Preparation**
   - GRDB training for team members
   - Set up testing environment
   - Define success criteria

3. **Documentation**
   - Create migration guide
   - Document new APIs
   - Update architecture diagrams

This plan provides a comprehensive roadmap for successfully integrating GRDB.swift into the RunAnywhere SDK, fixing the current database issues while adding powerful new capabilities.

---

## Legacy Code Cleanup Plan

### Files to Remove After GRDB Migration

#### 1. Database Layer (1 file)
- ✅ `Data/Storage/Database/Services/SQLiteDatabase.swift` - Old SQLite implementation
- 🔄 `Data/Storage/Database/Protocols/DatabaseCore.swift` - Keep temporarily as bridge

#### 2. Repository Implementations (4 files)
- ✅ `Data/Repositories/ConfigurationRepositoryImpl.swift` - Replace with GRDB version
- ✅ `Data/Repositories/GenerationAnalyticsRepositoryImpl.swift` - Replace with GRDB version
- ✅ `Data/Repositories/ModelMetadataRepositoryImpl.swift` - Replace with GRDB version
- ✅ `Data/Repositories/TelemetryRepositoryImpl.swift` - Replace with GRDB version

#### 3. Repository Support Files (Keep for now)
- 🔄 `Data/Protocols/ConfigurationRepository.swift` - Keep, used by services
- 🔄 `Data/Protocols/GenerationAnalyticsRepository.swift` - Keep, used by services
- 🔄 `Data/Protocols/ModelMetadataRepository.swift` - Keep, used by services
- 🔄 `Data/Protocols/TelemetryRepository.swift` - Keep, used by services
- 🔄 `Data/Protocols/Repository.swift` - Keep, base protocol
- 🔄 `Data/Models/Entities/RepositoryError.swift` - Keep, error handling

#### 4. Fallback Services (2 files)
- ✅ `Capabilities/Configuration/Services/InMemoryConfigurationService.swift` - Remove
- ✅ `Capabilities/GenerationAnalytics/Services/NoOpGenerationAnalyticsService.swift` - Remove

#### 5. Data Models to Simplify
- 🔄 Remove JSON serialization from all `Data/Models/Entities/*`
- 🔄 Remove `RepositoryEntity` protocol's JSON requirements
- 🔄 Simplify DTOs to match new normalized schema

#### 6. Service Updates
- 🔄 `Data/Network/DataSyncService.swift` - Update to use GRDB repositories
- 🔄 `Foundation/DependencyInjection/ServiceContainer.swift` - Remove fallback logic

### Total Files to Delete: 7
### Total Files to Modify: ~15

### Cleanup Timeline
1. **Phase 1C**: Create GRDB repositories alongside old ones
2. **Phase 1D**: Switch ServiceContainer to use GRDB repositories
3. **Phase 1E**: Delete old repository implementations
4. **Phase 1F**: Remove fallback services and clean up data models
5. **Final**: Remove DatabaseCore protocol and adapter once all code uses GRDB directly

---

## Implementation Progress

### Phase 1A: GRDB Foundation ✅ COMPLETED

#### 1.1 Add GRDB Dependency ✅
- Added GRDB.swift 7.6.1 (latest version) to Package.swift
- Updated target dependencies to include GRDB

#### 1.2 Create Database Manager ✅
- Created `DatabaseManager.swift` with singleton pattern
- Implemented database lifecycle management
- Added WAL mode and performance optimizations
- Included backup, vacuum, and statistics functionality
- Feature flag support for gradual rollout

- Created `DatabaseConfiguration.swift` with:
  - Configurable options for production/testing
  - Encryption support (SQLCipher ready)
  - Checkpoint modes and performance settings

- Created `DatabaseError.swift` with:
  - Comprehensive error types
  - Localized error descriptions
  - Recovery suggestions
  - GRDB error mapping

#### 1.3 Define Migration Strategy ✅
- Created `Migration001_InitialSchema.swift` with:
  - Normalized relational schema replacing JSON blobs
  - Configuration tables with proper relationships
  - Model metadata and usage tracking
  - Generation sessions and individual generations
  - Telemetry and user preferences
  - Proper foreign key constraints

- Created `Migration002_AddIndexes.swift` with:
  - Performance indexes for all tables
  - Composite indexes for common queries
  - Conditional indexes for sync operations
  - Optimized for read performance

### Additional Simplifications Implemented

Since the app is not in production:
- Removed feature flags and legacy database support
- Simplified database filename to `runanywhere.db`
- Created `GRDBDatabaseAdapter` to bridge GRDB with existing `DatabaseCore` protocol
- Updated `ServiceContainer` to use new GRDB database directly
- No migration from old database needed - starting fresh

### Phase 1B: Core Data Models ✅ COMPLETED

#### Created GRDB Record Types:
1. **ConfigurationRecord.swift** - Main configuration with proper types
2. **ModelMetadataRecord.swift** - Model metadata with JSON blob support
3. **GenerationSessionRecord.swift** - Generation sessions with associations
4. **GenerationRecord.swift** - Individual generations with associations
5. **TelemetryRecord.swift** - Telemetry events
6. **JSONHelpers.swift** - Helper utilities for JSON encoding/decoding

#### Key Features Implemented:
- All records conform to TableRecord, FetchableRecord, and PersistableRecord
- Type-safe column definitions using ColumnExpression
- Associations defined between related tables
- JSON blob support for flexible data (capabilities, requirements, etc.)
- Default values matching schema definition

### Phase 1C: Repository Migration ✅ COMPLETED

#### Completion Status:
- ✅ ConfigurationRepositoryImpl.swift - Fixed and using GRDB
- ✅ ModelMetadataRepositoryImpl.swift - Migrated to GRDB
- ✅ GenerationAnalyticsRepositoryImpl.swift - Migrated to GRDB
- ✅ TelemetryRepositoryImpl.swift - Migrated to GRDB
- ✅ ServiceContainer - Updated to use DatabaseManager directly
- ✅ GRDBDatabaseAdapter - Removed (no longer needed)
- ✅ DatabaseCore protocol - Removed (no longer needed)
- ✅ SQLiteDatabase.swift - Removed (old implementation)
- ✅ InMemoryConfigurationService - Removed (no fallback needed)
- ✅ NoOpGenerationAnalyticsService - Removed (no fallback needed)

#### What Was Done:
1. Fixed ConfigurationRepositoryImpl with proper mapping functions
2. Updated all repositories to use DatabaseManager instead of DatabaseCore
3. Implemented mapToRecord() and mapToEntity() functions for each repository
4. Updated ServiceContainer to create repositories with DatabaseManager
5. Fixed DataSyncService to accept repositories via constructor
6. Removed all legacy database code and adapters

### Next Steps - Phase 1D:
1. **Implement Database Observations** for real-time updates
2. **Add Backup and Recovery** functionality
3. **Remove JSON serialization** from entity models
4. **Add more advanced queries** and aggregations
5. **Performance optimization** with better indexes

### Key Achievements:
- ✅ All repositories now use GRDB directly
- ✅ Proper relational schema replacing JSON blobs
- ✅ Type-safe database operations
- ✅ Clean separation between entities and records
- ✅ No more database adapter layer
- ✅ Simplified dependency injection
2. **Replace** DatabaseCore/SQLite calls with DatabaseManager/GRDB
3. **Keep** the same repository protocols and public API
4. **Maintain** both local DB and remote API sync in same repository
5. **Hide** GRDB implementation details - no "GRDB" in names

#### Current Repository Structure (Correct Pattern):
```swift
// Existing ConfigurationRepositoryImpl
public actor ConfigurationRepositoryImpl: Repository, ConfigurationRepository {
    private let database: DatabaseCore  // ← Change to: DatabaseManager
    private let apiClient: APIClient?   // ← Keep as is

    // Repository handles BOTH:
    // 1. Local caching (database)
    // 2. Remote sync (apiClient)
}
```

#### Migration Steps:
1. Replace `DatabaseCore` with `DatabaseManager` in repositories
2. Replace JSON blob storage with GRDB record operations
3. Keep all sync() logic with APIClient unchanged
4. ServiceContainer remains unchanged (same interface)

---

## Cleanup Checklist

### After Phase 1 Completion:
- [x] Delete `SQLiteDatabase.swift` ✅
- [x] Delete old repository implementations (4 files) - Actually updated them instead ✅
- [x] Delete `InMemoryConfigurationService.swift` ✅
- [x] Delete `NoOpGenerationAnalyticsService.swift` ✅
- [ ] Remove JSON serialization from entity models (Phase 1D task)
- [x] Update `DataSyncService` to use GRDB repositories ✅
- [x] Clean up `ServiceContainer` fallback logic ✅
- [x] Remove `DatabaseCore` protocol and adapter ✅
- [ ] Update all imports and dependencies (ongoing)
- [ ] Run tests to ensure nothing breaks
- [ ] Update documentation to reflect new architecture
