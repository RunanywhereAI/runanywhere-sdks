# iOS vs Android/KMP SDK Implementation Analysis

**Generated:** 2025-10-09
**Purpose:** Comprehensive comparison of iOS and Android/KMP SDK implementations to identify gaps and prioritize fixes

---

## Executive Summary

This document provides a detailed analysis comparing the iOS Swift SDK implementation with the Android/KMP Kotlin SDK implementation. The comparison focuses on four key areas: **SDK Initialization**, **Model Management**, **Storage APIs**, and **Text Generation**.

### Key Findings

1. **Critical SDK API Gaps:** 5 missing APIs in Kotlin SDK
2. **Sample App Implementation Gaps:** Android Storage screen is completely unimplemented
3. **Data Structure Differences:** Minor differences in URL vs String handling
4. **Model Registration:** iOS uses adapter pattern, Kotlin uses direct registration (architectural difference, not a bug)

### Priority Issues

1. **Priority 1 (Critical):** Storage screen completely missing in Android app
2. **Priority 2 (High):** Missing `downloadModelWithProgress()` streaming API in Kotlin SDK
3. **Priority 3 (Medium):** Model registration UX differences between platforms

---

## Part 1: iOS SDK Public APIs

### 1.1 SDK Initialization

**File:** `/sdk/runanywhere-swift/Sources/RunAnywhere/Public/RunAnywhere.swift`

**Method Signature (Lines 58-65):**
```swift
public static func initialize(
    apiKey: String,
    baseURL: URL,
    environment: SDKEnvironment = .production
) throws
```

**Alternative String-based Initialization (Lines 72-79):**
```swift
public static func initialize(
    apiKey: String,
    baseURL: String,
    environment: SDKEnvironment = .production
) throws
```

**What Happens During Initialization (Lines 83-129):**

1. **Step 1 (Lines 92-96):** Validate API key (skip in development mode)
2. **Step 2 (Line 99):** Initialize logging system based on environment
3. **Step 3 (Lines 102-108):** Store parameters locally (keychain for production, skip for dev)
4. **Step 4 (Line 111):** Initialize local SQLite database
5. **Step 5 (Line 114):** Setup local-only services (NO network calls)
6. **Step 6 (Lines 117-119):** Mark as initialized and publish completion event

**Key Characteristics:**
- **Lightweight:** No network calls during initialization
- **Lazy Device Registration:** Device registration happens on first API call (Line 380)
- **Event-Driven:** Publishes events at each step (Lines 88, 119, 126)

### 1.2 Model Management APIs

**File:** `/sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/RunAnywhere+ModelManagement.swift`

#### Available Model APIs:

1. **`loadModelWithInfo(_ modelIdentifier: String) -> ModelInfo`** (Lines 10-27)
   - Loads a model by ID
   - Sets current model in generation service (Line 19)
   - Returns `ModelInfo` object
   - Publishes events: `loadStarted`, `loadCompleted`, `loadFailed`

2. **`unloadModel()`** (Lines 29-50)
   - Unloads currently loaded model
   - Clears from generation service (Line 42)
   - Publishes events: `unloadStarted`, `unloadCompleted`, `unloadFailed`

3. **`listAvailableModels() -> [ModelInfo]`** (Lines 52-61)
   - Returns array of available models
   - Uses model registry discovery (Line 58)
   - Publishes events: `listRequested`, `listCompleted`

4. **`downloadModel(_ modelIdentifier: String)`** (Lines 63-121)
   - Downloads a model by ID
   - Updates download status in database (Line 109)
   - Updates model registry (Lines 112-114)
   - Publishes events: `downloadStarted`, `downloadCompleted`, `downloadFailed`

5. **`deleteModel(_ modelIdentifier: String)`** (Lines 123-137)
   - Deletes a model from storage
   - Uses file manager service (Line 131)
   - Publishes events: `deleteStarted`, `deleteCompleted`, `deleteFailed`

6. **`addModelFromURL(_ url: URL, name: String, type: String) -> ModelInfo`** (Lines 139-173)
   - Registers a custom model from URL
   - Creates `ModelInfo` with defaults (Lines 153-167)
   - Registers in model registry (Line 170)
   - Returns `ModelInfo` immediately

7. **`registerBuiltInModel(_ model: ModelInfo)`** (Lines 175-183)
   - Registers a built-in model
   - Adds to model registry (Line 179)
   - Publishes event: `builtInModelRegistered`

**File:** `/sdk/runanywhere-swift/Sources/RunAnywhere/Public/RunAnywhere.swift`

8. **`availableModels() -> [ModelInfo]`** (Lines 521-529)
   - Alternative to `listAvailableModels()`
   - Same functionality, different name
   - Returns models from registry

9. **`currentModel: ModelInfo?`** (Lines 533-540)
   - Read-only property
   - Returns currently loaded model
   - Gets from generation service (Line 539)

### 1.3 Download APIs with Progress

**File:** `/sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/RunAnywhere+Download.swift`

1. **`downloadModelWithProgress(_ modelId: String) -> AsyncStream<DownloadProgress>`** (Lines 18-47)
   - Returns async stream of progress updates
   - Progress includes: `bytesDownloaded`, `totalBytes`, `state`, `speed`, `estimatedTimeRemaining`
   - Checks if already downloaded (Lines 27-40)
   - Creates download task with progress stream (Line 43-46)

**DownloadProgress Structure:**
```swift
struct DownloadProgress {
    let bytesDownloaded: Int64
    let totalBytes: Int64
    let state: DownloadState  // .idle, .downloading, .completed, .failed
    let speed: Double?        // bytes per second
    let estimatedTimeRemaining: TimeInterval?
    var percentage: Double { Double(bytesDownloaded) / Double(totalBytes) }
}
```

### 1.4 Storage APIs

**File:** `/sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/RunAnywhere+Storage.swift`

1. **`getStorageInfo() -> StorageInfo`** (Lines 8-18)
   - Returns comprehensive storage information
   - Uses storage analyzer service (Lines 13-14)
   - Publishes events: `infoRequested`, `infoRetrieved`

2. **`clearCache()`** (Lines 21-32)
   - Clears SDK cache
   - Uses file manager service (Line 26)
   - Publishes events: `clearCacheStarted`, `clearCacheCompleted`, `clearCacheFailed`

3. **`cleanTempFiles()`** (Lines 34-45)
   - Removes temporary files
   - Uses file manager service (Line 40)
   - Publishes events: `cleanTempStarted`, `cleanTempCompleted`, `cleanTempFailed`

4. **`deleteStoredModel(_ modelId: String)`** (Lines 48-61)
   - Deletes a specific stored model
   - Uses file manager service (Line 55)
   - Publishes events: `deleteModelStarted`, `deleteModelCompleted`, `deleteModelFailed`

5. **`getBaseDirectoryURL() -> URL`** (Lines 64-68)
   - Returns base directory for SDK storage
   - Uses file manager service (Line 66)

**StorageInfo Structure:**
```swift
struct StorageInfo {
    let appStorage: AppStorageInfo        // Total app storage
    let deviceStorage: DeviceStorageInfo  // Device-level storage
    let modelStorage: ModelStorageInfo    // Model-specific storage
    let storedModels: [StoredModel]       // List of stored models
}

struct AppStorageInfo {
    let totalSize: Int64
    let cacheSize: Int64
    let tempSize: Int64
}

struct DeviceStorageInfo {
    let totalSpace: Int64
    let freeSpace: Int64
    let usedSpace: Int64
}

struct ModelStorageInfo {
    let totalSize: Int64
    let modelCount: Int
}

struct StoredModel {
    let id: String
    let name: String
    let size: Int64
    let path: URL
    let format: ModelFormat
    let framework: LLMFramework?
    let createdDate: Date
    let lastUsed: Date?
    let checksum: String?
    let contextLength: Int?
    let metadata: ModelInfoMetadata?
}
```

### 1.5 Text Generation APIs

**File:** `/sdk/runanywhere-swift/Sources/RunAnywhere/Public/RunAnywhere.swift`

1. **`chat(_ prompt: String) -> String`** (Lines 358-360)
   - Simple chat method
   - Calls `generate()` with default options
   - Async/await pattern

2. **`generate(_ prompt: String, options: RunAnywhereGenerationOptions?) -> String`** (Lines 367-406)
   - Text generation with options
   - Ensures initialization (Lines 375-377)
   - Lazy device registration (Line 380)
   - Uses generation service (Lines 383-386)
   - Publishes events: `started`, `completed`, `failed`, `costCalculated`
   - Returns generated text

3. **`generateStream(_ prompt: String, options: RunAnywhereGenerationOptions?) -> AsyncThrowingStream<String, Error>`** (Lines 413-455)
   - Streaming text generation
   - Returns async stream of tokens
   - Ensures initialization and device registration (Lines 422-428)
   - Uses streaming service (Lines 430-433)
   - Publishes events for each token (Line 437)
   - Auto-accumulates full response (Line 435)

**RunAnywhereGenerationOptions Structure:**
```swift
struct RunAnywhereGenerationOptions {
    let maxTokens: Int = 100
    let temperature: Float = 0.7
    let topP: Float = 1.0
    let streamingEnabled: Bool = false
    let enableRealTimeTracking: Bool = true
    let stopSequences: [String] = []
    let systemPrompt: String? = nil
}
```

### 1.6 ModelInfo Data Structure

**File:** `/sdk/runanywhere-swift/Sources/RunAnywhere/Core/Models/Model/ModelInfo.swift`

