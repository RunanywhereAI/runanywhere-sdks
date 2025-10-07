# File System & Storage Management Comparison

## iOS Implementation

### FileManager Usage
The iOS SDK uses a comprehensive `SimplifiedFileManager` class that leverages the `Files` library for cross-platform file operations:

**Core Implementation**: `/Users/sanchitmonga/development/ODLM/sdks.worktree/android_init/sdk/runanywhere-swift/Sources/RunAnywhere/Data/Storage/FileSystem/SimplifiedFileManager.swift`

- Uses `Folder.documents` as the base directory
- Leverages the `Files` library for type-safe file operations
- Implements `ModelStorageStrategy` protocol for framework-specific storage

### Directory Structure
```
Documents/RunAnywhere/
├── Models/
│   ├── [Framework]/          # Framework-specific folders (e.g., whisperKit, llama)
│   │   └── [ModelId]/        # Individual model folders
│   └── [ModelId]/            # Legacy direct model storage
├── Cache/                    # General caching
├── Temp/                     # Temporary files
└── Downloads/                # Download staging area
```

### Model Storage Paths
- **Base Directory**: `~/Documents/RunAnywhere/`
- **Models**: `~/Documents/RunAnywhere/Models/[Framework]/[ModelId]/`
- **Cache**: `~/Documents/RunAnywhere/Cache/`
- **Temp**: `~/Documents/RunAnywhere/Temp/`
- **Downloads**: `~/Documents/RunAnywhere/Downloads/`

### Cache Management
- **Cache Storage**: Simple key-value cache with `.cache` extension
- **Cache Operations**: Store, load, and clear all cache
- **Temp File Cleanup**: Automatic cleanup of temporary files
- **Size Tracking**: Recursive directory size calculation using `FileManager.default.attributesOfItem`

### Temporary File Handling
- **Temp Directory**: Dedicated `Temp/` folder
- **Download Staging**: Uses `Downloads/` for temporary download files
- **UUID-based naming**: `{modelId}_{UUID().uuidString}.tmp`
- **Automatic cleanup**: `cleanTempFiles()` method

### Storage Permissions
- **iOS Sandbox**: Uses Documents directory (user-accessible)
- **File System Access**: Full read/write within app sandbox
- **No special permissions**: Standard iOS app sandbox permissions

### Framework-Specific Storage
**WhisperKit Storage Strategy** (`WhisperKitStorageStrategy.swift`):
- Directory-based models with `.mlmodelc` structure
- Complex file hierarchy: AudioEncoder, TextDecoder, MelSpectrogram
- Framework-aware file detection and validation
- Custom download strategy for multi-file models

## KMP Implementation

### Common Interface
**Core Abstraction**: `/Users/sanchitmonga/development/ODLM/sdks.worktree/android_init/sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/storage/FileSystem.kt`

```kotlin
interface FileSystem {
    suspend fun writeBytes(path: String, data: ByteArray)
    suspend fun readBytes(path: String): ByteArray
    suspend fun exists(path: String): Boolean
    suspend fun delete(path: String): Boolean
    suspend fun createDirectory(path: String): Boolean
    suspend fun fileSize(path: String): Long
    suspend fun listFiles(path: String): List<String>
    suspend fun move(from: String, to: String): Boolean
    suspend fun copy(from: String, to: String): Boolean
    suspend fun isDirectory(path: String): Boolean
    fun getCacheDirectory(): String
    fun getDataDirectory(): String
    fun getTempDirectory(): String
}
```

### Platform-Specific Implementations

#### Android (`AndroidFileSystem.kt`)
```kotlin
class AndroidFileSystem(private val context: Context) : SharedFileSystem() {
    override fun getCacheDirectory(): String = context.cacheDir.absolutePath
    override fun getDataDirectory(): String = context.filesDir.absolutePath
    override fun getTempDirectory(): String = context.cacheDir.absolutePath
}
```

#### JVM (`JvmFileSystem.kt`)
```kotlin
class JvmFileSystem : SharedFileSystem() {
    override fun getCacheDirectory(): String = System.getProperty("java.io.tmpdir") ?: "/tmp"
    override fun getDataDirectory(): String = System.getProperty("user.home") + "/.runanywhere"
    override fun getTempDirectory(): String = System.getProperty("java.io.tmpdir") ?: "/tmp"
}
```

