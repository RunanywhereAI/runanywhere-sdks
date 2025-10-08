# SDK Gap Analysis: Text-to-Text LLM Generation
## Focus: Kotlin SDK Parity with Swift SDK

**Generated:** 2025-10-08
**Swift SDK Version:** 1.0.0
**Kotlin SDK Version:** 0.1.0
**Analysis Scope:** Text-to-Text LLM generation path only

---

## Executive Summary

### Total Gaps Identified: 47

| Priority Level | Critical Gaps | Partial Gaps | Missing Features | Total |
|---------------|--------------|--------------|------------------|-------|
| 🔴 **Priority 1: Initialization** | 3 | 2 | 1 | **6** |
| 🔴 **Priority 2: Model Management** | 2 | 4 | 3 | **9** |
| 🔴 **Priority 3: LLM Generation APIs** | 1 | 6 | 2 | **9** |
| 🔴 **Priority 4: LLM Component** | 0 | 5 | 1 | **6** |
| 🟡 **Priority 5: Infrastructure** | 1 | 4 | 2 | **7** |
| 🟡 **Priority 6: Structured Output** | 0 | 2 | 0 | **2** |
| 🔵 **Priority 7: Voice (Interfaces)** | 0 | 0 | 0 | **0** |
| 🔵 **Priority 8: Other Features** | 0 | 0 | 8 | **8** |

### Estimated Effort to Parity
- **Priority 1-4 (Critical Path):** ~5-7 days
- **Priority 5-6 (Supporting):** ~3-4 days
- **Total Text-to-Text LLM Parity:** ~8-11 days

### Key Findings

