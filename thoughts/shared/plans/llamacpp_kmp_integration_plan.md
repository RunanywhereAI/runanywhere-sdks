# llama.cpp KMP Integration Plan

## Executive Summary

This document outlines the comprehensive integration of llama.cpp into the RunAnywhere Kotlin Multiplatform (KMP) SDK following the established modular architecture patterns. The integration will provide on-device LLM capabilities for both JVM and Android platforms through a dedicated `runanywhere-llm-llamacpp` module, leveraging existing provider patterns and native library management approaches.

## 1. Architecture Overview

### 1.1 Module Structure

Following the established modular architecture from MODULAR-ARCHITECTURE.md, we will create a new module:

```
modules/runanywhere-llm-llamacpp/
├── src/
│   ├── commonMain/kotlin/
│   │   └── com/runanywhere/sdk/llm/llamacpp/
│   │       ├── LlamaCppProvider.kt          # Service provider implementation
│   │       ├── LlamaCppConfiguration.kt     # Configuration classes
│   │       ├── LlamaCppModels.kt           # Model management
│   │       └── LlamaCppModule.kt           # Auto-registration module
│   ├── jvmAndroidMain/kotlin/
│   │   └── com/runanywhere/sdk/llm/llamacpp/
│   │       ├── LlamaCppService.kt          # Core service implementation
│   │       ├── LlamaCppNative.kt           # JNI interface declarations
│   │       ├── NativeLibraryLoader.kt      # Platform-aware native lib loading
│   │       ├── ModelManager.kt             # Model lifecycle management
│   │       └── MemoryManager.kt            # Memory tracking and cleanup
│   ├── jvmMain/kotlin/
│   │   └── com/runanywhere/sdk/llm/llamacpp/
│   │       └── JvmLlamaCppService.kt       # JVM-specific optimizations
│   └── androidMain/kotlin/
│       └── com/runanywhere/sdk/llm/llamacpp/
│           └── AndroidLlamaCppService.kt   # Android-specific optimizations
├── native/
│   ├── cpp/                                # JNI bridge implementation
│   │   ├── llamacpp_jni.cpp               # Main JNI implementation
│   │   ├── llamacpp_jni.h                 # JNI header declarations
│   │   └── memory_manager.cpp             # Native memory management
│   └── libs/                              # Pre-built native libraries
│       ├── jvm/
│       │   ├── linux-x64/libllama-jni.so
│       │   ├── macos-x64/libllama-jni.dylib
│       │   ├── macos-arm64/libllama-jni.dylib
│       │   └── windows-x64/libllama-jni.dll
│       └── android/
│           ├── arm64-v8a/libllama-jni.so
│           └── x86_64/libllama-jni.so
├── CMakeLists.txt                         # CMake build configuration
└── build.gradle.kts                      # Module build configuration
```

### 1.2 Integration Points

The module integrates with existing SDK infrastructure:

```kotlin
// Existing ModuleRegistry will automatically discover and register
object LlamaCppModule : AutoRegisteringModule {
    override fun register() {
        ModuleRegistry.shared.registerLLM(LlamaCppProvider())
    }

    override val isAvailable: Boolean
        get() = NativeLibraryLoader.isLlamaCppAvailable
}

// Integration with existing LLMServiceProvider interface
class LlamaCppProvider : LLMServiceProvider {
    override suspend fun generate(prompt: String, options: GenerationOptions): String
    override fun generateStream(prompt: String, options: GenerationOptions): Flow<String>
    override fun canHandle(modelId: String): Boolean
    override val name: String = "llama.cpp"
}
```

## 2. Native Library Integration

### 2.1 llama.cpp Compilation Strategy

Building on the existing whisper-jni approach, we'll create a similar compilation pipeline:

```cmake
# CMakeLists.txt
cmake_minimum_required(VERSION 3.18)
project(llama-jni C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Platform-specific optimizations
option(LLAMA_AVX        "Enable AVX"        ON)
option(LLAMA_AVX2       "Enable AVX2"       ON)
option(LLAMA_FMA        "Enable FMA"        ON)
option(LLAMA_F16C       "Enable F16C"       ON)
option(LLAMA_METAL      "Enable Metal"      ON)
option(LLAMA_CUBLAS     "Enable cuBLAS"     OFF)

find_package(JNI REQUIRED)

# Include llama.cpp as external project
set(LLAMA_CPP_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../EXTERNAL/llama.cpp")

add_subdirectory(${LLAMA_CPP_DIR} ${CMAKE_CURRENT_BINARY_DIR}/llama.cpp)

# Create JNI bridge library
add_library(llama-jni SHARED
    cpp/llamacpp_jni.cpp
    cpp/memory_manager.cpp
)

target_link_libraries(llama-jni
    llama
    ggml
    ${JNI_LIBRARIES}
)

target_include_directories(llama-jni PRIVATE
    ${JNI_INCLUDE_DIRS}
    ${LLAMA_CPP_DIR}/include
    ${LLAMA_CPP_DIR}/ggml/include
)

# Platform-specific configurations
if(APPLE)
    set_target_properties(llama-jni PROPERTIES
        INSTALL_RPATH "@loader_path"
        BUILD_WITH_INSTALL_RPATH TRUE
    )
elseif(UNIX AND NOT APPLE)
    set_target_properties(llama-jni PROPERTIES
        INSTALL_RPATH "$ORIGIN"
        BUILD_WITH_INSTALL_RPATH TRUE
    )
endif()
```

### 2.2 Native Library Loading