#### Shared Implementation (`SharedFileSystem.kt`)
- Uses Java `File` API for JVM and Android
- All operations wrapped with `withContext(Dispatchers.IO)`
- Thread-safe file operations

### FileManager vs FileSystem
**Dual Architecture Issue**: KMP has both `FileSystem` interface and platform-specific `FileManager` expect/actual classes:

1. **FileSystem Interface** (newer): Clean abstraction with expect/actual factory
2. **FileManager expect/actual** (legacy): Platform-specific implementations

**Android FileManager** (`/Users/sanchitmonga/development/ODLM/sdks.worktree/android_init/sdk/runanywhere-kotlin/src/androidMain/kotlin/com/runanywhere/sdk/files/FileManager.kt`):
- Comprehensive 600+ line implementation
- Thread-safe with `Mutex`
- Rich feature set: checksums, backups, storage analysis
- iOS-style directory structure in Android files directory

**JVM FileManager** (`/Users/sanchitmonga/development/ODLM/sdks.worktree/android_init/sdk/runanywhere-kotlin/src/jvmMain/kotlin/com/runanywhere/sdk/files/FileManager.kt`):
- Minimal 90-line implementation
- Direct `File` API usage
- Basic operations only

## Directory Structure Comparison

### iOS Structure
```
~/Documents/RunAnywhere/
├── Models/
│   ├── whisperKit/
│   │   └── whisper-base/
│   │       ├── AudioEncoder.mlmodelc/
│   │       ├── TextDecoder.mlmodelc/
│   │       ├── MelSpectrogram.mlmodelc/
│   │       ├── config.json
│   │       └── generation_config.json
│   └── llama/
│       └── [model-id]/
├── Cache/
├── Temp/
└── Downloads/
```

### KMP Android Structure (FileManager)
```
/data/data/[app]/files/runanywhere/
├── models/
│   └── [model-id].bin
├── cache/
├── temp/
├── logs/
├── database/
└── [base]/
```

### KMP JVM Structure
```
~/.runanywhere/
├── models/
│   └── [model-id].bin
├── cache/
└── temp/
```

### WhisperKit Module (KMP)
```
Android: /data/data/[app]/files/whisper/models/
JVM: ~/.runanywhere/models/
```

## Gaps and Misalignments

### 1. Directory Structure Inconsistencies
- **iOS**: Framework-aware hierarchical structure (`Models/[Framework]/[ModelId]/`)
- **KMP**: Flat model storage (`models/[model-id].bin`)
- **Gap**: KMP lacks framework-specific organization

### 2. Model Storage Strategy Misalignment
- **iOS**: Complex multi-file models (WhisperKit `.mlmodelc` directories)
- **KMP**: Single binary files only (`.bin` format)
- **Gap**: No multi-file model support in KMP

### 3. Cache Management Differences
- **iOS**: Key-based cache with `.cache` extensions
- **KMP Android**: Generic cache directory, no structured caching
- **KMP JVM**: Minimal cache support
- **Gap**: Inconsistent cache strategies

### 4. Path Management Inconsistencies
- **iOS**: Relative to Documents/RunAnywhere base
- **Android**: Context-based paths (`filesDir`, `cacheDir`)
- **JVM**: User home-based paths (`~/.runanywhere`)
- **Gap**: No unified path resolution

### 5. Permission Handling Differences
- **iOS**: Sandbox-compliant Documents directory
- **Android**: Internal storage with Context dependency
- **JVM**: User directory access
- **Gap**: Different permission models not abstracted

### 6. Storage Analysis Capabilities
- **iOS**: Rich storage analysis with `DefaultStorageAnalyzer`
- **KMP Android**: Basic `StorageInfo` class
- **KMP JVM**: Minimal storage information
- **Gap**: Inconsistent storage monitoring

### 7. Framework Integration
- **iOS**: `ModelStorageStrategy` protocol for pluggable storage
- **KMP**: No pluggable storage strategy pattern
- **Gap**: Missing extensible storage architecture

