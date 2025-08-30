# Data Package

The Data package contains all data access and storage operations for the RunAnywhere SDK. This layer handles network calls, database operations, and file system interactions.

## Architecture

The Data layer is purely focused on:
- **Network operations** (API calls, remote data fetching)
- **Database operations** (CRUD, queries, persistence)
- **File system operations** (reading/writing files)
- **Data caching** (temporary storage for performance)

## Structure

```
Data/
├── DataSources/          # Data source implementations
│   ├── LocalConfigurationDataSource.swift
│   └── RemoteConfigurationDataSource.swift
│
├── Models/               # Data models and DTOs
│   ├── Downloading/      # Download task models
│   ├── Entities/         # Core data entities
│   └── Storage/          # Storage info models
│
├── Network/              # Network and API layer
│   ├── AlamofireDownloadService.swift
│   ├── Models/
│   │   └── APIEndpoint.swift
│   └── Services/
│       └── APIClient.swift
│
├── Protocols/            # Repository and data protocols
│   ├── Repository.swift
│   ├── DataSource.swift
│   ├── Syncable.swift
│   └── [Domain]Repository.swift
│
├── Repositories/         # Repository implementations
│   ├── ConfigurationRepositoryImpl.swift
│   ├── ModelMetadataRepositoryImpl.swift
│   └── TelemetryRepositoryImpl.swift
│
├── Services/             # Data services (DB/Network operations only)
│   ├── ConfigurationService.swift    # Configuration data persistence
│   ├── TelemetryService.swift        # Telemetry data storage/transmission
│   ├── ModelMetadataService.swift    # Model metadata CRUD operations
│   └── RemoteLogger.swift            # Remote logging API calls
│
├── Storage/              # Storage implementations
│   ├── Cache/            # Data caching
│   │   ├── MetadataCache.swift
│   │   ├── RegistryCache.swift
│   │   └── RegistryStorage.swift
│   ├── Database/         # GRDB database layer
│   │   ├── Manager/
│   │   ├── Migrations/
│   │   └── Models/
│   └── FileSystem/       # File system operations
│       └── SimplifiedFileManager.swift
│
└── Sync/                 # Data synchronization
    └── SyncCoordinator.swift
```

## Usage

The Data layer is consumed by:
- **Capabilities Layer**: Business logic services that need data
- **Foundation Layer**: Infrastructure services requiring data access

### Key Services

#### Data Services (in Data/Services/)
- **ConfigurationService**: Loads/saves configuration from database and network
- **TelemetryService**: Persists and transmits telemetry data
- **ModelMetadataService**: Database CRUD for model metadata
- **RemoteLogger**: Network API for remote log submission

#### Storage Services
- **SimplifiedFileManager**: File system operations
- **DatabaseManager**: GRDB database management
- **Cache Services**: Temporary data storage for performance

#### Network Services
- **APIClient**: REST API client
- **AlamofireDownloadService**: File download management

### Design Principles

1. **Data Access Only**: No business logic, only data operations
2. **Repository Pattern**: Clean interface for data access
3. **Protocol-Oriented**: All repositories implement protocols
4. **Single Responsibility**: Each service handles one type of data operation
5. **No Orchestration**: Business logic stays in Capabilities layer
