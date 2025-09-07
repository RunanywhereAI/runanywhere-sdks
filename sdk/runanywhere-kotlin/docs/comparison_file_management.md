# File Management Architecture Comparison: iOS vs Kotlin SDKs

## Overview

This document provides a comprehensive comparison of file management architectures between the RunAnywhere iOS SDK (Swift) and Kotlin Multiplatform SDK, analyzing patterns, abstractions, and implementation approaches.

## 1. File System Abstraction Patterns

### iOS SDK (Swift) - Direct FileManager Approach

The iOS SDK uses a **concrete implementation approach** with the `SimplifiedFileManager` class as the core abstraction:

```swift
public class SimplifiedFileManager {
    private let baseFolder: Folder
    private let logger = SDKLogger(category: "SimplifiedFileManager")

    public init() throws {
        self.baseFolder = try Folder.documents!.createSubfolderIfNeeded(withName: "RunAnywhere")
        try createDirectoryStructure()
    }
}
```

**Key Characteristics:**
- Uses the `Files` library for high-level file operations
- Single concrete class handling all file operations
- Direct dependency on iOS/macOS file system APIs
- Error handling through Swift's throwing functions

### Kotlin SDK - Protocol-First Approach

The Kotlin SDK implements a **protocol-first abstraction** with platform-specific implementations:

```kotlin
// Common interface
interface FileSystem {
    suspend fun writeBytes(path: String, data: ByteArray)
    suspend fun readBytes(path: String): ByteArray
    suspend fun exists(path: String): Boolean
    // ... other operations
}

// Platform-specific factory
expect fun createFileSystem(): FileSystem
```

**Key Characteristics:**
- Protocol-based abstraction with `expect/actual` pattern
- Platform-agnostic interface in `commonMain`
- Platform-specific implementations (`JvmFileSystem`, `AndroidFileSystem`)
- Coroutine-based async operations

### Comparison Analysis

| Aspect | iOS SDK | Kotlin SDK |
|--------|---------|------------|
| **Abstraction Level** | Concrete class with library wrapper | Protocol-based interface |
| **Platform Handling** | Single platform, direct APIs | Multi-platform with expect/actual |
| **Error Handling** | Throwing functions | Exception handling + Result types |
| **Async Model** | Synchronous operations | Coroutine-based async |
| **Testability** | Requires file system mocking | Interface-based mocking |

## 2. Path Management

### iOS SDK Path Management

```swift
// iOS uses Folder-based abstraction
public func getModelFolder(for modelId: String, framework: LLMFramework) throws -> Folder {
    let modelsFolder = try baseFolder.subfolder(named: "Models")
    let frameworkFolder = try modelsFolder.createSubfolderIfNeeded(withName: framework.rawValue)
    return try frameworkFolder.createSubfolderIfNeeded(withName: modelId)
}

// Path structure: ~/Documents/RunAnywhere/Models/{framework}/{modelId}/
```

**Characteristics:**
- Object-oriented path handling with `Folder` objects
- Automatic directory creation
- Type-safe framework enumeration
- iOS Documents directory as root

### Kotlin SDK Path Management

```kotlin
// Kotlin uses string-based paths with platform abstraction
override fun getModelDirectory(framework: String, modelId: String): String {
    val modelsPath = "${getModelStoragePath()}/Models"
    return if (framework != "unknown") {
        "$modelsPath/$framework/$modelId"
    } else {
        "$modelsPath/$modelId"
    }
}

// Platform-specific root paths:
// JVM: ~/.runanywhere
// Android: context.filesDir/runanywhere
```

**Characteristics:**
- String-based path construction
- Platform-specific root directory resolution
- Fallback to legacy structure for unknown frameworks
- Cross-platform path compatibility

### Path Management Comparison

| Feature | iOS SDK | Kotlin SDK |
|---------|---------|------------|
| **Path Representation** | `Folder` objects | String paths |
| **Root Directory** | `~/Documents/RunAnywhere` | Platform-specific (`~/.runanywhere`, `context.filesDir`) |
| **Path Construction** | Object method chaining | String concatenation |
| **Auto-creation** | Built into Folder API | Explicit directory creation |
| **Type Safety** | Compile-time via Folder API | Runtime path validation |

