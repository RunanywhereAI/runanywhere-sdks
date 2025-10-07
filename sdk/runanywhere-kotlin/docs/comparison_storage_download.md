# Storage and Download Strategy Architecture Comparison: iOS vs Kotlin SDKs

This document provides a comprehensive comparison of the download and storage strategy architectures between the iOS Swift and Kotlin Multiplatform SDKs for the RunAnywhere platform.

## Executive Summary

Both SDKs implement a hierarchical storage strategy pattern with generic interfaces extending to module-specific implementations, then to platform-specific implementations. The architectures are remarkably consistent in their approach, with key differences primarily in language-specific patterns (protocols vs interfaces) and platform-specific file system handling.

## 1. Generic Storage Strategy Interfaces

### iOS Swift Implementation

**Protocol: `ModelStorageStrategy`** (`ModelStorageStrategy.swift`)
```swift
public protocol ModelStorageStrategy: DownloadStrategy {
    func findModelPath(modelId: String, in modelFolder: URL) -> URL?
    func detectModel(in modelFolder: URL) -> (format: ModelFormat, size: Int64)?
    func isValidModelStorage(at modelFolder: URL) -> Bool
    func getModelStorageInfo(at modelFolder: URL) -> ModelStorageDetails?
}
```

**Key Features:**
- Extends `DownloadStrategy` protocol, providing both download and storage capabilities
- Uses `URL` for file paths (Foundation framework)
- Returns tuples for model detection (`(format: ModelFormat, size: Int64)?`)
- Includes comprehensive default implementations in protocol extension

### Kotlin Implementation

**Interface: `ModelStorageStrategy`** (`ModelStorageStrategy.kt`)
```kotlin
interface ModelStorageStrategy {
    suspend fun findModelPath(modelId: String, modelFolder: String): String?
    suspend fun detectModel(modelFolder: String): ModelDetectionResult?
    suspend fun isValidModelStorage(modelFolder: String): Boolean
    suspend fun getModelStorageInfo(modelFolder: String): ModelStorageDetails?
    fun canHandle(model: ModelInfo): Boolean
    suspend fun download(model: ModelInfo, destinationFolder: String, progressHandler: ((Float) -> Unit)?): String
}
```

**Key Features:**
- All functions are `suspend` for coroutine support
- Uses `String` paths instead of `URL` objects
- Returns structured data classes instead of tuples
- Combines download and storage capabilities in single interface

### Comparison Analysis

| Aspect | iOS Swift | Kotlin |
|--------|-----------|--------|
| **Interface Pattern** | Protocol extending DownloadStrategy | Single interface with all methods |
| **Async Pattern** | Async/await with `async throws` | Kotlin coroutines with `suspend` |
| **Path Handling** | Foundation `URL` objects | String paths |
| **Return Types** | Tuples for structured data | Data classes for structured data |
| **Default Implementations** | Protocol extensions with defaults | Abstract class with defaults (in modules) |

## 2. Model Download Mechanisms

### iOS WhisperKit Download Implementation

**Class: `WhisperKitStorageStrategy`** (`WhisperKitStorageStrategy.swift`)

**Download Strategy:**
```swift
public func download(
    model: ModelInfo,
    to destinationFolder: URL,
    progressHandler: ((Double) -> Void)?
) async throws -> URL
```

**Key Implementation Details:**
- **Multi-file download**: Downloads `.mlmodelc` directories with multiple internal files
- **HuggingFace integration**: Maps model IDs to HuggingFace repository paths
- **Graceful error handling**: Continues downloading other files if one fails (404 handling)
- **Progress tracking**: File-based progress (files downloaded / total files)
- **Complex structure creation**: Creates subdirectories (`analytics`, `weights`)

**File Structure Management:**
```swift
private let mlmodelcFiles = [
    "AudioEncoder.mlmodelc": [
        "coremldata.bin", "metadata.json", "model.mil",
        "model.mlmodel", "weights/weight.bin"
    ],
    "TextDecoder.mlmodelc": [...],
    "MelSpectrogram.mlmodelc": [...]
]
```

