# LlamaCPP Module Architecture Analysis

**Purpose**: This document analyzes the existing LlamaCPP module in the runanywhere-kotlin SDK to understand the architectural patterns that should be replicated for the MLC-LLM module.

**Date**: October 11, 2025
**Module Path**: `/sdk/runanywhere-kotlin/modules/runanywhere-llm-llamacpp/`

---

## Executive Summary

The LlamaCPP module follows a clean, plugin-based architecture that integrates seamlessly with the core SDK through the ModuleRegistry pattern. It uses KMP expect/actual for platform-specific implementations while keeping business logic in commonMain. The module wraps native llama.cpp libraries via JNI, providing a streaming token generation API.

**Key Pattern**: Auto-registering module → Provider → Service → Native Integration

---

## 1. Module Structure

### Directory Organization

```
modules/runanywhere-llm-llamacpp/
├── build.gradle.kts                    # Build configuration
├── src/
│   ├── commonMain/
│   │   └── kotlin/com/runanywhere/sdk/llm/llamacpp/
│   │       ├── LlamaCppModule.kt       # Auto-registration entry point
│   │       ├── LlamaCppProvider.kt     # LLMServiceProvider implementation
│   │       └── LlamaCppService.kt      # expect declaration
│   └── jvmAndroidMain/
│       └── kotlin/com/runanywhere/sdk/llm/llamacpp/
│           ├── LlamaCppModuleActual.kt # Platform-specific module impl
│           ├── LlamaCppService.kt      # actual service implementation
│           └── LLamaAndroid.kt         # JNI wrapper

native/llama-jni/                       # Native library (separate from module)
├── CMakeLists.txt                      # CMake build configuration
└── src/
    └── llama-android.cpp               # JNI bridge to llama.cpp
```

### Key Characteristics

1. **Shared Source Set Pattern**: Uses `jvmAndroidMain` as a common source set for both JVM and Android platforms
2. **Separation of Concerns**: Native code lives outside the module directory (`native/llama-jni/`)
3. **Expect/Actual Pattern**: Service interface in commonMain, implementation in platform sources
4. **Auto-Registration**: Module automatically registers itself with ModuleRegistry

---

## 2. Provider Pattern Implementation

### 2.1 Module Registration (AutoRegisteringModule)

**File**: `src/commonMain/kotlin/.../LlamaCppModule.kt`

```kotlin
object LlamaCppModule : AutoRegisteringModule {

    private var provider: LlamaCppProvider? = null

    override fun register() {
        if (checkNativeLibraryAvailable()) {
            provider = LlamaCppProvider()
            ModuleRegistry.shared.registerLLM(provider!!)
        }
    }

    val isAvailable: Boolean
        get() = checkNativeLibraryAvailable()

    val name: String = "llama.cpp"
    val version: String = "0.1.0"
    val description: String = "On-device LLM inference using llama.cpp"

    fun cleanup() {
        provider = null
    }
}

// Platform-specific availability check
expect fun checkNativeLibraryAvailable(): Boolean
```

**Key Patterns**:
- Object singleton for module lifecycle management
- Conditional registration based on native library availability
- expect/actual for platform-specific library checking
- Cleanup method for resource management
- Module metadata (name, version, description)

### 2.2 Provider Implementation (LLMServiceProvider)

**File**: `src/commonMain/kotlin/.../LlamaCppProvider.kt`

```kotlin
class LlamaCppProvider : LLMServiceProvider {

    override suspend fun createLLMService(configuration: LLMConfiguration): LLMService {
        return LlamaCppService(configuration)
    }

    override fun canHandle(modelId: String?): Boolean {
        if (modelId == null) return false

        val modelIdLower = modelId.lowercase()
        return modelIdLower.contains("llama") ||
               modelIdLower.endsWith(".gguf") ||
               modelIdLower.endsWith(".ggml") ||
               modelIdLower.contains("mistral") ||
               // ... more model patterns
    }

    override val name: String = "LlamaCpp"
    override val framework: LLMFramework = LLMFramework.LLAMA_CPP

    override val supportedFeatures: Set<String> = setOf(
        "streaming",
        "context-window-8k",
        "context-window-32k",
        "context-window-128k",
        "gpu-acceleration",
        "quantization",
        "grammar-sampling",
        "rope-scaling",
        "flash-attention",
        "continuous-batching"
    )

    override fun validateModelCompatibility(model: ModelInfo): ModelCompatibilityResult {
        val warnings = mutableListOf<String>()

        val isCompatible = when {
            model.format.toString().contains("GGUF", ignoreCase = true) -> true
            model.format.toString().contains("GGML", ignoreCase = true) -> true
            else -> {
                warnings.add("Model format ${model.format} may not be fully supported")
                false
            }
        }

        val memoryRequired = estimateMemoryRequirements(model)
        val availableMemory = getAvailableSystemMemory()

        if (memoryRequired > availableMemory * 0.8) {
            warnings.add("Model may require more memory than available")
        }

        return ModelCompatibilityResult(
            isCompatible = isCompatible,
            details = "Model ${model.name} compatibility check for llama.cpp framework",
            memoryRequired = memoryRequired,
            recommendedConfiguration = getOptimalConfiguration(model),
            warnings = warnings
        )
    }

    override fun estimateMemoryRequirements(model: ModelInfo): Long {
        val modelSize = model.downloadSize ?: 8_000_000_000L
        val contextMemory = (model.contextLength ?: 2048) * 4L * 1024
        return modelSize + contextMemory
    }

    override fun getOptimalConfiguration(model: ModelInfo): HardwareConfiguration {
        val memoryMB = (estimateMemoryRequirements(model) / 1024 / 1024).toInt()

        return HardwareConfiguration(
            preferGPU = true,
            minMemoryMB = memoryMB,
            recommendedThreads = minOf(Runtime.getRuntime().availableProcessors(), 8),
            useMmap = true,
            lockMemory = memoryMB < 4096
        )
    }

    override fun createModelInfo(modelId: String): ModelInfo {
        return ModelInfo(
            id = modelId,
            name = modelId.split("/").lastOrNull() ?: modelId,
            category = ModelCategory.LANGUAGE,
            format = if (modelId.endsWith(".gguf")) {
                ModelFormat.GGUF
            } else {
                ModelFormat.GGML
            },
            // ... rest of ModelInfo fields
        )
    }

    private fun getAvailableSystemMemory(): Long {
        return Runtime.getRuntime().maxMemory()
    }
}
```