```swift
public struct ModelInfo: Codable, Sendable {
    // Essential identifiers (Lines 7-9)
    public let id: String
    public let name: String
    public let category: ModelCategory

    // Format and location (Lines 11-14)
    public let format: ModelFormat
    public let downloadURL: URL?
    public var localPath: URL?

    // Size information in bytes (Lines 16-18)
    public let downloadSize: Int64?
    public let memoryRequired: Int64?

    // Framework compatibility (Lines 20-22)
    public let compatibleFrameworks: [LLMFramework]
    public let preferredFramework: LLMFramework?

    // Model-specific capabilities (Lines 24-26)
    public let contextLength: Int?
    public let supportsThinking: Bool

    // Optional metadata (Lines 28-29)
    public let metadata: ModelInfoMetadata?

    // Tracking fields (Lines 31-36)
    public let source: ConfigurationSource
    public let createdAt: Date
    public var updatedAt: Date
    public var syncPending: Bool

    // Usage tracking (Lines 38-39)
    public var lastUsed: Date?
    public var usageCount: Int

    // Runtime properties (Lines 41-42)
    public var additionalProperties: [String: String] = [:]

    // Computed properties (Lines 46-55)
    public var isDownloaded: Bool {
        guard let localPath = localPath else { return false }
        return FileManager.default.fileExists(atPath: localPath.path)
    }

    public var isAvailable: Bool { isDownloaded }
}
```

---

## Part 2: iOS Sample App Usage

### 2.1 App Initialization

**File:** `/examples/ios/RunAnywhereAI/RunAnywhereAI/App/RunAnywhereAIApp.swift`

**SDK Initialization Location (Lines 66-139):**

```swift
private func initializeSDK() async {
    // Line 76-82: Determine environment
    #if DEBUG
    let environment = SDKEnvironment.development
    #else
    let environment = SDKEnvironment.production
    #endif

    // Line 87-91: Initialize in development mode
    try RunAnywhere.initialize(
        apiKey: "dev",
        baseURL: "localhost",
        environment: .development
    )

    // Line 95: Register adapters with models
    await registerAdaptersForDevelopment()
}
```

**Model Registration (Lines 148-271):**

All 7 LLM models registered using `registerFrameworkAdapter()` with `ModelRegistration` objects:

```swift
// Lines 166-223: LLM Models
try await RunAnywhere.registerFrameworkAdapter(
    LLMSwiftAdapter(),
    models: [
        // 1. SmolLM2 360M Q8_0 (Lines 168-174)
        try! ModelRegistration(
            url: "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf",
            framework: .llamaCpp,
            id: "smollm2-360m-q8-0",
            name: "SmolLM2 360M Q8_0",
            memoryRequirement: 500_000_000
        ),

        // 2. Qwen 2.5 0.5B Instruct Q6_K (Lines 176-182)
        try! ModelRegistration(
            url: "https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf",
            framework: .llamaCpp,
            id: "qwen-2.5-0.5b-instruct-q6-k",
            name: "Qwen 2.5 0.5B Instruct Q6_K",
            memoryRequirement: 600_000_000
        ),

        // 3. Llama 3.2 1B Instruct Q6_K (Lines 184-190)
        try! ModelRegistration(
            url: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q6_K.gguf",
            framework: .llamaCpp,
            id: "llama-3.2-1b-instruct-q6-k",
            name: "Llama 3.2 1B Instruct Q6_K",
            memoryRequirement: 1_200_000_000
        ),

        // 4. SmolLM2 1.7B Instruct Q6_K_L (Lines 192-198)
        try! ModelRegistration(
            url: "https://huggingface.co/bartowski/SmolLM2-1.7B-Instruct-GGUF/resolve/main/SmolLM2-1.7B-Instruct-Q6_K_L.gguf",
            framework: .llamaCpp,
            id: "smollm2-1.7b-instruct-q6-k-l",
            name: "SmolLM2 1.7B Instruct Q6_K_L",
            memoryRequirement: 1_800_000_000
        ),

        // 5. Qwen 2.5 1.5B Instruct Q6_K (Lines 200-206)
        try! ModelRegistration(
            url: "https://huggingface.co/ZeroWw/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-1.5B-Instruct.q6_k.gguf",
            framework: .llamaCpp,
            id: "qwen-2.5-1.5b-instruct-q6-k",
            name: "Qwen 2.5 1.5B Instruct Q6_K",
            memoryRequirement: 1_600_000_000
        ),

        // 6. LiquidAI LFM2 350M Q4_K_M (Lines 208-214)
        try! ModelRegistration(
            url: "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf",
            framework: .llamaCpp,
            id: "lfm2-350m-q4-k-m",
            name: "LiquidAI LFM2 350M Q4_K_M",
            memoryRequirement: 250_000_000
        ),

        // 7. LiquidAI LFM2 350M Q8_0 (Lines 216-222)
        try! ModelRegistration(
            url: "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf",
            framework: .llamaCpp,
            id: "lfm2-350m-q8-0",
            name: "LiquidAI LFM2 350M Q8_0",
            memoryRequirement: 400_000_000
        )
    ],
    options: lazyOptions
)
```

**Additional Models - WhisperKit (Lines 230-253):**
```swift
// 2 Whisper models for speech-to-text
try await RunAnywhere.registerFrameworkAdapter(
    WhisperKitAdapter.shared,
    models: [
        // Whisper Tiny (Lines 234-241)
        try! ModelRegistration(
            url: "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-tiny.en",
            framework: .whisperKit,
            id: "whisper-tiny",
            name: "Whisper Tiny",
            format: .mlmodel,
            memoryRequirement: 39_000_000
        ),

        // Whisper Base (Lines 243-250)
        try! ModelRegistration(
            url: "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-base",
            framework: .whisperKit,
            id: "whisper-base",
            name: "Whisper Base",
            format: .mlmodel,
            memoryRequirement: 74_000_000
        )
    ],
    options: lazyOptions
)
```

### 2.2 Storage Screen Implementation

**File:** `/examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Storage/StorageView.swift`

**ViewModel File:** `/examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Storage/StorageViewModel.swift`

**SDK API Calls in ViewModel:**

1. **Line 29:** `await RunAnywhere.getStorageInfo()`
   - Retrieves comprehensive storage information
   - Returns `StorageInfo` with app/device/model storage details

2. **Line 48:** `try await RunAnywhere.clearCache()`
   - Clears SDK cache
   - Refreshes data after completion (Line 49)

3. **Line 56:** `try await RunAnywhere.cleanTempFiles()`
   - Removes temporary files
   - Refreshes data after completion (Line 57)

4. **Line 66:** `try await RunAnywhere.deleteStoredModel(modelId)`
   - Deletes a specific model
   - Refreshes data after completion (Line 67)

**Data Displayed (StorageView.swift):**

**Storage Overview Section (Lines 114-148):**
- **Total Usage** (Line 120): `totalStorageSize` from `storageInfo.appStorage.totalSize`
- **Available Space** (Line 128): `availableSpace` from `storageInfo.deviceStorage.freeSpace`
- **Models Storage** (Line 136): `modelStorageSize` from `storageInfo.modelStorage.totalSize`
- **Downloaded Models Count** (Line 144): `storedModels.count`

**Downloaded Models Section (Lines 190-219):**
- Displays list of `StoredModel` objects from `storageInfo.storedModels`
- For each model shows (Lines 329-537):
  - **Name** (Line 340)
  - **Format badge** (Lines 344-349): Model format (GGUF, MLMODEL, etc.)
  - **Framework badge** (Lines 351-358): Framework name if available
  - **Size** (Line 365): File size in human-readable format
  - **Details section** (Lines 392-522) when expanded:
    - Format (Lines 395-401)
    - Framework (Lines 403-411)
    - Context Length (Lines 414-422)
    - Metadata (author, license, description, tags) (Lines 425-472)
    - File path (Lines 479-485)
    - Checksum (Lines 487-497)
    - Created date (Lines 499-505)
    - Last used date (Lines 507-515)

**Storage Management Section (Lines 239-291):**
- **Clear Cache button** (Lines 241-265): Calls `clearCache()`
- **Clean Temporary Files button** (Lines 266-289): Calls `cleanTempFiles()`

### 2.3 Model Management Implementation

**File:** `/examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Models/SimplifiedModelsView.swift`

**How Models Are Listed (Lines 149-193):**
```swift
// Line 152: Filter models by framework
let filteredModels = viewModel.availableModels.filter {
    $0.compatibleFrameworks.contains(expanded)
}

// Line 155: Display models in ForEach
ForEach(filteredModels, id: \.id) { model in
    ModelRow(model: model, ...)
}
```

**How Download Is Triggered (Lines 369-418):**
```swift
private func downloadModel() async {
    // Line 377: Use SDK progress API
    let progressStream = try await RunAnywhere.downloadModelWithProgress(model.id)

    // Line 380-408: Process progress updates
    for await progress in progressStream {
        await MainActor.run {
            self.downloadProgress = progress.percentage  // Line 382
        }

        switch progress.state {
        case .completed:  // Lines 388-395
            // Update UI and notify completion
            return
        case .failed(let error):  // Lines 397-402
            // Handle error
            return
        default:
            continue
        }
    }
}
```

**How Models Are Loaded (Lines 205-210):**
```swift
private func selectModel(_ model: ModelInfo) async {
    selectedModel = model

    // Line 209: Update view model
    await viewModel.selectModel(model)
}
```