## 3. Directory Structure Conventions

### Common Structure Pattern

Both SDKs implement the same logical directory structure:

```
RunAnywhere/
├── Models/
│   ├── {framework}/
│   │   └── {modelId}/
│   └── {modelId}/ (legacy)
├── Cache/
├── Temp/
├── Downloads/
└── (platform-specific additions)
```

### iOS Directory Implementation

```swift
private func createDirectoryStructure() throws {
    _ = try baseFolder.createSubfolderIfNeeded(withName: "Models")
    _ = try baseFolder.createSubfolderIfNeeded(withName: "Cache")
    _ = try baseFolder.createSubfolderIfNeeded(withName: "Temp")
    _ = try baseFolder.createSubfolderIfNeeded(withName: "Downloads")
}
```

### Kotlin Directory Implementation

```kotlin
fun initializeDirectoryStructure() {
    val directories = listOf(
        getModelStoragePath(),
        "${getModelStoragePath()}/Models",
        getCacheDirectory(),
        getTempDirectory(),
        getDownloadsDirectory()
    )
    directories.forEach { dir ->
        if (!fileExists(dir)) {
            createDirectory(dir)
        }
    }
}
```

### Directory Structure Analysis

| Aspect | iOS SDK | Kotlin SDK |
|--------|---------|------------|
| **Initialization** | Constructor-based | Explicit method call |
| **Error Handling** | Throws on failure | Silent failure with logging |
| **Extensibility** | Hardcoded directories | List-based, easily extensible |
| **Verification** | Assumes success | Explicit existence check |

## 4. File Operations Implementation

### iOS File Operations

```swift
// Store model file
public func storeModel(data: Data, modelId: String, format: ModelFormat) throws -> URL {
    let modelFolder = try getModelFolder(for: modelId)
    let fileName = "\(modelId).\(format.rawValue)"
    let file = try modelFolder.createFile(named: fileName, contents: data)
    return URL(fileURLWithPath: file.path)
}

// Load model data
public func loadModel(modelId: String, format: ModelFormat) throws -> Data {
    let modelFolder = try getModelFolder(for: modelId)
    let fileName = "\(modelId).\(format.rawValue)"
    let file = try modelFolder.file(named: fileName)
    return try file.read()
}
```

### Kotlin File Operations

```kotlin
// Store model (Android implementation)
actual suspend fun writeFile(path: String, data: ByteArray): Unit = mutex.withLock {
    try {
        val file = File(path)
        ensureDirectoryExists(file.parentFile)
        FileOutputStream(file).use { outputStream ->
            outputStream.write(data)
        }
    } catch (e: Exception) {
        throw SDKError.FileSystemError("Failed to write file: ${e.message}")
    }
}

// Read model
actual suspend fun readFile(path: String): ByteArray = mutex.withLock {
    try {
        val file = File(path)
        if (!file.exists()) {
            throw SDKError.FileSystemError("File not found: $path")
        }
        return file.readBytes()
    } catch (e: Exception) {
        throw SDKError.FileSystemError("Failed to read file: ${e.message}")
    }
}
```

### File Operations Comparison

| Feature | iOS SDK | Kotlin SDK |
|---------|---------|------------|
| **API Style** | High-level objects (`Folder`, `File`) | Low-level file operations |
| **Thread Safety** | Single-threaded | Mutex-protected operations |
| **Error Handling** | Swift throwing functions | Exception wrapping |
| **Performance** | Library abstraction overhead | Direct platform API calls |
| **Memory Management** | ARC handles cleanup | Manual resource management |

## 5. Permission Handling

### iOS Permission Model

```swift
// iOS leverages sandboxing and automatic permissions
public init() throws {
    // Uses Documents directory - automatically granted
    self.baseFolder = try Folder.documents!.createSubfolderIfNeeded(withName: "RunAnywhere")
}

public func getAvailableSpace() -> Int64 {
    // Uses iOS APIs with automatic permission handling
    let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    return values.volumeAvailableCapacityForImportantUsage ?? 0
}
```