Extending the existing PlatformUtils pattern for native library management:

```kotlin
object NativeLibraryLoader {
    private var llamaCppLoaded = false
    private val logger = SDKLogger("NativeLibraryLoader")

    val isLlamaCppAvailable: Boolean
        get() = try {
            loadLlamaCppLibrary()
            true
        } catch (e: Exception) {
            logger.warn("llama.cpp native library not available: ${e.message}")
            false
        }

    fun loadLlamaCppLibrary() {
        if (llamaCppLoaded) return

        try {
            when (PlatformUtils.getPlatformName()) {
                "jvm" -> loadJvmLibrary()
                "android" -> loadAndroidLibrary()
                else -> throw UnsupportedOperationException("Platform not supported")
            }
            llamaCppLoaded = true
            logger.info("llama.cpp native library loaded successfully")
        } catch (e: Exception) {
            throw SDKError.nativeLibraryError("Failed to load llama.cpp native library", e)
        }
    }

    private fun loadJvmLibrary() {
        val platformInfo = detectJvmPlatform()
        val libraryName = "libllama-jni-${platformInfo.os}-${platformInfo.arch}.${platformInfo.ext}"
        extractAndLoadLibrary(libraryName)
    }

    private fun loadAndroidLibrary() {
        System.loadLibrary("llama-jni")
    }

    private fun detectJvmPlatform(): PlatformInfo {
        val os = System.getProperty("os.name").lowercase()
        val arch = System.getProperty("os.arch").lowercase()

        return when {
            os.contains("linux") -> PlatformInfo("linux", normalizeArch(arch), "so")
            os.contains("mac") -> PlatformInfo("macos", normalizeArch(arch), "dylib")
            os.contains("windows") -> PlatformInfo("windows", normalizeArch(arch), "dll")
            else -> throw UnsupportedOperationException("Unsupported OS: $os")
        }
    }

    private fun normalizeArch(arch: String): String = when {
        arch.contains("amd64") || arch.contains("x86_64") -> "x64"
        arch.contains("aarch64") || arch.contains("arm64") -> "arm64"
        else -> throw UnsupportedOperationException("Unsupported architecture: $arch")
    }

    private data class PlatformInfo(val os: String, val arch: String, val ext: String)
}
```

## 3. JNI Bridge Design

### 3.1 JNI Interface Declaration

```kotlin
// LlamaCppNative.kt - Kotlin JNI interface
internal object LlamaCppNative {
    // Model lifecycle
    external fun createContext(modelPath: String, params: LongArray): Long
    external fun destroyContext(contextPtr: Long)

    // Text generation
    external fun tokenize(contextPtr: Long, text: String): IntArray
    external fun generate(contextPtr: Long, tokens: IntArray, maxTokens: Int): IntArray
    external fun generateStream(contextPtr: Long, tokens: IntArray, maxTokens: Int, callback: GenerationCallback): Int
    external fun detokenize(contextPtr: Long, tokens: IntArray): String

    // Model information
    external fun getModelInfo(contextPtr: Long): ModelInfo
    external fun getContextSize(contextPtr: Long): Int

    // Memory management
    external fun getMemoryUsage(contextPtr: Long): MemoryStats
    external fun clearKVCache(contextPtr: Long)

    // Generation control
    external fun stopGeneration(contextPtr: Long)
    external fun isGenerating(contextPtr: Long): Boolean

    // Callback interface for streaming
    interface GenerationCallback {
        fun onToken(token: String): Boolean // return false to stop generation
        fun onComplete()
        fun onError(message: String)
    }
}

data class ModelInfo(
    val vocabularySize: Int,
    val contextSize: Int,
    val embeddingSize: Int,
    val layerCount: Int
)

data class MemoryStats(
    val totalBytes: Long,
    val usedBytes: Long,
    val kvCacheBytes: Long
)
```

### 3.2 JNI Implementation (C++)