**Progress Tracking (Lines 222-224, 294-334):**
```swift
@State private var isDownloading = false
@State private var downloadProgress: Double = 0.0

// Display progress (Lines 295-299)
if isDownloading {
    ProgressView(value: downloadProgress)
    Text("\(Int(downloadProgress * 100))%")
}
```

### 2.4 Chat Implementation

**View File:** `/examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Chat/ChatInterfaceView.swift`
**ViewModel File:** `/examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Chat/ChatViewModel.swift`

**How Text Generation Is Called:**

**ViewModel method (ChatViewModel.swift - not fully shown, but referenced in ChatInterfaceView):**
```swift
// Streaming generation
func sendMessage() async {
    // Uses RunAnywhere.generateStream()
    // Accumulates tokens into message content
}
```

**Generation Options Used:**
- Not explicitly shown in the provided files, but likely uses default `RunAnywhereGenerationOptions`

**Streaming Implementation:**
- Messages are updated in real-time as tokens arrive
- `isGenerating` state tracks generation status
- Thinking mode support with `<think>` tags

**Error Handling:**
- Errors displayed via alerts (Lines 108-112)
- Error state stored in view model
- Debug messages logged (Lines 384-388)

---

## Part 3: Kotlin/KMP SDK API Analysis

### 3.1 SDK Initialization

**File:** `/sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/public/RunAnywhere.kt`

**Interface Definition (Lines 34-38):**
```kotlin
suspend fun initialize(
    apiKey: String,
    baseURL: String? = null,
    environment: SDKEnvironment = SDKEnvironment.DEVELOPMENT
)
```

**Implementation (BaseRunAnywhereSDK, Lines 279-343):**

**Comparison with iOS:**
- ✅ **SAME:** 5-step initialization process (Lines 298-327)
  - Step 1: Validate API key (skip in dev) - Lines 298-306
  - Step 2: Initialize logging - Line 310
  - Step 3: Store parameters locally - Lines 313-320
  - Step 4: Initialize database - Line 324
  - Step 5: Setup local services - Line 327
- ✅ **SAME:** No network calls during init
- ✅ **SAME:** Lazy device registration (Lines 457-560)
- ⚠️ **DIFFERENT:** Uses `String?` for baseURL instead of `URL` (Line 36)

### 3.2 Model Management APIs

**File:** `/sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/public/extensions/RunAnywhere+ModelManagement.kt`

**API Comparison:**

| iOS API | Kotlin API | Status | Notes |
|---------|------------|--------|-------|
| `loadModelWithInfo()` | ✅ `loadModelWithInfo()` | Present | Lines 28-44 |
| `unloadModel()` | ✅ `unloadModel()` | Present | Lines 49-70 |
| `listAvailableModels()` | ✅ `listAvailableModels()` | Present | Lines 76-83 |
| `downloadModel()` | ✅ `downloadModel()` | Present | Lines 89-134 |
| `deleteModel()` | ✅ `deleteModel()` | Present | Lines 140-151 |
| `addModelFromURL()` | ✅ `addModelFromURL()` | Present | Lines 160-222 |
| `registerBuiltInModel()` | ✅ `registerBuiltInModel()` | Present | Lines 228-233 |
| `availableModels()` | ✅ `availableModels()` | Present | In RunAnywhere.kt:132 |
| `currentModel` property | ✅ `currentModel` property | Present | In RunAnywhere.kt:153 |

**Additional Kotlin APIs not in iOS:**
- `getCurrentModel()` (Line 238)
- `isModelLoaded()` (Line 245)
- `getTotalModelsSize()` (Line 252)
- `clearAllModels()` (Line 259)
- `isModelAvailable()` (Line 266)

**Key Differences:**

1. **URL vs String (Lines 161-164):**
   ```kotlin
   // Kotlin uses String for URL
   suspend fun addModelFromURL(
       url: String,  // <-- String instead of URL
       name: String,
       type: String
   ): ModelInfo
   ```
   iOS uses `URL` type, Kotlin uses `String`

2. **Return Types:**
   - iOS: Returns `ModelInfo` synchronously from `addModelFromURL()`
   - Kotlin: Returns `ModelInfo` as suspend function (async)

3. **Error Handling:**
   - iOS: Throws Swift errors
   - Kotlin: Throws `SDKError` sealed class exceptions

### 3.3 Download APIs

**File:** `/sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/public/RunAnywhere.kt`

**API Comparison:**

| iOS API | Kotlin API | Status | Notes |
|---------|------------|--------|-------|
| `downloadModel()` | ✅ `downloadModel()` | Present | Line 137 |
| `downloadModelWithProgress()` | ❌ **MISSING** | **NOT FOUND** | **CRITICAL GAP** |

**Critical Gap:**
The iOS SDK provides `downloadModelWithProgress()` which returns an `AsyncStream<DownloadProgress>` for real-time progress updates. The Kotlin SDK has `downloadModel()` but **NO streaming progress API**.

**Impact:**
- Android app cannot show real-time download progress
- Users see "downloading" state but no percentage
- Poor UX compared to iOS

### 3.4 Storage APIs

**File:** Not found as an extension file in Kotlin SDK

**API Comparison:**

| iOS API | Kotlin API | Status | Notes |
|---------|------------|--------|-------|
| `getStorageInfo()` | ❌ **MISSING** | **NOT FOUND** | **CRITICAL GAP** |
| `clearCache()` | ❌ **MISSING** | **NOT FOUND** | **CRITICAL GAP** |
| `cleanTempFiles()` | ❌ **MISSING** | **NOT FOUND** | **CRITICAL GAP** |
| `deleteStoredModel()` | ❌ **MISSING** | **NOT FOUND** | **CRITICAL GAP** |
| `getBaseDirectoryURL()` | ❌ **MISSING** | **NOT FOUND** | **CRITICAL GAP** |

**Critical Gap:**
**ALL storage APIs are missing from Kotlin SDK.** This is why the Android Storage screen is unimplemented.

### 3.5 Text Generation APIs

**File:** `/sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/public/RunAnywhere.kt`

**API Comparison:**

| iOS API | Kotlin API | Status | Notes |
|---------|------------|--------|-------|
| `chat()` | ✅ `chat()` | Present | Line 591 |
| `generate()` | ✅ `generate()` | Present | Lines 598-658 |
| `generateStream()` | ✅ `generateStream()` | Present | Lines 663-723 |

**Implementation Details:**

1. **`chat()` (Lines 591-593):**
   ```kotlin
   override suspend fun chat(prompt: String): String {
       return generate(prompt, RunAnywhereGenerationOptions.DEFAULT)
   }
   ```
   ✅ Same as iOS

2. **`generate()` (Lines 598-658):**
   - ✅ Lazy device registration (Line 605)
   - ✅ Uses generation service
   - ✅ Fallback to LLM component
   - ⚠️ Different service architecture but same functionality

3. **`generateStream()` (Lines 663-723):**
   - ✅ Returns `Flow<String>` (Kotlin equivalent of `AsyncStream`)
   - ✅ Uses streaming service
   - ✅ Fallback to LLM component
   - ✅ Same functionality as iOS

**Additional Kotlin APIs not in iOS:**
- `generateWithHistory()` (Lines 773-786)
- `clearConversationContext()` (Lines 792-797)
- `estimateTokens()` (Lines 806-813)
- `fitsInContext()` (Lines 823-830)

### 3.6 ModelInfo Data Structure

**File:** `/sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/models/ModelInfo.kt`

**Comparison with iOS:**

| Field | iOS Type | Kotlin Type | Match? |
|-------|----------|-------------|--------|
| `id` | `String` | `String` | ✅ |
| `name` | `String` | `String` | ✅ |
| `category` | `ModelCategory` | `ModelCategory` | ✅ |
| `format` | `ModelFormat` | `ModelFormat` | ✅ |
| `downloadURL` | `URL?` | `String?` | ⚠️ Type diff |
| `localPath` | `URL?` | `String?` | ⚠️ Type diff |
| `downloadSize` | `Int64?` | `Long?` | ✅ (same type) |
| `memoryRequired` | `Int64?` | `Long?` | ✅ |
| `compatibleFrameworks` | `[LLMFramework]` | `List<LLMFramework>` | ✅ |
| `preferredFramework` | `LLMFramework?` | `LLMFramework?` | ✅ |
| `contextLength` | `Int?` | `Int?` | ✅ |
| `supportsThinking` | `Bool` | `Boolean` | ✅ |
| `metadata` | `ModelInfoMetadata?` | `ModelInfoMetadata?` | ✅ |
| `source` | `ConfigurationSource` | `ConfigurationSource` | ✅ |
| `createdAt` | `Date` | `SimpleInstant` | ⚠️ Type diff |
| `updatedAt` | `Date` | `SimpleInstant` | ⚠️ Type diff |
| `syncPending` | `Bool` | `Boolean` | ✅ |
| `lastUsed` | `Date?` | `SimpleInstant?` | ⚠️ Type diff |
| `usageCount` | `Int` | `Int` | ✅ |
| `additionalProperties` | `[String: String]` | `Map<String, String>` | ✅ |
| **EXTRA in Kotlin** | - | `sha256Checksum` | ➕ |
| **EXTRA in Kotlin** | - | `md5Checksum` | ➕ |

**Key Differences:**
1. **URL vs String:** iOS uses `URL` type, Kotlin uses `String` (pragmatic choice for KMP)
2. **Date vs SimpleInstant:** iOS uses `Date`, Kotlin uses custom `SimpleInstant` (KMP compatibility)
3. **Checksums:** Kotlin has additional checksum fields for integrity verification