**Key Patterns**:
- Smart model detection via file extensions and naming patterns
- Comprehensive feature declaration
- Memory estimation and hardware optimization
- Model compatibility validation with warnings
- Platform-specific memory checks

---

## 3. Component Architecture

### 3.1 Service Interface (expect/actual)

**File**: `src/commonMain/kotlin/.../LlamaCppService.kt`

```kotlin
expect class LlamaCppService(configuration: LLMConfiguration) : EnhancedLLMService {
    override suspend fun initialize(modelPath: String?)
    override suspend fun generate(prompt: String, options: RunAnywhereGenerationOptions): String
    override suspend fun streamGenerate(
        prompt: String,
        options: RunAnywhereGenerationOptions,
        onToken: (String) -> Unit
    )
    override val isReady: Boolean
    override val currentModel: String?
    override suspend fun cleanup()

    // EnhancedLLMService methods
    override suspend fun process(input: LLMInput): LLMOutput
    override fun streamProcess(input: LLMInput): Flow<LLMGenerationChunk>
    override suspend fun loadModel(modelInfo: ModelInfo)
    override fun cancelCurrent()
    override fun getTokenCount(text: String): Int
    override fun fitsInContext(prompt: String, maxTokens: Int): Boolean
}
```

**Key Patterns**:
- expect class with constructor parameters
- Implements both basic LLMService and EnhancedLLMService interfaces
- Full method signature declarations in expect

### 3.2 Service Implementation (actual)

**File**: `src/jvmAndroidMain/kotlin/.../LlamaCppService.kt`

```kotlin
actual class LlamaCppService actual constructor(
    private val configuration: LLMConfiguration
) : EnhancedLLMService {

    private val logger = SDKLogger("LlamaCppService")
    private val llama = LLamaAndroid.instance()
    private var modelPath: String? = null
    private var isInitialized = false

    actual override suspend fun initialize(modelPath: String?) = withContext(Dispatchers.IO) {
        val actualModelPath = modelPath ?: configuration.modelId
            ?: throw IllegalArgumentException("No model path provided")

        if (isInitialized) {
            logger.info("Already initialized, unloading previous model")
            cleanup()
        }

        logger.info("Initializing llama.cpp with model: $actualModelPath")

        try {
            llama.load(actualModelPath)
            this@LlamaCppService.modelPath = actualModelPath
            isInitialized = true
            logger.info("Initialized llama.cpp successfully")
        } catch (e: Exception) {
            logger.error("Failed to initialize llama.cpp", e)
            throw IllegalStateException("Failed to initialize llama.cpp: ${e.message}", e)
        }
    }

    actual override suspend fun generate(
        prompt: String,
        options: RunAnywhereGenerationOptions
    ): String = withContext(Dispatchers.IO) {
        if (!isInitialized) {
            throw IllegalStateException("LlamaCppService not initialized")
        }

        val result = StringBuilder()
        var tokenCount = 0
        val maxTokens = options.maxTokens

        llama.send(prompt, formatChat = false).collect { token ->
            result.append(token)
            tokenCount++
            if (tokenCount >= maxTokens) {
                return@collect
            }
        }

        result.toString()
    }

    actual override suspend fun streamGenerate(
        prompt: String,
        options: RunAnywhereGenerationOptions,
        onToken: (String) -> Unit
    ) = withContext(Dispatchers.IO) {
        if (!isInitialized) {
            throw IllegalStateException("LlamaCppService not initialized")
        }

        var tokenCount = 0
        val maxTokens = options.maxTokens

        llama.send(prompt, formatChat = false).collect { token ->
            onToken(token)
            tokenCount++
            if (tokenCount >= maxTokens) {
                return@collect
            }
        }
    }

    actual override suspend fun process(input: LLMInput): LLMOutput {
        if (!isInitialized) {
            throw IllegalStateException("LlamaCppService not initialized")
        }

        val startTime = currentTimeMillis()

        // Build prompt from messages
        val prompt = buildPrompt(input.messages, input.systemPrompt)

        val options = input.options ?: RunAnywhereGenerationOptions(
            maxTokens = configuration.maxTokens,
            temperature = configuration.temperature.toFloat(),
            streamingEnabled = false
        )

        val response = generate(prompt, options)

        val generationTime = currentTimeMillis() - startTime
        val promptTokens = estimateTokenCount(prompt)
        val completionTokens = estimateTokenCount(response)
        val tokensPerSecond = if (generationTime > 0) {
            (completionTokens.toDouble() * 1000.0) / generationTime
        } else null

        return LLMOutput(
            text = response,
            tokenUsage = TokenUsage(
                promptTokens = promptTokens,
                completionTokens = completionTokens
            ),
            metadata = GenerationMetadata(
                modelId = currentModel ?: "unknown",
                temperature = options.temperature,
                generationTime = generationTime,
                tokensPerSecond = tokensPerSecond
            ),
            finishReason = FinishReason.COMPLETED,
            timestamp = startTime
        )
    }

    actual override fun streamProcess(input: LLMInput): Flow<LLMGenerationChunk> {
        if (!isInitialized) {
            throw IllegalStateException("LlamaCppService not initialized")
        }

        val prompt = buildPrompt(input.messages, input.systemPrompt)
        val options = input.options ?: RunAnywhereGenerationOptions(
            maxTokens = configuration.maxTokens,
            temperature = configuration.temperature.toFloat(),
            streamingEnabled = true
        )

        var chunkIndex = 0
        var tokenCount = 0
        val maxTokens = options.maxTokens

        return llama.send(prompt, formatChat = false).map { token ->
            val currentChunk = chunkIndex++
            val currentTokens = tokenCount++
            val isComplete = currentTokens >= maxTokens

            LLMGenerationChunk(
                text = token,
                isComplete = isComplete,
                chunkIndex = currentChunk,
                timestamp = currentTimeMillis()
            )
        }
    }

    actual override suspend fun cleanup() = withContext(Dispatchers.IO) {
        if (isInitialized) {
            logger.info("Cleaning up llama.cpp context")
            llama.unload()
            isInitialized = false
            modelPath = null
        }
    }

    actual override val isReady: Boolean
        get() = isInitialized

    actual override val currentModel: String?
        get() = modelPath?.split("/")?.lastOrNull()

    // Helper methods
    private fun estimateTokenCount(text: String): Int {
        return text.length / 4  // Rough estimation
    }

    private fun buildPrompt(messages: List<Message>, systemPrompt: String?): String {
        val prompt = StringBuilder()

        // Use Qwen2 chat template format
        val system = systemPrompt ?: """You are a helpful, friendly AI assistant.
Answer questions clearly and concisely."""

        prompt.append("<|im_start|>system\n")
        prompt.append(system)
        prompt.append("<|im_end|>\n")

        for (message in messages) {
            val role = when (message.role) {
                MessageRole.USER -> "user"
                MessageRole.ASSISTANT -> "assistant"
                MessageRole.SYSTEM -> "system"
            }
            prompt.append("<|im_start|>$role\n")
            prompt.append(message.content)
            prompt.append("<|im_end|>\n")
        }

        prompt.append("<|im_start|>assistant\n")
        return prompt.toString()
    }
}
```