```cpp
// llamacpp_jni.cpp
#include <jni.h>
#include <string>
#include <memory>
#include <unordered_map>
#include <mutex>
#include "llama.h"
#include "llamacpp_jni.h"

class LlamaContext {
public:
    llama_model* model;
    llama_context* ctx;
    std::vector<llama_token> tokens;
    std::mutex generation_mutex;
    bool is_generating;

    LlamaContext(llama_model* m, llama_context* c)
        : model(m), ctx(c), is_generating(false) {}

    ~LlamaContext() {
        if (ctx) llama_free(ctx);
        if (model) llama_free_model(model);
    }
};

// Context management
static std::unordered_map<jlong, std::unique_ptr<LlamaContext>> contexts;
static std::mutex contexts_mutex;
static jlong next_context_id = 1;

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LlamaCppNative_createContext(
    JNIEnv* env, jobject, jstring modelPath, jlongArray params) {

    const char* path = env->GetStringUTFChars(modelPath, nullptr);
    jlong* paramsArray = env->GetLongArrayElements(params, nullptr);

    // Initialize llama.cpp
    llama_model_params model_params = llama_model_default_params();
    llama_context_params ctx_params = llama_context_default_params();

    // Configure parameters from Java array
    ctx_params.n_ctx = static_cast<uint32_t>(paramsArray[0]);
    ctx_params.n_batch = static_cast<uint32_t>(paramsArray[1]);
    ctx_params.n_threads = static_cast<uint32_t>(paramsArray[2]);

    // Load model
    llama_model* model = llama_load_model_from_file(path, model_params);
    if (!model) {
        env->ReleaseStringUTFChars(modelPath, path);
        env->ReleaseLongArrayElements(params, paramsArray, JNI_ABORT);
        return 0;
    }

    // Create context
    llama_context* ctx = llama_new_context_with_model(model, ctx_params);
    if (!ctx) {
        llama_free_model(model);
        env->ReleaseStringUTFChars(modelPath, path);
        env->ReleaseLongArrayElements(params, paramsArray, JNI_ABORT);
        return 0;
    }

    // Store context
    std::lock_guard<std::mutex> lock(contexts_mutex);
    jlong context_id = next_context_id++;
    contexts[context_id] = std::make_unique<LlamaContext>(model, ctx);

    env->ReleaseStringUTFChars(modelPath, path);
    env->ReleaseLongArrayElements(params, paramsArray, JNI_ABORT);

    return context_id;
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LlamaCppNative_destroyContext(
    JNIEnv* env, jobject, jlong contextPtr) {

    std::lock_guard<std::mutex> lock(contexts_mutex);
    auto it = contexts.find(contextPtr);
    if (it != contexts.end()) {
        contexts.erase(it);
    }
}

JNIEXPORT jintArray JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LlamaCppNative_generate(
    JNIEnv* env, jobject, jlong contextPtr, jintArray inputTokens, jint maxTokens) {

    std::lock_guard<std::mutex> lock(contexts_mutex);
    auto it = contexts.find(contextPtr);
    if (it == contexts.end()) {
        return nullptr;
    }

    LlamaContext* llamaCtx = it->second.get();
    std::lock_guard<std::mutex> gen_lock(llamaCtx->generation_mutex);

    if (llamaCtx->is_generating) {
        return nullptr; // Already generating
    }

    llamaCtx->is_generating = true;

    // Convert input tokens
    jint* tokens = env->GetIntArrayElements(inputTokens, nullptr);
    jsize tokenCount = env->GetArrayLength(inputTokens);

    std::vector<llama_token> input_tokens(tokens, tokens + tokenCount);
    std::vector<llama_token> output_tokens;

    // Perform generation
    // ... llama.cpp generation logic here ...

    // Convert output tokens to Java array
    jintArray result = env->NewIntArray(output_tokens.size());
    if (result) {
        env->SetIntArrayRegion(result, 0, output_tokens.size(),
                              reinterpret_cast<const jint*>(output_tokens.data()));
    }

    env->ReleaseIntArrayElements(inputTokens, tokens, JNI_ABORT);
    llamaCtx->is_generating = false;

    return result;
}

// ... Additional JNI method implementations ...

}
```

## 4. Service Implementation

### 4.1 Core LlamaCpp Service

```kotlin
// LlamaCppService.kt
class LlamaCppService internal constructor(
    private val configuration: LlamaCppConfiguration,
    private val memoryManager: MemoryManager = MemoryManager()
) {
    private val logger = SDKLogger("LlamaCppService")
    private var contextPtr: Long = 0
    private var modelInfo: ModelInfo? = null

    suspend fun initialize() = withContext(Dispatchers.IO) {
        if (contextPtr != 0L) {
            logger.warn("Service already initialized")
            return@withContext
        }

        try {
            // Load native library
            NativeLibraryLoader.loadLlamaCppLibrary()

            // Prepare context parameters
            val params = longArrayOf(
                configuration.contextSize.toLong(),
                configuration.batchSize.toLong(),
                configuration.threads.toLong(),
                if (configuration.useGpu) 1L else 0L
            )

            // Create native context
            contextPtr = LlamaCppNative.createContext(configuration.modelPath, params)
            if (contextPtr == 0L) {
                throw SDKError.modelLoadingFailed("Failed to create llama.cpp context")
            }

            // Get model information
            modelInfo = LlamaCppNative.getModelInfo(contextPtr)

            // Register memory usage
            memoryManager.registerModel(contextPtr, configuration.modelPath)

            logger.info("llama.cpp service initialized successfully")

        } catch (e: Exception) {
            logger.error("Failed to initialize llama.cpp service: ${e.message}")
            cleanup()
            throw e
        }
    }

    suspend fun generate(prompt: String, options: GenerationOptions): String =
        withContext(Dispatchers.Default) {
            ensureInitialized()

            try {
                // Tokenize input
                val inputTokens = LlamaCppNative.tokenize(contextPtr, prompt)

                // Generate tokens
                val outputTokens = LlamaCppNative.generate(
                    contextPtr,
                    inputTokens,
                    options.maxTokens
                )

                // Detokenize output
                LlamaCppNative.detokenize(contextPtr, outputTokens)

            } catch (e: Exception) {
                logger.error("Generation failed: ${e.message}")
                throw SDKError.generationFailed("llama.cpp generation failed", e)
            }
        }

    fun generateStream(prompt: String, options: GenerationOptions): Flow<String> = flow {
        ensureInitialized()

        val channel = Channel<String>(Channel.UNLIMITED)

        val callback = object : LlamaCppNative.GenerationCallback {
            override fun onToken(token: String): Boolean {
                channel.trySend(token)
                return true // Continue generation
            }

            override fun onComplete() {
                channel.close()
            }

            override fun onError(message: String) {
                channel.close(Exception("Generation error: $message"))
            }
        }

        // Start async generation
        withContext(Dispatchers.IO) {
            val inputTokens = LlamaCppNative.tokenize(contextPtr, prompt)
            LlamaCppNative.generateStream(contextPtr, inputTokens, options.maxTokens, callback)
        }

        // Emit tokens as they arrive
        try {
            for (token in channel) {
                emit(token)
            }
        } finally {
            // Ensure cleanup
            if (LlamaCppNative.isGenerating(contextPtr)) {
                LlamaCppNative.stopGeneration(contextPtr)
            }
        }
    }

    suspend fun cleanup() = withContext(Dispatchers.IO) {
        if (contextPtr != 0L) {
            try {
                // Stop any ongoing generation
                if (LlamaCppNative.isGenerating(contextPtr)) {
                    LlamaCppNative.stopGeneration(contextPtr)
                }

                // Cleanup native context
                LlamaCppNative.destroyContext(contextPtr)

                // Unregister memory usage
                memoryManager.unregisterModel(contextPtr)

                logger.info("llama.cpp service cleaned up")

            } catch (e: Exception) {
                logger.error("Error during cleanup: ${e.message}")
            } finally {
                contextPtr = 0L
                modelInfo = null
            }
        }
    }

    fun getMemoryUsage(): MemoryStats? {
        return if (contextPtr != 0L) {
            LlamaCppNative.getMemoryUsage(contextPtr)
        } else null
    }

    fun clearKVCache() {
        if (contextPtr != 0L) {
            LlamaCppNative.clearKVCache(contextPtr)
        }
    }

    private fun ensureInitialized() {
        if (contextPtr == 0L) {
            throw SDKError.notInitialized("LlamaCpp service not initialized")
        }
    }
}
```