---

## Part 4: Android Sample App Implementation Analysis

### 4.1 App Initialization

**File:** `/examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/RunAnywhereApplication.kt`

**SDK Initialization (Lines 33-107):**

```kotlin
private suspend fun initializeSDK() {
    // Lines 41-47: Determine environment (same as iOS)
    val environment = if (BuildConfig.DEBUG) {
        SDKEnvironment.DEVELOPMENT
    } else {
        SDKEnvironment.PRODUCTION
    }

    // Lines 52-57: Initialize SDK
    RunAnywhere.initialize(
        context = this@RunAnywhereApplication,
        apiKey = "dev",
        baseURL = "localhost",
        environment = SDKEnvironment.DEVELOPMENT
    )

    // Line 61: Register models
    registerModelsForDevelopment()
}
```

**Model Registration (Lines 113-188):**

All 7 models registered using `addModelFromURL()`:

```kotlin
// 1. SmolLM2 360M Q8_0 (Lines 121-125)
addModelFromURL(
    url = "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf",
    name = "SmolLM2 360M Q8_0",
    type = "LLM"
)

// 2. Qwen 2.5 0.5B Instruct Q6_K (Lines 129-133)
addModelFromURL(
    url = "https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf",
    name = "Qwen 2.5 0.5B Instruct Q6_K",
    type = "LLM"
)

// 3. Llama 3.2 1B Instruct Q6_K (Lines 136-140)
addModelFromURL(
    url = "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q6_K.gguf",
    name = "Llama 3.2 1B Instruct Q6_K",
    type = "LLM"
)

// 4. SmolLM2 1.7B Instruct Q6_K_L (Lines 144-148)
addModelFromURL(
    url = "https://huggingface.co/bartowski/SmolLM2-1.7B-Instruct-GGUF/resolve/main/SmolLM2-1.7B-Instruct-Q6_K_L.gguf",
    name = "SmolLM2 1.7B Instruct Q6_K_L",
    type = "LLM"
)

// 5. Qwen 2.5 1.5B Instruct Q6_K (Lines 152-156)
addModelFromURL(
    url = "https://huggingface.co/ZeroWw/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-1.5B-Instruct.q6_k.gguf",
    name = "Qwen 2.5 1.5B Instruct Q6_K",
    type = "LLM"
)

// 6. LiquidAI LFM2 350M Q4_K_M (Lines 161-165)
addModelFromURL(
    url = "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf",
    name = "LiquidAI LFM2 350M Q4_K_M",
    type = "LLM"
)

// 7. LiquidAI LFM2 350M Q8_0 (Lines 169-173)
addModelFromURL(
    url = "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf",
    name = "LiquidAI LFM2 350M Q8_0",
    type = "LLM"
)
```

**Comparison with iOS:**
- ✅ **SAME:** All 7 LLM models registered with identical URLs
- ⚠️ **DIFFERENT:** Uses `addModelFromURL()` directly instead of adapter pattern
- ⚠️ **MISSING:** No Whisper models registered (iOS registers 2 Whisper models)

### 4.2 Storage Screen

**File:** `/examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/presentation/storage/StorageScreen.kt`

**Current Implementation (Lines 11-27):**

```kotlin
@Composable
fun StorageScreen() {
    Column(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Text(
            text = "Storage Management",
            style = MaterialTheme.typography.headlineMedium
        )
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = "Model storage and management coming soon",
            style = MaterialTheme.typography.bodyMedium
        )
    }
}
```

**Status:** ❌ **COMPLETELY UNIMPLEMENTED**

**Missing Implementation:**
1. No ViewModel
2. No SDK API calls
3. No data display
4. No storage information
5. No model deletion
6. No cache clearing

**Reason:** Kotlin SDK is missing all storage APIs (`getStorageInfo()`, `clearCache()`, etc.)

### 4.3 Model Management

**Android already has model selection and download implementation** - analyzed in previous reports.

**Key Differences from iOS:**
1. ✅ Model listing works
2. ✅ Model download works
3. ⚠️ No real-time progress percentage (iOS shows %, Android shows spinner)
4. ✅ Model loading works

### 4.4 Chat Implementation

**File:** `/examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/presentation/chat/ChatViewModel.kt`

**How Text Generation Is Called (Lines 148-158):**

```kotlin
generationJob = viewModelScope.launch {
    try {
        if (currentState.useStreaming) {
            generateWithStreaming(prompt, assistantMessage.id)
        } else {
            generateWithoutStreaming(prompt, assistantMessage.id)
        }
    } catch (e: Exception) {
        handleGenerationError(e, assistantMessage.id)
    }
}
```

**Streaming Implementation (Lines 165-294):**

```kotlin
private suspend fun generateWithStreaming(prompt: String, messageId: String) {
    // Line 182: Use SDK streaming API
    RunAnywhere.generateStream(prompt)
        .collect { token ->
            fullResponse += token
            totalTokensReceived++

            // Lines 202-231: Handle thinking mode
            if (fullResponse.contains("<think>")) {
                // Extract thinking content
            }

            // Line 234-238: Update message
            updateAssistantMessage(
                messageId = messageId,
                content = responseContent,
                thinkingContent = thinkingContent
            )
        }
}
```

**Non-Streaming Implementation (Lines 299-331):**

```kotlin
private suspend fun generateWithoutStreaming(prompt: String, messageId: String) {
    // Line 303: Use SDK generate API
    val response = RunAnywhere.generate(prompt)

    // Line 306: Update message
    updateAssistantMessage(messageId, response, null)
}
```

**Generation Options:**
- Default options used (no custom options passed)
- Streaming enabled by default (Line 31: `useStreaming: Boolean = true`)

**Error Handling (Lines 336-350):**
```kotlin
private fun handleGenerationError(error: Exception, messageId: String) {
    val errorMessage = when {
        !_uiState.value.isModelLoaded -> "❌ No model is loaded..."
        else -> "❌ Generation failed: ${error.message}"
    }

    updateAssistantMessage(messageId, errorMessage, null)
    _uiState.value = _uiState.value.copy(
        isGenerating = false,
        error = error
    )
}
```

**Comparison with iOS:**
- ✅ **SAME:** Streaming support with token-by-token updates
- ✅ **SAME:** Thinking mode support with `<think>` tags
- ✅ **SAME:** Analytics tracking (lines 390-456)
- ✅ **SAME:** Error handling patterns
- ✅ **SAME:** Message history management

---

## Part 5: Gap Analysis & Priority List

### Priority 1: Critical SDK APIs Missing

#### 1.1 Storage APIs (ALL MISSING)

**Impact:** ⚠️ **CRITICAL** - Storage screen cannot be implemented

**Missing APIs:**
1. `getStorageInfo() -> StorageInfo`
   - **iOS Location:** `RunAnywhere+Storage.swift:8-18`
   - **Kotlin Location:** NOT FOUND
   - **Impact:** Cannot display storage overview

2. `clearCache()`
   - **iOS Location:** `RunAnywhere+Storage.swift:21-32`
   - **Kotlin Location:** NOT FOUND
   - **Impact:** Cannot clear SDK cache

3. `cleanTempFiles()`
   - **iOS Location:** `RunAnywhere+Storage.swift:34-45`
   - **Kotlin Location:** NOT FOUND
   - **Impact:** Cannot clean temporary files

4. `deleteStoredModel(_ modelId: String)`
   - **iOS Location:** `RunAnywhere+Storage.swift:48-61`
   - **Kotlin Location:** NOT FOUND
   - **Impact:** Cannot delete individual models from storage screen

5. `getBaseDirectoryURL() -> URL`
   - **iOS Location:** `RunAnywhere+Storage.swift:64-68`
   - **Kotlin Location:** NOT FOUND
   - **Impact:** Cannot show storage location

**Required Data Structures:**
```kotlin
// Need to create these in Kotlin SDK
data class StorageInfo(
    val appStorage: AppStorageInfo,
    val deviceStorage: DeviceStorageInfo,
    val modelStorage: ModelStorageInfo,
    val storedModels: List<StoredModel>
)

data class AppStorageInfo(
    val totalSize: Long,
    val cacheSize: Long,
    val tempSize: Long
)

data class DeviceStorageInfo(
    val totalSpace: Long,
    val freeSpace: Long,
    val usedSpace: Long
)

data class ModelStorageInfo(
    val totalSize: Long,
    val modelCount: Int
)

data class StoredModel(
    val id: String,
    val name: String,
    val size: Long,
    val path: String,
    val format: ModelFormat,
    val framework: LLMFramework?,
    val createdDate: SimpleInstant,
    val lastUsed: SimpleInstant?,
    val checksum: String?,
    val contextLength: Int?,
    val metadata: ModelInfoMetadata?
)
```

#### 1.2 Download Progress API

**Impact:** ⚠️ **HIGH** - Cannot show real-time download progress

**Missing API:**
```kotlin
// iOS API
fun downloadModelWithProgress(modelId: String): AsyncStream<DownloadProgress>

// Kotlin equivalent needed
fun downloadModelWithProgress(modelId: String): Flow<DownloadProgress>
```

**Required Data Structure:**
```kotlin
data class DownloadProgress(
    val bytesDownloaded: Long,
    val totalBytes: Long,
    val state: DownloadState,
    val speed: Double?,  // bytes per second
    val estimatedTimeRemaining: Long?  // milliseconds
) {
    val percentage: Double
        get() = bytesDownloaded.toDouble() / totalBytes.toDouble()
}

enum class DownloadState {
    IDLE,
    DOWNLOADING,
    COMPLETED,
    FAILED
}
```