**Key Patterns**:
- Singleton native library instance (`LLamaAndroid.instance()`)
- State management (isInitialized, modelPath)
- Coroutine dispatchers for blocking I/O operations (`Dispatchers.IO`)
- Comprehensive logging with SDKLogger
- Error handling with specific exceptions
- Token counting and performance metrics
- Prompt building with chat templates (Qwen2 format)
- Flow-based streaming with mapping to SDK types

---

## 4. Native Integration

### 4.1 JNI Wrapper Class

**File**: `src/jvmAndroidMain/kotlin/.../LLamaAndroid.kt`

```kotlin
class LLamaAndroid {
    private val logger = SDKLogger("LLamaAndroid")

    private val threadLocalState: ThreadLocal<State> = ThreadLocal.withInitial { State.Idle }

    // Dedicated thread for native code execution
    private val runLoop: CoroutineDispatcher = Executors.newSingleThreadExecutor {
        thread(start = false, name = "Llama-RunLoop") {
            logger.info("Dedicated thread for native code: ${Thread.currentThread().name}")

            // Load native library
            try {
                System.loadLibrary("llama-android")
                logger.info("Successfully loaded llama-android native library")
            } catch (e: UnsatisfiedLinkError) {
                logger.error("Failed to load llama-android native library", e)
                throw e
            }

            // Initialize backend
            log_to_android()
            backend_init(false)

            logger.info(system_info())

            it.run()
        }.apply {
            uncaughtExceptionHandler = Thread.UncaughtExceptionHandler { _, exception ->
                logger.error("Unhandled exception in llama thread", exception)
            }
        }
    }.asCoroutineDispatcher()

    private val nlen: Int = 256

    // Native method declarations
    private external fun log_to_android()
    private external fun load_model(filename: String): Long
    private external fun free_model(model: Long)
    private external fun new_context(model: Long): Long
    private external fun free_context(context: Long)
    private external fun backend_init(numa: Boolean)
    private external fun backend_free()
    private external fun new_batch(nTokens: Int, embd: Int, nSeqMax: Int): Long
    private external fun free_batch(batch: Long)
    private external fun new_sampler(): Long
    private external fun free_sampler(sampler: Long)
    private external fun system_info(): String
    private external fun completion_init(
        context: Long,
        batch: Long,
        text: String,
        formatChat: Boolean,
        nLen: Int
    ): Int
    private external fun completion_loop(
        context: Long,
        batch: Long,
        sampler: Long,
        nLen: Int,
        ncur: IntVar
    ): String?
    private external fun kv_cache_clear(context: Long)

    suspend fun load(pathToModel: String) {
        withContext(runLoop) {
            when (threadLocalState.get()) {
                is State.Idle -> {
                    logger.info("Loading model from: $pathToModel")

                    val model = load_model(pathToModel)
                    if (model == 0L) throw IllegalStateException("load_model() failed")

                    val context = new_context(model)
                    if (context == 0L) throw IllegalStateException("new_context() failed")

                    val batch = new_batch(512, 0, 1)
                    if (batch == 0L) throw IllegalStateException("new_batch() failed")

                    val sampler = new_sampler()
                    if (sampler == 0L) throw IllegalStateException("new_sampler() failed")

                    logger.info("Model loaded successfully: $pathToModel")
                    threadLocalState.set(State.Loaded(model, context, batch, sampler))
                }
                else -> throw IllegalStateException("Model already loaded")
            }
        }
    }

    fun send(message: String, formatChat: Boolean = false): Flow<String> = flow {
        when (val state = threadLocalState.get()) {
            is State.Loaded -> {
                val ncur = IntVar(completion_init(state.context, state.batch, message, formatChat, nlen))
                while (ncur.value <= nlen) {
                    val str = completion_loop(state.context, state.batch, state.sampler, nlen, ncur)
                    if (str == null) {
                        break
                    }
                    if (str.isNotEmpty()) {
                        emit(str)
                    }
                }
                kv_cache_clear(state.context)
            }
            else -> {
                logger.error("Cannot generate: model not loaded")
                throw IllegalStateException("Model not loaded")
            }
        }
    }.flowOn(runLoop)

    suspend fun unload() {
        withContext(runLoop) {
            when (val state = threadLocalState.get()) {
                is State.Loaded -> {
                    logger.info("Unloading model")
                    free_context(state.context)
                    free_model(state.model)
                    free_batch(state.batch)
                    free_sampler(state.sampler)

                    threadLocalState.set(State.Idle)
                    logger.info("Model unloaded successfully")
                }
                else -> {
                    logger.debug("No model to unload")
                }
            }
        }
    }

    val isLoaded: Boolean
        get() = threadLocalState.get() is State.Loaded

    companion object {
        class IntVar(initialValue: Int) {
            @Volatile
            var value: Int = initialValue
                private set

            fun inc() {
                synchronized(this) {
                    value += 1
                }
            }

            fun getValue(): Int = value
        }

        private sealed interface State {
            data object Idle : State
            data class Loaded(val model: Long, val context: Long, val batch: Long, val sampler: Long) : State
        }

        private val _instance: LLamaAndroid = LLamaAndroid()

        fun instance(): LLamaAndroid = _instance
    }
}
```