### 4.2 Provider Implementation

```kotlin
// LlamaCppProvider.kt
class LlamaCppProvider : LLMServiceProvider {
    private val logger = SDKLogger("LlamaCppProvider")
    private val services = mutableMapOf<String, LlamaCppService>()

    override suspend fun generate(prompt: String, options: GenerationOptions): String {
        val service = getOrCreateService(options.model)
        return service.generate(prompt, options)
    }

    override fun generateStream(prompt: String, options: GenerationOptions): Flow<String> {
        val service = runBlocking { getOrCreateService(options.model) }
        return service.generateStream(prompt, options)
    }

    override fun canHandle(modelId: String): Boolean {
        return modelId.startsWith("llama-") ||
               modelId.contains("llama") ||
               modelId.endsWith(".gguf")
    }

    override val name: String = "llama.cpp"

    private suspend fun getOrCreateService(modelId: String?): LlamaCppService {
        val effectiveModelId = modelId ?: "default-llama"

        return services[effectiveModelId] ?: run {
            val configuration = createConfiguration(effectiveModelId)
            val service = LlamaCppService(configuration)
            service.initialize()
            services[effectiveModelId] = service
            service
        }
    }

    private fun createConfiguration(modelId: String): LlamaCppConfiguration {
        // This would typically load from configuration service
        return LlamaCppConfiguration(
            modelPath = resolveModelPath(modelId),
            contextSize = 2048,
            batchSize = 32,
            threads = detectOptimalThreadCount(),
            useGpu = detectGpuAvailability()
        )
    }

    private fun resolveModelPath(modelId: String): String {
        // Integration with existing ModelManager
        val modelManager = ServiceContainer.shared.get<ModelManager>()
        return modelManager.getModelPath(modelId)
            ?: throw SDKError.modelNotFound("Model not found: $modelId")
    }

    private fun detectOptimalThreadCount(): Int {
        return when (PlatformUtils.getPlatformName()) {
            "android" -> minOf(Runtime.getRuntime().availableProcessors(), 4)
            "jvm" -> Runtime.getRuntime().availableProcessors()
            else -> 1
        }
    }

    private fun detectGpuAvailability(): Boolean {
        return when (PlatformUtils.getPlatformName()) {
            "android" -> true // Most Android devices have GPU
            "jvm" -> System.getProperty("os.name").contains("Mac") // Metal on macOS
            else -> false
        }
    }

    fun cleanup() {
        services.values.forEach { service ->
            runBlocking { service.cleanup() }
        }
        services.clear()
    }
}
```

## 5. Configuration and Model Management

### 5.1 Configuration Classes

```kotlin
// LlamaCppConfiguration.kt
data class LlamaCppConfiguration(
    val modelPath: String,
    val contextSize: Int = 2048,
    val batchSize: Int = 32,
    val threads: Int = -1, // -1 for auto-detect
    val useGpu: Boolean = true,
    val temperature: Float = 0.7f,
    val topP: Float = 0.9f,
    val topK: Int = 40,
    val repeatPenalty: Float = 1.1f,
    val presencePenalty: Float = 0.0f,
    val frequencyPenalty: Float = 0.0f,
    val mirostat: Int = 0,
    val mirostatTau: Float = 5.0f,
    val mirostatEta: Float = 0.1f
) {
    companion object {
        fun forModel(modelType: LlamaModelType): LlamaCppConfiguration {
            return when (modelType) {
                LlamaModelType.TINY -> LlamaCppConfiguration(
                    modelPath = "", // Set by provider
                    contextSize = 1024,
                    batchSize = 16
                )
                LlamaModelType.SMALL -> LlamaCppConfiguration(
                    modelPath = "",
                    contextSize = 2048,
                    batchSize = 32
                )
                LlamaModelType.MEDIUM -> LlamaCppConfiguration(
                    modelPath = "",
                    contextSize = 4096,
                    batchSize = 64
                )
                LlamaModelType.LARGE -> LlamaCppConfiguration(
                    modelPath = "",
                    contextSize = 8192,
                    batchSize = 128
                )
            }
        }
    }
}

enum class LlamaModelType {
    TINY,    // < 1B parameters
    SMALL,   // 1-3B parameters
    MEDIUM,  // 3-7B parameters
    LARGE    // 7B+ parameters
}
```