**Current Workaround:**
- Android app shows spinner without progress percentage
- iOS app shows "27%" style progress

### Priority 2: Sample App Implementation Gaps

#### 2.1 Storage Screen (Android)

**Status:** ❌ **COMPLETELY UNIMPLEMENTED**

**What iOS Has:**
1. Storage overview with 4 metrics
2. List of downloaded models with details
3. Model deletion functionality
4. Cache clearing
5. Temporary files cleanup

**What Android Needs:**
1. Create `StorageViewModel.kt`
2. Implement `StorageScreen.kt` UI
3. Add storage APIs to Kotlin SDK first (see Priority 1.1)
4. Mirror iOS functionality

**Effort Estimate:** 3-4 days (after SDK APIs are added)

#### 2.2 Download Progress UI (Android)

**Current State:**
- Shows "Downloading..." text with spinner
- No percentage shown

**What iOS Has:**
- Real-time progress percentage (e.g., "27%")
- Progress bar with visual feedback
- Download speed (optional)
- Time remaining (optional)

**What Android Needs:**
1. Add `downloadModelWithProgress()` to Kotlin SDK (see Priority 1.2)
2. Update `ModelRow` in Models screen to show percentage
3. Add progress bar UI component

**Effort Estimate:** 1 day (after SDK API is added)

#### 2.3 Whisper Models Registration (Android)

**Current State:**
- Only 7 LLM models registered
- No STT models

**What iOS Has:**
- 7 LLM models + 2 Whisper models
- Framework adapter pattern for STT

**What Android Needs:**
- Decide on STT model registration approach
- Either:
  - Option A: Register Whisper models using `addModelFromURL()`
  - Option B: Implement adapter pattern like iOS

**Effort Estimate:** 2-3 hours

### Priority 3: Data Structure Inconsistencies

#### 3.1 URL vs String Type Differences

**iOS ModelInfo:**
```swift
public let downloadURL: URL?
public var localPath: URL?
```

**Kotlin ModelInfo:**
```kotlin
val downloadURL: String?
var localPath: String?
```

**Impact:** Low - This is a pragmatic choice for KMP compatibility

**Recommendation:** Keep as-is (String is more KMP-friendly)

#### 3.2 Date vs SimpleInstant

**iOS:**
```swift
public let createdAt: Date
public var updatedAt: Date
public var lastUsed: Date?
```

**Kotlin:**
```kotlin
val createdAt: SimpleInstant
var updatedAt: SimpleInstant
var lastUsed: SimpleInstant?
```

**Impact:** Low - Custom `SimpleInstant` provides KMP compatibility

**Recommendation:** Keep as-is

#### 3.3 Checksum Fields (Kotlin Only)

**Kotlin has extra fields:**
```kotlin
val sha256Checksum: String?
val md5Checksum: String?
```

**Impact:** Low - These are useful additions for integrity verification

**Recommendation:** Consider adding to iOS SDK as well

---

## Action Items

### Immediate (Week 1)

**High Priority:**

1. ✅ **Add Storage APIs to Kotlin SDK**
   - [ ] Create `RunAnywhere+Storage.kt` extension file
   - [ ] Implement `getStorageInfo()`
   - [ ] Implement `clearCache()`
   - [ ] Implement `cleanTempFiles()`
   - [ ] Implement `deleteStoredModel()`
   - [ ] Implement `getBaseDirectoryURL()`
   - [ ] Create required data structures (StorageInfo, StoredModel, etc.)
   - **Files to create:**
     - `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/public/extensions/RunAnywhere+Storage.kt`
     - `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/models/StorageInfo.kt`
   - **Estimated effort:** 2 days

2. ✅ **Add Download Progress API to Kotlin SDK**
   - [ ] Create `RunAnywhere+Download.kt` extension file
   - [ ] Implement `downloadModelWithProgress()`
   - [ ] Create `DownloadProgress` data class
   - [ ] Create `DownloadState` enum
   - **Files to create:**
     - `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/public/extensions/RunAnywhere+Download.kt`
     - `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/models/DownloadProgress.kt`
   - **Estimated effort:** 1 day

### Short Term (Week 2)

**High Priority:**

3. ✅ **Implement Android Storage Screen**
   - [ ] Create `StorageViewModel.kt`
   - [ ] Implement storage data loading
   - [ ] Create `StorageScreen.kt` UI matching iOS design
   - [ ] Add model deletion functionality
   - [ ] Add cache/temp file cleanup buttons
   - **Files to create:**
     - `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/presentation/storage/StorageViewModel.kt`
     - Update: `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/presentation/storage/StorageScreen.kt`
   - **Estimated effort:** 2 days

4. ✅ **Add Download Progress UI to Android**
   - [ ] Update model download logic to use `downloadModelWithProgress()`
   - [ ] Add progress bar UI component
   - [ ] Show percentage during download
   - **Files to update:**
     - Models screen where download happens
   - **Estimated effort:** 4 hours

### Medium Term (Week 3-4)

**Medium Priority:**

5. ✅ **Add Whisper Models to Android**
   - [ ] Decide on STT model registration approach
   - [ ] Register 2 Whisper models (Tiny and Base)
   - [ ] Test STT functionality if available
   - **Files to update:**
     - `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/RunAnywhereApplication.kt`
   - **Estimated effort:** 3 hours

6. ✅ **Documentation Updates**
   - [ ] Update Android sample app README with storage features
   - [ ] Document storage API usage examples
   - [ ] Add download progress API examples
   - **Estimated effort:** 2 hours

### Long Term (Backlog)

**Low Priority:**

7. ⭕ **Consider Adding Checksums to iOS ModelInfo**
   - [ ] Evaluate benefit of `sha256Checksum` and `md5Checksum` fields
   - [ ] Add to iOS `ModelInfo` if valuable
   - **Estimated effort:** 1 hour

---

## Appendix: Model Registration Comparison

### iOS Model Registration (Adapter Pattern)

**Location:** `examples/ios/RunAnywhereAI/RunAnywhereAI/App/RunAnywhereAIApp.swift:148-271`

```swift
try await RunAnywhere.registerFrameworkAdapter(
    LLMSwiftAdapter(),
    models: [
        try! ModelRegistration(
            url: "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf",
            framework: .llamaCpp,
            id: "smollm2-360m-q8-0",
            name: "SmolLM2 360M Q8_0",
            memoryRequirement: 500_000_000
        ),
        // ... 6 more models
    ],
    options: lazyOptions
)
```

**Characteristics:**
- Uses framework adapter pattern
- Registers multiple models at once
- Includes framework-specific configuration
- Supports lazy loading via options

### Android Model Registration (Direct Pattern)

**Location:** `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/RunAnywhereApplication.kt:113-188`

```kotlin
addModelFromURL(
    url = "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf",
    name = "SmolLM2 360M Q8_0",
    type = "LLM"
)
// ... 6 more calls
```

**Characteristics:**
- Direct model registration
- One call per model
- Simpler API
- No framework adapter concept

### Side-by-Side: All 7 Models

| # | Model Name | iOS ID | Android Name | URL Match? |
|---|------------|--------|--------------|------------|
| 1 | SmolLM2 360M Q8_0 | `smollm2-360m-q8-0` | SmolLM2 360M Q8_0 | ✅ Identical |
| 2 | Qwen 2.5 0.5B Q6_K | `qwen-2.5-0.5b-instruct-q6-k` | Qwen 2.5 0.5B Instruct Q6_K | ✅ Identical |
| 3 | Llama 3.2 1B Q6_K | `llama-3.2-1b-instruct-q6-k` | Llama 3.2 1B Instruct Q6_K | ✅ Identical |
| 4 | SmolLM2 1.7B Q6_K_L | `smollm2-1.7b-instruct-q6-k-l` | SmolLM2 1.7B Instruct Q6_K_L | ✅ Identical |
| 5 | Qwen 2.5 1.5B Q6_K | `qwen-2.5-1.5b-instruct-q6-k` | Qwen 2.5 1.5B Instruct Q6_K | ✅ Identical |
| 6 | LiquidAI LFM2 350M Q4_K_M | `lfm2-350m-q4-k-m` | LiquidAI LFM2 350M Q4_K_M | ✅ Identical |
| 7 | LiquidAI LFM2 350M Q8_0 | `lfm2-350m-q8-0` | LiquidAI LFM2 350M Q8_0 | ✅ Identical |

**Additional iOS Models (Not in Android):**

| # | Model Name | Framework | ID |
|---|------------|-----------|-----|
| 8 | Whisper Tiny | WhisperKit | `whisper-tiny` |
| 9 | Whisper Base | WhisperKit | `whisper-base` |

---

## Part 6: Library Dependencies Comparison

### 6.1 iOS SDK Dependencies (Package.swift)

**File:** `/sdk/runanywhere-swift/Package.swift`

The iOS SDK uses the following Swift Package Manager dependencies:

1. **swift-crypto (3.0.0+)** - Lines 19
   - Purpose: Cryptographic operations (hashing, encryption)
   - Platform: Apple platforms
   - Category: Security/Cryptography

2. **Alamofire (5.9.0+)** - Lines 20
   - Purpose: HTTP networking, download/upload management with progress tracking
   - Platform: Apple platforms
   - Category: Networking
   - **Key Features:**
     - Elegant HTTP request/response handling
     - Download progress tracking with percentage and speed
     - Upload progress tracking
     - Request/response serialization
     - Session management
     - Network reachability
     - **Used for:** Model downloads with progress streams in `RunAnywhere+Download.swift`