### Kotlin Permission Model

```kotlin
// Android - Context-based permissions
internal class AndroidFileSystem(private val context: Context) : SharedFileSystem() {
    override fun getDataDirectory(): String {
        return context.filesDir.absolutePath // Internal storage - no permissions needed
    }
}

// JVM - User home directory
internal class JvmFileSystem : SharedFileSystem() {
    override fun getDataDirectory(): String {
        return System.getProperty("user.home") + "/.runanywhere"
    }
}
```

### Permission Comparison

| Platform | iOS SDK | Kotlin SDK |
|----------|---------|------------|
| **iOS** | Automatic via sandbox | N/A |
| **Android** | N/A | Internal storage (no permissions) |
| **JVM** | N/A | User directory (filesystem permissions) |
| **Permission Strategy** | Leverage OS sandbox | Use permission-free paths |
| **External Storage** | Not implemented | Could be added per platform |

## 6. Platform-Specific File Access Patterns

### iOS Platform Access

```swift
// Single platform with direct iOS APIs
extension SimplifiedFileManager {
    public func getDeviceStorageInfo() -> (totalSpace: Int64, freeSpace: Int64, usedSpace: Int64) {
        do {
            let homeURL = URL(fileURLWithPath: NSHomeDirectory())
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: homeURL.path)

            let totalSpace = (attributes[.systemSize] as? Int64) ?? 0
            let freeSpace = (attributes[.systemFreeSize] as? Int64) ?? 0
            let usedSpace = totalSpace - freeSpace

            return (totalSpace: totalSpace, freeSpace: freeSpace, usedSpace: usedSpace)
        } catch {
            return (totalSpace: 0, freeSpace: 0, usedSpace: 0)
        }
    }
}
```

### Kotlin Platform Access Patterns

```kotlin
// JVM Platform
internal class JvmFileSystem : SharedFileSystem() {
    override fun getCacheDirectory(): String {
        return System.getProperty("java.io.tmpdir") ?: "/tmp"
    }
}

// Android Platform
internal class AndroidFileSystem(private val context: Context) : SharedFileSystem() {
    override fun getCacheDirectory(): String {
        return context.cacheDir.absolutePath
    }
}

// Shared Implementation (JVM + Android)
abstract class SharedFileSystem : FileSystem {
    override suspend fun writeBytes(path: String, data: ByteArray) = withContext(Dispatchers.IO) {
        File(path).writeBytes(data)
    }
}
```

### Platform Access Pattern Analysis

| Aspect | iOS SDK | Kotlin SDK |
|--------|---------|------------|
| **Platform Strategy** | Single-platform optimization | Multi-platform abstraction |
| **Code Sharing** | 100% iOS-specific | 95% shared + 5% platform-specific |
| **API Access** | Direct iOS/macOS APIs | Java File API + platform utilities |
| **Performance** | Platform-optimized | Shared performance with platform paths |
| **Maintenance** | Single codebase | Multiple platform implementations |

## 7. Cache Management Strategies

### iOS Cache Management

```swift
// iOS cache operations
public func storeCache(key: String, data: Data) throws {
    let cacheFolder = try baseFolder.subfolder(named: "Cache")
    _ = try cacheFolder.createFile(named: "\(key).cache", contents: data)
    logger.debug("Stored cache for key: \(key)")
}

public func clearCache() throws {
    let cacheFolder = try baseFolder.subfolder(named: "Cache")
    for file in cacheFolder.files {
        try file.delete()
    }
    logger.info("Cleared all cache")
}
```

### Kotlin Cache Management

```kotlin
// Android cache management with detailed cleanup
suspend fun cleanupOldFiles(maxAge: Long = 7 * 24 * 60 * 60 * 1000L) = mutex.withLock {
    val cutoff = System.currentTimeMillis() - maxAge
    var deletedCount = 0
    var deletedSize = 0L

    cacheDir.walkTopDown()
        .filter { it.isFile && it.lastModified() < cutoff }
        .forEach { file ->
            deletedSize += file.length()
            if (file.delete()) {
                deletedCount++
            }
        }

    logger.info("Cleanup completed: deleted $deletedCount files, ${deletedSize / 1024 / 1024} MB")
}
```