### 5.2 Model Management Integration

```kotlin
// ModelManager.kt extension for llama.cpp
class LlamaModelManager(
    private val modelManager: ModelManager,
    private val memoryManager: MemoryManager
) {
    private val logger = SDKLogger("LlamaModelManager")

    suspend fun downloadModel(modelId: String, progressCallback: (Float) -> Unit = {}): String {
        val modelInfo = getSupportedModels().find { it.id == modelId }
            ?: throw SDKError.modelNotFound("Unsupported model: $modelId")

        return modelManager.downloadModel(modelId, progressCallback)
    }

    suspend fun loadModel(modelPath: String): LlamaCppConfiguration {
        // Validate model file
        if (!File(modelPath).exists()) {
            throw SDKError.modelNotFound("Model file not found: $modelPath")
        }

        // Estimate memory requirements
        val fileSize = File(modelPath).length()
        val estimatedMemoryMB = (fileSize / (1024 * 1024) * 1.2).toInt() // 20% overhead

        if (!memoryManager.canAllocateMemory(estimatedMemoryMB)) {
            throw SDKError.insufficientMemory("Not enough memory for model: ${estimatedMemoryMB}MB required")
        }

        // Detect model type from filename/metadata
        val modelType = detectModelType(modelPath)
        return LlamaCppConfiguration.forModel(modelType).copy(modelPath = modelPath)
    }

    private fun detectModelType(modelPath: String): LlamaModelType {
        val filename = File(modelPath).name.lowercase()
        return when {
            filename.contains("tiny") || filename.contains("1b") -> LlamaModelType.TINY
            filename.contains("small") || filename.contains("3b") -> LlamaModelType.SMALL
            filename.contains("medium") || filename.contains("7b") -> LlamaModelType.MEDIUM
            else -> LlamaModelType.LARGE
        }
    }

    fun getSupportedModels(): List<ModelInfo> {
        return listOf(
            ModelInfo(
                id = "llama-3.1-8b-instruct-q4_0",
                name = "Llama 3.1 8B Instruct (4-bit)",
                description = "Meta's Llama 3.1 8B model, 4-bit quantized for efficiency",
                sizeBytes = 4_600_000_000L, // ~4.6GB
                type = "llm",
                provider = "llama.cpp",
                downloadUrl = "https://models.runanywhere.ai/llama3.1-8b-instruct-q4_0.gguf"
            ),
            ModelInfo(
                id = "llama-3.1-3b-instruct-q4_0",
                name = "Llama 3.1 3B Instruct (4-bit)",
                description = "Meta's Llama 3.1 3B model, 4-bit quantized",
                sizeBytes = 1_800_000_000L, // ~1.8GB
                type = "llm",
                provider = "llama.cpp",
                downloadUrl = "https://models.runanywhere.ai/llama3.1-3b-instruct-q4_0.gguf"
            ),
            ModelInfo(
                id = "phi-3.5-mini-instruct-q4_0",
                name = "Phi-3.5 Mini Instruct (4-bit)",
                description = "Microsoft's Phi-3.5 Mini model, 4-bit quantized",
                sizeBytes = 2_300_000_000L, // ~2.3GB
                type = "llm",
                provider = "llama.cpp",
                downloadUrl = "https://models.runanywhere.ai/phi3.5-mini-instruct-q4_0.gguf"
            )
        )
    }
}
```

## 6. Memory Management

### 6.1 Memory Tracking

```kotlin
// MemoryManager.kt extension for llama.cpp
class LlamaMemoryManager {
    private val logger = SDKLogger("LlamaMemoryManager")
    private val activeModels = mutableMapOf<Long, ModelMemoryInfo>()
    private val memoryMutex = Mutex()

    suspend fun registerModel(contextPtr: Long, modelPath: String) = memoryMutex.withLock {
        val fileSize = File(modelPath).length()
        val info = ModelMemoryInfo(
            contextPtr = contextPtr,
            modelPath = modelPath,
            estimatedSize = fileSize,
            loadTime = System.currentTimeMillis()
        )
        activeModels[contextPtr] = info

        logger.info("Registered model memory: $modelPath (${fileSize / 1024 / 1024}MB)")

        // Track with global memory monitor
        MemoryMonitor.shared.trackAllocation("llama-model", fileSize)
    }

    suspend fun unregisterModel(contextPtr: Long) = memoryMutex.withLock {
        val info = activeModels.remove(contextPtr)
        if (info != null) {
            logger.info("Unregistered model memory: ${info.modelPath}")
            MemoryMonitor.shared.trackDeallocation("llama-model", info.estimatedSize)
        }
    }

    fun getMemoryUsage(): MemoryUsage {
        val totalEstimated = activeModels.values.sumOf { it.estimatedSize }
        val actualUsage = activeModels.keys.mapNotNull { contextPtr ->
            try {
                LlamaCppNative.getMemoryUsage(contextPtr)
            } catch (e: Exception) {
                null
            }
        }

        return MemoryUsage(
            estimatedBytes = totalEstimated,
            actualBytes = actualUsage.sumOf { it.totalBytes },
            kvCacheBytes = actualUsage.sumOf { it.kvCacheBytes },
            modelCount = activeModels.size
        )
    }

    suspend fun canAllocateMemory(additionalMB: Int): Boolean {
        val additionalBytes = additionalMB * 1024L * 1024L
        val currentUsage = getMemoryUsage()
        val availableMemory = getAvailableSystemMemory()

        return (currentUsage.actualBytes + additionalBytes) < (availableMemory * 0.8) // 80% threshold
    }

    private fun getAvailableSystemMemory(): Long {
        return when (PlatformUtils.getPlatformName()) {
            "android" -> {
                try {
                    val runtime = Runtime.getRuntime()
                    val maxMemory = runtime.maxHeapSize()
                    val usedMemory = runtime.totalMemory() - runtime.freeMemory()
                    maxMemory - usedMemory
                } catch (e: Exception) {
                    2L * 1024L * 1024L * 1024L // 2GB default
                }
            }
            "jvm" -> {
                val runtime = Runtime.getRuntime()
                runtime.maxMemory() - (runtime.totalMemory() - runtime.freeMemory())
            }
            else -> 4L * 1024L * 1024L * 1024L // 4GB default
        }
    }

    private data class ModelMemoryInfo(
        val contextPtr: Long,
        val modelPath: String,
        val estimatedSize: Long,
        val loadTime: Long
    )
}

data class MemoryUsage(
    val estimatedBytes: Long,
    val actualBytes: Long,
    val kvCacheBytes: Long,
    val modelCount: Int
)
```