3. **Files (4.3.0+)** - Lines 21
   - Purpose: File system operations (reading, writing, organizing files)
   - Platform: Apple platforms
   - Category: File Management
   - **Key Features:**
     - Simplified file system operations
     - Type-safe file paths
     - Directory traversal
     - File metadata access

4. **ZIPFoundation (0.9.0+)** - Lines 22
   - Purpose: ZIP compression and decompression
   - Platform: Apple platforms
   - Category: File Management
   - **Used for:** Model archive extraction after download

5. **GRDB.swift (7.6.1+)** - Lines 23
   - Purpose: SQLite database with Swift bindings
   - Platform: Apple platforms
   - Category: Database
   - **Key Features:**
     - Type-safe SQL queries
     - Migration management
     - Database observations
     - **Used for:** Local model metadata, configuration storage, analytics caching

6. **DeviceKit (5.6.0+)** - Lines 24
   - Purpose: Device information (model, OS, capabilities)
   - Platform: Apple platforms
   - Category: Device Information

7. **SwiftLintPlugins (0.57.1+)** - Lines 25
   - Purpose: Code quality and style enforcement
   - Category: Development Tools

8. **Pulse (4.0.0+)** - Lines 26
   - Purpose: Logging and network debugging
   - Platform: Apple platforms
   - Category: Logging/Debugging
   - **Key Features:**
     - Structured logging
     - Network traffic inspection
     - Performance monitoring

**Summary:**
- **Total Dependencies:** 8
- **Core Functionality:** Networking (Alamofire), Database (GRDB), File Management (Files, ZIPFoundation)
- **Platform:** iOS 14+, macOS 12+, tvOS 14+, watchOS 7+

### 6.2 Kotlin SDK Dependencies (build.gradle.kts)

**File:** `/sdk/runanywhere-kotlin/build.gradle.kts`

The Kotlin SDK uses the following dependencies:

#### CommonMain Dependencies (Lines 42-52):
1. **kotlinx-coroutines-core**
   - Purpose: Asynchronous programming
   - Platform: All KMP targets
   - Category: Concurrency

2. **kotlinx-serialization-json**
   - Purpose: JSON serialization/deserialization
   - Platform: All KMP targets
   - Category: Serialization

3. **kotlinx-datetime**
   - Purpose: Date/time operations
   - Platform: All KMP targets
   - Category: Date/Time

4. **ktor-client-core**
   - Purpose: HTTP networking (KMP native)
   - Platform: All KMP targets
   - Category: Networking
   - **Key Features:**
     - Multiplatform HTTP client
     - Coroutine-based async operations
     - Plugin architecture (logging, content negotiation)

5. **ktor-client-content-negotiation**
   - Purpose: Automatic serialization/deserialization
   - Category: Networking

6. **ktor-client-logging**
   - Purpose: Network request/response logging
   - Category: Networking/Debugging

7. **ktor-serialization-kotlinx-json**
   - Purpose: JSON serialization for Ktor
   - Category: Networking/Serialization

#### JVM & Android Shared Dependencies (Lines 63-72):
8. **whisper-jni**
   - Purpose: Speech-to-text (Whisper model JNI bindings)
   - Category: AI/ML

9. **okhttp (3.x)**
   - Purpose: HTTP client (used as Ktor engine)
   - Platform: JVM, Android
   - Category: Networking
   - **Key Features:**
     - Connection pooling
     - HTTP/2 support
     - Transparent GZIP compression
     - Response caching

10. **okhttp-logging**
    - Purpose: HTTP request/response logging
    - Category: Networking/Debugging

11. **gson**
    - Purpose: JSON serialization (Google)
    - Platform: JVM, Android
    - Category: Serialization

12. **commons-io**
    - Purpose: File I/O utilities
    - Platform: JVM, Android
    - Category: File Management
    - **Key Features:**
      - File operations
      - Stream utilities
      - File size calculations

13. **ktor-client-okhttp**
    - Purpose: OkHttp engine for Ktor
    - Category: Networking

#### Android-Specific Dependencies (Lines 86-99):
14. **androidx.core-ktx**
    - Purpose: Android core utilities
    - Category: Android Framework

15. **kotlinx-coroutines-android**
    - Purpose: Android-specific coroutine dispatchers
    - Category: Concurrency

16. **android-vad-webrtc**
    - Purpose: Voice activity detection
    - Category: Audio/ML

17. **prdownloader**
    - Purpose: Download manager with progress tracking
    - Category: Networking/Downloads
    - **Key Features:**
      - Progress callbacks
      - Pause/resume support
      - Download queue management

18. **androidx.work-runtime-ktx**
    - Purpose: Background task management
    - Category: Android Framework

19. **androidx.room-runtime & androidx.room-ktx**
    - Purpose: SQLite database (Android Jetpack)
    - Category: Database
    - **Key Features:**
      - Type-safe SQL queries with compile-time verification
      - LiveData/Flow integration
      - Migration support
      - **NOTE:** Room 2.7.0+ supports KMP

20. **androidx.security-crypto**
    - Purpose: Encrypted storage (SharedPreferences, files)
    - Category: Security

21. **retrofit & retrofit-gson**
    - Purpose: Type-safe HTTP client
    - Category: Networking
    - **Key Features:**
      - Declarative API definitions
      - Built-in serialization support
      - Error handling

**Summary:**
- **Total Dependencies:** 21 (7 commonMain + 6 jvmAndroid + 8 Android)
- **Core Functionality:** Networking (Ktor + OkHttp + Retrofit), Database (Room), File Management (commons-io)
- **Platform:** JVM 17+, Android API 24+

### 6.3 Android Example App Dependencies

**File:** `/examples/android/RunAnywhereAI/app/build.gradle.kts`

Additional dependencies in the example app (Lines 200-274):

1. **Compose BOM** - Complete Jetpack Compose UI toolkit
2. **Navigation Compose** - Navigation between screens
3. **Material 3** - Material Design components
4. **Accompanist Permissions** - Permission handling in Compose
5. **Play Core** - In-app updates
6. **Timber** - Logging library

### 6.4 Critical Library Gaps Analysis

#### Gap 1: Download Progress Tracking

**iOS (Alamofire):**
```swift
// RunAnywhere+Download.swift: Lines 18-47
func downloadModelWithProgress(_ modelId: String) -> AsyncStream<DownloadProgress> {
    // Returns real-time progress: bytesDownloaded, totalBytes, speed, ETA
}
```

**Kotlin (Current):**
- **Ktor:** No built-in streaming progress API in current implementation
- **OkHttp:** Has progress interceptors but not exposed in SDK
- **prdownloader:** Android-specific, not in SDK public API

**Impact:** Android cannot show real-time download percentage like iOS

#### Gap 2: File Management Capabilities

**iOS (Files + FileManager):**
- Files library: 12K GitHub stars, actively maintained
- Full file system abstraction
- Directory traversal and metadata

**Kotlin (commons-io):**
- Apache Commons IO: 1.3K GitHub stars
- Basic file utilities
- No elegant file system abstraction like iOS

**Missing in Kotlin:**
- Modern file system API like Okio
- File metadata operations
- Storage calculation utilities

#### Gap 3: ZIP Handling

**iOS (ZIPFoundation):**
- Native Swift ZIP library
- Used for model archive extraction

**Kotlin:**
- Not explicitly listed in dependencies
- May rely on Java's built-in ZIP support

#### Gap 4: Database Parity

**iOS (GRDB):**
- 6.8K GitHub stars
- Swift-native SQLite
- Database observations (reactive)

**Kotlin (Room):**
- Official Android Jetpack library
- KMP support since v2.7.0
- Flow integration

**Status:** Both are production-ready, Room is catching up with KMP support

### 6.5 Missing iOS Extension APIs in Kotlin SDK

#### Configuration APIs (RunAnywhere+Configuration.swift)

**iOS APIs:**
1. `getCurrentGenerationSettings()` - Lines 10-19
2. `getCurrentRoutingPolicy()` - Lines 23-30
3. `syncUserPreferences()` - Lines 33-44

**Kotlin Status:** ❌ Not found in Kotlin SDK

#### Logging APIs (RunAnywhere+Logging.swift)

**iOS APIs:**
1. `configureSDKLogging(endpoint:enabled:)` - Lines 19-21
2. `configureLocalLogging(enabled:)` - Lines 25-29
3. `setLogLevel(_:)` - Lines 33-37
4. `setDebugMode(_:)` - Lines 63-77
5. `flushAll()` - Lines 80-86

**Kotlin Status:** ❌ Not found in Kotlin SDK

#### Framework Management APIs (RunAnywhere+Frameworks.swift)

**iOS APIs:**
1. `registerFrameworkAdapter(_:models:options:)` - Lines 30-116
2. `getRegisteredAdapters()` - Lines 120-132
3. `getAvailableFrameworks()` - Lines 136-148
4. `getFrameworkAvailability()` - Lines 152-164
5. `getModelsForFramework(_:)` - Lines 169-184
6. `getFrameworks(for:)` - Lines 189-204
7. `getPrimaryModality(for:)` - Lines 209-214
8. `frameworkSupports(_:modality:)` - Lines 221-226

**Kotlin Status:** ⚠️ Partially implemented (basic adapter registration exists)