**Key Patterns**:
- Singleton pattern for native library management
- Dedicated thread with custom coroutine dispatcher for native calls
- ThreadLocal state management for model lifecycle
- Sealed interface for type-safe state tracking
- Flow-based streaming API
- Resource lifecycle management (load → use → unload)
- Error handling with null checks and exceptions
- Native library loading in dedicated thread
- Backend initialization on library load
- KV cache clearing after generation

### 4.2 Native C++ Implementation

**File**: `native/llama-jni/src/llama-android.cpp`

Key aspects:
- Standard JNI naming conventions: `Java_<package>_<class>_<method>`
- Android logging integration (`__android_log_print`)
- UTF-8 validation for safe string handling
- Method caching for better performance (`jclass`, `jmethodID`)
- Proper memory management (malloc/free for batches)
- llama.cpp API integration:
  - Model loading: `llama_model_load_from_file()`
  - Context creation: `llama_init_from_model()`
  - Tokenization: `common_tokenize()`
  - Sampling: `llama_sampler_sample()`
  - Decoding: `llama_decode()`
  - Token to string: `common_token_to_piece()`

**JNI Method Categories**:
1. **Lifecycle**: load_model, free_model, new_context, free_context
2. **Backend**: backend_init, backend_free, log_to_android
3. **Inference**: new_batch, free_batch, new_sampler, free_sampler
4. **Generation**: completion_init, completion_loop
5. **Cache**: kv_cache_clear
6. **Info**: system_info

### 4.3 CMake Build Configuration

**File**: `native/llama-jni/CMakeLists.txt`

```cmake
cmake_minimum_required(VERSION 3.22.1)

project("llama-android")

# Path resolution to llama.cpp in EXTERNAL directory
get_filename_component(PROJECT_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../.." ABSOLUTE)
set(LLAMA_CPP_DIR "${PROJECT_ROOT}/EXTERNAL/llama.cpp")

# Verify llama.cpp exists
if(NOT EXISTS "${LLAMA_CPP_DIR}/CMakeLists.txt")
    message(FATAL_ERROR "llama.cpp not found at ${LLAMA_CPP_DIR}")
endif()

# Add llama.cpp as subdirectory
add_subdirectory(${LLAMA_CPP_DIR} build-llama)

# Create JNI wrapper library
add_library(${CMAKE_PROJECT_NAME} SHARED
    src/llama-android.cpp
)

# Link llama.cpp libraries
target_link_libraries(${CMAKE_PROJECT_NAME}
    llama      # Core llama.cpp library
    common     # Common utilities (tokenization, etc.)
    android    # Android system library
    log        # Android logging
)

# Include directories
target_include_directories(${CMAKE_PROJECT_NAME} PRIVATE
    ${LLAMA_CPP_DIR}/include
    ${LLAMA_CPP_DIR}/common
    ${LLAMA_CPP_DIR}/src
    ${LLAMA_CPP_DIR}
)
```

**Key Patterns**:
- External dependency management (llama.cpp in EXTERNAL/)
- Subdirectory inclusion with custom build directory
- Proper linking order (llama, common, android, log)
- Multiple include paths for llama.cpp headers

---

## 5. Build Configuration

### 5.1 Module build.gradle.kts

**File**: `modules/runanywhere-llm-llamacpp/build.gradle.kts`

```kotlin
plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.library)
    `maven-publish`
}

kotlin {
    jvm {
        compilations.all {
            kotlinOptions.jvmTarget = "17"
        }
    }

    androidTarget {
        compilations.all {
            kotlinOptions.jvmTarget = "17"
        }
    }

    sourceSets {
        val commonMain by getting {
            dependencies {
                // Depend on core SDK for interfaces and models
                api(project.parent!!.parent!!)  // References root SDK project
                implementation(libs.kotlinx.coroutines.core)
                implementation(libs.kotlinx.serialization.json)
            }
        }

        val commonTest by getting {
            dependencies {
                implementation(kotlin("test"))
                implementation(libs.kotlinx.coroutines.test)
            }
        }

        val jvmAndroidMain by creating {
            dependsOn(commonMain)
        }

        val jvmMain by getting {
            dependsOn(jvmAndroidMain)
        }

        val androidMain by getting {
            dependsOn(jvmAndroidMain)
        }

        val jvmTest by getting
        val androidUnitTest by getting
    }
}

android {
    namespace = "com.runanywhere.sdk.llm.llamacpp"
    compileSdk = 36

    defaultConfig {
        minSdk = 24

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        ndk {
            // Target ARM 64-bit only (modern Android devices)
            abiFilters += listOf("arm64-v8a")
        }

        externalNativeBuild {
            cmake {
                // llama.cpp build configuration
                arguments += "-DLLAMA_CURL=OFF"
                arguments += "-DLLAMA_BUILD_COMMON=ON"
                arguments += "-DGGML_LLAMAFILE=OFF"
                arguments += "-DCMAKE_BUILD_TYPE=Release"
                arguments += "-DGGML_NEON=ON"  // Enable ARM NEON SIMD

                // Optimization flags for ARM Cortex-A53
                cppFlags += "-O3"
                cppFlags += "-march=armv8-a"
                cppFlags += "-mtune=cortex-a53"
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    externalNativeBuild {
        cmake {
            path = file("../../native/llama-jni/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}
```