## 7. Integration with Existing GenerationService

### 7.1 Enhanced GenerationService Integration

```kotlin
// GenerationService.kt - Add llama.cpp integration
class GenerationService {
    // ... existing code ...

    private suspend fun performGeneration(
        prompt: String,
        options: GenerationOptions
    ): String {
        // Check for LLM provider availability
        val llmProvider = ModuleRegistry.shared.llmProvider(options.model)
        if (llmProvider != null) {
            logger.info("Using LLM provider: ${llmProvider.name}")
            return llmProvider.generate(prompt, options)
        }

        // Fallback to existing cloud/mock implementation
        return performCloudGeneration(prompt, options)
    }

    // Enhanced streaming with LLM provider support
    fun streamGenerate(
        prompt: String,
        options: GenerationOptions? = null
    ): Flow<GenerationChunk> = flow {
        val resolvedOptions = optionsResolver.resolve(options)

        val llmProvider = ModuleRegistry.shared.llmProvider(resolvedOptions.model)
        if (llmProvider != null) {
            logger.info("Using streaming LLM provider: ${llmProvider.name}")

            var tokenCount = 0
            llmProvider.generateStream(prompt, resolvedOptions).collect { token ->
                tokenCount++
                emit(GenerationChunk(
                    text = token,
                    isComplete = false,
                    tokenCount = tokenCount
                ))
            }

            // Emit completion chunk
            emit(GenerationChunk(
                text = "",
                isComplete = true,
                tokenCount = tokenCount
            ))
        } else {
            // Fallback to existing streaming implementation
            streamingService.stream(prompt, resolvedOptions).collect { chunk ->
                emit(chunk)
            }
        }
    }
}
```

## 8. Build Configuration

### 8.1 Gradle Module Configuration

```kotlin
// build.gradle.kts
plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.library)
    id("maven-publish")
}

kotlin {
    jvm()
    androidTarget()

    sourceSets {
        commonMain {
            dependencies {
                api(project(":modules:runanywhere-core"))
                implementation(libs.kotlinx.coroutines.core)
                implementation(libs.kotlinx.datetime)
            }
        }

        val jvmAndroidMain by creating {
            dependsOn(commonMain.get())
            dependencies {
                implementation(libs.kotlinx.coroutines.core)
            }
        }

        jvmMain {
            dependsOn(jvmAndroidMain)
        }

        androidMain {
            dependsOn(jvmAndroidMain)
        }

        commonTest {
            dependencies {
                implementation(kotlin("test"))
                implementation(libs.kotlinx.coroutines.test)
            }
        }
    }
}

android {
    namespace = "com.runanywhere.sdk.llm.llamacpp"
    compileSdk = 36
    defaultConfig.minSdk = 24

    // Configure native library packaging
    packagingOptions {
        jniLibs {
            pickFirsts += "**/libllama-jni.so"
        }
    }
}

// Native library build task
tasks.register("buildNativeLibraries") {
    group = "build"
    description = "Build native llama.cpp libraries"

    doLast {
        // Build native libraries using CMake
        exec {
            workingDir = projectDir
            commandLine("cmake", "-B", "build", "-S", ".")
        }
        exec {
            workingDir = projectDir
            commandLine("cmake", "--build", "build", "--config", "Release")
        }
    }
}

// Ensure native libraries are built before compilation
tasks.named("preBuild") {
    dependsOn("buildNativeLibraries")
}

publishing {
    publications {
        create<MavenPublication>("maven") {
            from(components["kotlin"])
            groupId = project.group.toString()
            artifactId = "runanywhere-llm-llamacpp"
            version = project.version.toString()
        }
    }
}
```

## 9. Testing Strategy

### 9.1 Unit Tests