### Kotlin WhisperKit Download Implementation

**Class: `DefaultWhisperStorage`** (platform-specific implementations)

**Download Strategy:**
```kotlin
suspend fun downloadModel(type: WhisperModelType, onProgress: (Float) -> Unit)
```

**Platform-Specific Implementations:**

**JVM Implementation:**
```kotlin
// JvmWhisperStorage.kt
val connection = url.openConnection()
val totalSize = connection.contentLengthLong

connection.getInputStream().use { input ->
    tempFile.outputStream().use { output ->
        val buffer = ByteArray(8192)
        var bytesRead: Int
        var totalBytesRead = 0L

        while (input.read(buffer).also { bytesRead = it } != -1) {
            output.write(buffer, 0, bytesRead)
            totalBytesRead += bytesRead

            if (totalSize > 0) {
                val progress = totalBytesRead.toFloat() / totalSize.toFloat()
                onProgress(progress)
            }
        }
    }
}
```

**Android Implementation:**
```kotlin
// AndroidWhisperStorage.kt - Similar streaming approach
// Uses Android Context for file system access
private val modelsDir: File by lazy {
    val dir = File(context.filesDir, "whisper/models")
    if (!dir.exists()) {
        dir.mkdirs()
    }
    dir
}
```

### Download Mechanism Comparison

| Aspect | iOS WhisperKit | Kotlin WhisperKit |
|--------|----------------|-------------------|
| **Model Type** | Core ML (.mlmodelc directories) | GGML (.bin files) |
| **Download Source** | HuggingFace argmaxinc/whisperkit-coreml | HuggingFace ggerganov/whisper.cpp |
| **File Structure** | Multi-directory, multi-file | Single binary file |
| **Progress Tracking** | File count based (discrete jumps) | Byte-based (smooth progress) |
| **Error Handling** | Continue on 404, retry logic | Temp file cleanup, atomic moves |
| **Concurrency** | URLSession async/await | Kotlin coroutines with Dispatchers.IO |

## 3. Progress Tracking Patterns

### iOS Progress Tracking

**DownloadProgress Structure:**
```swift
public struct DownloadProgress {
    public let bytesDownloaded: Int64
    public let totalBytes: Int64
    public let state: DownloadState
    public let estimatedTimeRemaining: TimeInterval?

    public var percentage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesDownloaded) / Double(totalBytes)
    }
}
```

**WhisperKit Implementation:**
- File-based progress: `Double(filesDownloaded) / Double(totalFiles)`
- Progress updates after each file completion
- Handles unknown total sizes gracefully

### Kotlin Progress Tracking

**Simple Float-based Progress:**
```kotlin
// Progress handler type
progressHandler: ((Float) -> Unit)?

// Implementation
val progress = totalBytesRead.toFloat() / totalSize.toFloat()
onProgress(progress)
```

**Characteristics:**
- Byte-level granularity
- Real-time streaming updates
- Range: 0.0f to 1.0f

### Progress Tracking Comparison

| Aspect | iOS | Kotlin |
|--------|-----|--------|
| **Granularity** | File-based (discrete) | Byte-based (continuous) |
| **Progress Type** | `Double` (0.0 to 1.0) | `Float` (0.0f to 1.0f) |
| **Additional Info** | Bytes, state, time estimates | Simple percentage only |
| **Update Frequency** | Per file completion | Per buffer read (8KB chunks) |
| **Unknown Size Handling** | Graceful fallback | Skips progress updates |

## 4. Error Handling and Retry Logic

### iOS Error Handling

**DownloadError Enum:**
```swift
public enum DownloadError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case timeout
    case partialDownload
    case checksumMismatch
    case extractionFailed(String)
    case unsupportedArchive(String)
    case httpError(Int)
    case cancelled
    case insufficientSpace
    case modelNotFound
    case connectionLost
}
```