**✅ What Kotlin Has Well:**
- Comprehensive LLMConfiguration with 30+ parameters (vs Swift's simpler approach)
- More advanced generation options (topK, repetitionPenalty, seed, etc.)
- Better structured bootstrap process (8-step vs 5-step)
- Strong model registry with search capabilities

**⚠️ Critical Gaps in Kotlin:**
- Missing lazy device registration (requires explicit bootstrap)
- No AsyncThrowingStream equivalent for streaming (uses Flow)
- Missing model download progress with detailed metadata
- No model verification/checksums in download flow
- Missing offline model loading APIs
- Generation options lack some Swift parameters (grammar, etc.)

**❌ Missing in Kotlin:**
- Lazy initialization pattern (auto-registration on first call)
- Model unloading APIs
- Model removal/cleanup APIs
- Resume capability for downloads
- Memory estimation per model
- Cost tracking integration

---

## 🔴 PRIORITY 1: SDK Initialization & Configuration

### Gap Summary

| Feature/API | Swift Implementation | Kotlin Implementation | Gap Status | Action Required |
|-------------|---------------------|----------------------|------------|-----------------|
| **Initialization Flow** | 5-step lightweight (no network) | 8-step bootstrap (network required) | ⚠️ Different | Match Swift's lazy approach |
| **Device Registration** | Lazy (automatic on first API call) | Explicit (manual bootstrap) | ❌ Missing | Implement lazy registration |
| **Initialize API** | `try RunAnywhere.initialize(apiKey:baseURL:environment:)` | `suspend fun initialize(apiKey:baseURL:environment:)` | ✅ Parity | - |
| **Bootstrap API** | No explicit bootstrap needed | `suspend fun bootstrap(params)` | ⚠️ Extra step | Make optional |
| **Environment Enum** | `SDKEnvironment` (.development, .staging, .production) | `SDKEnvironment` (same) | ✅ Parity | - |
| **Configuration Loading** | Lazy, on-demand | Eager, in bootstrap | ⚠️ Different | Add lazy option |

---

### 1.1 Initialization Flow

**Swift (5-step Lightweight):**
```swift
// File: RunAnywhere.swift (lines 243-347)

public static func initialize(
    apiKey: String,
    baseURL: URL,
    environment: SDKEnvironment
) throws {
    // Step 1: Validation (skipped in dev mode)
    if environment != .development {
        try ValidationService.validateApiKey(apiKey)
    }

    // Step 2: Logging
    SDKLogger.initialize(level: environment.logLevel)

    // Step 3: Storage (keychain for prod, UserDefaults for dev)
    try secureStorage.store(apiKey: apiKey)

    // Step 4: Database (local GRDB)
    try initializeDatabase()

    // Step 5: Local services only (NO NETWORK)
    setupLocalServices()

    isInitialized = true

    // Device registration happens LAZILY on first API call
}
```

**Kotlin (8-step Bootstrap):**
```kotlin
// File: RunAnywhere.kt (lines 243-347)

override suspend fun initialize(
    apiKey: String,
    baseURL: String?,
    environment: SDKEnvironment
) {
    // Step 1: Platform initialization
    platformContext.initialize()

    // Step 2: Validation
    validationService.validateApiKey(apiKey)

    // Step 3: Logging
    initializeLogging(environment)

    // Step 4: Storage
    secureStorage.store("api_key", apiKey)

    // Step 5: Database
    initializeDatabase()

    // MISSING: Lazy registration
    // Kotlin requires explicit bootstrap() call

    _isSDKInitialized.value = true
}

// Separate bootstrap required
suspend fun bootstrap(params: SDKInitParams): ConfigurationData {
    // Step 6: Authentication (NETWORK CALL)
    authenticationService.initialize()

    // Step 7: Health Check (NETWORK CALL)
    healthCheck()

    // Step 8: Services (NETWORK DEPENDENT)
    ServiceContainer.shared.bootstrap(params)

    return configurationData
}
```

**Gap:** Kotlin forces network calls in initialization, Swift delays them

**Action Required:**
1. Add lazy device registration to Kotlin (match Swift pattern)
2. Make `bootstrap()` optional in Kotlin
3. Auto-call bootstrap on first `generate()` call
4. Add retry logic with exponential backoff (like Swift)

**Estimated Effort:** Medium (2 days)

**Dependencies:** None

---

### 1.2 Lazy Device Registration

**Swift Implementation:**
```swift
// File: RunAnywhere.swift (lines 400-450)

public static func generate(_ prompt: String, options: RunAnywhereGenerationOptions?) async throws -> String {
    guard isInitialized else { throw SDKError.notInitialized }

    // LAZY REGISTRATION: First call triggers device registration
    try await ensureDeviceRegistered()

    return try await generationService.generate(prompt, options)
}

private static func ensureDeviceRegistered() async throws {
    guard !isDeviceRegistered else { return }

    do {
        // Retry logic with exponential backoff
        try await registerDevice(maxRetries: 3)
        isDeviceRegistered = true
    } catch {
        // In dev mode, continue with mock device ID
        if environment == .development {
            logger.warning("Device registration failed, using mock ID")
            isDeviceRegistered = true
        } else {
            throw error
        }
    }
}
```

**Kotlin Current State:**
```kotlin
// File: RunAnywhere.kt

override suspend fun generate(prompt: String, options: RunAnywhereGenerationOptions?): String {
    if (!_isSDKInitialized.value) {
        throw SDKError.NotInitialized
    }

    // MISSING: No lazy registration check
    // User must manually call bootstrap() before this

    return generationService.generate(prompt, options)
}
```

**Gap:** ❌ Missing entirely

**Action Required:**
1. Add `ensureDeviceRegistered()` function to Kotlin
2. Auto-call on first API usage
3. Implement retry logic (3 retries, exponential backoff)
4. Dev mode fallback to mock device ID
5. Cache registration status

**Estimated Effort:** Small (1 day)

**Dependencies:** Authentication service

---

### 1.3 Configuration Management

**Swift (Lazy Loading):**
```swift
// Configuration loaded on-demand
public var configurationService: ConfigurationServiceProtocol {
    get async {
        // Loaded lazily when first accessed
        await _configurationService.load()
    }
}
```

**Kotlin (Eager Loading):**
```kotlin
// Configuration loaded eagerly in bootstrap
suspend fun bootstrap(params: SDKInitParams): ConfigurationData {
    val config = configurationService.loadConfiguration()
    // Always loads, even if not needed
    return config
}
```

**Gap:** ⚠️ Different approach, Kotlin less efficient

**Action Required:**
1. Add lazy configuration loading option
2. Cache loaded configurations
3. Only load when needed

**Estimated Effort:** Small (0.5 days)

---

## 🔴 PRIORITY 2: Model Management (Download & Storage)

### Gap Summary

| Feature/API | Swift Implementation | Kotlin Implementation | Gap Status | Action Required |
|-------------|---------------------|----------------------|------------|-----------------|
| **Model Discovery** | `availableModels() -> [ModelInfo]` | `availableModels() -> List<ModelInfo>` | ✅ Parity | - |
| **Model Download** | `downloadModel(_ id: String)` | `downloadModel(id: String): Flow<Float>` | ⚠️ Partial | Add detailed progress |
| **Download Progress** | `AsyncStream<DownloadProgress>` with speed, ETA | `Flow<Float>` (percentage only) | ⚠️ Partial | Add metadata |
| **Download Resume** | ✅ Supported (Range headers) | ✅ Supported (Range headers) | ✅ Parity | - |
| **Download Verification** | ✅ SHA256 checksums | ❌ Missing | ❌ Missing | Add checksum validation |
| **Model Storage Path** | `~/.runanywhere/models/` or bundle | `~/.runanywhere/models/` or app internal | ✅ Parity | - |
| **Model Metadata** | Rich ModelInfo with 15+ fields | Rich ModelInfo with 15+ fields | ✅ Parity | - |
| **Offline Loading** | ✅ Bundle support | ⚠️ Local path only | ⚠️ Partial | Add bundle support |
| **Model Removal** | ❌ Missing | ❌ Missing | ❌ Both Missing | Both need implementation |
| **Model Unloading** | `unloadModel()` API | ❌ Missing | ❌ Missing | Add unload API |

---

### 2.1 Model Discovery API

**Swift:**
```swift
// File: RunAnywhere.swift (line 521)

public static func availableModels() async throws -> [ModelInfo] {
    guard isInitialized else { throw SDKError.notInitialized }

    let registry = await ServiceContainer.shared.modelRegistry
    let models = try await registry.discoverModels()

    return models
}

// ModelInfo structure (15 fields)
public struct ModelInfo: Codable, Sendable {
    public let id: String
    public let name: String
    public let category: ModelCategory
    public let framework: LLMFramework
    public let format: ModelFormat
    public let quantization: QuantizationLevel?
    public let size: Int64
    public let contextLength: Int
    public let languages: [String]?
    public let downloadURL: URL?
    public let localPath: String?
    public let sha256: String?
    public let requiresGPU: Bool
    public let metadata: ModelInfoMetadata?
    public let createdAt: Date?
}
```

**Kotlin:**
```kotlin
// File: RunAnywhere.kt (line 126)

override suspend fun availableModels(): List<ModelInfo> {
    if (!_isSDKInitialized.value) {
        throw SDKError.NotInitialized
    }

    val registry = ServiceContainer.shared.modelRegistry
    return registry.discoverModels()
}

// ModelInfo structure (16 fields - slightly different)
data class ModelInfo(
    val id: String,
    val name: String,
    val category: ModelCategory,
    val format: ModelFormat,
    val downloadURL: String? = null,
    val localPath: String? = null,
    val downloadSize: Long? = null,
    val memoryRequired: Long? = null,
    val sha256Checksum: String? = null,
    val compatibleFrameworks: List<LLMFramework> = emptyList(),
    val preferredFramework: LLMFramework? = null,
    val contextLength: Int? = null,
    val supportsThinking: Boolean = false,
    val metadata: Map<String, Any>? = null,
    val createdAt: SimpleInstant? = null,
    val updatedAt: SimpleInstant? = null
)
```

**Gap:** ✅ **Parity** - Both have comprehensive ModelInfo structures

**Minor Differences:**
- Swift has `languages: [String]?` - Kotlin missing
- Swift has `requiresGPU: Bool` - Kotlin missing
- Kotlin has `supportsThinking: Boolean` - Swift missing
- Kotlin has `updatedAt` - Swift missing

**Action:** Align field names and add missing fields to both

**Estimated Effort:** Small (0.5 days)

---

### 2.2 Model Download with Progress

**Swift (Rich Progress Metadata):**
```swift
// File: RunAnywhere+Download.swift

static func downloadModelWithProgress(_ modelId: String) async throws -> AsyncStream<DownloadProgress> {
    let logger = SDKLogger(category: "RunAnywhere.Download")

    return AsyncStream { continuation in
        Task {
            do {
                let modelInfo = try await getModelInfo(modelId)

                // Rich progress with speed, ETA, state
                let stream = await downloadService.downloadWithProgress(modelInfo)

                for await progress in stream {
                    continuation.yield(progress)
                }

                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

// DownloadProgress struct (7 fields)
public struct DownloadProgress: Sendable {
    public let bytesDownloaded: Int64
    public let totalBytes: Int64
    public let percentComplete: Float
    public let state: DownloadState
    public let speed: Int64?               // Bytes per second
    public let estimatedTimeRemaining: TimeInterval?  // Seconds
    public let currentFile: String?
}

public enum DownloadState {
    case pending
    case downloading
    case paused
    case completed
    case failed(Error)
}
```

**Kotlin (Simple Percentage):**
```kotlin
// File: RunAnywhere.kt (line 131)

override suspend fun downloadModel(modelId: String): Flow<Float> {
    if (!_isSDKInitialized.value) {
        throw SDKError.NotInitialized
    }

    val modelInfo = ServiceContainer.shared.modelRegistry.getModel(modelId)
        ?: throw SDKError.ModelNotFound(modelId)

    // Returns ONLY percentage (0.0 to 1.0)
    return flow {
        downloadService.downloadModelStream(modelInfo).collect { progress ->
            emit(progress.percentComplete)
        }
    }
}

// DownloadProgress in Kotlin (simpler, 5 fields)
data class DownloadProgress(
    val bytesDownloaded: Long,
    val totalBytes: Long,
    val state: DownloadState,
    val speed: Long? = null,  // Has it but not exposed
    val estimatedTimeRemaining: Long? = null  // Has it but not exposed
) {
    val percentComplete: Float
        get() = if (totalBytes > 0) (bytesDownloaded.toFloat() / totalBytes) else 0f
}
```

**Gap:** ⚠️ **Partial** - Kotlin has metadata internally but doesn't expose it

**Action Required:**
1. Change Kotlin `downloadModel()` return type from `Flow<Float>` to `Flow<DownloadProgress>`
2. Expose speed and ETA in Flow
3. Add `currentFile` field for multi-file downloads
4. Match Swift's DownloadState enum

**Code Change:**
```kotlin
// Before:
suspend fun downloadModel(modelId: String): Flow<Float>

// After (match Swift):
suspend fun downloadModel(modelId: String): Flow<DownloadProgress>

// Or provide both:
suspend fun downloadModel(modelId: String): Flow<Float>  // Simple
suspend fun downloadModelWithProgress(modelId: String): Flow<DownloadProgress>  // Detailed
```

**Estimated Effort:** Small (1 day)

**Dependencies:** None

---

### 2.3 Download Verification (Checksums)

**Swift:**
```swift
// File: ModelLoadingService.swift

func downloadModel(_ model: ModelInfo) async throws -> String {
    // Download file
    let localPath = try await downloadService.download(model.downloadURL)

    // VERIFY CHECKSUM
    if let expectedChecksum = model.sha256 {
        let actualChecksum = try calculateSHA256(localPath)

        guard actualChecksum == expectedChecksum else {
            try fileSystem.deleteFile(at: localPath)
            throw SDKError.checksumMismatch(
                expected: expectedChecksum,
                actual: actualChecksum
            )
        }
    }

    return localPath
}
```

**Kotlin:**
```kotlin
// File: ModelManager.kt

suspend fun downloadModel(modelInfo: ModelInfo, onProgress: (DownloadProgress) -> Unit): String {
    // Download file
    val localPath = downloadService.downloadModel(modelInfo) { progress ->
        onProgress(progress)
    }

    // MISSING: No checksum verification

    return localPath
}
```

**Gap:** ❌ **Missing** - Kotlin doesn't verify checksums

**Action Required:**
1. Add `validateModel()` function to ModelManager
2. Call after download completes
3. Delete file if checksum fails
4. Add `SDKError.ChecksumMismatch` error type

**Code to Add:**
```kotlin
// Add to ModelManager.kt

suspend fun validateModel(modelPath: String, expectedChecksum: String?): Boolean {
    if (expectedChecksum == null) return true

    val actualChecksum = calculateSHA256(modelPath)

    if (actualChecksum != expectedChecksum) {
        fileSystem.deleteFile(modelPath)
        throw SDKError.ChecksumMismatch(
            expected = expectedChecksum,
            actual = actualChecksum
        )
    }

    return true
}

private suspend fun calculateSHA256(filePath: String): String {
    // Use platform-specific crypto
    return withContext(Dispatchers.IO) {
        // Implementation
    }
}
```

**Estimated Effort:** Medium (1 day)

**Dependencies:** Crypto library (already have kotlinx.crypto)

---

### 2.4 Model Loading API

**Swift:**
```swift
// File: RunAnywhere.swift (line 495)

public static func loadModel(_ modelId: String) async throws {
    EventBus.shared.publish(SDKModelEvent.loadStarted(modelId: modelId))

    guard isInitialized else { throw SDKError.notInitialized }

    let loadingService = await ServiceContainer.shared.modelLoadingService
    try await loadingService.loadModel(modelId)

    // Set current model
    _currentModel = try await getModelInfo(modelId)

    EventBus.shared.publish(SDKModelEvent.loadCompleted(modelId: modelId))
}

// Also has currentModel property
public static var currentModel: ModelInfo? {
    _currentModel
}
```

**Kotlin:**
```kotlin
// File: RunAnywhere.kt (line 136)

override suspend fun loadModel(modelId: String): Boolean {
    if (!_isSDKInitialized.value) {
        throw SDKError.NotInitialized
    }

    EventBus.publish(SDKModelEvent.LoadStarted(modelId))

    val loadingService = ServiceContainer.shared.modelLoadingService
    val handle = loadingService.loadModel(modelId)

    // MISSING: No current model tracking

    EventBus.publish(SDKModelEvent.LoadCompleted(modelId))

    return true
}

// MISSING: No currentModel property
```

**Gap:** ⚠️ **Partial** - Missing current model tracking

**Action Required:**
1. Add `currentModel: ModelInfo?` property to Kotlin RunAnywhere
2. Update on successful `loadModel()`
3. Clear on `unloadModel()` (needs to be added)

**Estimated Effort:** Small (0.5 days)

---

### 2.5 Model Unloading (Missing in Both, but Swift has API)

**Swift:**
```swift
// File: LLMComponent.swift (line 200)

public func unloadModel() async throws {
    guard let service = service else {
        throw SDKError.componentNotReady("LLM service not initialized")
    }

    try await service.unloadModel()

    // Clear from memory
    self.service = nil

    EventBus.shared.publish(SDKModelEvent.unloaded(modelId: configuration.modelId))
}
```

**Kotlin:**
```kotlin
// MISSING: No unloadModel() API anywhere
```

**Gap:** ❌ **Missing** - Kotlin has no model unloading

**Action Required:**
1. Add `unloadModel()` to LLMComponent
2. Add `unloadModel(modelId: String)` to RunAnywhere
3. Clear service references
4. Publish unload events

**Estimated Effort:** Small (0.5 days)

---

### 2.6 Offline Model Loading

**Swift (Bundle Support):**
```swift
// Can load models from app bundle
let bundlePath = Bundle.main.path(forResource: "llama-2-7b", ofType: "gguf")
try await loadModel(localPath: bundlePath)
```

**Kotlin:**
```kotlin
// Only supports downloaded models
// No bundle/asset loading
```

**Gap:** ⚠️ **Partial** - Kotlin missing bundle/asset support

**Action Required:**
1. Add asset loading for Android (from `/assets`)
2. Add resource loading for JVM
3. Add `loadModelFromPath()` API

**Estimated Effort:** Medium (1 day)

---

## 🔴 PRIORITY 3: LLM Text Generation APIs

### Gap Summary

| Feature/API | Swift Implementation | Kotlin Implementation | Gap Status | Action Required |
|-------------|---------------------|----------------------|------------|-----------------|
| **Simple Chat** | `chat(_ prompt: String) -> String` | `chat(prompt: String): String` | ✅ Parity | - |
| **Generation** | `generate(_ prompt:options:) -> String` | `generate(prompt:options:): String` | ✅ Parity | - |
| **Streaming** | `generateStream() -> AsyncThrowingStream<String>` | `generateStream() -> Flow<String>` | ⚠️ Different | AsyncThrowingStream vs Flow |
| **Generation Options** | 9 parameters | 14 parameters | ⚠️ Partial | Kotlin has MORE |
| **Options: temperature** | ✅ Float (0.0-1.0) | ✅ Float (0.0-2.0) | ⚠️ Different range | Align ranges |
| **Options: topP** | ✅ Float | ✅ Float | ✅ Parity | - |
| **Options: topK** | ❌ Missing | ✅ Int | ⚠️ Swift Missing | Add to Swift |
| **Options: maxTokens** | ✅ Int | ✅ Int | ✅ Parity | - |
| **Options: stopSequences** | ✅ [String] | ✅ List<String> | ✅ Parity | - |
| **Options: repetitionPenalty** | ❌ Missing | ✅ Float | ⚠️ Swift Missing | Add to Swift |
| **Options: frequencyPenalty** | ❌ Missing | ✅ Float | ⚠️ Swift Missing | Add to Swift |
| **Options: presencePenalty** | ❌ Missing | ✅ Float | ⚠️ Swift Missing | Add to Swift |
| **Options: seed** | ❌ Missing | ✅ Int | ⚠️ Swift Missing | Add to Swift |
| **Options: grammar** | ❌ Missing | ❌ Missing | ❌ Both Missing | Both need it |
| **Context Management** | Basic | ✅ Conversation history | ⚠️ Kotlin Better | Add to Swift |
| **Token Counting** | ❌ Missing in public API | ✅ `estimateTokens()` | ⚠️ Swift Missing | Add to Swift |

---

### 3.1 Simple Chat API

**Swift:**
```swift
// File: RunAnywhere.swift (line 380)

public static func chat(_ prompt: String) async throws -> String {
    return try await generate(prompt, options: nil)
}
```

**Kotlin:**
```kotlin
// File: RunAnywhere.kt (line 45)

override suspend fun chat(prompt: String): String {
    return generate(prompt, options = null)
}
```

**Gap:** ✅ **Parity** - Identical implementation

---

### 3.2 Generation with Options

**Swift:**
```swift
// File: RunAnywhere.swift (line 395)

public static func generate(
    _ prompt: String,
    options: RunAnywhereGenerationOptions?
) async throws -> String {
    guard isInitialized else { throw SDKError.notInitialized }

    try await ensureDeviceRegistered()

    let generationService = await ServiceContainer.shared.generationService

    let result = try await generationService.generate(
        prompt: prompt,
        options: options ?? RunAnywhereGenerationOptions()
    )

    return result.text
}
```

**Kotlin:**
```kotlin
// File: RunAnywhere.kt (line 51)

override suspend fun generate(
    prompt: String,
    options: RunAnywhereGenerationOptions?
): String {
    if (!_isSDKInitialized.value) {
        throw SDKError.NotInitialized
    }

    // MISSING: ensureDeviceRegistered() call

    val generationService = ServiceContainer.shared.generationService

    val result = generationService.generate(
        prompt = prompt,
        options = options ?: RunAnywhereGenerationOptions.DEFAULT
    )

    return result.text
}
```

**Gap:** ⚠️ **Partial** - Missing lazy registration check

**Action Required:** Add `ensureDeviceRegistered()` call

---

### 3.3 Streaming Generation

**Swift (AsyncThrowingStream):**
```swift
// File: RunAnywhere.swift (line 420)

public static func generateStream(
    _ prompt: String,
    options: RunAnywhereGenerationOptions?
) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        Task {
            guard isInitialized else {
                continuation.finish(throwing: SDKError.notInitialized)
                return
            }

            do {
                try await ensureDeviceRegistered()

                let streamingService = await ServiceContainer.shared.streamingService

                for try await token in streamingService.stream(prompt: prompt, options: options) {
                    continuation.yield(token)
                }

                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

// Usage:
for try await token in RunAnywhere.generateStream("Hello") {
    print(token, terminator: "")
}
```

**Kotlin (Flow):**
```kotlin
// File: RunAnywhere.kt (line 70)

override fun generateStream(
    prompt: String,
    options: RunAnywhereGenerationOptions?
): Flow<String> = flow {
    if (!_isSDKInitialized.value) {
        throw SDKError.NotInitialized
    }

    // MISSING: ensureDeviceRegistered() call

    val streamingService = ServiceContainer.shared.streamingService

    streamingService.stream(prompt, options ?: RunAnywhereGenerationOptions.DEFAULT)
        .collect { token ->
            emit(token)
        }
}

// Usage:
RunAnywhere.generateStream("Hello").collect { token ->
    print(token)
}
```

**Gap:** ⚠️ **Different** - Flow vs AsyncThrowingStream (acceptable, platform idioms)

**Action Required:**
1. Add `ensureDeviceRegistered()` call
2. Consider adding Kotlin `asAsyncSequence()` extension for API parity

**Estimated Effort:** Small (0.5 days)

---

### 3.4 Generation Options Comparison

**Swift (9 parameters, simpler):**
```swift
// File: GenerationOptions.swift

public struct RunAnywhereGenerationOptions: Sendable {
    public let maxTokens: Int = 100
    public let temperature: Float = 0.7
    public let topP: Float = 1.0
    public let enableRealTimeTracking: Bool = true
    public let stopSequences: [String] = []
    public let streamingEnabled: Bool = false
    public let preferredExecutionTarget: ExecutionTarget? = nil
    public let structuredOutput: StructuredOutputConfig? = nil
    public let systemPrompt: String? = nil
}
```

**Kotlin (14 parameters, comprehensive):**
```kotlin
// File: GenerationOptions.kt

data class RunAnywhereGenerationOptions(
    val maxTokens: Int = 100,
    val temperature: Float = 0.7f,
    val topP: Float = 1.0f,
    val enableRealTimeTracking: Boolean = true,
    val stopSequences: List<String> = emptyList(),
    val streamingEnabled: Boolean = false,
    val preferredExecutionTarget: ExecutionTarget? = null,
    val structuredOutput: StructuredOutputConfig? = null,
    val systemPrompt: String? = null,

    // KOTLIN HAS THESE EXTRAS:
    val topK: Int? = null,                      // ❌ Swift Missing
    val repetitionPenalty: Float? = null,       // ❌ Swift Missing
    val frequencyPenalty: Float? = null,        // ❌ Swift Missing
    val presencePenalty: Float? = null,         // ❌ Swift Missing
    val seed: Int? = null,                      // ❌ Swift Missing
    val contextLength: Int? = null              // ❌ Swift Missing
)
```

**Gap:** ⚠️ **Kotlin has MORE parameters than Swift**

**Action Required (Swift needs to add):**
1. `topK: Int?` - Top-K sampling
2. `repetitionPenalty: Float?` - Penalize repetition
3. `frequencyPenalty: Float?` - Frequency penalty (OpenAI style)
4. `presencePenalty: Float?` - Presence penalty (OpenAI style)
5. `seed: Int?` - Random seed for reproducibility
6. `contextLength: Int?` - Override context window

**Estimated Effort:** Small (0.5 days to add to Swift)

---

### 3.5 Context Management

**Swift (Basic):**
```swift
// No public conversation history API
// Only LLMComponent has internal context
```

**Kotlin (Full Conversation API):**
```kotlin
// File: LLMComponent.kt

class LLMComponent {
    // Conversation context management
    fun getConversationContext(): Context?
    fun setConversationContext(context: Context?)
    fun clearConversationContext()

    // Message-based generation
    suspend fun generateWithHistory(
        messages: List<Message>,
        systemPrompt: String?
    ): LLMOutput
}

data class Message(
    val role: MessageRole,
    val content: String
)

enum class MessageRole { USER, ASSISTANT, SYSTEM }
```

**Gap:** ⚠️ **Kotlin Better** - Has conversation management, Swift missing

**Action Required:** Add conversation APIs to Swift

**Estimated Effort:** Medium (1 day for Swift)

---

### 3.6 Token Counting

**Swift:**
```swift
// No public token counting API
// Only internal in LLMComponent
```

**Kotlin:**
```kotlin
// File: LLMComponent.kt

class LLMComponent {
    // Public token counting
    fun getTokenCount(text: String): Int

    fun fitsInContext(prompt: String, maxTokens: Int): Boolean
}
```

**Gap:** ⚠️ **Kotlin Better** - Has public token API, Swift missing

**Action Required:** Expose token counting in Swift public API

**Estimated Effort:** Small (0.5 days for Swift)

---

## 🔴 PRIORITY 4: LLM Component Architecture

### Gap Summary

| Feature/API | Swift Implementation | Kotlin Implementation | Gap Status | Action Required |
|-------------|---------------------|----------------------|------------|-----------------|
| **Component Lifecycle** | 3 states (notInitialized, initializing, ready, failed) | 9 states (includes download states) | ⚠️ Kotlin has more | Align states |
| **Component Health** | ✅ `healthCheck()` | ✅ `healthCheck()` | ✅ Parity | - |
| **Error Handling** | Typed errors (SDKError enum) | Sealed classes (SDKError hierarchy) | ⚠️ Different | Both valid |
| **Provider Pattern** | ✅ Protocol-based | ✅ Interface-based | ✅ Parity | - |
| **Module Registry** | @MainActor singleton | Object singleton | ⚠️ Different concurrency | Both valid |
| **Event Emission** | Combine PassthroughSubject | Kotlin SharedFlow | ⚠️ Different | Both valid |

---

### 4.1 Component State Machine

**Swift (4 states, simpler):**
```swift
// File: ComponentState.swift

public enum ComponentState: String, Sendable {
    case notInitialized = "not_initialized"
    case initializing = "initializing"
    case ready = "ready"
    case failed = "failed"
}

// State transitions:
// notInitialized → initializing → ready
//                        ↓
//                     failed
```

**Kotlin (9 states, includes downloads):**
```kotlin
// File: ComponentState.kt

enum class ComponentState {
    NOT_INITIALIZED,
    CHECKING,
    DOWNLOAD_REQUIRED,
    DOWNLOADING,
    DOWNLOADED,
    INITIALIZING,
    READY,
    PROCESSING,
    FAILED
}

// State transitions:
// NOT_INITIALIZED → CHECKING → DOWNLOAD_REQUIRED → DOWNLOADING → DOWNLOADED
//                       ↓ (if local)              ↓
//                  INITIALIZING ← ← ← ← ← ← ← ← ←
//                       ↓
//                    READY ⟷ PROCESSING
//                       ↓
//                    FAILED
```

**Gap:** ⚠️ **Different complexity** - Kotlin handles downloads in component, Swift in separate service

**Action Required:**
- Decide: Should Swift add download states to Component, or keep separate?
- **Recommendation:** Keep Swift's simpler approach, downloads handled by ModelLoadingService

**Estimated Effort:** None (accept difference)

---

### 4.2 LLMComponent Initialization

**Swift:**
```swift
// File: LLMComponent.swift (line 100)

@MainActor
public final class LLMComponent: BaseComponent<LLMService> {

    public override func createService() async throws -> LLMService {
        // Get provider from registry
        let provider = ModuleRegistry.shared.llmProvider(for: configuration.modelId)

        guard let provider = provider else {
            throw SDKError.componentNotAvailable("No LLM provider for: \(configuration.modelId)")
        }

        // Provider creates service
        let service = try await provider.createLLMService(configuration: configuration)

        return service
    }

    public override func initializeService() async throws {
        guard let service = service else {
            throw SDKError.componentNotReady("LLM service not created")
        }

        // Load model
        if let modelId = configuration.modelId {
            try await service.loadModel(modelId)
        }
    }
}
```

**Kotlin:**
```kotlin
// File: LLMComponent.kt (line 50)

class LLMComponent(configuration: LLMConfiguration) : BaseComponent<LLMServiceWrapper>(configuration) {

    override suspend fun createService(): LLMServiceWrapper {
        // 1. Check if model exists
        val modelInfo = serviceContainer?.modelRegistry?.getModel(configuration.modelId ?: "")

        // 2. Download if needed (COMPONENT HANDLES DOWNLOAD)
        if (modelInfo != null && !isModelDownloaded(modelInfo.id)) {
            transitionTo(ComponentState.DOWNLOAD_REQUIRED)
            transitionTo(ComponentState.DOWNLOADING)

            downloadModel(modelInfo.id)

            transitionTo(ComponentState.DOWNLOADED)
        }

        // 3. Get provider from registry
        val provider = ModuleRegistry.llmProvider(configuration.modelId)
            ?: throw SDKError.ComponentNotAvailable("No LLM provider")

        // 4. Create service
        val llmService = provider.createLLMService(configuration)

        return LLMServiceWrapper(llmService)
    }

    override suspend fun initializeService() {
        val service = service?.wrappedService
            ?: throw SDKError.ComponentNotReady("LLM service not created")

        // Initialize service (model already loaded in createService)
        service.initialize(modelPath)
    }
}
```

**Gap:** ⚠️ **Different** - Kotlin component handles downloads, Swift delegates to ModelLoadingService

**Action Required:**
- **Recommendation:** Keep Kotlin's approach (more self-contained)
- Consider extracting download to separate method for clarity

**Estimated Effort:** None (both approaches valid)

---

### 4.3 Provider Pattern

**Swift:**
```swift
// File: LLMServiceProvider.swift

public protocol LLMServiceProvider {
    var name: String { get }
    var framework: LLMFramework { get }

    func createLLMService(configuration: LLMConfiguration) async throws -> LLMService
    func canHandle(modelId: String?) -> Bool
}
```

**Kotlin:**
```kotlin
// File: LLMService.kt

interface LLMServiceProvider {
    val name: String
    val framework: LLMFramework
    val supportedFeatures: Set<String>

    suspend fun createLLMService(configuration: LLMConfiguration): LLMService
    fun canHandle(modelId: String?): Boolean

    // Advanced features (Kotlin has more)
    fun validateModelCompatibility(model: ModelInfo): ModelCompatibilityResult
    suspend fun downloadModel(modelId: String, onProgress: (Float) -> Unit): ModelInfo
    fun estimateMemoryRequirements(model: ModelInfo): Long
    fun getOptimalConfiguration(model: ModelInfo): HardwareConfiguration
}
```

**Gap:** ⚠️ **Kotlin has MORE** - Additional provider capabilities

**Action Required:** Consider adding these to Swift provider interface

**Estimated Effort:** Small (0.5 days for Swift)

---

## 🟡 PRIORITY 5: Supporting Infrastructure (for Text Generation)

### Gap Summary

| Feature/API | Swift Implementation | Kotlin Implementation | Gap Status | Action Required |
|-------------|---------------------|----------------------|------------|-----------------|
| **Networking** | Alamofire | Ktor | ⚠️ Different libs | Both valid |
| **File System** | Files.swift | Platform expect/actual | ⚠️ Different | Both valid |
| **Error Types** | SDKError enum | SDKError sealed class | ⚠️ Different | Both valid |
| **Logging** | os_log + Pulse | Platform logging | ⚠️ Different | Both valid |
| **Analytics** | ✅ TelemetryService + GRDB | ✅ AnalyticsService + Room | ✅ Parity | - |
| **Memory Management** | ✅ MemoryService | ✅ MemoryService | ✅ Parity | - |
| **Cost Tracking (LLM)** | ⚠️ Partial (defined, not fully integrated) | ⚠️ Partial (defined, not fully integrated) | ⚠️ Both Partial | Both need work |

---

### 5.1 Networking Layer

**Swift (Alamofire):**
```swift
// File: NetworkService.swift

final class AlamofireNetworkService: NetworkService {
    private let session: Session

    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        let request = session.request(endpoint.url, method: endpoint.method)

        let response = await request.serializingDecodable(T.self).response

        guard let value = response.value else {
            throw NetworkError.decodingFailed
        }

        return value
    }
}
```

**Kotlin (Ktor):**
```kotlin
// File: NetworkService.kt

class KtorNetworkService(private val client: HttpClient) : NetworkService {

    override suspend fun <T> request(endpoint: Endpoint, type: KClass<T>): T {
        val response = client.request {
            url(endpoint.url)
            method = endpoint.method
        }

        return response.body()
    }
}
```

**Gap:** ⚠️ **Different libraries, same functionality**

**Action Required:** None (both are production-ready)

---

### 5.2 Error Handling Patterns

**Swift (Enum with Associated Values):**
```swift
// File: SDKError.swift

public enum SDKError: Error, Sendable {
    case notInitialized
    case invalidAPIKey(String)
    case invalidState(String)
    case componentNotInitialized(String)
    case componentNotAvailable(String)
    case networkError(String)
    case timeout(String)
    case serverError(String)
    case validationFailed(String)
    case storageError(String)
    case checksumMismatch(expected: String, actual: String)
}

// Usage:
throw SDKError.checksumMismatch(expected: "abc", actual: "def")
```

**Kotlin (Sealed Class Hierarchy):**
```kotlin
// File: SDKError.kt

sealed class SDKError(message: String) : Exception(message) {
    object NotInitialized : SDKError("SDK not initialized")

    data class InvalidAPIKey(val key: String) : SDKError("Invalid API key: $key")
    data class InvalidState(val state: String) : SDKError("Invalid state: $state")
    data class ComponentNotInitialized(val component: String) : SDKError("Component not initialized: $component")
    data class ComponentNotAvailable(val component: String) : SDKError("Component not available: $component")
    data class NetworkError(override val message: String) : SDKError(message)
    data class Timeout(override val message: String) : SDKError(message)
    data class ServerError(override val message: String) : SDKError(message)
    data class ValidationFailed(override val message: String) : SDKError(message)
    data class StorageError(override val message: String) : SDKError(message)
    data class ChecksumMismatch(val expected: String, val actual: String) :
        SDKError("Checksum mismatch: expected $expected, got $actual")
}

// Usage:
throw SDKError.ChecksumMismatch(expected = "abc", actual = "def")
```

**Gap:** ⚠️ **Different approaches, both type-safe**

**Action Required:** None (both are idiomatic for their platforms)

---

### 5.3 Cost Tracking Integration

**Swift (Partially Implemented):**
```swift
// File: RunAnywhere.swift

// API is defined but not fully wired
public static func getCostStatistics(
    for period: CostStatistics.TimePeriod
) async throws -> CostStatistics {
    // TODO: Implement cost tracking
    fatalError("Cost tracking not yet implemented")
}
```

**Kotlin (Partially Implemented):**
```kotlin
// File: RunAnywhere.kt

// API is defined but stubbed
override suspend fun enableCostTracking(config: CostTrackingConfig) {
    // TODO: Implement cost tracking service
}

override suspend fun getCostStatistics(period: CostStatistics.TimePeriod): CostStatistics {
    // TODO: Implement cost statistics retrieval
    return CostStatistics.empty()
}
```

**Gap:** ❌ **Both Missing** - Neither SDK has full cost tracking for LLM

**Action Required (Both SDKs):**
1. Implement CostTracker service
2. Track tokens per request (prompt + completion)
3. Calculate costs based on model pricing
4. Store in database for historical queries
5. Real-time tracking option (if `enableRealTimeTracking = true`)

**Estimated Effort:** Medium (2 days for both SDKs)

---

## 🟡 PRIORITY 6: Structured Output (Text-to-Text Advanced)

### Gap Summary

| Feature/API | Swift Implementation | Kotlin Implementation | Gap Status | Action Required |
|-------------|---------------------|----------------------|------------|-----------------|
| **Structured Output** | ✅ `StructuredOutputConfig` | ✅ `StructuredOutputConfig` | ✅ Parity | - |
| **JSON Schema Support** | ✅ JSON schema validation | ✅ JSON schema validation | ✅ Parity | - |
| **Type-Safe Output** | ⚠️ Manual parsing | ✅ `generateStructured<T>()` with reified types | ⚠️ Kotlin Better | Add to Swift |

---

### 6.1 Structured Output Configuration

**Swift:**
```swift
// File: StructuredOutputConfig.swift

public struct StructuredOutputConfig: Sendable {
    public let schema: JSONSchema
    public let strictMode: Bool
    public let maxRetries: Int

    public init(schema: JSONSchema, strictMode: Bool = true, maxRetries: Int = 3) {
        self.schema = schema
        self.strictMode = strictMode
        self.maxRetries = maxRetries
    }
}

// Usage:
let options = RunAnywhereGenerationOptions(
    structuredOutput: StructuredOutputConfig(
        schema: personSchema,
        strictMode: true
    )
)

let json = try await RunAnywhere.generate(prompt, options: options)
// Manual parsing needed:
let person = try JSONDecoder().decode(Person.self, from: json.data(using: .utf8)!)
```

**Kotlin:**
```kotlin
// File: StructuredOutputConfig.kt

data class StructuredOutputConfig(
    val schema: JSONSchema,
    val strictMode: Boolean = true,
    val maxRetries: Int = 3
)

// Type-safe API:
suspend inline fun <reified T : Generatable> generateStructured(
    prompt: String,
    options: RunAnywhereGenerationOptions? = null
): T {
    val opts = options?.copy(
        structuredOutput = StructuredOutputConfig(
            schema = T::class.generateSchema()
        )
    ) ?: RunAnywhereGenerationOptions.DEFAULT

    val json = generate(prompt, opts)

    return Json.decodeFromString<T>(json)
}

// Usage (type-safe):
data class Person(val name: String, val age: Int) : Generatable

val person = RunAnywhere.generateStructured<Person>(
    prompt = "Generate a person named John, age 30"
)
// Returns typed Person object directly!
```

**Gap:** ⚠️ **Kotlin Better** - Has type-safe generic API

**Action Required:** Add Swift generic version with Codable

**Code to Add to Swift:**
```swift
// Add to RunAnywhere.swift

public static func generateStructured<T: Codable>(
    _ prompt: String,
    options: RunAnywhereGenerationOptions?,
    type: T.Type
) async throws -> T {
    let opts = options ?? RunAnywhereGenerationOptions()

    // Auto-generate schema from Codable type
    let schema = try JSONSchema.from(type: type)

    let optionsWithSchema = RunAnywhereGenerationOptions(
        // ... copy other fields ...
        structuredOutput: StructuredOutputConfig(schema: schema)
    )

    let json = try await generate(prompt, options: optionsWithSchema)

    let data = json.data(using: .utf8)!
    return try JSONDecoder().decode(T.self, from: data)
}

// Usage:
struct Person: Codable {
    let name: String
    let age: Int
}

let person = try await RunAnywhere.generateStructured(
    "Generate a person",
    options: nil,
    type: Person.self
)
```

**Estimated Effort:** Medium (1 day for Swift)

---

## 🔵 PRIORITY 7: Voice Pipeline (INTERFACES ONLY - Implementation Later)

### Status: ⏸️ **DEFERRED** - Document interfaces, implementation is Phase 2

Both SDKs have voice component **interfaces** defined. The Kotlin SDK should copy Swift's interface signatures for future compatibility, but **actual implementation is deferred**.

**Swift Voice Components:**
- `STTComponent` - Speech-to-text interface (WhisperKit provider available)
- `VADComponent` - Voice activity detection (SimpleEnergyVAD provider)
- `TTSComponent` - Text-to-speech interface (AVSpeechSynthesizer provider)
- `SpeakerDiarizationComponent` - Speaker identification (FluidAudio provider)
- `VoiceAgentComponent` - Full pipeline orchestration

**Kotlin Voice Components:**
- `STTComponent` - ✅ Interface copied from Swift (WhisperCPP provider available)
- `VADComponent` - ✅ Interface copied from Swift (SimpleEnergyVAD provider)
- `TTSComponent` - ⚠️ Stub only, needs interface parity
- `SpeakerDiarizationComponent` - ✅ Interface copied from Swift
- `VoiceAgentComponent` - ❌ Missing, needs interface

**Action Required (Kotlin):**
1. Copy `TTSComponent` interface from Swift (add missing methods)
2. Add `VoiceAgentComponent` interface
3. Mark all as `@Deprecated("Implementation deferred to Phase 2")`

**Estimated Effort:** Small (0.5 days to align interfaces)

---

## 🔵 PRIORITY 8: Other Features (Document for Future)

These features exist in Swift but are **NOT needed** for text-to-text LLM generation:

| Feature | Swift Status | Kotlin Status | Notes |
|---------|-------------|---------------|-------|
| **VLM (Vision Language Models)** | ⚠️ Partial (protocol defined) | ⚠️ Partial (interface only) | Phase 3 |
| **Wake Word Detection** | ⚠️ Partial (protocol defined) | ❌ Missing | Phase 3 |
| **Real-time Audio Processing** | ✅ Working | ❌ Missing | Phase 3 |
| **Advanced Diarization** | ✅ FluidAudio integrated | ⚠️ Interface only | Phase 3 |
| **Voice Agent Pipeline** | ✅ Full pipeline | ⚠️ Partial | Phase 2 |
| **SwiftUI Integration** | ✅ Combine support | N/A | iOS-specific |
| **Jetpack Compose Integration** | N/A | ❌ Missing | Android-specific, Phase 3 |
| **Background Processing** | ✅ URLSession | ⚠️ WorkManager on Android | Phase 3 |

**Recommendation:** Document these for future reference but **do not implement** until text-to-text LLM is complete.

---

## Appendix A: Swift SDK Code References

### A.1 Initialization
```swift
// File: Sources/RunAnywhere/Public/RunAnywhere.swift (lines 243-347)

public static func initialize(
    apiKey: String,
    baseURL: URL,
    environment: SDKEnvironment
) throws {
    // 5-step lightweight init
    // 1. Validation
    // 2. Logging
    // 3. Storage
    // 4. Database
    // 5. Local services
    // NO NETWORK CALLS
}
```

### A.2 Lazy Device Registration
```swift
// File: Sources/RunAnywhere/Public/RunAnywhere.swift (lines 400-450)

private static func ensureDeviceRegistered() async throws {
    guard !isDeviceRegistered else { return }

    try await registerDevice(maxRetries: 3)
    isDeviceRegistered = true
}
```

### A.3 Generation Options
```swift
// File: Sources/RunAnywhere/Public/Models/GenerationOptions.swift

public struct RunAnywhereGenerationOptions: Sendable {
    public let maxTokens: Int = 100
    public let temperature: Float = 0.7
    public let topP: Float = 1.0
    public let enableRealTimeTracking: Bool = true
    public let stopSequences: [String] = []
    public let streamingEnabled: Bool = false
    public let preferredExecutionTarget: ExecutionTarget? = nil
    public let structuredOutput: StructuredOutputConfig? = nil
    public let systemPrompt: String? = nil
}
```

### A.4 Model Download with Progress
```swift
// File: Sources/RunAnywhere/Public/Extensions/RunAnywhere+Download.swift

static func downloadModelWithProgress(_ modelId: String) async throws -> AsyncStream<DownloadProgress> {
    // Returns detailed progress with speed, ETA, state
}

public struct DownloadProgress: Sendable {
    public let bytesDownloaded: Int64
    public let totalBytes: Int64
    public let percentComplete: Float
    public let state: DownloadState
    public let speed: Int64?
    public let estimatedTimeRemaining: TimeInterval?
    public let currentFile: String?
}
```

---

## Appendix B: Kotlin SDK Code References

### B.1 Initialization
```kotlin
// File: src/commonMain/kotlin/com/runanywhere/sdk/public/RunAnywhere.kt (lines 243-347)

override suspend fun initialize(
    apiKey: String,
    baseURL: String?,
    environment: SDKEnvironment
) {
    // Initial setup only
    // Requires separate bootstrap() call
}

suspend fun bootstrap(params: SDKInitParams): ConfigurationData {
    // 8-step bootstrap (includes network calls)
}
```

### B.2 Generation Options
```kotlin
// File: src/commonMain/kotlin/com/runanywhere/sdk/models/GenerationOptions.kt

data class RunAnywhereGenerationOptions(
    val maxTokens: Int = 100,
    val temperature: Float = 0.7f,
    val topP: Float = 1.0f,
    val enableRealTimeTracking: Boolean = true,
    val stopSequences: List<String> = emptyList(),
    val streamingEnabled: Boolean = false,
    val preferredExecutionTarget: ExecutionTarget? = null,
    val structuredOutput: StructuredOutputConfig? = null,
    val systemPrompt: String? = null,

    // KOTLIN HAS EXTRAS:
    val topK: Int? = null,
    val repetitionPenalty: Float? = null,
    val frequencyPenalty: Float? = null,
    val presencePenalty: Float? = null,
    val seed: Int? = null,
    val contextLength: Int? = null
)
```

### B.3 LLM Configuration (Advanced)
```kotlin
// File: src/commonMain/kotlin/com/runanywhere/sdk/components/llm/LLMConfiguration.kt

data class LLMConfiguration(
    // 30+ parameters for hardware optimization
    val contextLength: Int = 2048,
    val useGPUIfAvailable: Boolean = true,
    val quantizationLevel: QuantizationLevel? = null,
    val cacheSize: Int = 100,
    val cpuThreads: Int? = null,
    val gpuLayers: Int? = null,
    val memoryMapping: Boolean = true,
    val flashAttention: Boolean = true,
    val kvCacheOptimization: Boolean = true,
    // ... 20+ more parameters
)
```

---

## Appendix C: Implementation Roadmap

### Phase 1: Critical Path (5-7 days)

**Week 1: Foundation**
1. **Day 1-2:** Lazy device registration
   - Add `ensureDeviceRegistered()` to Kotlin
   - Auto-call on first API usage
   - Implement retry logic
   - Dev mode fallback

2. **Day 3:** Model download improvements
   - Change return type to `Flow<DownloadProgress>`
   - Expose speed and ETA
   - Add checksum verification

3. **Day 4:** Generation options alignment
   - Add missing parameters to Swift (topK, penalties, seed)
   - Validate parameter ranges
   - Update documentation

4. **Day 5-6:** Model management APIs
   - Add `unloadModel()` to both SDKs
   - Add current model tracking
   - Offline/bundle loading support

5. **Day 7:** Testing and validation
   - Integration tests for lazy registration
   - Model download verification tests
   - Generation options tests

### Phase 2: Supporting Features (3-4 days)

**Week 2: Enhancements**
1. **Day 1:** Cost tracking
   - Implement CostTracker service
   - Token usage tracking
   - Database storage

2. **Day 2:** Structured output improvements
   - Add Swift generic API
   - Schema auto-generation
   - Type-safe parsing

3. **Day 3:** Context management
   - Add conversation APIs to Swift
   - Token counting public API
   - Context window validation

4. **Day 4:** Voice interface alignment (interfaces only)
   - Copy Swift voice interfaces to Kotlin
   - Mark as deferred
   - Document for Phase 2

### Phase 3: Polish (1-2 days)

1. Documentation updates
2. Example code for both SDKs
3. Migration guide
4. Performance testing

---

## Conclusion

### Summary of Findings

**Kotlin SDK has solid foundations** but needs alignment with Swift's simpler initialization and richer model management APIs. The **critical path to parity** focuses on:

1. **Lazy initialization** (biggest gap)
2. **Model download metadata** (user experience)
3. **Checksum verification** (security/reliability)
4. **Generation option parity** (feature completeness)

**Estimated Total Effort:** 8-11 days for full text-to-text LLM parity

### Recommended Next Steps

1. **Immediate (Priority 1-2):** Implement lazy device registration and model download improvements
2. **Short-term (Priority 3-4):** Align generation APIs and component architecture
3. **Medium-term (Priority 5-6):** Add cost tracking and structured output enhancements
4. **Long-term (Priority 7-8):** Voice pipeline implementation (Phase 2)

### Key Decision Points

1. **Initialization Pattern:** Should Kotlin fully adopt Swift's lazy pattern, or keep explicit bootstrap?
   - **Recommendation:** Adopt lazy pattern for better UX, keep explicit bootstrap as option

2. **Component States:** Should Swift add download states, or keep separate?
   - **Recommendation:** Keep separate (simpler, clearer separation of concerns)

3. **Generation Options:** Should both SDKs have identical parameters?
   - **Recommendation:** Yes, align to superset of both (Kotlin's current parameters)

4. **Error Handling:** Enum vs Sealed Classes?
   - **Recommendation:** Keep platform idioms (both are type-safe and valid)

---

**Document Version:** 1.0
**Last Updated:** 2025-10-08
**Next Review:** After Phase 1 implementation