```kotlin
// LlamaCppServiceTest.kt
@OptIn(ExperimentalCoroutinesApi::class)
class LlamaCppServiceTest {
    private val testDispatcher = StandardTestDispatcher()

    @BeforeEach
    fun setup() {
        Dispatchers.setMain(testDispatcher)
    }

    @AfterEach
    fun teardown() {
        Dispatchers.resetMain()
    }

    @Test
    fun `service initializes successfully with valid model`() = runTest {
        // Assuming we have a test model available
        val config = LlamaCppConfiguration(
            modelPath = getTestModelPath(),
            contextSize = 512
        )

        val service = LlamaCppService(config)

        assertDoesNotThrow {
            service.initialize()
        }

        service.cleanup()
    }

    @Test
    fun `generation produces non-empty output`() = runTest {
        val service = createInitializedService()

        val result = service.generate("Hello", GenerationOptions(maxTokens = 10))

        assertTrue(result.isNotEmpty())
        service.cleanup()
    }

    @Test
    fun `streaming generation emits multiple tokens`() = runTest {
        val service = createInitializedService()
        val tokens = mutableListOf<String>()

        service.generateStream("Hello", GenerationOptions(maxTokens = 5))
            .take(5)
            .collect { token ->
                tokens.add(token)
            }

        assertTrue(tokens.isNotEmpty())
        service.cleanup()
    }

    private suspend fun createInitializedService(): LlamaCppService {
        val config = LlamaCppConfiguration(
            modelPath = getTestModelPath(),
            contextSize = 512
        )
        val service = LlamaCppService(config)
        service.initialize()
        return service
    }

    private fun getTestModelPath(): String {
        // Return path to a small test model or mock implementation
        return System.getProperty("test.model.path") ?: "/tmp/test-model.gguf"
    }
}
```

### 9.2 Integration Tests

```kotlin
// LlamaCppProviderIntegrationTest.kt
class LlamaCppProviderIntegrationTest {

    @BeforeEach
    fun setup() {
        // Register provider
        ModuleRegistry.shared.registerLLM(LlamaCppProvider())
    }

    @Test
    fun `provider integrates with ModuleRegistry`() {
        val provider = ModuleRegistry.shared.llmProvider("llama-test")
        assertNotNull(provider)
        assertEquals("llama.cpp", provider.name)
    }

    @Test
    fun `provider handles model selection correctly`() {
        val provider = ModuleRegistry.shared.llmProvider()
        assertNotNull(provider)

        assertTrue(provider.canHandle("llama-3.1-8b"))
        assertTrue(provider.canHandle("test.gguf"))
        assertFalse(provider.canHandle("whisper-base"))
    }

    @Test
    fun `generation service uses llama provider when available`() = runTest {
        val generationService = GenerationService()

        val options = GenerationOptions(
            model = "llama-test",
            maxTokens = 10
        )

        val result = generationService.generate("Test prompt", options)
        assertNotNull(result)
    }
}
```

## 10. Error Handling and Edge Cases

### 10.1 Comprehensive Error Handling

```kotlin
// Enhanced error handling in LlamaCppService
suspend fun generate(prompt: String, options: GenerationOptions): String =
    withContext(Dispatchers.Default) {
        ensureInitialized()

        // Input validation
        if (prompt.isEmpty()) {
            throw SDKError.invalidInput("Prompt cannot be empty")
        }

        if (options.maxTokens <= 0) {
            throw SDKError.invalidInput("Max tokens must be positive")
        }

        // Memory check before generation
        val memoryStats = getMemoryUsage()
        if (memoryStats != null && memoryStats.usedBytes > memoryStats.totalBytes * 0.9) {
            logger.warn("Memory usage high (${memoryStats.usedBytes}/${memoryStats.totalBytes})")
            clearKVCache() // Attempt to free memory
        }

        try {
            // Check if model is still loaded
            if (!LlamaCppNative.isModelLoaded(contextPtr)) {
                throw SDKError.modelLoadingFailed("Model is no longer loaded")
            }

            // Tokenize input with length validation
            val inputTokens = LlamaCppNative.tokenize(contextPtr, prompt)
            if (inputTokens.isEmpty()) {
                throw SDKError.tokenizationFailed("Failed to tokenize input prompt")
            }

            // Check context limits
            val contextSize = LlamaCppNative.getContextSize(contextPtr)
            if (inputTokens.size + options.maxTokens > contextSize) {
                throw SDKError.contextExceeded(
                    "Input + max tokens (${inputTokens.size + options.maxTokens}) " +
                    "exceeds context size ($contextSize)"
                )
            }

            // Perform generation with timeout
            val outputTokens = withTimeout(60_000) { // 60 second timeout
                LlamaCppNative.generate(contextPtr, inputTokens, options.maxTokens)
            }

            if (outputTokens.isEmpty()) {
                throw SDKError.generationFailed("No tokens generated")
            }

            // Detokenize output
            val result = LlamaCppNative.detokenize(contextPtr, outputTokens)
            if (result.isEmpty()) {
                throw SDKError.detokenizationFailed("Failed to detokenize output")
            }

            result

        } catch (e: TimeoutCancellationException) {
            logger.error("Generation timed out")
            LlamaCppNative.stopGeneration(contextPtr)
            throw SDKError.generationTimeout("Generation timed out after 60 seconds")
        } catch (e: SDKError) {
            throw e // Re-throw SDK errors as-is
        } catch (e: Exception) {
            logger.error("Unexpected error during generation: ${e.message}")
            throw SDKError.generationFailed("llama.cpp generation failed", e)
        }
    }
```

### 10.2 Platform-Specific Error Handling