**Key Patterns**:
1. **KMP Plugin Configuration**: kotlin.multiplatform + android.library
2. **Source Set Hierarchy**: commonMain → jvmAndroidMain → {jvmMain, androidMain}
3. **Core SDK Dependency**: `api(project.parent!!.parent!!)` - allows transitive dependencies
4. **Native Build Integration**: externalNativeBuild with CMake
5. **Platform-Specific Optimizations**: ARM NEON, Cortex-A53 tuning, -O3
6. **ABI Filtering**: arm64-v8a only (modern devices)
7. **CMake Arguments**: Disable unnecessary features, enable specific backends

### 5.2 Root settings.gradle.kts

**File**: `sdk/runanywhere-kotlin/settings.gradle.kts`

```kotlin
rootProject.name = "RunAnywhereKotlinSDK"

// Include JNI module
include(":jni")

// WhisperKit module - standalone STT module
include(":modules:runanywhere-whisperkit")

// LlamaCpp module - provides LLM capabilities via llama.cpp
include(":modules:runanywhere-llm-llamacpp")
```

**Key Patterns**:
- Simple include statements
- Clear naming convention: `:modules:<module-name>`
- Comments explaining module purpose

---

## 6. API Surface

### 6.1 Public APIs

**Module Entry Point**:
```kotlin
// Auto-registration (happens automatically if module is in classpath)
LlamaCppModule.register()

// Check availability
if (LlamaCppModule.isAvailable) {
    // Module is ready to use
}
```

**Provider Access** (via ModuleRegistry):
```kotlin
// Get LLM provider for a model
val provider = ModuleRegistry.llmProvider("model.gguf")

// Create service
val service = provider?.createLLMService(LLMConfiguration(
    modelId = "/path/to/model.gguf",
    contextLength = 4096,
    temperature = 0.7,
    maxTokens = 256
))

// Initialize and use
service?.initialize()
val response = service?.generate("Hello, world!", options)
```

**Direct Service Usage**:
```kotlin
val config = LLMConfiguration(
    modelId = "/sdcard/models/qwen-1.5b.gguf",
    contextLength = 2048,
    temperature = 0.7,
    maxTokens = 100
)

val service = LlamaCppService(config)
service.initialize()

// Streaming generation
service.streamGenerate(prompt, options) { token ->
    print(token)
}

// Structured I/O
val input = LLMInput(
    messages = listOf(
        Message(MessageRole.USER, "What is 2+2?")
    ),
    systemPrompt = "You are a helpful assistant."
)

val output = service.process(input)
println(output.text)
println("Tokens: ${output.tokenUsage.completionTokens}")
println("Speed: ${output.metadata.tokensPerSecond} tok/s")

// Streaming with structured types
service.streamProcess(input).collect { chunk ->
    print(chunk.text)
}

// Cleanup
service.cleanup()
```

### 6.2 Configuration Options

**LLMConfiguration** (from core SDK):
```kotlin
LLMConfiguration(
    // Model
    modelId: String? = null,

    // Context
    contextLength: Int = 2048,

    // Generation
    temperature: Double = 0.7,
    maxTokens: Int = 100,
    systemPrompt: String? = null,
    streamingEnabled: Boolean = true,

    // Hardware
    useGPUIfAvailable: Boolean = true,
    cpuThreads: Int? = null,
    gpuLayers: Int? = null,
    memoryMapping: Boolean = true,
    memoryLock: Boolean = false,

    // Optimization
    quantizationLevel: QuantizationLevel? = null,
    flashAttention: Boolean = true,
    kvCacheOptimization: Boolean = true,

    // Monitoring
    verboseLogging: Boolean = false,
    performanceMonitoring: Boolean = true
)
```

**Preset Configurations**:
```kotlin
LLMConfiguration.MOBILE     // Optimized for mobile
LLMConfiguration.DESKTOP    // Optimized for desktop
LLMConfiguration.SPEED      // Optimized for speed
LLMConfiguration.QUALITY    // Optimized for quality
LLMConfiguration.LOW_MEMORY // For low-memory systems
```

### 6.3 Model Management APIs

```kotlin
// Provider capabilities
provider.canHandle("qwen-1.5b.gguf")  // true
provider.supportedFeatures            // Set<String>
provider.framework                    // LLMFramework.LLAMA_CPP

// Model validation
val compatibility = provider.validateModelCompatibility(modelInfo)
if (compatibility.isCompatible) {
    println("Memory required: ${compatibility.memoryRequired / 1024 / 1024}MB")
    println("Warnings: ${compatibility.warnings}")
}

// Memory estimation
val memRequired = provider.estimateMemoryRequirements(modelInfo)

// Hardware optimization
val hwConfig = provider.getOptimalConfiguration(modelInfo)
println("Threads: ${hwConfig.recommendedThreads}")
println("GPU: ${hwConfig.preferGPU}")
```

---

## 7. Integration with Core SDK

### 7.1 Dependencies

```kotlin
// Module depends on core SDK
api(project.parent!!.parent!!)  // Root SDK project

// Core SDK provides:
// - LLMService interface
// - EnhancedLLMService interface
// - LLMServiceProvider interface
// - LLMConfiguration
// - ModelInfo, LLMInput, LLMOutput
// - SDKLogger, EventBus, ModuleRegistry
```

### 7.2 Registration Flow

```
App Startup
    ↓
LlamaCppModule.register()  // Auto-called if using AutoRegisteringModule
    ↓
checkNativeLibraryAvailable()  // Platform-specific check
    ↓
LlamaCppProvider instantiated
    ↓
ModuleRegistry.shared.registerLLM(provider)
    ↓
Provider available via ModuleRegistry.llmProvider()
```

