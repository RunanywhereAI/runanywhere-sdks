# Download Architecture: Swift vs Kotlin SDK

## Swift SDK Download Flow

The Swift SDK implements model downloads through a layered architecture:

### 1. Public API Layer (`RunAnywhere+Storage.swift`)
```swift
static func downloadModel(_ modelId: String) async throws -> AsyncStream<DownloadProgress> {
    // 1. Get model info from registry
    let models = try await availableModels()
    guard let model = models.first(where: { $0.id == modelId }) else {
        throw SDKError.general(.modelNotFound, "Model not found: \(modelId)")
    }

    // 2. Start download via AlamofireDownloadService
    let task = try await AlamofireDownloadService.shared.downloadModel(model)
    return task.progress
}
```

### 2. Download Service Layer (`AlamofireDownloadService.swift`)
The download service handles:
- Getting destination path from `CppBridge.ModelPaths`
- Tracking download in C++ download manager
- Actual HTTP download via Alamofire
- Progress callbacks
- Archive extraction if needed
- Model metadata update via `CppBridge.ModelRegistry`

```swift
func downloadModelWithArtifactType(_ model: ModelInfo) async throws -> DownloadTask {
    guard let downloadURL = model.downloadURL else { throw SDKError }

    // 1. Emit download started event
    CppBridge.Events.emitDownloadStarted(modelId: model.id, totalBytes: model.downloadSize ?? 0)

    // 2. Determine if extraction needed (for .tar.gz, .zip archives)
    var requiresExtraction = model.artifactType.requiresExtraction

    // 3. Get destination folder from C++ path utilities
    let destinationFolder = try CppBridge.ModelPaths.getModelFolder(modelId: model.id, framework: model.framework)

    // 4. Start tracking in C++ download manager
    let taskId = try await CppBridge.Download.shared.startDownload(...)

    // 5. Execute HTTP download via Alamofire with progress
    let downloadedURL = try await performDownload(url: downloadURL, ...)

    // 6. Handle extraction if needed
    let finalModelPath = try await handlePostDownloadProcessing(
        downloadedURL: downloadedURL,
        requiresExtraction: requiresExtraction
    )

    // 7. Update model metadata via C++ registry
    try await CppBridge.ModelRegistry.shared.save(updatedModel)

    return finalModelPath
}
```

### 3. CppBridge Download Layer (`CppBridge+Download.swift`)
Provides C++ interop for:
- Task tracking
- Progress calculation
- Retry logic

### 4. Key Extraction Handling
Swift uses `SWCompression` library for archive extraction:
- `.tar.gz` → Native tar + gzip extraction
- `.zip` → Native zip extraction
- Extracts to model folder, then cleans up archive

## Current Kotlin Implementation (BROKEN)

```kotlin
actual fun RunAnywhere.downloadModel(modelId: String): Flow<DownloadProgress> = flow {
    emit(DownloadProgress(..., progress = 0f))

    // BUG: Just updates status without actually downloading!
    CppBridgeModelRegistry.updateModelStatusCallback(modelId, DOWNLOADING)
    CppBridgeModelRegistry.updateModelStatusCallback(modelId, DOWNLOADED)  // WRONG!

    emit(DownloadProgress(..., progress = 1f))
}
```

The Kotlin implementation:
1. ❌ Does NOT actually download the file
2. ❌ Does NOT use CppBridgeDownload infrastructure
3. ❌ Does NOT handle archive extraction
4. ❌ Does NOT update model local path

## Required Kotlin Fix

The Kotlin implementation needs to:

1. **Get model info** - Retrieve download URL from registered models
2. **Use CppBridgeDownload** - Call `startDownloadCallback()` for actual HTTP download
3. **Track progress** - Convert callback-based progress to Kotlin Flow
4. **Handle extraction** - Extract `.tar.gz` and `.zip` archives
5. **Update registry** - Set model local path after download complete

### Extraction Libraries for Android
- `org.apache.commons:commons-compress` - For tar.gz extraction
- Native `java.util.zip` - For zip extraction

## File Structure After Download

```
{baseDir}/models/
├── llm/
│   └── {modelId}/
│       └── model.gguf
├── stt/
│   └── {modelId}/
│       ├── model.onnx
│       └── tokens.txt
└── tts/
    └── {modelId}/
        ├── model.onnx
        └── tokens.txt
```

## Events Emitted During Download

1. `ModelEvent.DOWNLOAD_STARTED` - When download begins
2. `ModelEvent.DOWNLOAD_PROGRESS` - Every ~5% progress
3. `ModelEvent.DOWNLOAD_COMPLETED` - When download + extraction finishes
4. `ModelEvent.DOWNLOAD_FAILED` - On any error

## Model Status Flow

```
AVAILABLE → DOWNLOADING → DOWNLOADED → LOADED (after load)
                       ↓
                 DOWNLOAD_FAILED
```