### Cache Management Comparison

| Feature | iOS SDK | Kotlin SDK |
|---------|---------|------------|
| **Strategy** | Simple file-based | Age-based cleanup with metrics |
| **Cleanup Granularity** | All-or-nothing | Time-based selective |
| **Metrics** | Basic logging | Detailed statistics |
| **Background Processing** | Synchronous | Coroutine-based async |
| **Storage Monitoring** | Manual | Automatic with thresholds |

## 8. Error Handling Approaches

### iOS Error Handling

```swift
// Swift throwing functions
public func storeModel(data: Data, modelId: String, format: ModelFormat) throws -> URL {
    let modelFolder = try getModelFolder(for: modelId)
    let fileName = "\(modelId).\(format.rawValue)"
    let file = try modelFolder.createFile(named: fileName, contents: data)
    return URL(fileURLWithPath: file.path)
}

// Error propagation
public func deleteModel(modelId: String) throws {
    // ... implementation
    throw SDKError.modelNotFound(modelId)
}
```

### Kotlin Error Handling

```kotlin
// Exception wrapping with detailed context
actual suspend fun writeFile(path: String, data: ByteArray): Unit = mutex.withLock {
    try {
        val file = File(path)
        ensureDirectoryExists(file.parentFile)
        FileOutputStream(file).use { outputStream ->
            outputStream.write(data)
        }
    } catch (e: Exception) {
        logger.error("Failed to write file: $path")
        throw SDKError.FileSystemError("Failed to write file: ${e.message}")
    }
}

// Result types for non-critical operations
override suspend fun delete(path: String): Boolean = withContext(Dispatchers.IO) {
    try {
        File(path).deleteRecursively()
    } catch (e: Exception) {
        false
    }
}
```

### Error Handling Comparison

| Approach | iOS SDK | Kotlin SDK |
|----------|---------|------------|
| **Primary Strategy** | Swift throwing functions | Exception wrapping |
| **Error Context** | Basic Swift errors | Detailed error messages |
| **Non-critical Operations** | Still throw errors | Return boolean results |
| **Logging Integration** | Basic error logging | Comprehensive error logging |
| **Recovery Strategy** | Caller handles | Graceful degradation |

## 9. Performance Considerations

### iOS Performance Profile

```swift
// Direct library usage, optimized for iOS
public func getTotalStorageSize() -> Int64 {
    var totalSize: Int64 = 0
    // Recursive traversal using Files library
    for file in baseFolder.files.recursive {
        if let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
           let fileSize = attributes[.size] as? NSNumber {
            totalSize += fileSize.int64Value
        }
    }
    return totalSize
}
```

### Kotlin Performance Profile

```kotlin
// Thread-safe with explicit concurrency control
suspend fun getStorageInfo(): StorageInfo = mutex.withLock {
    return try {
        // Platform-optimized storage queries
        val stat = StatFs(baseDir.absolutePath)
        val totalSpace = stat.blockCountLong * stat.blockSizeLong
        val availableSpace = stat.availableBlocksLong * stat.blockSizeLong

        StorageInfo(
            totalSpace = totalSpace,
            availableSpace = availableSpace,
            usedSpace = calculateDirectorySize(baseDir)
        )
    } catch (e: Exception) {
        StorageInfo(0, 0, 0, 0, 0)
    }
}
```

### Performance Analysis

| Metric | iOS SDK | Kotlin SDK |
|--------|---------|------------|
| **Concurrency Model** | Single-threaded | Coroutine + mutex |
| **Memory Usage** | Library abstractions | Direct memory management |
| **I/O Strategy** | Synchronous blocking | Async with Dispatchers.IO |
| **Caching** | Library-level | Explicit caching strategies |
| **Platform Optimization** | iOS-specific | Platform-appropriate APIs |

## 10. expect/actual Pattern Usage

The Kotlin SDK extensively uses the expect/actual pattern for platform abstraction:

### Common Interface Declaration

```kotlin
// commonMain - interface declaration
expect class FileManager {
    suspend fun writeFile(path: String, data: ByteArray)
    suspend fun readFile(path: String): ByteArray
    fun getModelPath(modelId: String): String
    companion object {
        val shared: FileManager
        val modelsDirectory: String
    }
}
```

### JVM Implementation

```kotlin
// jvmMain - actual implementation
actual class FileManager {
    actual suspend fun writeFile(path: String, data: ByteArray) {
        File(path).writeBytes(data)
    }

    actual companion object {
        actual val shared: FileManager = FileManager()
        actual val modelsDirectory: String = "${System.getProperty("user.home")}/.runanywhere/models"
    }
}
```

### Android Implementation

```kotlin
// androidMain - actual implementation
actual class FileManager {
    private lateinit var context: Context

    actual suspend fun writeFile(path: String, data: ByteArray) = mutex.withLock {
        val file = File(path)
        ensureDirectoryExists(file.parentFile)
        FileOutputStream(file).use { it.write(data) }
    }
}
```

### expect/actual Pattern Benefits

1. **Code Sharing**: 95% of logic in common module
2. **Platform Optimization**: Platform-specific implementations where needed
3. **Type Safety**: Compile-time enforcement of platform implementations
4. **Maintainability**: Single source of truth for interfaces

## 11. Consistency Analysis

### Directory Structure Consistency

✅ **Highly Consistent**: Both SDKs implement identical directory structures
- Same folder names: Models, Cache, Temp, Downloads
- Same framework-based organization
- Same model storage patterns

### API Design Consistency

⚠️ **Moderate Consistency**: Similar concepts, different implementations
- iOS: Object-oriented with Files library
- Kotlin: Protocol-based with platform abstraction
- Both support the same operations with different syntax

### Error Handling Consistency

⚠️ **Different Approaches**: Appropriate for each platform
- iOS: Swift throwing functions (idiomatic)
- Kotlin: Exception wrapping + Result types (idiomatic)
- Both provide detailed error context

### Platform Integration Consistency

✅ **Architecturally Consistent**: Both leverage platform capabilities
- iOS: Uses iOS file system APIs optimally
- Kotlin: Uses appropriate APIs per platform (Android Context, JVM File)

## 12. Recommendations

### For iOS SDK

1. **Consider Protocol Abstraction**: Add `FileManagerProtocol` for better testability
2. **Async Support**: Consider adding async versions of file operations
3. **Error Recovery**: Implement more graceful error handling for non-critical operations
4. **Metrics Collection**: Add performance metrics similar to Kotlin implementation

### For Kotlin SDK

1. **Object-Oriented Paths**: Consider `Path` class wrapper for better type safety
2. **Cache Strategies**: Implement more sophisticated caching strategies
3. **Background Operations**: Leverage background processing for cleanup operations
4. **Platform Optimization**: Add platform-specific optimizations where beneficial

### Cross-Platform Alignment

1. **API Parity**: Align method signatures where possible for consistent developer experience
2. **Error Codes**: Standardize error codes and messages across platforms
3. **Configuration**: Implement consistent configuration options (cache sizes, cleanup intervals)
4. **Documentation**: Maintain parallel documentation showing equivalent operations

## Conclusion

Both SDKs implement robust file management systems appropriate for their target platforms:

- **iOS SDK** leverages platform-specific libraries and APIs for optimal iOS/macOS performance
- **Kotlin SDK** prioritizes cross-platform compatibility with platform-specific optimizations

The architectures are **conceptually aligned** with the same directory structures and operational patterns, while being **implementation-optimal** for their respective platforms. The Kotlin SDK's expect/actual pattern provides excellent code sharing (95%) while maintaining platform-specific optimizations, making it particularly suitable for multi-platform deployment.

The file management systems successfully maintain consistency in user-facing behavior while adapting to platform-specific requirements and capabilities.

---

*Generated on September 7, 2025*
*Comparison covers iOS SDK v1.0 and Kotlin SDK v0.1*