### 8. Temporary File Management
- **iOS**: Dedicated download staging with UUID naming
- **KMP**: Basic temp directory usage
- **Gap**: Less sophisticated temporary file handling

### 9. File Operations Sophistication
- **iOS**: Type-safe operations with `Files` library
- **KMP**: Raw string paths with potential for errors
- **Gap**: Less type safety in KMP

### 10. Architecture Duplication
- **KMP**: Both `FileSystem` interface and `FileManager` expect/actual
- **Confusion**: Two competing file management approaches
- **Gap**: No clear pattern for which to use when

## Recommendations to Address Gaps

### 1. Directory Standardization
```kotlin
// Implement iOS-style directory structure in KMP
class StandardizedFileManager {
    fun getModelsDirectory(framework: String? = null): String {
        val baseModels = getDataDirectory() + "/models"
        return framework?.let { "$baseModels/$it" } ?: baseModels
    }
}
```

### 2. Framework-Aware Storage
```kotlin
// Add framework support to KMP storage
interface ModelStorageStrategy {
    suspend fun getModelPath(modelId: String, framework: String): String
    suspend fun isDirectoryBased(): Boolean
    suspend fun getRequiredFiles(): List<String>
}
```

### 3. Unified FileSystem Implementation
```kotlin
// Consolidate dual architecture into single FileSystem approach
expect fun createPlatformFileSystem(): FileSystem

// Deprecate FileManager expect/actual in favor of FileSystem
```

### 4. Cache Strategy Unification
```kotlin
// Implement iOS-style structured caching
interface CacheManager {
    suspend fun store(key: String, data: ByteArray, ttl: Long? = null)
    suspend fun retrieve(key: String): ByteArray?
    suspend fun clear()
    suspend fun size(): Long
}
```

### 5. Multi-File Model Support
```kotlin
// Add support for complex model structures
data class ModelLayout(
    val isDirectoryBased: Boolean,
    val files: List<ModelFile>,
    val requiredFiles: Set<String>
)

data class ModelFile(
    val path: String,
    val required: Boolean,
    val size: Long? = null
)
```

### 6. Platform Path Abstraction
```kotlin
// Create unified path management
class PathManager {
    fun getBasePath(): String
    fun getModelsPath(framework: String? = null): String
    fun getCachePath(): String
    fun getTempPath(): String
    fun resolvePath(components: List<String>): String
}
```

### 7. Storage Analysis Alignment
```kotlin
// Implement iOS-style storage analysis in KMP
interface StorageAnalyzer {
    suspend fun analyzeStorage(): StorageInfo
    suspend fun getRecommendations(): List<StorageRecommendation>
    suspend fun checkAvailability(requiredBytes: Long): StorageAvailability
}
```

### 8. Permission Abstraction
```kotlin
// Abstract platform-specific permissions
interface PermissionManager {
    suspend fun requestStoragePermissions(): Boolean
    suspend fun hasStorageAccess(): Boolean
    fun getAccessibleDirectories(): List<String>
}
```

### 9. Migration Strategy
1. **Phase 1**: Deprecate `FileManager` expect/actual, standardize on `FileSystem`
2. **Phase 2**: Implement framework-aware directory structure
3. **Phase 3**: Add multi-file model support
4. **Phase 4**: Unify cache management strategies
5. **Phase 5**: Implement storage analysis capabilities

### 10. Type Safety Improvements
```kotlin
// Add type-safe path handling
@JvmInline
value class FilePath(val path: String) {
    init {
        require(path.isNotBlank()) { "Path cannot be blank" }
    }
}

@JvmInline
value class DirectoryPath(val path: String) {
    init {
        require(path.isNotBlank()) { "Directory path cannot be blank" }
    }
}
```

## Priority Implementation Order

1. **High Priority**: Consolidate dual FileSystem/FileManager architecture
2. **High Priority**: Implement framework-aware directory structure
3. **Medium Priority**: Add multi-file model support
4. **Medium Priority**: Unify cache management strategies
5. **Low Priority**: Implement comprehensive storage analysis
6. **Low Priority**: Add permission abstraction layer

This alignment will ensure consistent behavior across iOS and KMP implementations while maintaining platform-specific optimizations where needed.