#### Model Assignment APIs (RunAnywhere+ModelAssignments.swift)

**iOS APIs:**
1. `fetchModelAssignments(forceRefresh:)` - Lines 12-59
2. `getModelsForFramework(_:)` - Lines 64-81
3. `getModelsForCategory(_:)` - Lines 86-103
4. `clearModelAssignmentsCache()` - Lines 106-117

**Kotlin Status:** ❌ Not found in Kotlin SDK

#### Structured Output APIs (RunAnywhere+StructuredOutput.swift)

**iOS APIs:**
1. `generateStructured<T>(_:prompt:options:)` - Lines 96-149
2. `generateStructuredStream<T>(_:content:options:)` - Lines 157-254
3. `generateWithStructuredOutput(prompt:structuredOutput:options:)` - Lines 262-307

**Kotlin Status:** ⚠️ Type definitions exist in `ExtensionTypes.kt` but implementations not found

#### Voice APIs (RunAnywhere+Voice.swift)

**iOS APIs:**
1. `transcribe(audio:modelId:options:)` - Lines 13-67
2. `createVoiceConversation(sttModelId:llmModelId:ttsVoice:)` - Lines 75-103
3. `processVoiceTurn(audio:sttModelId:llmModelId:ttsVoice:)` - Lines 112-148

**Kotlin Status:** ⚠️ Type definitions exist but implementations not found

### 6.6 Summary: Extension API Coverage

**iOS SDK Extension Files Found: 9**
1. RunAnywhere+Configuration.swift (3 methods)
2. RunAnywhere+Download.swift (1 method - already documented)
3. RunAnywhere+Frameworks.swift (8 methods)
4. RunAnywhere+Logging.swift (5 methods)
5. RunAnywhere+ModelAssignments.swift (4 methods)
6. RunAnywhere+ModelManagement.swift (9 methods - already documented)
7. RunAnywhere+Storage.swift (5 methods - already documented)
8. RunAnywhere+StructuredOutput.swift (3 methods)
9. RunAnywhere+Voice.swift (3 methods)

**Total iOS Extension Methods: 41**

**Kotlin SDK Extension Files Found: 3**
1. ExtensionTypes.kt (type definitions only)
2. RunAnywhere+ModelManagement.kt (9 methods - already documented)
3. RunAnywhereExtensions.kt (documentation placeholder)

**Kotlin Extension Methods Actually Implemented: 9**
**Kotlin Extension Methods Missing: 32**

**API Coverage:**
- Model Management: 9/9 (100%)
- Storage: 0/5 (0%)
- Download Progress: 0/1 (0%)
- Configuration: 0/3 (0%)
- Logging: 0/5 (0%)
- Frameworks: ~2/8 (25% - basic registration only)
- Model Assignments: 0/4 (0%)
- Structured Output: 0/3 (0%)
- Voice: 0/3 (0%)

**Overall Extension API Coverage: 11/41 (27%)**

---

## Summary Statistics

### API Coverage

**Kotlin SDK API Coverage (Core APIs):**
- ✅ **Model Management:** 9/9 APIs (100%)
- ❌ **Storage:** 0/5 APIs (0%)
- ⚠️ **Download Progress:** 0/1 API (0%)
- ✅ **Text Generation:** 3/3 APIs (100%)
- **Overall Core APIs:** 12/18 (67%)

**Kotlin SDK API Coverage (Extension APIs):**
- ✅ **Model Management Extensions:** 9/9 (100%)
- ❌ **Storage Extensions:** 0/5 (0%)
- ❌ **Download Extensions:** 0/1 (0%)
- ❌ **Configuration Extensions:** 0/3 (0%)
- ❌ **Logging Extensions:** 0/5 (0%)
- ⚠️ **Framework Extensions:** ~2/8 (25%)
- ❌ **Model Assignment Extensions:** 0/4 (0%)
- ❌ **Structured Output Extensions:** 0/3 (0%)
- ❌ **Voice Extensions:** 0/3 (0%)
- **Overall Extension APIs:** 11/41 (27%)

**Combined Total API Coverage:** 23/59 APIs (39%)

### Sample App Feature Parity

**Android App Feature Parity:**
- ✅ **Initialization:** 100%
- ✅ **Model Management UI:** 90% (missing progress %)
- ❌ **Storage UI:** 0%
- ✅ **Chat UI:** 100%
- **Overall:** ~63% feature parity

### Data Structure Compatibility

**ModelInfo Compatibility:** 95%
- Minor type differences (URL vs String, Date vs SimpleInstant)
- Kotlin has 2 extra fields (checksums)
- All essential fields present

---

## Conclusion

The Kotlin/KMP SDK is architecturally sound and has **excellent API parity** for model management and text generation (100%). However, there are **critical gaps** in storage APIs that block the Android Storage screen implementation.

**Top 3 Issues:**
1. **Storage APIs completely missing** - Blocks Storage screen
2. **Download progress API missing** - Degrades UX
3. **Whisper models not registered** - Feature gap

**Recommended Action:**
Prioritize implementing storage APIs in Kotlin SDK first, then update Android app's Storage screen. This will bring Android to full feature parity with iOS.

---

## Part 7: KMP Implementation Roadmap (JVM + Android)

### 7.1 Critical Context: Kotlin Multiplatform Architecture

The RunAnywhere Kotlin SDK is a **Kotlin Multiplatform (KMP) project** supporting:
- **JVM** (desktop, IntelliJ plugins)
- **Android** (mobile apps)
- **Future:** Native targets (iOS, macOS, Linux, Windows)

**Key Principle:** All business logic must be in `commonMain` to work across all platforms. Platform-specific code goes in `jvmMain`, `androidMain`, etc.

### 7.2 Library Selection for KMP Compatibility

#### ✅ Recommended Libraries (KMP-Compatible)

| Library | Purpose | Stars | KMP Support | Use Case |
|---------|---------|-------|-------------|----------|
| **Okio 3.x** | File system operations | 9.0K | ✅ Full | Storage APIs, file management |
| **Ktor Client** | HTTP networking | 12.9K | ✅ Full | Download with progress |
| **Room 2.7.0+** | SQLite database | Google | ✅ Full | Model metadata, analytics |
| **Kermit** | Logging | 2.1K | ✅ Full | Multiplatform logging |
| **kotlinx.serialization** | JSON serialization | Official | ✅ Full | Already in use ✅ |
| **kotlinx.coroutines** | Async/concurrency | Official | ✅ Full | Already in use ✅ |

#### ❌ Libraries to Remove/Replace

| Current Library | Issue | Replacement | Priority |
|-----------------|-------|-------------|----------|
| **commons-io** | JVM-only | Okio FileSystem | HIGH |
| **prdownloader** | Android-only | Ktor download progress | HIGH |
| **Retrofit** | Redundant with Ktor | Remove (already have Ktor) | MEDIUM |
| **Gson** | Redundant | kotlinx.serialization | LOW |

### 7.3 Phase 1: Foundation (Critical - Week 1)

#### Priority 1: Add Okio Dependency

**File:** `sdk/runanywhere-kotlin/build.gradle.kts`

```kotlin
kotlin {
    sourceSets {
        commonMain.dependencies {
            // Add Okio for file system operations
            implementation("com.squareup.okio:okio:3.9.0")
            implementation("com.squareup.okio:okio-fakefilesystem:3.9.0") // For testing
        }
    }
}
```

**Effort:** 30 minutes

#### Priority 2: Implement Storage APIs with Okio

**File to create:** `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/public/extensions/RunAnywhere+Storage.kt`

**APIs to implement:**
1. `suspend fun getStorageInfo(): StorageInfo` - Calculate total/used/available storage
2. `suspend fun clearCache()` - Delete cache files
3. `suspend fun cleanTempFiles()` - Remove temporary files
4. `suspend fun deleteStoredModel(modelId: String)` - Delete model from disk
5. `fun getBaseDirectoryURL(): String` - Get base storage directory path

**Implementation Guide:**

```kotlin
package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.foundation.SDKLogger
import okio.FileSystem
import okio.Path.Companion.toPath
import okio.SYSTEM

data class StorageInfo(
    val totalSpace: Long,
    val usedSpace: Long,
    val availableSpace: Long,
    val modelCount: Int,
    val modelsTotalSize: Long
)

suspend fun RunAnywhereSDK.getStorageInfo(): StorageInfo {
    val fileSystem = FileSystem.SYSTEM
    val baseDir = getBaseDirectoryURL().toPath()

    // Platform-specific implementation via expect/actual
    val totalSpace = getPlatformTotalSpace()
    val availableSpace = getPlatformAvailableSpace()

    // Calculate model storage
    val modelsDir = baseDir / "models"
    var modelsTotalSize = 0L
    var modelCount = 0

    if (fileSystem.exists(modelsDir)) {
        fileSystem.list(modelsDir).forEach { modelPath ->
            if (fileSystem.metadata(modelPath).isRegularFile) {
                modelsTotalSize += fileSystem.metadata(modelPath).size ?: 0L
                modelCount++
            }
        }
    }

    return StorageInfo(
        totalSpace = totalSpace,
        usedSpace = totalSpace - availableSpace,
        availableSpace = availableSpace,
        modelCount = modelCount,
        modelsTotalSize = modelsTotalSize
    )
}

// Expect/actual for platform-specific storage calculations
expect suspend fun getPlatformTotalSpace(): Long
expect suspend fun getPlatformAvailableSpace(): Long
```

**Effort:** 2-3 days (includes testing)

#### Priority 3: Implement Download Progress API