**Retry Logic in WhisperKit:**
```swift
if httpResponse.statusCode == 404 {
    // File doesn't exist, skip it
    logger.info("File \(file) not found (404), skipping - this is normal for some models")
    // Continue with next file instead of failing
    continue
}
```

**Error Handling Strategy:**
- Graceful degradation (skip missing files)
- Detailed error categorization
- Continue processing on non-critical errors
- Localized error messages

### Kotlin Error Handling

**WhisperError Sealed Class:**
```kotlin
sealed class WhisperError : Exception() {
    data class ModelNotFound(override val message: String) : WhisperError()
    data class ModelDownloadFailed(override val message: String) : WhisperError()
    data class InitializationFailed(override val message: String) : WhisperError()
    data class TranscriptionFailed(override val message: String) : WhisperError()
    data class ServiceNotReady(override val message: String = "Whisper service is not ready") : WhisperError()
    data class InvalidAudioFormat(override val message: String) : WhisperError()
    data class NetworkError(override val message: String) : WhisperError()
}
```

**Cleanup Strategy:**
```kotlin
} catch (e: Exception) {
    // Clean up temp file if exists
    val tempFile = File(modelsDir, "${type.fileName}.tmp")
    if (tempFile.exists()) {
        tempFile.delete()
    }
    throw WhisperError.ModelDownloadFailed(
        "Failed to download model ${type.modelName}: ${e.message}"
    )
}
```

**Error Handling Characteristics:**
- Atomic operations (temp file + rename)
- Resource cleanup on failure
- Structured error hierarchy
- Fail-fast approach (no graceful degradation)

### Error Handling Comparison

| Aspect | iOS | Kotlin |
|--------|-----|--------|
| **Error Types** | Enum with associated values | Sealed class hierarchy |
| **Recovery Strategy** | Graceful degradation | Fail-fast with cleanup |
| **Resource Cleanup** | Automatic (ARC) | Manual temp file cleanup |
| **Error Detail** | Rich contextual information | Simple message strings |
| **Retry Logic** | Skip missing files, continue | Atomic download or complete failure |

## 5. Storage Validation Approaches

### iOS Storage Validation

**WhisperKit Validation:**
```swift
public func isValidModelStorage(at modelFolder: URL) -> Bool {
    let fileManager = FileManager.default

    // At minimum, we need AudioEncoder and TextDecoder
    let audioEncoderPath = modelFolder.appendingPathComponent("AudioEncoder.mlmodelc")
    let textDecoderPath = modelFolder.appendingPathComponent("TextDecoder.mlmodelc")

    return fileManager.fileExists(atPath: audioEncoderPath.path) &&
           fileManager.fileExists(atPath: textDecoderPath.path)
}
```

**Model Detection:**
```swift
public func detectModel(in modelFolder: URL) -> (format: ModelFormat, size: Int64)? {
    // Check if required components exist
    for component in requiredComponents {
        let componentPath = modelFolder.appendingPathComponent(component)
        if !fileManager.fileExists(atPath: componentPath.path) {
            return nil
        }
    }

    // Calculate total size of all files
    let totalSize = calculateDirectorySize(at: modelFolder)
    return (.mlmodel, totalSize)
}
```

### Kotlin Storage Validation

**WhisperKit Module Validation:**
```kotlin
override suspend fun isValidModelStorage(modelFolder: String): Boolean {
    // Check if the model file exists
    return true // Platform-specific implementation
}

override suspend fun detectModel(modelFolder: String): ModelDetectionResult? {
    // Check if this is a valid Whisper model folder
    // For Whisper, we expect .bin files
    return ModelDetectionResult(
        format = ModelFormat.BIN,
        sizeBytes = 0 // Platform-specific implementation will calculate
    )
}
```

**Platform Implementation (JVM):**
```kotlin
override suspend fun isModelDownloaded(type: WhisperModelType): Boolean = withContext(Dispatchers.IO) {
    File(modelsDir, type.fileName).exists()
}
```

### Validation Approach Comparison