```kotlin
// Platform-specific error handling in NativeLibraryLoader
private fun loadJvmLibrary() {
    val platformInfo = try {
        detectJvmPlatform()
    } catch (e: Exception) {
        throw SDKError.platformNotSupported(
            "Cannot detect JVM platform: ${e.message}", e
        )
    }

    val libraryName = "libllama-jni-${platformInfo.os}-${platformInfo.arch}.${platformInfo.ext}"

    try {
        extractAndLoadLibrary(libraryName)
    } catch (e: UnsatisfiedLinkError) {
        // Provide helpful error messages based on common issues
        val message = when {
            e.message?.contains("cannot find") == true ->
                "Native library not found for ${platformInfo.os}-${platformInfo.arch}. " +
                "Ensure the correct native library is included in the distribution."

            e.message?.contains("wrong ELF class") == true ->
                "Architecture mismatch: library compiled for different architecture. " +
                "Expected: ${platformInfo.arch}"

            e.message?.contains("symbol") == true ->
                "Symbol resolution failed. This may indicate an incompatible library version."

            else -> "Failed to load native library: ${e.message}"
        }

        throw SDKError.nativeLibraryError(message, e)
    }
}
```

## 11. Implementation Roadmap

### Phase 1: Foundation (Weeks 1-2)
- [ ] Set up module structure following modular architecture
- [ ] Create basic JNI interface declarations
- [ ] Implement native library loading mechanism
- [ ] Set up CMake build configuration
- [ ] Create basic provider registration

**Deliverables:**
- Module structure with build.gradle.kts
- Native library loader with platform detection
- Basic JNI interface (no implementation yet)
- CMake configuration for llama.cpp integration
- Auto-registration module

### Phase 2: JNI Implementation (Weeks 3-4)
- [ ] Implement core JNI bridge in C++
- [ ] Model loading and context management
- [ ] Basic text generation functionality
- [ ] Memory management integration
- [ ] Build native libraries for all platforms

**Deliverables:**
- Complete JNI bridge implementation
- Native libraries for Linux, macOS, Windows, Android
- Basic generation functionality working
- Memory tracking and cleanup

### Phase 3: Service Implementation (Weeks 5-6)
- [ ] Complete LlamaCppService implementation
- [ ] Provider integration with ModuleRegistry
- [ ] Configuration management
- [ ] Error handling and validation
- [ ] Integration with existing GenerationService

**Deliverables:**
- Full service implementation
- Provider registration and discovery
- Configuration classes and model management
- Comprehensive error handling

### Phase 4: Streaming and Advanced Features (Weeks 7-8)
- [ ] Implement streaming generation
- [ ] Advanced generation parameters
- [ ] KV cache management
- [ ] Performance optimizations
- [ ] GPU acceleration support

**Deliverables:**
- Streaming generation with proper cancellation
- Advanced configuration options
- Performance optimizations
- GPU support (Metal on macOS, OpenCL on Android)

### Phase 5: Testing and Integration (Weeks 9-10)
- [ ] Unit test suite
- [ ] Integration tests with existing SDK
- [ ] Performance benchmarking
- [ ] Memory usage validation
- [ ] Platform compatibility testing

**Deliverables:**
- Comprehensive test suite
- Performance benchmarks
- Memory usage analysis
- Platform compatibility report

### Phase 6: Documentation and Examples (Weeks 11-12)
- [ ] API documentation
- [ ] Integration guide
- [ ] Example applications
- [ ] Migration guide from cloud to on-device
- [ ] Best practices documentation

**Deliverables:**
- Complete API documentation
- Integration examples
- Best practices guide
- Migration documentation

## 12. Success Metrics

### Performance Targets
- **Initialization Time**: < 2 seconds for 3B models, < 5 seconds for 7B models
- **Generation Speed**: > 10 tokens/second on modern hardware
- **Memory Efficiency**: < 150% of model file size in RAM usage
- **Streaming Latency**: < 100ms time-to-first-token

### Compatibility Targets
- **Platform Coverage**: JVM (Linux, macOS, Windows), Android (ARM64, x86_64)
- **Model Support**: GGUF format, Q4_0, Q4_1, Q5_0, Q5_1, Q8_0 quantizations
- **Integration**: Seamless integration with existing ModuleRegistry pattern

### Quality Targets
- **Test Coverage**: > 80% line coverage
- **Error Handling**: Comprehensive error messages and recovery
- **Memory Management**: No memory leaks in long-running operations
- **Thread Safety**: Full thread-safe implementation

## 13. Future Enhancements

### Short Term (3-6 months)
- **Model Variants**: Support for additional quantization formats
- **Performance**: SIMD optimizations for specific architectures
- **Features**: Function calling and structured generation
- **Models**: Integration with newer Llama versions

### Medium Term (6-12 months)
- **Multi-Modal**: Integration with vision capabilities
- **Distributed**: Multi-model inference coordination
- **Optimization**: Dynamic quantization and pruning
- **Platforms**: iOS/Native platform support

### Long Term (12+ months)
- **Custom Models**: Fine-tuning and model customization
- **Edge Computing**: Specialized edge device optimizations
- **Federation**: Federated learning capabilities
- **Advanced**: Retrieval-augmented generation (RAG)

## 14. Conclusion

This comprehensive plan provides a roadmap for integrating llama.cpp into the RunAnywhere KMP SDK while maintaining the established modular architecture patterns. The implementation prioritizes type safety, memory efficiency, and seamless integration with existing services.

Key benefits of this approach:
- **Modular Design**: Clean separation enabling optional LLM functionality
- **Platform Consistency**: Unified interface across JVM and Android
- **Memory Efficiency**: Careful memory management and cleanup
- **Performance**: Native acceleration and optimizations
- **Extensibility**: Easy to add new models and features

The phased implementation approach ensures steady progress while maintaining code quality and thorough testing throughout the development process.