**File to create:** `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/public/extensions/RunAnywhere+Download.kt`

**API to implement:**
```kotlin
fun RunAnywhereSDK.downloadModelWithProgress(modelId: String): Flow<DownloadProgress>
```

**Implementation with Ktor:**

```kotlin
package com.runanywhere.sdk.public.extensions

import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.utils.io.*
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import okio.FileSystem
import okio.buffer
import okio.sink

data class DownloadProgress(
    val bytesDownloaded: Long,
    val totalBytes: Long,
    val percentage: Float,
    val speed: Long, // bytes per second
    val estimatedTimeRemaining: Long // seconds
)

fun RunAnywhereSDK.downloadModelWithProgress(modelId: String): Flow<DownloadProgress> = flow {
    // Get model info
    val model = availableModels().find { it.id == modelId }
        ?: throw IllegalArgumentException("Model not found: $modelId")

    val downloadURL = model.downloadURL
        ?: throw IllegalStateException("Model has no download URL")

    // Get HTTP client from service container
    val httpClient = HttpClient {
        expectSuccess = true
    }

    val fileSystem = FileSystem.SYSTEM
    val outputPath = (getBaseDirectoryURL() + "/models/${modelId}.gguf").toPath()

    var startTime = System.currentTimeMillis()
    var lastEmitTime = startTime
    var bytesDownloaded = 0L

    httpClient.prepareGet(downloadURL).execute { response ->
        val totalBytes = response.contentLength() ?: 0L
        val channel = response.body<ByteReadChannel>()

        fileSystem.sink(outputPath).buffer().use { sink ->
            val buffer = ByteArray(8192)

            while (!channel.isClosedForRead) {
                val bytesRead = channel.readAvailable(buffer)
                if (bytesRead == -1) break

                sink.write(buffer, 0, bytesRead)
                bytesDownloaded += bytesRead

                // Emit progress every 100ms
                val now = System.currentTimeMillis()
                if (now - lastEmitTime >= 100 || bytesDownloaded == totalBytes) {
                    val elapsed = (now - startTime) / 1000.0
                    val speed = if (elapsed > 0) (bytesDownloaded / elapsed).toLong() else 0L
                    val remaining = if (speed > 0) ((totalBytes - bytesDownloaded) / speed) else 0L

                    emit(DownloadProgress(
                        bytesDownloaded = bytesDownloaded,
                        totalBytes = totalBytes,
                        percentage = if (totalBytes > 0) (bytesDownloaded.toFloat() / totalBytes * 100) else 0f,
                        speed = speed,
                        estimatedTimeRemaining = remaining
                    ))

                    lastEmitTime = now
                }
            }
        }
    }

    httpClient.close()
}
```

**Effort:** 1-2 days

### 7.4 Phase 2: Android Sample App Updates (Week 2)

#### Update Storage Screen

**File:** `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/presentation/storage/StorageScreen.kt`

**Current state:** Shows "Model storage and management coming soon"

**Implementation:**
1. Create `StorageViewModel` that calls SDK `getStorageInfo()`
2. Display storage info (total/used/available) with visual indicators
3. List downloaded models with sizes
4. Add "Clear Cache" and "Delete Model" actions
5. Match iOS StorageView layout and UX

**Reference iOS implementation:**
- File: `examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Storage/StorageView.swift`
- Lines 20-150 for UI layout
- Lines 50-80 for storage info display

**Effort:** 2 days

#### Update Model Selection for Download Progress

**File:** `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/presentation/models/ModelSelectionViewModel.kt`

**Current implementation:**
```kotlin
// Line 98-120: Uses basic downloadModel()
RunAnywhere.downloadModel(modelId).collect { progress ->
    // Only gets Float percentage
}
```

**Update to:**
```kotlin
RunAnywhere.downloadModelWithProgress(modelId).collect { progress ->
    _uiState.update {
        it.copy(
            loadingProgress = "Downloading: ${progress.percentage.toInt()}%\n" +
                "Speed: ${formatBytes(progress.speed)}/s\n" +
                "ETA: ${formatTime(progress.estimatedTimeRemaining)}"
        )
    }
}
```

**Effort:** 1 day

### 7.5 Phase 3: Additional Extensions (Week 3)

#### Logging Extensions

**File to create:** `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/public/extensions/RunAnywhere+Logging.kt`

**Library:** Add Kermit for multiplatform logging

```kotlin
// build.gradle.kts
dependencies {
    implementation("co.touchlab:kermit:2.0.3")
}
```

**APIs to implement:**
1. `fun configureSDKLogging(enabled: Boolean)`
2. `fun setLogLevel(level: LogLevel)`
3. `fun setDebugMode(enabled: Boolean)`
4. `suspend fun flushAll()`

**Effort:** 1 day

#### Framework Extensions (if needed)

**File:** Already exists: `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/foundation/DependencyInjection/AdapterRegistry.kt`

**Enhance with:**
- `getAvailableFrameworks()` - List registered frameworks
- `getFrameworkAvailability()` - Check framework status
- `getModelsForFramework()` - Filter models by framework

**Effort:** 1 day

### 7.6 Migration Plan: Remove Redundant Libraries

#### Step 1: Replace commons-io with Okio

**Files to update:**
- Search for `import org.apache.commons.io.*` across codebase
- Replace with Okio equivalents

**Example migration:**
```kotlin
// Before (commons-io)
import org.apache.commons.io.FileUtils
val size = FileUtils.sizeOf(file)

// After (Okio)
import okio.FileSystem
import okio.SYSTEM
val size = FileSystem.SYSTEM.metadata(path).size
```

**Effort:** 1 day

#### Step 2: Remove prdownloader from Android SDK

**Reason:** Using Ktor for downloads now

**File:** `sdk/runanywhere-kotlin/build.gradle.kts`
- Remove prdownloader dependency (line ~94)

**Effort:** 30 minutes

#### Step 3: Consolidate on kotlinx.serialization

**Reason:** Remove Gson redundancy

**Migration:**
- Replace Gson usage with kotlinx.serialization
- Already have kotlinx.serialization, just remove Gson

**Effort:** 1 day

### 7.7 Testing Strategy

#### Unit Tests

**Files to create:**
```
sdk/runanywhere-kotlin/src/commonTest/kotlin/
  ├── storage/
  │   └── StorageAPITest.kt
  ├── download/
  │   └── DownloadProgressTest.kt
  └── logging/
      └── LoggingAPITest.kt
```

**Use Okio FakeFileSystem for testing:**
```kotlin
import okio.fakefilesystem.FakeFileSystem

@Test
fun `getStorageInfo should calculate correct storage`() = runTest {
    val fakeFS = FakeFileSystem()
    // Setup test files
    // Call getStorageInfo()
    // Assert results
}
```

**Effort:** 2 days

#### Integration Tests

**Test on both platforms:**
1. JVM desktop app test
2. Android instrumented tests

**Effort:** 2 days

### 7.8 Summary: Total Implementation Effort

| Phase | Tasks | Effort | Priority |
|-------|-------|--------|----------|
| **Phase 1: Foundation** | Add Okio, Storage APIs, Download Progress | 5-6 days | CRITICAL |
| **Phase 2: Sample App** | Storage Screen, Download UI | 3 days | HIGH |
| **Phase 3: Extensions** | Logging, Framework APIs | 2 days | MEDIUM |
| **Migration** | Remove redundant libraries | 2.5 days | MEDIUM |
| **Testing** | Unit + Integration tests | 4 days | HIGH |
| **Total** | | **16-17 days** | |

### 7.9 Success Criteria

**Definition of Done:**

✅ **Storage APIs:**
- All 5 storage APIs implemented in commonMain
- Okio used for file operations
- Works on JVM and Android

✅ **Download Progress:**
- Real-time progress with percentage, speed, ETA
- Ktor-based implementation
- Matches iOS UX

✅ **Android Storage Screen:**
- Shows storage info (total/used/available)
- Lists downloaded models
- Clear cache / delete model actions
- Matches iOS layout

✅ **Library Cleanup:**
- commons-io removed
- prdownloader removed
- Consolidated on KMP-compatible libraries

✅ **Tests:**
- Unit tests passing on JVM and Android
- Integration tests on both platforms

✅ **Feature Parity:**
- Android app feature parity with iOS: 95%+
- API coverage: 70%+ (core APIs, storage, download)

### 7.10 Open Questions & Decisions

**Q1:** Should we migrate Room database to commonMain now or later?
**Recommendation:** Later (Phase 4) - Room 2.7.0 KMP support is stable but not urgent

**Q2:** Do we need all iOS extension APIs (logging, framework, etc.)?
**Recommendation:** Start with critical APIs (storage, download), add others based on user needs

**Q3:** Should we support Native targets (iOS, macOS) now?
**Recommendation:** No - focus on JVM + Android first, Native targets in future milestone

---

## Implementation Decision

**Status:** ✅ **READY FOR IMPLEMENTATION**

This document provides:
- ✅ Complete API gap analysis
- ✅ Library recommendations (KMP-compatible)
- ✅ Detailed implementation plan with code examples
- ✅ Effort estimates
- ✅ Testing strategy
- ✅ Success criteria

**Next Steps:**
1. Review this document
2. Approve Phase 1 priorities (Storage APIs + Download Progress)
3. Begin implementation following Section 7.3

---

**Document Version:** 2.0
**Last Updated:** 2025-10-09
**Author:** Claude (Anthropic)
**Review Status:** ✅ Ready for Implementation