### 7.3 Service Lifecycle

```
Configuration Creation
    ↓
Provider.createLLMService(config) → LlamaCppService
    ↓
service.initialize(modelPath)
    ↓
    - Load native library (if not loaded)
    - Load model file
    - Create context, batch, sampler
    - Set isInitialized = true
    ↓
service.generate() / service.streamGenerate()
    ↓
    - Build prompt with chat template
    - Call LLamaAndroid.send()
    - Flow-based token streaming
    ↓
service.cleanup()
    ↓
    - Free native resources
    - Clear state
```

---

## 8. Key Design Patterns to Replicate

### 8.1 Module Structure Pattern

```
modules/runanywhere-llm-<framework>/
├── build.gradle.kts
└── src/
    ├── commonMain/kotlin/.../
    │   ├── <Framework>Module.kt        # AutoRegisteringModule
    │   ├── <Framework>Provider.kt      # LLMServiceProvider
    │   └── <Framework>Service.kt       # expect class
    └── jvmAndroidMain/kotlin/.../      # or androidMain if JVM not needed
        ├── <Framework>ModuleActual.kt  # actual implementation
        ├── <Framework>Service.kt       # actual class
        └── <Framework>Wrapper.kt       # Native wrapper (if needed)
```

### 8.2 Provider Pattern Template

```kotlin
// 1. Module object with auto-registration
object <Framework>Module : AutoRegisteringModule {
    private var provider: <Framework>Provider? = null

    override fun register() {
        if (checkNativeLibraryAvailable()) {
            provider = <Framework>Provider()
            ModuleRegistry.shared.registerLLM(provider!!)
        }
    }

    val isAvailable: Boolean
        get() = checkNativeLibraryAvailable()

    val name: String = "<framework-name>"
    val version: String = "0.1.0"
}

expect fun checkNativeLibraryAvailable(): Boolean

// 2. Provider implementation
class <Framework>Provider : LLMServiceProvider {
    override suspend fun createLLMService(configuration: LLMConfiguration): LLMService {
        return <Framework>Service(configuration)
    }

    override fun canHandle(modelId: String?): Boolean {
        // Framework-specific model detection
    }

    override val name: String = "<Framework>"
    override val framework: LLMFramework = LLMFramework.<FRAMEWORK>
    override val supportedFeatures: Set<String> = setOf(/* features */)

    // Implement other LLMServiceProvider methods
}

// 3. Service expect/actual
expect class <Framework>Service(configuration: LLMConfiguration) : EnhancedLLMService

actual class <Framework>Service actual constructor(
    private val configuration: LLMConfiguration
) : EnhancedLLMService {
    // Implementation
}
```

### 8.3 Streaming Pattern

```kotlin
// Native wrapper provides Flow<String>
fun nativeGenerate(prompt: String): Flow<String> = flow {
    // Native call that yields tokens
    while (hasMoreTokens()) {
        val token = getNextToken()
        emit(token)
    }
}.flowOn(Dispatchers.IO)  // Run on IO dispatcher

// Service wraps into SDK types
override fun streamProcess(input: LLMInput): Flow<LLMGenerationChunk> {
    return nativeGenerate(prompt).map { token ->
        LLMGenerationChunk(
            text = token,
            isComplete = isLastToken,
            chunkIndex = index++,
            timestamp = currentTimeMillis()
        )
    }
}
```

### 8.4 State Management Pattern

```kotlin
// Use sealed interface for type-safe states
private sealed interface State {
    data object Idle : State
    data class Loaded(val nativeHandle: Long) : State
    data class Generating(val nativeHandle: Long) : State
}

private var currentState: State = State.Idle

// State transitions with validation
suspend fun load(path: String) {
    when (currentState) {
        is State.Idle -> {
            val handle = nativeLoad(path)
            currentState = State.Loaded(handle)
        }
        else -> throw IllegalStateException("Already loaded")
    }
}
```

### 8.5 Error Handling Pattern

```kotlin
// Wrap native calls with try-catch
try {
    val result = nativeOperation()
    if (result == null || result == 0L) {
        throw IllegalStateException("Operation failed")
    }
    // Success
} catch (e: Exception) {
    logger.error("Operation failed", e)
    throw IllegalStateException("Friendly message: ${e.message}", e)
}
```

### 8.6 Resource Management Pattern

```kotlin
// Lifecycle management
suspend fun initialize() {
    if (isInitialized) {
        cleanup()  // Clean up previous instance
    }

    // Load resources
    nativeLoad()
    isInitialized = true
}

suspend fun cleanup() {
    if (isInitialized) {
        // Free in reverse order of allocation
        nativeFreeResource3()
        nativeFreeResource2()
        nativeFreeResource1()

        isInitialized = false
    }
}
```

---

## 9. MLC-LLM Specific Considerations

### 9.1 Differences from LlamaCPP

Based on the LlamaCPP analysis, here's what might differ for MLC-LLM:

1. **Native Library**: MLC uses different native libs (likely `libmlc_llm.so` or similar)
2. **Model Format**: MLC uses compiled models (not GGUF), detection logic will differ
3. **Initialization**: MLC might need different context parameters
4. **Streaming API**: MLC's streaming interface might differ from llama.cpp's token-by-token flow
5. **GPU Acceleration**: MLC has strong GPU support, might need more configuration options

### 9.2 Expected Module Structure

```
modules/runanywhere-llm-mlc/
├── build.gradle.kts
└── src/
    ├── commonMain/kotlin/com/runanywhere/sdk/llm/mlc/
    │   ├── MLCModule.kt
    │   ├── MLCProvider.kt
    │   └── MLCService.kt
    └── androidMain/kotlin/com/runanywhere/sdk/llm/mlc/
        ├── MLCModuleActual.kt
        ├── MLCService.kt
        └── MLCAndroid.kt  # Wrapper for MLC native APIs

native/mlc-jni/  # If using JNI
├── CMakeLists.txt
└── src/
    └── mlc-android.cpp
```

