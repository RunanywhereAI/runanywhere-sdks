# RunAnywhere Kotlin SDK - Architecture Reference
## For VLM Implementation

**Document Purpose:** Detailed architecture analysis to guide VLM implementation
**Last Updated:** 2025-10-26

---

## Table of Contents

1. [SDK Architecture Overview](#sdk-architecture-overview)
2. [Component System Deep Dive](#component-system-deep-dive)
3. [Module Registry & Plugin System](#module-registry--plugin-system)
4. [Service Provider Pattern](#service-provider-pattern)
5. [LLM Module Reference Implementation](#llm-module-reference-implementation)
6. [VLM Component Current State](#vlm-component-current-state)
7. [Platform Abstraction (expect/actual)](#platform-abstraction-expectactual)
8. [Configuration Patterns](#configuration-patterns)
9. [Event System](#event-system)
10. [File Locations Quick Reference](#file-locations-quick-reference)

---

## SDK Architecture Overview

The RunAnywhere Kotlin SDK follows a **plugin-based, component-driven architecture** with these core principles:

### Core Design Principles

1. **Component-Based Architecture**
   - All features (STT, VAD, LLM, VLM) are components
   - Inherit from `BaseComponent<TService>`
   - Unified lifecycle management
   - Event-driven state changes

2. **Plugin System**
   - Runtime service discovery via `ModuleRegistry`
   - Providers register themselves
   - No hard dependencies between components and implementations
   - Support multiple providers per modality

3. **Platform Abstraction**
   - Business logic in `commonMain/`
   - Platform-specific code in `jvmMain/`, `androidMain/`, etc.
   - `expect/actual` for platform APIs only

4. **Configuration-Driven**
   - Immutable configuration data classes
   - Validation at construction time
   - Sensible defaults and presets

5. **Async-First**
   - All operations are `suspend` functions or `Flow`-based
   - Structured concurrency with Kotlin coroutines
   - Thread-safe by design

---

## Component System Deep Dive

### BaseComponent Pattern

**Location:** `/sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/components/base/Component.kt`

```kotlin
abstract class BaseComponent<TService : Any>(
    protected val configuration: ComponentConfiguration,
    serviceContainer: ServiceContainer? = null
) : Component {

    // State management
    override var state: ComponentState = ComponentState.NOT_INITIALIZED
        protected set

    private var service: TService? = null
    protected val eventBus = EventBus

    // Abstract method - platform-specific service creation
    protected abstract suspend fun createService(): TService

    // Initialization lifecycle
    suspend fun initialize() {
        if (state != ComponentState.NOT_INITIALIZED) {
            throw IllegalStateException("Component already initialized")
        }

        try {
            state = ComponentState.INITIALIZING
            publishEvent(ComponentInitializationEvent.InitializationStarted(component))

            // Validate configuration
            configuration.validate()

            // Create platform-specific service
            service = createService()

            state = ComponentState.READY
            publishEvent(ComponentInitializationEvent.ComponentReady(component))
        } catch (e: Exception) {
            state = ComponentState.FAILED
            publishEvent(ComponentInitializationEvent.ComponentFailed(component, e))
            throw e
        }
    }

    // Cleanup lifecycle
    override suspend fun cleanup() {
        try {
            performCleanup()
            service = null
            serviceContainer = null
            state = ComponentState.NOT_INITIALIZED
        } catch (e: Exception) {
            SDKLogger.error("BaseComponent", "Cleanup failed", e)
            throw e
        }
    }

    // Health check
    override suspend fun healthCheck(): ComponentHealth {
        return when (state) {
            ComponentState.READY -> ComponentHealth.Healthy
            ComponentState.INITIALIZING -> ComponentHealth.Degraded("Still initializing")
            ComponentState.FAILED -> ComponentHealth.Unhealthy("Component failed")
            ComponentState.NOT_INITIALIZED -> ComponentHealth.Unhealthy("Not initialized")
        }
    }

    // Protected helpers
    protected fun getService(): TService {
        return service ?: throw IllegalStateException("Service not initialized")
    }

    protected open suspend fun performCleanup() {
        // Override in subclasses for specific cleanup
    }

    private fun publishEvent(event: ComponentEvent) {
        eventBus.publish(event)
    }

    val isReady: Boolean get() = state == ComponentState.READY
}
```

### Component States

```kotlin
enum class ComponentState {
    NOT_INITIALIZED,  // Initial state
    INITIALIZING,     // Loading models, setting up
    READY,            // Service ready for use
    FAILED            // Error occurred
}
```

### Component Interface

```kotlin
interface Component {
    val state: ComponentState
    val isReady: Boolean

    suspend fun initialize()
    suspend fun cleanup()
    suspend fun healthCheck(): ComponentHealth
}
```

### ComponentHealth

```kotlin
sealed class ComponentHealth {
    object Healthy : ComponentHealth()
    data class Degraded(val reason: String) : ComponentHealth()
    data class Unhealthy(val reason: String) : ComponentHealth()
}
```

---

## Module Registry & Plugin System

### ModuleRegistry

**Location:** `/sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/core/ModuleRegistry.kt`

```kotlin
object ModuleRegistry {
    private val lock = Any()

    // Provider storage (thread-safe)
    private val llmProviders = mutableListOf<LLMServiceProvider>()
    private val sttProviders = mutableListOf<STTServiceProvider>()
    private val vlmProviders = mutableListOf<VLMServiceProvider>()
    private val ttsProviders = mutableListOf<TTSServiceProvider>()
    private val vadProviders = mutableListOf<VADServiceProvider>()

    // Registration methods (thread-safe)
    fun registerLLM(provider: LLMServiceProvider) {
        synchronized(lock) {
            if (llmProviders.none { it.name == provider.name }) {
                llmProviders.add(provider)
                SDKLogger.info("ModuleRegistry", "Registered LLM provider: ${provider.name}")
            }
        }
    }

    fun registerVLM(provider: VLMServiceProvider) {
        synchronized(lock) {
            if (vlmProviders.none { it.name == provider.name }) {
                vlmProviders.add(provider)
                SDKLogger.info("ModuleRegistry", "Registered VLM provider: ${provider.name}")
            }
        }
    }

    // Provider lookup (thread-safe)
    fun llmProvider(modelId: String? = null): LLMServiceProvider? {
        synchronized(lock) {
            return if (modelId == null) {
                llmProviders.firstOrNull()
            } else {
                llmProviders.firstOrNull { it.canHandle(modelId) }
            }
        }
    }

    fun vlmProvider(modelId: String? = null): VLMServiceProvider? {
        synchronized(lock) {
            return if (modelId == null) {
                vlmProviders.firstOrNull()
            } else {
                vlmProviders.firstOrNull { it.canHandle(modelId) }
            }
        }
    }

    // List all providers
    fun listLLMProviders(): List<LLMServiceProvider> {
        synchronized(lock) {
            return llmProviders.toList()
        }
    }

    fun listVLMProviders(): List<VLMServiceProvider> {
        synchronized(lock) {
            return vlmProviders.toList()
        }
    }

    // Cleanup
    fun clear() {
        synchronized(lock) {
            llmProviders.clear()
            sttProviders.clear()
            vlmProviders.clear()
            ttsProviders.clear()
            vadProviders.clear()
        }
    }
}
```

### AutoRegisteringModule Interface

```kotlin
interface AutoRegisteringModule {
    val name: String
    val version: String

    fun register()
}
```

### Module Registration Example

```kotlin
class LlamaCppModule : AutoRegisteringModule {
    override val name: String = "llama.cpp LLM"
    override val version: String = "0.1.0"

    override fun register() {
        ModuleRegistry.registerLLM(LlamaCppServiceProvider())
        SDKLogger.info("LlamaCppModule", "Registered llama.cpp LLM provider")
    }
}

// Auto-registration happens at SDK initialization
// RunAnywhere.initialize() -> discovers and registers all modules
```

---

## Service Provider Pattern

### Provider Interface (LLM Example)

**Location:** `/sdk/runanywhere-kotlin/modules/runanywhere-llm-llamacpp/src/commonMain/kotlin/LlamaCppServiceProvider.kt`

```kotlin
interface LLMServiceProvider {
    // Identification
    val name: String
    val version: String
    val supportedModels: List<String>

    // Service creation
    suspend fun createLLMService(configuration: LLMConfiguration): LLMService

    // Model validation
    fun canHandle(modelId: String?): Boolean
    suspend fun validateModel(modelPath: String): ModelValidationResult

    // Memory & hardware optimization
    suspend fun estimateMemoryRequirement(modelPath: String): MemoryEstimate
    suspend fun getOptimalConfiguration(
        modelPath: String,
        constraints: HardwareConstraints
    ): LLMConfiguration

    // Model management
    suspend fun downloadModel(
        modelId: String,
        destination: Path
    ): Flow<DownloadProgress>

    suspend fun listAvailableModels(): List<ModelInfo>

    // Lifecycle
    suspend fun cleanup()
}
```

### Provider Implementation Pattern

```kotlin
class LlamaCppServiceProvider : LLMServiceProvider {
    override val name: String = "llama.cpp"
    override val version: String = "0.1.0"
    override val supportedModels: List<String> = listOf(
        "llama-2-7b", "llama-2-13b", "mistral-7b", "phi-2"
    )

    override suspend fun createLLMService(
        configuration: LLMConfiguration
    ): LLMService {
        // Platform-specific service creation via expect/actual
        return createLlamaCppService(configuration)
    }

    override fun canHandle(modelId: String?): Boolean {
        if (modelId == null) return true
        return supportedModels.any { modelId.contains(it, ignoreCase = true) }
    }

    override suspend fun validateModel(modelPath: String): ModelValidationResult {
        // Check if file exists
        if (!fileSystem.exists(modelPath)) {
            return ModelValidationResult.Invalid("Model file not found: $modelPath")
        }

        // Parse GGUF metadata
        try {
            val metadata = parseGGUFMetadata(modelPath)
            return ModelValidationResult.Valid(metadata)
        } catch (e: Exception) {
            return ModelValidationResult.Invalid("Invalid GGUF file: ${e.message}")
        }
    }

    override suspend fun estimateMemoryRequirement(
        modelPath: String
    ): MemoryEstimate {
        val fileSize = fileSystem.size(modelPath)
        val metadata = parseGGUFMetadata(modelPath)

        // Estimate based on model size and quantization
        val baseMemory = fileSize
        val contextMemory = calculateContextMemory(metadata.contextSize)
        val kvCacheMemory = calculateKVCacheMemory(metadata)

        return MemoryEstimate(
            minimum = baseMemory + contextMemory,
            recommended = baseMemory + contextMemory + kvCacheMemory,
            optimal = (baseMemory + contextMemory + kvCacheMemory) * 1.5
        )
    }

    override suspend fun getOptimalConfiguration(
        modelPath: String,
        constraints: HardwareConstraints
    ): LLMConfiguration {
        val memoryEstimate = estimateMemoryRequirement(modelPath)

        return when {
            constraints.availableMemory < memoryEstimate.minimum -> {
                throw InsufficientMemoryError(
                    "Need ${memoryEstimate.minimum}MB, have ${constraints.availableMemory}MB"
                )
            }
            constraints.isMobile -> LLMConfiguration.MOBILE
            constraints.hasGPU -> LLMConfiguration.GPU_ACCELERATED
            else -> LLMConfiguration.DESKTOP
        }
    }

    override suspend fun cleanup() {
        // Cleanup any cached resources
    }
}
```

### VLMServiceProvider Interface (TO BE IMPLEMENTED)

```kotlin
interface VLMServiceProvider {
    // Identification
    val name: String
    val version: String
    val supportedModels: List<String>

    // Service creation
    suspend fun createVLMService(configuration: VLMConfiguration): VLMService

    // Model validation (VLM requires TWO files: LLM + projector)
    fun canHandle(modelId: String?): Boolean
    suspend fun validateModel(modelPath: String): ModelValidationResult
    suspend fun validateVisionProjector(projectorPath: String): ModelValidationResult

    // Memory & hardware
    suspend fun estimateMemoryRequirement(
        modelPath: String,
        projectorPath: String
    ): MemoryEstimate

    suspend fun getOptimalConfiguration(
        modelPath: String,
        constraints: HardwareConstraints
    ): VLMConfiguration

    // Model management
    suspend fun downloadModel(
        modelId: String,
        destination: Path
    ): Flow<DownloadProgress>

    suspend fun listAvailableModels(): List<VLMModelInfo>

    // Lifecycle
    suspend fun cleanup()
}
```

---

## LLM Module Reference Implementation

### Module Structure

**Location:** `/sdk/runanywhere-kotlin/modules/runanywhere-llm-llamacpp/`

```
runanywhere-llm-llamacpp/
├── src/
│   ├── commonMain/kotlin/com/runanywhere/llm/llamacpp/
│   │   ├── LlamaCppModule.kt              # Auto-registration entry point
│   │   ├── LlamaCppServiceProvider.kt     # Provider implementation
│   │   ├── LlamaCppService.kt (expect)    # Service interface declaration
│   │   └── models/
│   │       ├── ModelInfo.kt
│   │       └── GenerationConfig.kt
│   │
│   ├── jvmAndroidMain/kotlin/com/runanywhere/llm/llamacpp/
│   │   ├── LlamaCppService.kt (actual)    # JVM/Android implementation
│   │   └── LLamaAndroid.kt                # JNI wrapper
│   │
│   └── jvmMain/kotlin/com/runanywhere/llm/llamacpp/
│       └── LlamaCppService.kt (actual)    # JVM-only implementation
│
├── native/
│   └── jni/
│       ├── llama_jni.cpp                  # JNI bindings
│       ├── CMakeLists.txt                 # Native build config
│       └── README.md
│
├── build.gradle.kts                       # Module build config
└── README.md
```

### LlamaCppModule.kt

```kotlin
package com.runanywhere.llm.llamacpp

import com.runanywhere.sdk.core.AutoRegisteringModule
import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.foundation.SDKLogger

class LlamaCppModule : AutoRegisteringModule {
    override val name: String = "llama.cpp LLM"
    override val version: String = "0.1.0"

    override fun register() {
        ModuleRegistry.registerLLM(LlamaCppServiceProvider())
        SDKLogger.info("LlamaCppModule", "Registered llama.cpp LLM provider")
    }
}
```

### LlamaCppService.kt (expect)

```kotlin
package com.runanywhere.llm.llamacpp

import com.runanywhere.sdk.services.llm.*
import kotlinx.coroutines.flow.Flow

expect class LlamaCppService(
    configuration: LLMConfiguration
) : LLMService {
    override suspend fun initialize()
    override suspend fun loadModel(modelPath: String)
    override suspend fun unloadModel()
    override suspend fun generate(prompt: String): String
    override fun generateStream(prompt: String): Flow<String>
    override suspend fun cleanup()
    override suspend fun healthCheck(): ServiceHealth
}
```

### LlamaCppService.kt (actual - jvmAndroidMain)

```kotlin
package com.runanywhere.llm.llamacpp

import android.llama.cpp.LLamaAndroid
import com.runanywhere.sdk.services.llm.*
import kotlinx.coroutines.flow.Flow

actual class LlamaCppService actual constructor(
    private val configuration: LLMConfiguration
) : LLMService {

    private var llamaAndroid: LLamaAndroid? = null
    private var isInitialized = false

    actual override suspend fun initialize() {
        llamaAndroid = LLamaAndroid()
        isInitialized = true
    }

    actual override suspend fun loadModel(modelPath: String) {
        val llama = llamaAndroid ?: throw IllegalStateException("Not initialized")
        llama.load(modelPath)
    }

    actual override suspend fun unloadModel() {
        llamaAndroid?.unload()
    }

    actual override suspend fun generate(prompt: String): String {
        val llama = llamaAndroid ?: throw IllegalStateException("Not initialized")
        val responseBuilder = StringBuilder()

        llama.send(prompt).collect { token ->
            responseBuilder.append(token)
        }

        return responseBuilder.toString()
    }

    actual override fun generateStream(prompt: String): Flow<String> {
        val llama = llamaAndroid ?: throw IllegalStateException("Not initialized")
        return llama.send(prompt)
    }

    actual override suspend fun cleanup() {
        llamaAndroid?.cleanup()
        llamaAndroid = null
        isInitialized = false
    }

    actual override suspend fun healthCheck(): ServiceHealth {
        return when {
            !isInitialized -> ServiceHealth.Unhealthy("Not initialized")
            llamaAndroid == null -> ServiceHealth.Unhealthy("LLamaAndroid is null")
            else -> ServiceHealth.Healthy
        }
    }
}
```

### LLamaAndroid.kt (JNI Wrapper)

```kotlin
package android.llama.cpp

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.asCoroutineDispatcher
import java.util.concurrent.Executors

class LLamaAndroid {
    private val runLoop = Executors.newSingleThreadExecutor().asCoroutineDispatcher()
    private var context: Long = 0L

    companion object {
        init {
            System.loadLibrary("llama_android")
        }
    }

    // Native methods
    private external fun load_model(filename: String, nThreads: Int): Long
    private external fun free_model(context: Long)
    private external fun completion_init(
        context: Long,
        prompt: String,
        nPredict: Int
    ): String
    private external fun completion_loop(
        context: Long,
        token: String
    ): String?

    // High-level API
    suspend fun load(modelPath: String) {
        context = load_model(modelPath, nThreads = 4)
        if (context == 0L) {
            throw IllegalStateException("Failed to load model")
        }
    }

    fun send(prompt: String): Flow<String> = flow {
        if (context == 0L) {
            throw IllegalStateException("Model not loaded")
        }

        val initialToken = completion_init(context, prompt, nPredict = 512)
        emit(initialToken)

        var token = initialToken
        while (true) {
            val nextToken = completion_loop(context, token) ?: break
            emit(nextToken)
            token = nextToken
        }
    }.flowOn(runLoop)

    fun cleanup() {
        if (context != 0L) {
            free_model(context)
            context = 0L
        }
    }
}
```

---

## VLM Component Current State

### Current VLMComponent.kt

**Location:** `/sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/components/VLMComponent.kt`

```kotlin
class VLMComponent(
    configuration: VLMConfiguration,
    serviceContainer: ServiceContainer? = null
) : BaseComponent<VLMService>(configuration, serviceContainer) {

    override suspend fun createService(): VLMService {
        // TODO: Use ModuleRegistry to find provider
        // val provider = ModuleRegistry.vlmProvider(configuration.modelId)
        //     ?: throw VLMServiceError.NoProviderAvailable()
        // return provider.createVLMService(configuration)

        // Current stub implementation
        return DefaultVLMService()
    }
}
```

### Current VLMConfiguration.kt

```kotlin
data class VLMConfiguration(
    val modelId: String,
    val imageSize: ImageSize = ImageSize.DEFAULT,
    val confidenceThreshold: Float = 0.5f,
    val supportedLanguages: List<String> = listOf("en")
) : ComponentConfiguration {
    override fun validate() {
        require(modelId.isNotBlank()) { "Model ID cannot be blank" }
        require(confidenceThreshold in 0.0..1.0) { "Confidence threshold must be between 0 and 1" }
    }
}

data class ImageSize(val width: Int, val height: Int) {
    companion object {
        val DEFAULT = ImageSize(336, 336)
    }
}
```

### Current VLMService.kt (Stub)

```kotlin
interface VLMService {
    suspend fun processImage(imageBytes: ByteArray, prompt: String): VLMOutput
}

data class VLMOutput(
    val description: String,
    val detectedObjects: List<DetectedObject> = emptyList(),
    val confidence: Float,
    val processingTimeMs: Long,
    val metadata: ImageMetadata
)

data class DetectedObject(
    val label: String,
    val confidence: Float,
    val boundingBox: BoundingBox
)

data class BoundingBox(
    val x: Int,
    val y: Int,
    val width: Int,
    val height: Int
)

data class ImageMetadata(
    val width: Int,
    val height: Int,
    val format: String
)

class DefaultVLMService : VLMService {
    override suspend fun processImage(imageBytes: ByteArray, prompt: String): VLMOutput {
        // Stub implementation
        return VLMOutput(
            description = "Stub response",
            confidence = 0.0f,
            processingTimeMs = 0L,
            metadata = ImageMetadata(0, 0, "unknown")
        )
    }
}
```

### What Needs to Be Added

1. **Complete VLMService Interface:**
   - Add lifecycle methods (initialize, loadModel, cleanup)
   - Add streaming support (processImageStream)
   - Add health check
   - Add model info methods

2. **Enhanced VLMConfiguration:**
   - Add hardware parameters (nThreads, nGpuLayers)
   - Add generation parameters (maxTokens, temperature)
   - Add optimization presets (MOBILE, DESKTOP, GPU_ACCELERATED)
   - Add model paths (modelPath, projectorPath)

3. **VLMServiceError:**
   - Create error enum with specific error types
   - Add error recovery suggestions
   - Add error event types

4. **VLMServiceProvider:**
   - Create interface matching LLMServiceProvider pattern
   - Add to ModuleRegistry

5. **Update VLMComponent:**
   - Use ModuleRegistry for provider lookup
   - Implement full lifecycle
   - Add event publishing
   - Add health checks

---

## Platform Abstraction (expect/actual)

### Purpose

The `expect/actual` mechanism allows:
- Defining interfaces in `commonMain/`
- Platform-specific implementations in `jvmMain/`, `androidMain/`, etc.
- Zero runtime overhead
- Compile-time verification

### Pattern: Service Interface

**commonMain/kotlin/Service.kt (expect):**
```kotlin
expect class PlatformService(config: Configuration) : Service {
    override suspend fun initialize()
    override suspend fun process(input: ByteArray): Output
    override suspend fun cleanup()
}
```

**jvmAndroidMain/kotlin/Service.kt (actual):**
```kotlin
actual class PlatformService actual constructor(
    private val config: Configuration
) : Service {
    private var nativeContext: Long = 0L

    actual override suspend fun initialize() {
        // JNI initialization
        nativeContext = native_init(config)
    }

    actual override suspend fun process(input: ByteArray): Output {
        // JNI call
        return native_process(nativeContext, input)
    }

    actual override suspend fun cleanup() {
        native_cleanup(nativeContext)
    }

    private external fun native_init(config: Configuration): Long
    private external fun native_process(ctx: Long, input: ByteArray): Output
    private external fun native_cleanup(ctx: Long)
}
```

### Pattern: Platform Context

**commonMain/kotlin/PlatformContext.kt (expect):**
```kotlin
expect class PlatformContext {
    fun initialize()
    fun getFileSystem(): FileSystem
    fun getHttpClient(): HttpClient
}
```

**androidMain/kotlin/PlatformContext.kt (actual):**
```kotlin
actual class PlatformContext(private val context: Context) {
    actual fun initialize() {
        // Android-specific setup
    }

    actual fun getFileSystem(): FileSystem {
        return AndroidFileSystem(context)
    }

    actual fun getHttpClient(): HttpClient {
        return AndroidHttpClient()
    }
}
```

### What Goes in commonMain vs Platform

**commonMain (Business Logic):**
- Interfaces and abstract classes
- Data models and enums
- Business logic and algorithms
- Service contracts
- Component definitions
- Event definitions

**Platform Modules (Platform-Specific):**
- JNI bindings
- Platform APIs (Android Context, iOS UIKit)
- File system access
- Network implementations
- Hardware access

---

## Configuration Patterns

### Configuration Interface

```kotlin
interface ComponentConfiguration {
    fun validate()
}
```

### Configuration Pattern

```kotlin
data class LLMConfiguration(
    // Model settings
    val modelId: String,
    val modelPath: String,

    // Hardware settings
    val nThreads: Int = 4,
    val nGpuLayers: Int = 0,
    val useMlock: Boolean = false,
    val useMmap: Boolean = true,

    // Generation settings
    val maxTokens: Int = 512,
    val temperature: Float = 0.7f,
    val topP: Float = 0.95f,
    val topK: Int = 40,
    val repeatPenalty: Float = 1.1f,

    // Context settings
    val contextSize: Int = 2048,
    val batchSize: Int = 512,

    // Optimization preset
    val preset: LLMPreset = LLMPreset.BALANCED
) : ComponentConfiguration {

    companion object {
        val MOBILE = LLMConfiguration(
            modelId = "phi-2",
            nThreads = 4,
            nGpuLayers = 0,
            maxTokens = 256,
            contextSize = 1024,
            preset = LLMPreset.SPEED
        )

        val DESKTOP = LLMConfiguration(
            modelId = "llama-2-7b",
            nThreads = 8,
            nGpuLayers = 32,
            maxTokens = 512,
            contextSize = 2048,
            preset = LLMPreset.QUALITY
        )

        val GPU_ACCELERATED = LLMConfiguration(
            modelId = "llama-2-13b",
            nThreads = 4,
            nGpuLayers = 99, // All layers
            maxTokens = 512,
            contextSize = 4096,
            preset = LLMPreset.QUALITY
        )
    }

    override fun validate() {
        require(modelId.isNotBlank()) { "Model ID cannot be blank" }
        require(nThreads > 0) { "nThreads must be positive" }
        require(maxTokens > 0) { "maxTokens must be positive" }
        require(temperature >= 0f) { "temperature must be non-negative" }
        require(contextSize > 0) { "contextSize must be positive" }
    }
}

enum class LLMPreset {
    SPEED,      // Fast inference, lower quality
    BALANCED,   // Balance speed and quality
    QUALITY     // Best quality, slower
}
```

---

## Event System

### EventBus

**Location:** `/sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/events/EventBus.kt`

```kotlin
object EventBus {
    private val _componentEvents = MutableSharedFlow<ComponentEvent>(
        replay = 0,
        extraBufferCapacity = 100,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )
    val componentEvents: SharedFlow<ComponentEvent> = _componentEvents.asSharedFlow()

    private val _sdkEvents = MutableSharedFlow<SDKEvent>(
        replay = 0,
        extraBufferCapacity = 100,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )
    val sdkEvents: SharedFlow<SDKEvent> = _sdkEvents.asSharedFlow()

    fun publish(event: ComponentEvent) {
        _componentEvents.tryEmit(event)
    }

    fun publish(event: SDKEvent) {
        _sdkEvents.tryEmit(event)
    }
}
```

### ComponentEvent Hierarchy

```kotlin
sealed class ComponentEvent {
    abstract val component: SDKComponent
    abstract val timestamp: Long
}

enum class SDKComponent {
    STT, VAD, LLM, VLM, TTS, ANALYTICS, MODEL_MANAGER
}

// Initialization events
sealed class ComponentInitializationEvent : ComponentEvent() {
    data class InitializationStarted(
        override val component: SDKComponent,
        override val timestamp: Long = System.currentTimeMillis()
    ) : ComponentInitializationEvent()

    data class ComponentReady(
        override val component: SDKComponent,
        val modelId: String? = null,
        override val timestamp: Long = System.currentTimeMillis()
    ) : ComponentInitializationEvent()

    data class ComponentFailed(
        override val component: SDKComponent,
        val error: Throwable,
        override val timestamp: Long = System.currentTimeMillis()
    ) : ComponentInitializationEvent()
}

// Model events
sealed class ModelEvent : ComponentEvent() {
    data class ModelLoadStarted(
        override val component: SDKComponent,
        val modelId: String,
        override val timestamp: Long = System.currentTimeMillis()
    ) : ModelEvent()

    data class ModelLoadCompleted(
        override val component: SDKComponent,
        val modelId: String,
        val loadTimeMs: Long,
        override val timestamp: Long = System.currentTimeMillis()
    ) : ModelEvent()

    data class ModelLoadFailed(
        override val component: SDKComponent,
        val modelId: String,
        val error: Throwable,
        override val timestamp: Long = System.currentTimeMillis()
    ) : ModelEvent()
}
```

### Event Usage

```kotlin
// Subscribe to events
viewModelScope.launch {
    EventBus.componentEvents
        .filterIsInstance<ComponentInitializationEvent.ComponentReady>()
        .filter { it.component == SDKComponent.VLM }
        .collect { event ->
            println("VLM component ready with model: ${event.modelId}")
        }
}

// Publish events
EventBus.publish(ComponentInitializationEvent.ComponentReady(
    component = SDKComponent.VLM,
    modelId = "mobilevlm-1.7b"
))
```

---

## File Locations Quick Reference

### SDK Core Files

```
/sdk/runanywhere-kotlin/src/
├── commonMain/kotlin/com/runanywhere/sdk/
│   ├── components/
│   │   ├── base/
│   │   │   └── Component.kt              # BaseComponent pattern
│   │   ├── STTComponent.kt
│   │   ├── VADComponent.kt
│   │   ├── LLMComponent.kt
│   │   └── VLMComponent.kt               # TO BE ENHANCED
│   │
│   ├── core/
│   │   ├── ModuleRegistry.kt             # Plugin registry
│   │   └── AutoRegisteringModule.kt
│   │
│   ├── foundation/
│   │   ├── ServiceContainer.kt           # DI container
│   │   └── SDKLogger.kt
│   │
│   ├── services/
│   │   ├── llm/
│   │   │   ├── LLMService.kt
│   │   │   └── LLMServiceProvider.kt
│   │   └── vlm/
│   │       ├── VLMService.kt             # TO BE ENHANCED
│   │       └── VLMServiceProvider.kt     # TO BE CREATED
│   │
│   └── events/
│       ├── EventBus.kt
│       ├── ComponentEvent.kt
│       └── SDKEvent.kt
```

### LLM Module (Reference)

```
/sdk/runanywhere-kotlin/modules/runanywhere-llm-llamacpp/
├── src/
│   ├── commonMain/kotlin/com/runanywhere/llm/llamacpp/
│   │   ├── LlamaCppModule.kt
│   │   ├── LlamaCppServiceProvider.kt
│   │   └── LlamaCppService.kt (expect)
│   │
│   ├── jvmAndroidMain/kotlin/com/runanywhere/llm/llamacpp/
│   │   ├── LlamaCppService.kt (actual)
│   │   └── LLamaAndroid.kt
│   │
│   └── jvmMain/kotlin/com/runanywhere/llm/llamacpp/
│       └── LlamaCppService.kt (actual)
│
├── native/
│   └── jni/
│       ├── llama_jni.cpp
│       └── CMakeLists.txt
│
└── build.gradle.kts
```

### VLM Module (To Be Created)

```
/sdk/runanywhere-kotlin/modules/runanywhere-vlm-llamacpp/
├── src/
│   ├── commonMain/kotlin/com/runanywhere/vlm/llamacpp/
│   │   ├── LlamaCppVLMModule.kt          # TO CREATE
│   │   ├── LlamaCppVLMServiceProvider.kt # TO CREATE
│   │   └── LlamaCppVLMService.kt (expect) # TO CREATE
│   │
│   ├── jvmAndroidMain/kotlin/com/runanywhere/vlm/llamacpp/
│   │   └── LlamaCppVLMService.kt (actual) # TO CREATE
│   │
│   └── jvmMain/kotlin/com/runanywhere/vlm/llamacpp/
│       └── LlamaCppVLMService.kt (actual) # TO CREATE
│
├── native/
│   └── jni/
│       ├── clip_jni.cpp                  # TO CREATE
│       └── CMakeLists.txt                # TO UPDATE
│
└── build.gradle.kts                      # TO CREATE
```

### Sample App

```
/examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/android/
├── ui/
│   ├── llm/
│   │   ├── LLMScreen.kt
│   │   └── LLMViewModel.kt
│   │
│   └── vlm/                              # TO CREATE
│       ├── VLMScreen.kt                  # TO CREATE
│       ├── VLMViewModel.kt               # TO CREATE
│       └── components/
│           ├── CameraPreview.kt          # TO CREATE
│           └── ImagePicker.kt            # TO CREATE
│
└── MainActivity.kt                       # TO UPDATE (add VLM tab)
```

---

## Summary for VLM Implementation

### Must Follow These Patterns

1. **Component Pattern:**
   - Inherit from `BaseComponent<VLMService>`
   - Implement `createService()` using `ModuleRegistry`
   - Publish events for all state changes

2. **Module Pattern:**
   - Create `LlamaCppVLMModule` with auto-registration
   - Register provider in `ModuleRegistry.registerVLM()`

3. **Provider Pattern:**
   - Implement complete `VLMServiceProvider` interface
   - Match LLM provider capabilities
   - Support model validation and memory estimation

4. **Service Pattern:**
   - Define service interface in `commonMain/` (expect)
   - Implement platform-specific in `jvmAndroidMain/` (actual)
   - Use JNI wrapper (`LLamaAndroid`) for native calls

5. **Configuration Pattern:**
   - Immutable data class with validation
   - Provide sensible presets (MOBILE, DESKTOP, GPU_ACCELERATED)
   - Support hardware optimization parameters

6. **Error Pattern:**
   - Create sealed class hierarchy for errors
   - Provide specific error types
   - Convert to events for observability

---

**END OF ARCHITECTURE REFERENCE**