| Aspect | iOS | Kotlin |
|--------|-----|--------|
| **Validation Depth** | Deep structural validation | Simple file existence check |
| **Model Structure** | Multi-directory validation | Single file validation |
| **Size Calculation** | Recursive directory traversal | File.length() for single files |
| **Required Components** | Explicit component list checking | Type-based filename checking |
| **Implementation** | Generic with defaults | Platform-specific with expect/actual |

## 6. Model Detection Strategies

### iOS Detection Strategy

**Generic Protocol Default:**
```swift
func detectModel(in modelFolder: URL) -> (format: ModelFormat, size: Int64)? {
    let fileManager = FileManager.default
    do {
        let files = try fileManager.contentsOfDirectory(at: modelFolder, includingPropertiesForKeys: [.fileSizeKey])
        for file in files {
            let ext = file.pathExtension.lowercased()
            if let format = ModelFormat(rawValue: ext) {
                let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                return (format, Int64(size))
            }
        }
    } catch {
        return nil
    }
    return nil
}
```

**WhisperKit Override:**
- Validates specific directory structure
- Checks for required `.mlmodelc` components
- Calculates total directory size recursively

### Kotlin Detection Strategy

**Generic Interface:**
```kotlin
suspend fun detectModel(modelFolder: String): ModelDetectionResult?

data class ModelDetectionResult(
    val format: ModelFormat,
    val sizeBytes: Long
)
```

**WhisperKit Implementation:**
```kotlin
override suspend fun detectModel(modelFolder: String): ModelDetectionResult? {
    return ModelDetectionResult(
        format = ModelFormat.BIN,
        sizeBytes = 0 // Platform-specific implementation will calculate
    )
}
```

### Detection Strategy Comparison

| Aspect | iOS | Kotlin |
|--------|-----|--------|
| **Return Type** | Tuple `(format, size)` | Data class `ModelDetectionResult` |
| **File Enumeration** | FileManager directory listing | Platform-specific file operations |
| **Format Detection** | Extension-based with ModelFormat enum | Hardcoded based on model type |
| **Size Calculation** | Real-time calculation with resource values | Deferred to platform implementations |
| **Error Handling** | Try-catch with nil return | Suspend function exception propagation |

## 7. Cache Management

### iOS Cache Management

**Storage Info Structure:**
```swift
public struct ModelStorageDetails {
    public let format: ModelFormat
    public let totalSize: Int64
    public let fileCount: Int
    public let primaryFile: String? // Main file for single-file models
    public let isDirectoryBased: Bool
}
```

**Capabilities:**
- Rich metadata collection
- Directory vs. file distinction
- File count tracking
- Primary file identification

### Kotlin Cache Management

**Storage Details:**
```kotlin
data class ModelStorageDetails(
    val format: ModelFormat,
    val totalSize: Long,
    val fileCount: Int,
    val primaryFile: String? = null,
    val isDirectoryBased: Boolean = false
)
```

**Platform-Specific Operations (Android):**
```kotlin
suspend fun getTotalStorageUsed(): Long = withContext(Dispatchers.IO) {
    modelsDir.listFiles()?.sumOf { it.length() } ?: 0L
}

suspend fun cleanupOldModels(keepTypes: List<WhisperModelType>): Unit = withContext(Dispatchers.IO) {
    val keepFileNames = keepTypes.map { it.fileName }.toSet()

    modelsDir.listFiles()?.forEach { file ->
        if (file.name.endsWith(".bin") && !keepFileNames.contains(file.name)) {
            file.delete()
        }
    }
}

suspend fun updateLastUsed(type: WhisperModelType) = withContext(Dispatchers.IO) {
    val modelFile = File(modelsDir, type.fileName)
    if (modelFile.exists()) {
        modelFile.setLastModified(System.currentTimeMillis())
    }
}
```

### Cache Management Comparison

| Aspect | iOS | Kotlin |
|--------|-----|--------|
| **Storage Metadata** | Rich, comprehensive details | Basic details, platform-extended |
| **Cleanup Strategy** | Not explicitly implemented | Selective cleanup by model type |
| **Usage Tracking** | Not explicitly implemented | Last-used timestamp tracking |
| **Storage Calculation** | On-demand recursive calculation | Cached total with platform optimizations |
| **Model Lifecycle** | Download and validation focus | Full lifecycle with cleanup operations |