### 9.3 Provider Implementation Strategy

```kotlin
class MLCProvider : LLMServiceProvider {
    override fun canHandle(modelId: String?): Boolean {
        if (modelId == null) return false

        val modelIdLower = modelId.lowercase()
        // MLC-specific patterns
        return modelIdLower.endsWith(".mlc") ||
               modelIdLower.contains("mlc-compiled") ||
               modelIdLower.contains("mlc-chat") ||
               // Add MLC model patterns
    }

    override val framework: LLMFramework = LLMFramework.MLC_LLM

    override val supportedFeatures: Set<String> = setOf(
        "streaming",
        "gpu-acceleration",
        "quantization",
        "context-window-8k",
        // MLC-specific features
    )
}
```

### 9.4 Integration Points

1. **Module Registration**: Same pattern as LlamaCPP
2. **Provider Interface**: Implement same LLMServiceProvider interface
3. **Configuration**: Use LLMConfiguration with MLC-specific options in frameworkOptions
4. **Service Interface**: Implement EnhancedLLMService
5. **Streaming**: Use Flow<String> or Flow<LLMGenerationChunk>
6. **Native Integration**: JNI or direct library binding (depending on MLC's API)

### 9.5 MLC Native Wrapper (Expected)

```kotlin
class MLCAndroid {
    private external fun mlcInitialize(): Long
    private external fun mlcLoadModel(engineHandle: Long, modelPath: String): Long
    private external fun mlcGenerate(
        modelHandle: Long,
        prompt: String,
        maxTokens: Int,
        temperature: Float
    ): String
    private external fun mlcGenerateStream(
        modelHandle: Long,
        prompt: String,
        maxTokens: Int,
        temperature: Float,
        callback: (String) -> Unit
    )
    private external fun mlcFreeModel(modelHandle: Long)
    private external fun mlcShutdown(engineHandle: Long)

    // Kotlin wrapper
    fun generate(prompt: String, options: GenerationOptions): Flow<String> = flow {
        // Call native streaming with callback
        mlcGenerateStream(handle, prompt, options.maxTokens, options.temperature) { token ->
            // This callback might need special handling
            emit(token)
        }
    }.flowOn(Dispatchers.IO)

    companion object {
        init {
            System.loadLibrary("mlc_llm_android")  // or whatever MLC uses
        }
    }
}
```

---

## 10. Build Configuration for MLC

### 10.1 Expected build.gradle.kts

```kotlin
plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.library)
    `maven-publish`
}

kotlin {
    androidTarget {
        compilations.all {
            kotlinOptions.jvmTarget = "17"
        }
    }

    // MLC might not need JVM target if it's Android-only
    // jvm { ... }

    sourceSets {
        val commonMain by getting {
            dependencies {
                api(project.parent!!.parent!!)  // Core SDK
                implementation(libs.kotlinx.coroutines.core)
                implementation(libs.kotlinx.serialization.json)
            }
        }

        val androidMain by getting {
            // MLC might have specific dependencies
            dependencies {
                // implementation("ai.mlc:mlc-llm-android:x.x.x")  // If available
            }
        }
    }
}

android {
    namespace = "com.runanywhere.sdk.llm.mlc"
    compileSdk = 36

    defaultConfig {
        minSdk = 24

        ndk {
            // MLC might support more ABIs
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }

        externalNativeBuild {
            cmake {
                // MLC-specific build flags
                arguments += "-DMLC_USE_CUDA=OFF"  # Example
                arguments += "-DCMAKE_BUILD_TYPE=Release"

                cppFlags += "-O3"
                cppFlags += "-std=c++17"
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("../../native/mlc-jni/CMakeLists.txt")
            version = "3.22.1"
        }
    }
}
```

### 10.2 CMakeLists.txt (If using JNI)

```cmake
cmake_minimum_required(VERSION 3.22.1)

project("mlc-android")

# Path to MLC-LLM (if building from source)
set(MLC_LLM_DIR "${PROJECT_ROOT}/EXTERNAL/mlc-llm")

# Or use prebuilt libraries
# find_library(MLC_LIB mlc_llm PATHS ${MLC_LLM_DIR}/lib)

add_library(${CMAKE_PROJECT_NAME} SHARED
    src/mlc-android.cpp
)

target_link_libraries(${CMAKE_PROJECT_NAME}
    mlc_llm  # MLC library
    android
    log
)

target_include_directories(${CMAKE_PROJECT_NAME} PRIVATE
    ${MLC_LLM_DIR}/include
)
```

---

## 11. Testing Strategy

### 11.1 Unit Tests

```kotlin
class MLCServiceTest {
    @Test
    fun `should initialize successfully`() = runTest {
        val config = LLMConfiguration(modelId = "/path/to/model")
        val service = MLCService(config)

        service.initialize()

        assertTrue(service.isReady)
    }

    @Test
    fun `should generate text`() = runTest {
        val service = createInitializedService()

        val result = service.generate("Hello", options)

        assertNotNull(result)
        assertTrue(result.isNotEmpty())
    }

    @Test
    fun `should stream tokens`() = runTest {
        val service = createInitializedService()
        val tokens = mutableListOf<String>()

        service.streamGenerate("Hello", options) { token ->
            tokens.add(token)
        }

        assertTrue(tokens.isNotEmpty())
    }
}
```

### 11.2 Integration Tests

```kotlin
class MLCIntegrationTest {
    @Test
    fun `should register with ModuleRegistry`() {
        MLCModule.register()

        assertTrue(ModuleRegistry.hasLLM)
        val provider = ModuleRegistry.llmProvider("test.mlc")
        assertNotNull(provider)
        assertEquals("MLC", provider.name)
    }
}
```

---

## 12. Documentation Requirements

### 12.1 README.md Template

```markdown
# MLC-LLM Module

On-device LLM inference using MLC-LLM framework.

## Features

- [Feature list]

## Installation

```kotlin
// In your build.gradle.kts
dependencies {
    implementation("com.runanywhere.sdk:runanywhere-llm-mlc:0.1.0")
}
```

## Usage

```kotlin
// Auto-registration
MLCModule.register()

// Configuration
val config = LLMConfiguration(
    modelId = "/path/to/model",
    contextLength = 4096,
    temperature = 0.7
)

// Create service
val service = MLCService(config)
service.initialize()

// Generate
val response = service.generate("Hello!", options)

// Stream
service.streamGenerate("Hello!", options) { token ->
    print(token)
}

// Cleanup
service.cleanup()
```

## Model Support

- Supported formats: [list formats]
- Supported architectures: [list architectures]

## Requirements

- Android API 24+
- Min 4GB RAM
- [Other requirements]

## Performance

[Performance benchmarks]
```

---

## 13. Checklist for MLC-LLM Implementation

### Architecture
- [ ] Create module directory structure
- [ ] Set up commonMain source set
- [ ] Set up androidMain source set
- [ ] Configure build.gradle.kts

### Module Registration
- [ ] Implement MLCModule object
- [ ] Implement AutoRegisteringModule interface
- [ ] Add checkNativeLibraryAvailable() expect/actual
- [ ] Add module metadata (name, version, description)

### Provider Implementation
- [ ] Create MLCProvider class
- [ ] Implement LLMServiceProvider interface
- [ ] Implement canHandle() with MLC model detection
- [ ] Define supportedFeatures set
- [ ] Implement validateModelCompatibility()
- [ ] Implement estimateMemoryRequirements()
- [ ] Implement getOptimalConfiguration()
- [ ] Implement createModelInfo()

### Service Implementation
- [ ] Create MLCService expect class in commonMain
- [ ] Create MLCService actual class in androidMain
- [ ] Implement initialize() method
- [ ] Implement generate() method
- [ ] Implement streamGenerate() method
- [ ] Implement process() method (EnhancedLLMService)
- [ ] Implement streamProcess() method
- [ ] Implement cleanup() method
- [ ] Implement isReady property
- [ ] Implement currentModel property
- [ ] Add state management
- [ ] Add error handling
- [ ] Add logging

### Native Integration (if needed)
- [ ] Create native wrapper class (MLCAndroid)
- [ ] Set up native library loading
- [ ] Create dedicated coroutine dispatcher
- [ ] Implement native method declarations
- [ ] Create JNI bridge (if using JNI)
- [ ] Set up CMakeLists.txt
- [ ] Configure NDK build
- [ ] Test native library loading

### Streaming & Flow
- [ ] Implement Flow<String> streaming from native
- [ ] Map to Flow<LLMGenerationChunk>
- [ ] Add token counting
- [ ] Add performance metrics
- [ ] Handle cancellation
- [ ] Test streaming behavior

### Configuration
- [ ] Support LLMConfiguration parameters
- [ ] Add MLC-specific frameworkOptions
- [ ] Validate configuration
- [ ] Add configuration presets (mobile, desktop, etc.)

### Testing
- [ ] Unit tests for provider
- [ ] Unit tests for service
- [ ] Integration tests with ModuleRegistry
- [ ] Native integration tests
- [ ] Streaming tests
- [ ] Error handling tests

### Documentation
- [ ] Module README.md
- [ ] Code documentation (KDoc)
- [ ] Usage examples
- [ ] Model compatibility guide
- [ ] Performance benchmarks

### Integration
- [ ] Add to settings.gradle.kts
- [ ] Test with example app
- [ ] Verify auto-registration
- [ ] Test with different models
- [ ] Performance profiling

---

## 14. Summary

The LlamaCPP module demonstrates a clean, extensible architecture that:

1. **Separates concerns** through layers (Module → Provider → Service → Native)
2. **Uses KMP effectively** with expect/actual for platform specifics
3. **Integrates seamlessly** via ModuleRegistry auto-registration
4. **Provides rich APIs** with both basic and enhanced service interfaces
5. **Handles resources properly** with clear lifecycle management
6. **Streams efficiently** using Kotlin Flow
7. **Optimizes for platforms** with hardware-specific configurations
8. **Documents capabilities** through provider metadata and features

The MLC-LLM module should follow these same patterns while adapting to MLC's specific requirements around model formats, initialization, and native APIs.

---

## Appendices

### A. Related Files Reference

**Core SDK Interfaces**:
- `/src/commonMain/kotlin/com/runanywhere/sdk/components/llm/LLMService.kt`
- `/src/commonMain/kotlin/com/runanywhere/sdk/components/llm/LLMConfiguration.kt`
- `/src/commonMain/kotlin/com/runanywhere/sdk/core/ModuleRegistry.kt`

**Model Types**:
- `/src/commonMain/kotlin/com/runanywhere/sdk/models/ModelInfo.kt`
- `/src/commonMain/kotlin/com/runanywhere/sdk/models/LLMInput.kt`
- `/src/commonMain/kotlin/com/runanywhere/sdk/models/LLMOutput.kt`

**Native Integration**:
- `/native/llama-jni/CMakeLists.txt`
- `/native/llama-jni/src/llama-android.cpp`

### B. Key Dependencies

```kotlin
// Core
kotlinx-coroutines-core
kotlinx-serialization-json

// Native (llama.cpp)
llama.cpp (via git submodule in EXTERNAL/)

// Platform
Android SDK 24+
NDK with CMake 3.22.1+
```

### C. Useful Commands

```bash
# Build module
./gradlew :modules:runanywhere-llm-llamacpp:build

# Publish to Maven Local
./gradlew :modules:runanywhere-llm-llamacpp:publishToMavenLocal

# Run tests
./gradlew :modules:runanywhere-llm-llamacpp:test

# Build native libraries
./gradlew :modules:runanywhere-llm-llamacpp:externalNativeBuildRelease
```

---

**End of Analysis**