## 8. Platform-Specific Storage Implementations

### iOS Platform Implementation

**Single Implementation:** All iOS variants (iOS, macOS, tvOS, watchOS) use the same Foundation-based implementation.

**Key Characteristics:**
- Foundation `FileManager` for all operations
- `URL`-based path handling
- Unified across Apple platforms
- Resource value queries for file metadata

### Kotlin Platform Implementations

**JVM Implementation:**
```kotlin
private val modelsDir: File by lazy {
    val userHome = System.getProperty("user.home")
    val dir = File(userHome, ".runanywhere/whisper/models")
    if (!dir.exists()) {
        dir.mkdirs()
    }
    dir
}
```

**Android Implementation:**
```kotlin
private val modelsDir: File by lazy {
    val dir = File(context.filesDir, "whisper/models")
    if (!dir.exists()) {
        dir.mkdirs()
    }
    dir
}
```

**Native Implementation:** (Expected pattern)
- Platform-specific native file system APIs
- Native path handling conventions

### Platform Implementation Comparison

| Platform | Storage Location | Key APIs | Characteristics |
|----------|-----------------|----------|----------------|
| **iOS** | App sandbox documents | Foundation FileManager | Unified across Apple ecosystem |
| **Android** | App private files directory | Java File API + Context | Android-specific permissions |
| **JVM** | User home directory | Java File API | Cross-platform compatibility |
| **Native** | Platform conventions | Platform-specific APIs | Optimal native performance |

## 9. Architecture Hierarchy Summary

### iOS Hierarchy
```
DownloadStrategy (base protocol)
    ↓
ModelStorageStrategy (extends DownloadStrategy)
    ↓
WhisperKitStorageStrategy (concrete implementation)
```

### Kotlin Hierarchy
```
ModelStorageStrategy (base interface)
    ↓
WhisperStorageStrategy (abstract class)
    ↓
DefaultWhisperStorage (expect/actual implementations)
    ↓
[JvmWhisperStorage, AndroidWhisperStorage, NativeWhisperStorage]
```

## 10. Key Architectural Decisions

### Consistency Strengths
1. **Interface Alignment:** Both platforms maintain similar method signatures and responsibilities
2. **Hierarchical Structure:** Generic → module-specific → platform-specific pattern
3. **Progress Tracking:** Both implement progress callbacks with 0.0-1.0 range
4. **Error Handling:** Structured error types with meaningful categorization
5. **Storage Validation:** Similar validation concepts with platform-appropriate implementations

### Platform-Specific Optimizations
1. **iOS:** Leverages Foundation framework for robust file system operations
2. **Kotlin:** Uses expect/actual pattern for true multiplatform implementations
3. **Path Handling:** URL objects (iOS) vs. String paths (Kotlin) based on platform conventions
4. **Async Patterns:** Native async/await (iOS) vs. Kotlin coroutines

### Divergent Design Choices
1. **Download Strategy:** Multi-file complex structure (iOS) vs. single-file binary (Kotlin)
2. **Error Recovery:** Graceful degradation (iOS) vs. fail-fast (Kotlin)
3. **Progress Granularity:** File-based (iOS) vs. byte-based (Kotlin)
4. **Cache Management:** Basic (iOS) vs. comprehensive lifecycle management (Kotlin)

## Conclusion

The storage and download architectures demonstrate excellent consistency in design philosophy while adapting appropriately to platform-specific patterns and capabilities. The iOS implementation focuses on robust, fault-tolerant operations suitable for the Core ML ecosystem, while the Kotlin implementation provides comprehensive lifecycle management suitable for cross-platform deployment.

Both architectures successfully achieve the goal of providing a unified interface for storage operations while allowing platform-specific optimizations, making them suitable for their respective ecosystems and use cases.
