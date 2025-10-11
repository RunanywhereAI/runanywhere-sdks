# MLC-LLM Module Integration Plan

**Project**: RunAnywhere Kotlin SDK - MLC-LLM Module
**Date**: October 11, 2025
**Status**: Ready for Implementation
**Version**: 1.0

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Module Structure & Setup](#2-module-structure--setup)
3. [Build Configuration](#3-build-configuration)
4. [Provider Implementation](#4-provider-implementation)
5. [Service Implementation](#5-service-implementation)
6. [MLC Engine Wrapper](#6-mlc-engine-wrapper)
7. [Configuration Classes](#7-configuration-classes)
8. [Auto-Registration](#8-auto-registration)
9. [API Surface Design](#9-api-surface-design)
10. [Integration Points](#10-integration-points)
11. [Dependencies & Native Libraries](#11-dependencies--native-libraries)
12. [Testing Strategy](#12-testing-strategy)
13. [Example Usage](#13-example-usage)
14. [Documentation Requirements](#14-documentation-requirements)
15. [Implementation Phases](#15-implementation-phases)
16. [Key Differences from LlamaCPP](#16-key-differences-from-llamacpp)
17. [Potential Challenges & Solutions](#17-potential-challenges--solutions)
18. [Complete File Checklist](#18-complete-file-checklist)

---

## 1. Executive Summary

### Objective

Create a standalone MLC-LLM module for the runanywhere-kotlin SDK that provides on-device LLM inference using the MLC-LLM framework. The module will follow the established architectural patterns from the LlamaCPP module while adapting to MLC-LLM's specific requirements.

### Key Goals

1. **Seamless Integration**: Auto-register with ModuleRegistry, plug-and-play architecture
2. **GPU Acceleration**: Leverage OpenCL for mobile GPU acceleration
3. **Streaming Support**: Token-by-token generation via Kotlin Flow
4. **Multi-Modal**: Support text and image inputs (MLC's vision model capabilities)
5. **Production-Ready**: Comprehensive error handling, logging, and resource management

### Architecture Pattern

```
MLCModule (auto-registration)
    ↓
MLCProvider (LLMServiceProvider implementation)
    ↓
MLCService (EnhancedLLMService implementation)
    ↓
MLCEngine (wrapper around mlc4j native library)
    ↓
TVM/MLC Native Runtime (libtvm4j_runtime_packed.so)
```

### Success Criteria

- [ ] Module builds successfully for Android (arm64-v8a)
- [ ] Auto-registers with ModuleRegistry on classpath inclusion
- [ ] Can load and run MLC-compiled models
- [ ] Streaming generation works via Kotlin Flow
- [ ] Memory management is robust (no leaks)
- [ ] Integration tests pass with sample models
- [ ] Documentation is complete and accurate

---

## 2. Module Structure & Setup

### 2.1 Directory Structure

Create the following directory structure under `sdk/runanywhere-kotlin/modules/`:

```
modules/runanywhere-llm-mlc/
├── build.gradle.kts                    # Module build configuration
├── proguard-rules.pro                  # ProGuard rules (if needed)
├── README.md                           # Module documentation
├── libs/                               # Native libraries and JARs
│   ├── mlc4j/                         # mlc4j library files
│   │   ├── tvm4j_core.jar            # TVM Java bindings
│   │   ├── arm64-v8a/                # Native libs per ABI
│   │   │   └── libtvm4j_runtime_packed.so
│   │   └── armeabi-v7a/              # (Optional: 32-bit ARM)
│   │       └── libtvm4j_runtime_packed.so
└── src/
    ├── commonMain/
    │   └── kotlin/com/runanywhere/sdk/llm/mlc/
    │       ├── MLCModule.kt            # AutoRegisteringModule implementation
    │       ├── MLCProvider.kt          # LLMServiceProvider implementation
    │       └── MLCService.kt           # expect class declaration
    │
    ├── commonTest/
    │   └── kotlin/com/runanywhere/sdk/llm/mlc/
    │       ├── MLCProviderTest.kt
    │       └── MLCServiceTest.kt
    │
    ├── androidMain/
    │   └── kotlin/com/runanywhere/sdk/llm/mlc/
    │       ├── MLCModuleActual.kt      # actual checkNativeLibraryAvailable()
    │       ├── MLCService.kt           # actual service implementation
    │       └── MLCEngine.kt            # Wrapper for mlc4j MLCEngine
    │
    └── androidUnitTest/
        └── kotlin/com/runanywhere/sdk/llm/mlc/
            └── MLCIntegrationTest.kt
```

### 2.2 Package Structure

**Package naming**: `com.runanywhere.sdk.llm.mlc`

**Rationale**: Follows the pattern established by `com.runanywhere.sdk.llm.llamacpp`, placing all LLM framework modules under `llm.*`

### 2.3 Source Set Organization

```kotlin
// Source set hierarchy:
commonMain                  # Interfaces, data classes, common logic
    ↓
androidMain                 # Android-specific implementation (MLC only supports Android/iOS)
```

**Note**: Unlike LlamaCPP, MLC-LLM likely won't support JVM (desktop) as it's optimized for mobile GPUs. We'll use `androidMain` directly instead of `jvmAndroidMain`.

---

## 3. Build Configuration

### 3.1 Module `build.gradle.kts`

**Location**: `modules/runanywhere-llm-mlc/build.gradle.kts`

```kotlin
plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.library)
    `maven-publish`
}

kotlin {
    androidTarget {
        compilations.all {
            kotlinOptions {
                jvmTarget = "17"
            }
        }
    }

    sourceSets {
        val commonMain by getting {
            dependencies {
                // Core SDK dependency (provides interfaces and models)
                api(project.parent!!.parent!!)

                // Coroutines for streaming
                implementation(libs.kotlinx.coroutines.core)

                // JSON serialization for MLC API
                implementation(libs.kotlinx.serialization.json)
            }
        }

        val commonTest by getting {
            dependencies {
                implementation(kotlin("test"))
                implementation(libs.kotlinx.coroutines.test)
            }
        }

        val androidMain by getting {
            dependencies {
                // Android-specific dependencies
                implementation(libs.androidx.core.ktx)

                // MLC4J library (JAR) - local dependency
                implementation(files("libs/mlc4j/tvm4j_core.jar"))
            }
        }

        val androidUnitTest by getting {
            dependencies {
                implementation(kotlin("test-junit"))
                implementation(libs.androidx.test.core)
            }
        }
    }
}

android {
    namespace = "com.runanywhere.sdk.llm.mlc"
    compileSdk = 36

    defaultConfig {
        minSdk = 24  // Match MLC-LLM's minimum (Android 5.1+)

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        ndk {
            // MLC-LLM supports these ABIs
            abiFilters += listOf(
                "arm64-v8a",      // Primary target (modern devices)
                "armeabi-v7a"     // Optional: older 32-bit devices
            )
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

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // Native library location
    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("libs/mlc4j")
        }
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }

        // Include native libraries in final AAR
        jniLibs {
            useLegacyPackaging = false
        }
    }
}

// Publishing configuration
publishing {
    publications {
        create<MavenPublication>("release") {
            from(components["release"])

            groupId = "com.runanywhere.sdk"
            artifactId = "runanywhere-llm-mlc"
            version = "0.1.0"

            pom {
                name.set("RunAnywhere MLC-LLM Module")
                description.set("On-device LLM inference using MLC-LLM framework")
                url.set("https://github.com/runanywhere/sdks")
            }
        }
    }
}
```

### 3.2 Root `settings.gradle.kts` Update

**Location**: `sdk/runanywhere-kotlin/settings.gradle.kts`

Add to the file:

```kotlin
// MLC-LLM module - provides LLM capabilities via MLC-LLM framework
include(":modules:runanywhere-llm-mlc")
```

### 3.3 ProGuard Rules

**Location**: `modules/runanywhere-llm-mlc/proguard-rules.pro`

```proguard
# Keep MLC-LLM native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep TVM classes
-keep class org.apache.tvm.** { *; }

# Keep MLC classes
-keep class ai.mlc.mlcllm.** { *; }

# Keep Kotlin serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt
-keepclassmembers class kotlinx.serialization.json.** {
    *** Companion;
}
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# Keep SDK classes
-keep class com.runanywhere.sdk.llm.mlc.** { *; }
```

### 3.4 Dependencies Summary

**Core Dependencies**:
- Core SDK (`api(project.parent!!.parent!!)`)
- kotlinx-coroutines-core
- kotlinx-serialization-json

**Android Dependencies**:
- androidx.core:core-ktx
- tvm4j_core.jar (local file dependency)
- libtvm4j_runtime_packed.so (native library)

**Test Dependencies**:
- kotlin-test
- kotlinx-coroutines-test
- androidx.test.core

---

## 4. Provider Implementation

### 4.1 MLCProvider Class

**Location**: `src/commonMain/kotlin/com/runanywhere/sdk/llm/mlc/MLCProvider.kt`

```kotlin
package com.runanywhere.sdk.llm.mlc

import com.runanywhere.sdk.components.llm.LLMConfiguration
import com.runanywhere.sdk.components.llm.LLMService
import com.runanywhere.sdk.components.llm.LLMServiceProvider
import com.runanywhere.sdk.models.*
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.ModelFormat

/**
 * LLM Service Provider for MLC-LLM framework
 *
 * Provides on-device inference using MLC-compiled models with GPU acceleration
 * via OpenCL. Supports streaming generation and multi-modal inputs.
 */
class MLCProvider : LLMServiceProvider {

    override suspend fun createLLMService(configuration: LLMConfiguration): LLMService {
        return MLCService(configuration)
    }

    override fun canHandle(modelId: String?): Boolean {
        if (modelId == null) return false

        val modelIdLower = modelId.lowercase()

        // MLC-specific model patterns
        return modelIdLower.endsWith("-mlc") ||
               modelIdLower.contains("mlc-chat") ||
               modelIdLower.contains("mlc-compiled") ||
               modelIdLower.contains("mlc-ai") ||
               // Common architectures that MLC supports
               modelIdLower.contains("phi") ||
               modelIdLower.contains("llama") ||
               modelIdLower.contains("mistral") ||
               modelIdLower.contains("qwen") ||
               modelIdLower.contains("gemma") ||
               // Vision models
               modelIdLower.contains("llava") ||
               modelIdLower.contains("clip")
    }

    override val name: String = "MLC-LLM"

    override val framework: LLMFramework = LLMFramework.MLC_LLM

    override val supportedFeatures: Set<String> = setOf(
        // Core features
        "streaming",
        "batch-processing",

        // GPU acceleration
        "gpu-acceleration-opencl",
        "gpu-memory-management",

        // Context windows
        "context-window-2k",
        "context-window-4k",
        "context-window-8k",
        "context-window-32k",
        "context-window-128k",

        // Advanced features
        "quantization",
        "kv-cache-optimization",
        "continuous-batching",
        "speculative-decoding",

        // Multi-modal
        "multi-modal-text-image",
        "vision-language-models",

        // Performance
        "compiled-models",
        "tvm-optimization",
        "operator-fusion",
        "memory-planning"
    )

    override fun validateModelCompatibility(model: ModelInfo): ModelCompatibilityResult {
        val warnings = mutableListOf<String>()
        val recommendations = mutableListOf<String>()

        // Check model format
        val isCompatible = when {
            model.format.toString().contains("MLC", ignoreCase = true) -> true
            model.format.toString().contains("TVM", ignoreCase = true) -> true
            else -> {
                warnings.add("Model format ${model.format} is not a recognized MLC-compiled format")
                warnings.add("Expected model format: MLC-compiled or TVM")
                false
            }
        }

        // Estimate memory requirements
        val memoryRequired = estimateMemoryRequirements(model)
        val availableMemory = getAvailableSystemMemory()

        // Memory validation
        when {
            memoryRequired > availableMemory -> {
                warnings.add("Model requires ${memoryRequired / 1024 / 1024}MB but only ${availableMemory / 1024 / 1024}MB available")
                recommendations.add("Consider using a smaller quantized model")
            }
            memoryRequired > availableMemory * 0.8 -> {
                warnings.add("Model will use over 80% of available memory (${memoryRequired / 1024 / 1024}MB / ${availableMemory / 1024 / 1024}MB)")
                recommendations.add("Close other apps before loading this model")
            }
        }

        // GPU availability check
        if (!checkOpenCLAvailable()) {
            warnings.add("OpenCL not available - will fall back to CPU (slower)")
            recommendations.add("For best performance, use a device with OpenCL support")
        }

        // Context window check
        val contextLength = model.contextLength ?: 2048
        if (contextLength > 8192) {
            recommendations.add("Large context window ($contextLength tokens) may impact performance")
        }

        return ModelCompatibilityResult(
            isCompatible = isCompatible,
            details = "Model ${model.name} validation for MLC-LLM framework",
            memoryRequired = memoryRequired,
            recommendedConfiguration = getOptimalConfiguration(model),
            warnings = warnings,
            recommendations = recommendations
        )
    }

    override suspend fun downloadModel(
        modelId: String,
        onProgress: (Float) -> Unit
    ): ModelInfo {
        // MLC models are typically downloaded via HuggingFace
        // This is a placeholder - actual implementation would:
        // 1. Parse model URL (e.g., HF://mlc-ai/Phi-3-mini-4k-instruct-q4f16_1-MLC)
        // 2. Download model files (mlc-chat-config.json, params, etc.)
        // 3. Track progress via onProgress callback
        // 4. Return ModelInfo when complete

        TODO("Model download implementation - will integrate with ModelManager")
    }

    override fun estimateMemoryRequirements(model: ModelInfo): Long {
        // Base model size (from download size or parameters)
        val modelSize = model.downloadSize ?: run {
            // Estimate from parameter count if available
            val params = model.parameters ?: 1_000_000_000L // Default 1B params
            // Rough estimate: 2 bytes per param for typical quantization (q4)
            params * 2
        }

        // Context memory (KV cache)
        val contextLength = model.contextLength ?: 2048
        val kvCacheMemory = contextLength * 4L * 1024  // ~4KB per token for KV cache

        // GPU memory overhead (buffers, intermediate tensors)
        val gpuOverhead = modelSize * 0.15  // ~15% overhead for GPU

        return (modelSize + kvCacheMemory + gpuOverhead).toLong()
    }

    override fun getOptimalConfiguration(model: ModelInfo): HardwareConfiguration {
        val memoryMB = (estimateMemoryRequirements(model) / 1024 / 1024).toInt()
        val availableMemoryMB = (getAvailableSystemMemory() / 1024 / 1024).toInt()
        val contextLength = model.contextLength ?: 2048

        return HardwareConfiguration(
            // GPU acceleration is highly recommended for MLC
            preferGPU = checkOpenCLAvailable(),
            gpuLayers = if (checkOpenCLAvailable()) -1 else 0,  // -1 = all layers on GPU

            // Memory settings
            minMemoryMB = memoryMB,
            recommendedMemoryMB = (memoryMB * 1.2).toInt(),  // 20% buffer

            // Thread settings (less important for GPU inference)
            recommendedThreads = minOf(Runtime.getRuntime().availableProcessors(), 4),

            // MLC-specific optimizations
            useMmap = false,  // MLC handles memory differently
            lockMemory = false,

            // Context configuration
            contextLength = contextLength,
            prefillChunkSize = when {
                contextLength <= 2048 -> 512
                contextLength <= 8192 -> 1024
                else -> 2048
            },

            // Additional MLC-specific settings
            additionalSettings = mapOf(
                "use_opencl" to checkOpenCLAvailable().toString(),
                "device_type" to if (checkOpenCLAvailable()) "opencl" else "cpu",
                "max_batch_size" to "1",
                "sliding_window_size" to contextLength.toString()
            )
        )
    }

    override fun createModelInfo(modelId: String): ModelInfo {
        // Parse model ID to extract information
        val modelName = modelId.split("/").lastOrNull() ?: modelId
        val isVisionModel = modelName.lowercase().contains("llava") ||
                           modelName.lowercase().contains("clip")

        return ModelInfo(
            id = modelId,
            name = modelName,
            category = if (isVisionModel) ModelCategory.MULTI_MODAL else ModelCategory.LANGUAGE,
            format = ModelFormat.MLC_COMPILED,
            framework = LLMFramework.MLC_LLM,

            // Extract context length from model name if present
            contextLength = extractContextLength(modelName),

            // Extract quantization info
            quantization = extractQuantization(modelName),

            // Capabilities
            capabilities = buildSet {
                add("text-generation")
                add("streaming")
                if (isVisionModel) {
                    add("image-understanding")
                    add("multi-modal")
                }
            },

            // Provider info
            provider = name,

            // Metadata
            metadata = mapOf(
                "framework" to "MLC-LLM",
                "gpu_accelerated" to "true",
                "requires_compilation" to "true"
            )
        )
    }

    // Helper methods

    private fun getAvailableSystemMemory(): Long {
        return Runtime.getRuntime().maxMemory()
    }

    private fun checkOpenCLAvailable(): Boolean {
        // This will be implemented in androidMain
        // For now, return true as most modern Android devices support OpenCL
        return true
    }

    private fun extractContextLength(modelName: String): Int? {
        // Extract context length from model name patterns like "4k", "8k", "32k"
        val contextRegex = Regex("""(\d+)k""", RegexOption.IGNORE_CASE)
        val match = contextRegex.find(modelName)
        return match?.groupValues?.get(1)?.toIntOrNull()?.times(1024)
    }

    private fun extractQuantization(modelName: String): String? {
        // Extract quantization info like "q4f16_1"
        val quantRegex = Regex("""q(\d+)f(\d+)(_\d+)?""", RegexOption.IGNORE_CASE)
        return quantRegex.find(modelName)?.value
    }
}
```

### 4.2 Model Detection Logic

**Pattern Matching Strategy**:

1. **File Extensions**: `-mlc`, `-MLC`
2. **Keywords**: `mlc-chat`, `mlc-compiled`, `mlc-ai`
3. **Architecture Names**: `phi`, `llama`, `mistral`, `qwen`, `gemma`
4. **Vision Models**: `llava`, `clip`

**Rationale**: MLC-LLM models are typically compiled and distributed with clear naming conventions that include the framework name and architecture.

---

## 5. Service Implementation

### 5.1 Service Interface (expect)

**Location**: `src/commonMain/kotlin/com/runanywhere/sdk/llm/mlc/MLCService.kt`

```kotlin
package com.runanywhere.sdk.llm.mlc

import com.runanywhere.sdk.components.llm.EnhancedLLMService
import com.runanywhere.sdk.components.llm.LLMConfiguration
import com.runanywhere.sdk.models.*
import kotlinx.coroutines.flow.Flow

/**
 * MLC-LLM Service interface
 *
 * Provides on-device LLM inference using MLC-compiled models.
 * expect/actual pattern allows platform-specific implementations.
 */
expect class MLCService(configuration: LLMConfiguration) : EnhancedLLMService {

    // Basic LLMService methods
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

### 5.2 Service Implementation (actual)

**Location**: `src/androidMain/kotlin/com/runanywhere/sdk/llm/mlc/MLCService.kt`

```kotlin
package com.runanywhere.sdk.llm.mlc

import com.runanywhere.sdk.components.llm.EnhancedLLMService
import com.runanywhere.sdk.components.llm.LLMConfiguration
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext
import kotlin.system.measureTimeMillis

/**
 * MLC-LLM Service implementation for Android
 */
actual class MLCService actual constructor(
    private val configuration: LLMConfiguration
) : EnhancedLLMService {

    private val logger = SDKLogger("MLCService")

    // MLC Engine instance (singleton wrapper)
    private val engine = MLCEngine.instance()

    // State tracking
    private var modelPath: String? = null
    private var modelLib: String? = null
    private var isInitialized = false
    private var contextLength: Int = configuration.contextLength

    // Cancellation support
    @Volatile
    private var shouldCancel = false

    actual override suspend fun initialize(modelPath: String?) = withContext(Dispatchers.IO) {
        val actualModelPath = modelPath ?: configuration.modelId
            ?: throw IllegalArgumentException("No model path provided")

        if (isInitialized) {
            logger.info("Already initialized, unloading previous model")
            cleanup()
        }

        logger.info("Initializing MLC-LLM with model: $actualModelPath")

        try {
            // Extract model lib from configuration or infer from model
            val actualModelLib = configuration.frameworkOptions["modelLib"] as? String
                ?: inferModelLib(actualModelPath)

            // Load model via MLC Engine
            engine.reload(actualModelPath, actualModelLib)

            this@MLCService.modelPath = actualModelPath
            this@MLCService.modelLib = actualModelLib
            isInitialized = true

            logger.info("Initialized MLC-LLM successfully")
        } catch (e: Exception) {
            logger.error("Failed to initialize MLC-LLM", e)
            throw IllegalStateException("Failed to initialize MLC-LLM: ${e.message}", e)
        }
    }

    actual override suspend fun generate(
        prompt: String,
        options: RunAnywhereGenerationOptions
    ): String = withContext(Dispatchers.IO) {
        if (!isInitialized) {
            throw IllegalStateException("MLCService not initialized")
        }

        val result = StringBuilder()
        var tokenCount = 0
        val maxTokens = options.maxTokens

        // Use MLC's streaming API and collect all tokens
        val messages = listOf(
            ChatCompletionMessage(
                role = ChatCompletionRole.user,
                content = ChatCompletionMessageContent(text = prompt)
            )
        )

        val channel = engine.chat.completions.create(
            messages = messages,
            temperature = options.temperature,
            max_tokens = maxTokens,
            stream_options = StreamOptions(include_usage = false)
        )

        for (response in channel) {
            if (response.choices.isNotEmpty()) {
                val token = response.choices[0].delta.content?.asText() ?: ""
                result.append(token)
                tokenCount++

                if (tokenCount >= maxTokens) {
                    break
                }
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
            throw IllegalStateException("MLCService not initialized")
        }

        shouldCancel = false
        var tokenCount = 0
        val maxTokens = options.maxTokens

        val messages = listOf(
            ChatCompletionMessage(
                role = ChatCompletionRole.user,
                content = ChatCompletionMessageContent(text = prompt)
            )
        )

        val channel = engine.chat.completions.create(
            messages = messages,
            temperature = options.temperature,
            max_tokens = maxTokens,
            stream_options = StreamOptions(include_usage = false)
        )

        for (response in channel) {
            if (shouldCancel) {
                logger.info("Generation cancelled")
                break
            }

            if (response.choices.isNotEmpty()) {
                val token = response.choices[0].delta.content?.asText() ?: ""
                if (token.isNotEmpty()) {
                    onToken(token)
                    tokenCount++

                    if (tokenCount >= maxTokens) {
                        break
                    }
                }
            }
        }
    }

    actual override suspend fun process(input: LLMInput): LLMOutput {
        if (!isInitialized) {
            throw IllegalStateException("MLCService not initialized")
        }

        val startTime = System.currentTimeMillis()

        // Build messages from input
        val messages = buildMessages(input)

        val options = input.options ?: RunAnywhereGenerationOptions(
            maxTokens = configuration.maxTokens,
            temperature = configuration.temperature.toFloat(),
            streamingEnabled = false
        )

        // Generate response
        val result = StringBuilder()
        var tokenCount = 0

        val channel = engine.chat.completions.create(
            messages = messages,
            temperature = options.temperature,
            max_tokens = options.maxTokens,
            stream_options = StreamOptions(include_usage = true)
        )

        var usage: CompletionUsage? = null

        for (response in channel) {
            if (response.usage != null) {
                usage = response.usage
            } else if (response.choices.isNotEmpty()) {
                val token = response.choices[0].delta.content?.asText() ?: ""
                result.append(token)
                tokenCount++
            }
        }

        val generationTime = System.currentTimeMillis() - startTime
        val tokensPerSecond = if (generationTime > 0) {
            (tokenCount.toDouble() * 1000.0) / generationTime
        } else null

        return LLMOutput(
            text = result.toString(),
            tokenUsage = TokenUsage(
                promptTokens = usage?.prompt_tokens ?: estimateTokenCount(input.messages),
                completionTokens = tokenCount
            ),
            metadata = GenerationMetadata(
                modelId = currentModel ?: "unknown",
                temperature = options.temperature,
                generationTime = generationTime,
                tokensPerSecond = tokensPerSecond,
                additionalInfo = buildMap {
                    usage?.extra?.let { extra ->
                        extra.prefill_tokens_per_s?.let { put("prefill_tokens_per_s", it) }
                        extra.decode_tokens_per_s?.let { put("decode_tokens_per_s", it) }
                        extra.num_prefill_tokens?.let { put("num_prefill_tokens", it) }
                    }
                }
            ),
            finishReason = FinishReason.COMPLETED,
            timestamp = startTime
        )
    }

    actual override fun streamProcess(input: LLMInput): Flow<LLMGenerationChunk> = flow {
        if (!isInitialized) {
            throw IllegalStateException("MLCService not initialized")
        }

        shouldCancel = false

        val messages = buildMessages(input)
        val options = input.options ?: RunAnywhereGenerationOptions(
            maxTokens = configuration.maxTokens,
            temperature = configuration.temperature.toFloat(),
            streamingEnabled = true
        )

        var chunkIndex = 0
        var tokenCount = 0
        val maxTokens = options.maxTokens

        val channel = engine.chat.completions.create(
            messages = messages,
            temperature = options.temperature,
            max_tokens = maxTokens,
            stream_options = StreamOptions(include_usage = false)
        )

        for (response in channel) {
            if (shouldCancel) {
                emit(LLMGenerationChunk(
                    text = "",
                    isComplete = true,
                    chunkIndex = chunkIndex,
                    timestamp = System.currentTimeMillis(),
                    metadata = mapOf("cancelled" to true)
                ))
                break
            }

            if (response.choices.isNotEmpty()) {
                val token = response.choices[0].delta.content?.asText() ?: ""
                if (token.isNotEmpty()) {
                    val isComplete = tokenCount >= maxTokens ||
                                   response.choices[0].finish_reason != null

                    emit(LLMGenerationChunk(
                        text = token,
                        isComplete = isComplete,
                        chunkIndex = chunkIndex++,
                        timestamp = System.currentTimeMillis()
                    ))

                    tokenCount++

                    if (isComplete) {
                        break
                    }
                }
            }
        }
    }

    actual override suspend fun loadModel(modelInfo: ModelInfo) {
        val modelPath = modelInfo.id  // Assume ID is the path
        val modelLib = modelInfo.metadata["modelLib"] as? String
            ?: inferModelLib(modelPath)

        // Store in configuration for reload
        configuration.frameworkOptions["modelLib"] = modelLib

        initialize(modelPath)
    }

    actual override fun cancelCurrent() {
        shouldCancel = true
        logger.info("Cancellation requested")
    }

    actual override fun getTokenCount(text: String): Int {
        // Rough estimation: ~4 characters per token
        return text.length / 4
    }

    actual override fun fitsInContext(prompt: String, maxTokens: Int): Boolean {
        val promptTokens = getTokenCount(prompt)
        val totalTokens = promptTokens + maxTokens
        return totalTokens <= contextLength
    }

    actual override suspend fun cleanup() = withContext(Dispatchers.IO) {
        if (isInitialized) {
            logger.info("Cleaning up MLC-LLM context")
            try {
                engine.unload()
            } catch (e: Exception) {
                logger.error("Error during cleanup", e)
            }
            isInitialized = false
            modelPath = null
            modelLib = null
        }
    }

    actual override val isReady: Boolean
        get() = isInitialized

    actual override val currentModel: String?
        get() = modelPath?.split("/")?.lastOrNull()

    // Helper methods

    private fun buildMessages(input: LLMInput): List<ChatCompletionMessage> {
        val messages = mutableListOf<ChatCompletionMessage>()

        // Add system prompt if present
        input.systemPrompt?.let { systemPrompt ->
            messages.add(
                ChatCompletionMessage(
                    role = ChatCompletionRole.system,
                    content = ChatCompletionMessageContent(text = systemPrompt)
                )
            )
        }

        // Add conversation messages
        for (message in input.messages) {
            val role = when (message.role) {
                MessageRole.USER -> ChatCompletionRole.user
                MessageRole.ASSISTANT -> ChatCompletionRole.assistant
                MessageRole.SYSTEM -> ChatCompletionRole.system
            }

            messages.add(
                ChatCompletionMessage(
                    role = role,
                    content = ChatCompletionMessageContent(text = message.content)
                )
            )
        }

        return messages
    }

    private fun estimateTokenCount(messages: List<Message>): Int {
        val totalText = messages.joinToString(" ") { it.content }
        return getTokenCount(totalText)
    }

    private fun inferModelLib(modelPath: String): String {
        // Extract model lib name from model path or configuration
        // MLC models typically have a corresponding model lib
        // Format: {model_name}_{quantization}_{hash}

        val modelName = modelPath.split("/").lastOrNull() ?: ""

        // Try to extract from model directory
        // Expected structure: {modelPath}/mlc-chat-config.json contains model_lib
        // For now, throw an error requiring explicit modelLib specification

        throw IllegalArgumentException(
            "Model lib must be specified in configuration.frameworkOptions[\"modelLib\"]. " +
            "Cannot infer from model path: $modelPath"
        )
    }
}
```

---

## 6. MLC Engine Wrapper

### 6.1 MLCEngine Class

**Location**: `src/androidMain/kotlin/com/runanywhere/sdk/llm/mlc/MLCEngine.kt`

```kotlin
package com.runanywhere.sdk.llm.mlc

import ai.mlc.mlcllm.MLCEngine as NativeMLCEngine
import ai.mlc.mlcllm.OpenAIProtocol.*
import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.channels.ReceiveChannel

/**
 * Wrapper around mlc4j MLCEngine
 *
 * Provides a simplified, thread-safe interface to the native MLC engine.
 * Manages engine lifecycle and provides Kotlin-friendly APIs.
 */
class MLCEngine private constructor() {

    private val logger = SDKLogger("MLCEngine")

    // Native MLC engine instance
    private var nativeEngine: NativeMLCEngine? = null

    // State tracking
    private var isLoaded = false

    /**
     * Chat API accessor
     */
    val chat: Chat
        get() = checkNotNull(nativeEngine).chat

    /**
     * Reload engine with new model
     *
     * @param modelPath Path to model directory
     * @param modelLib Model library name (system://{lib_name})
     */
    fun reload(modelPath: String, modelLib: String) {
        synchronized(this) {
            try {
                logger.info("Reloading MLC engine with model: $modelPath, lib: $modelLib")

                // Unload existing model if loaded
                if (isLoaded) {
                    unload()
                }

                // Create or reuse engine
                val engine = nativeEngine ?: NativeMLCEngine().also { nativeEngine = it }

                // Reload with new model
                engine.reload(modelPath, modelLib)

                isLoaded = true
                logger.info("MLC engine reloaded successfully")
            } catch (e: Exception) {
                logger.error("Failed to reload MLC engine", e)
                throw IllegalStateException("Failed to reload MLC engine: ${e.message}", e)
            }
        }
    }

    /**
     * Unload current model and free resources
     */
    fun unload() {
        synchronized(this) {
            if (!isLoaded) {
                logger.debug("No model to unload")
                return
            }

            try {
                logger.info("Unloading MLC engine")
                nativeEngine?.unload()
                isLoaded = false
                logger.info("MLC engine unloaded successfully")
            } catch (e: Exception) {
                logger.error("Error unloading MLC engine", e)
                throw e
            }
        }
    }

    /**
     * Reset conversation state (clear KV cache)
     */
    fun reset() {
        synchronized(this) {
            if (!isLoaded) {
                logger.warn("Cannot reset: engine not loaded")
                return
            }

            try {
                nativeEngine?.reset()
                logger.debug("MLC engine reset")
            } catch (e: Exception) {
                logger.error("Error resetting MLC engine", e)
            }
        }
    }

    companion object {
        private val _instance = MLCEngine()

        /**
         * Get singleton instance
         */
        fun instance(): MLCEngine = _instance
    }
}

// Type aliases for convenience
typealias ChatCompletionMessage = ai.mlc.mlcllm.OpenAIProtocol.ChatCompletionMessage
typealias ChatCompletionMessageContent = ai.mlc.mlcllm.OpenAIProtocol.ChatCompletionMessageContent
typealias ChatCompletionRole = ai.mlc.mlcllm.OpenAIProtocol.ChatCompletionRole
typealias ChatCompletionStreamResponse = ai.mlc.mlcllm.OpenAIProtocol.ChatCompletionStreamResponse
typealias StreamOptions = ai.mlc.mlcllm.OpenAIProtocol.StreamOptions
typealias CompletionUsage = ai.mlc.mlcllm.OpenAIProtocol.CompletionUsage
```

### 6.2 Threading Model

**MLC-LLM Threading**:
- MLC engine internally manages 2 background threads:
  1. Inference thread (high priority)
  2. Streaming callback thread

**Our Wrapper Strategy**:
- Use `Dispatchers.IO` for all suspend functions
- MLCEngine is thread-safe via `synchronized` blocks
- Native engine handles its own threading internally

### 6.3 State Management

**States**:
1. **Unloaded**: No model loaded
2. **Loaded**: Model loaded and ready
3. **Generating**: Currently generating (tracked in service, not engine)

**Transitions**:
```
Unloaded → reload() → Loaded
Loaded → unload() → Unloaded
Loaded → reload() → Loaded (with new model)
```

---

## 7. Configuration Classes

### 7.1 LLMConfiguration Extensions

MLC-specific configuration options are stored in `configuration.frameworkOptions` map:

```kotlin
// Example usage:
val config = LLMConfiguration(
    modelId = "/sdcard/models/Phi-3-mini-4k-instruct-q4f16_1-MLC",
    contextLength = 4096,
    temperature = 0.7,
    maxTokens = 512,
    useGPUIfAvailable = true,

    // MLC-specific options in frameworkOptions
    frameworkOptions = mapOf(
        "modelLib" to "phi_msft_q4f16_1_686d8979c6ebf05d142d9081f1b87162",
        "deviceType" to "opencl",  // or "cpu"
        "prefillChunkSize" to 512,
        "slidingWindowSize" to 768  // For models with sliding window attention
    )
)
```

### 7.2 MLC-Specific Parameters

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `modelLib` | String | Model library name (required) | - |
| `deviceType` | String | "opencl" or "cpu" | "opencl" |
| `prefillChunkSize` | Int | Chunk size for prompt processing | 512 |
| `slidingWindowSize` | Int | Sliding window attention size | null |
| `logitBias` | Map<Int, Float> | Token logit biases | null |
| `seed` | Int | Random seed for reproducibility | null |

---

## 8. Auto-Registration

### 8.1 MLCModule Object

**Location**: `src/commonMain/kotlin/com/runanywhere/sdk/llm/mlc/MLCModule.kt`

```kotlin
package com.runanywhere.sdk.llm.mlc

import com.runanywhere.sdk.core.AutoRegisteringModule
import com.runanywhere.sdk.core.ModuleRegistry

/**
 * MLC-LLM Module - auto-registers with ModuleRegistry
 *
 * Provides on-device LLM inference using MLC-compiled models.
 */
object MLCModule : AutoRegisteringModule {

    private var provider: MLCProvider? = null

    override fun register() {
        if (checkNativeLibraryAvailable()) {
            provider = MLCProvider()
            ModuleRegistry.shared.registerLLM(provider!!)
        }
    }

    /**
     * Check if MLC-LLM native library is available
     */
    val isAvailable: Boolean
        get() = checkNativeLibraryAvailable()

    /**
     * Module name
     */
    val name: String = "MLC-LLM"

    /**
     * Module version
     */
    val version: String = "0.1.0"

    /**
     * Module description
     */
    val description: String = "On-device LLM inference using MLC-LLM framework with GPU acceleration"

    /**
     * Cleanup resources
     */
    fun cleanup() {
        provider = null
    }
}

/**
 * Platform-specific check for native library availability
 */
expect fun checkNativeLibraryAvailable(): Boolean
```

### 8.2 Platform-Specific Implementation

**Location**: `src/androidMain/kotlin/com/runanywhere/sdk/llm/mlc/MLCModuleActual.kt`

```kotlin
package com.runanywhere.sdk.llm.mlc

/**
 * Check if MLC-LLM native library is available on Android
 */
actual fun checkNativeLibraryAvailable(): Boolean {
    return try {
        // Try to load the TVM runtime library
        System.loadLibrary("tvm4j_runtime_packed")
        true
    } catch (e: UnsatisfiedLinkError) {
        false
    } catch (e: Exception) {
        false
    }
}
```

### 8.3 Registration Flow

```
Application Startup
    ↓
ClassLoader loads MLCModule
    ↓
MLCModule.register() called (if AutoRegisteringModule)
    ↓
checkNativeLibraryAvailable() checks for native lib
    ↓
If available: MLCProvider created
    ↓
ModuleRegistry.shared.registerLLM(provider)
    ↓
Provider available via ModuleRegistry.llmProvider()
```

---

## 9. API Surface Design

### 9.1 Public APIs

**Module Entry Point**:
```kotlin
// Auto-registration (happens automatically)
MLCModule.register()

// Check availability
if (MLCModule.isAvailable) {
    // Module is ready to use
}
```

**Provider Access** (via ModuleRegistry):
```kotlin
// Get provider for MLC model
val provider = ModuleRegistry.llmProvider("Phi-3-mini-4k-instruct-q4f16_1-MLC")

// Create service
val service = provider?.createLLMService(config)
```

**Direct Service Usage**:
```kotlin
val config = LLMConfiguration(
    modelId = "/sdcard/models/phi-3-mini-mlc",
    contextLength = 4096,
    temperature = 0.7,
    maxTokens = 256,
    frameworkOptions = mapOf(
        "modelLib" to "phi_msft_q4f16_1_686d8979"
    )
)

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

### 9.2 Streaming APIs

**Token-by-token streaming**:
```kotlin
service.streamGenerate(prompt, options) { token ->
    // Called for each token
    print(token)
}
```

**Flow-based streaming**:
```kotlin
service.streamProcess(input).collect { chunk ->
    print(chunk.text)
    if (chunk.isComplete) {
        println("\nGeneration complete")
    }
}
```

### 9.3 Multi-Turn Conversation

```kotlin
val messages = mutableListOf<Message>()

// Turn 1
messages.add(Message(MessageRole.USER, "What is 2+2?"))
val output1 = service.process(LLMInput(messages = messages))
messages.add(Message(MessageRole.ASSISTANT, output1.text))

// Turn 2
messages.add(Message(MessageRole.USER, "What about 3+3?"))
val output2 = service.process(LLMInput(messages = messages))
messages.add(Message(MessageRole.ASSISTANT, output2.text))
```

### 9.4 Multi-Modal (Image + Text)

```kotlin
// Build multi-modal content
val content = ChatCompletionMessageContent(
    parts = listOf(
        mapOf("type" to "text", "text" to "What's in this image?"),
        mapOf("type" to "image_url", "image_url" to imageBase64Url)
    )
)

val messages = listOf(
    ChatCompletionMessage(
        role = ChatCompletionRole.user,
        content = content
    )
)

// Generate response
val channel = engine.chat.completions.create(
    messages = messages,
    stream_options = StreamOptions(include_usage = true)
)

for (response in channel) {
    // Handle response...
}
```

---

## 10. Integration Points

### 10.1 ModuleRegistry Integration

```kotlin
// Registration
ModuleRegistry.shared.registerLLM(mlcProvider)

// Access
val provider = ModuleRegistry.llmProvider("model-mlc")
val provider = ModuleRegistry.llmProvider(LLMFramework.MLC_LLM)
```

### 10.2 EventBus Integration

```kotlin
// Publish events during initialization
EventBus.publish(ComponentInitializationEvent.ComponentReady(
    component = SDKComponent.LLM,
    modelId = modelPath
))

// Publish generation events
EventBus.publish(LLMGenerationEvent.GenerationStarted(
    modelId = currentModel,
    prompt = prompt
))

EventBus.publish(LLMGenerationEvent.GenerationCompleted(
    modelId = currentModel,
    tokensGenerated = tokenCount,
    duration = duration
))
```

### 10.3 Configuration Service Integration

```kotlin
// Load configuration from ConfigurationService
val configService = ServiceContainer.shared.configurationService
val mlcConfig = configService.getComponentConfiguration("mlc-llm")

// Apply configuration to service
val service = MLCService(mlcConfig)
```

### 10.4 Analytics Integration

```kotlin
// Track model load
AnalyticsService.trackEvent("mlc_model_loaded", mapOf(
    "model_id" to modelId,
    "model_size_mb" to modelSizeMB,
    "load_time_ms" to loadTime
))

// Track generation performance
AnalyticsService.trackEvent("mlc_generation", mapOf(
    "model_id" to modelId,
    "tokens_generated" to tokenCount,
    "tokens_per_second" to tokensPerSecond,
    "duration_ms" to duration
))
```

---

## 11. Dependencies & Native Libraries

### 11.1 Dependency Acquisition

**Option 1: Pre-built mlc4j from MLC-LLM Release**

1. Download from MLC-LLM releases: https://github.com/mlc-ai/mlc-llm
2. Extract `mlc4j` directory containing:
   - `tvm4j_core.jar`
   - `{ABI}/libtvm4j_runtime_packed.so`
3. Copy to `modules/runanywhere-llm-mlc/libs/mlc4j/`

**Option 2: Build from Source**

```bash
# Clone MLC-LLM
cd EXTERNAL
git clone https://github.com/mlc-ai/mlc-llm.git
cd mlc-llm

# Build mlc4j
cd android/mlc4j
./gradlew build

# Copy outputs
cp build/libs/*.jar ../../sdk/runanywhere-kotlin/modules/runanywhere-llm-mlc/libs/mlc4j/
cp build/outputs/jniLibs/* ../../sdk/runanywhere-kotlin/modules/runanywhere-llm-mlc/libs/mlc4j/
```

### 11.2 Library Structure

```
libs/mlc4j/
├── tvm4j_core.jar                    # TVM Java bindings
├── arm64-v8a/                        # 64-bit ARM (primary target)
│   └── libtvm4j_runtime_packed.so
└── armeabi-v7a/                      # 32-bit ARM (optional)
    └── libtvm4j_runtime_packed.so
```

### 11.3 Version Management

**Recommended Versions**:
- MLC-LLM: 0.1.0+ (latest stable)
- TVM: Built with MLC-LLM (bundled)
- Minimum Android SDK: 24 (Android 5.1)

**Version Tracking**:
```kotlin
// In MLCModule.kt
object MLCModule {
    val version: String = "0.1.0"
    val mlcLLMVersion: String = "0.1.0"  // MLC-LLM native library version
    val tvmVersion: String = "0.13.0"    // TVM version (bundled with MLC)
}
```

### 11.4 License Compliance

**MLC-LLM License**: Apache 2.0
**TVM License**: Apache 2.0

Ensure compliance by:
1. Including LICENSE files in module
2. Attributing in documentation
3. Not modifying native libraries (use as-is)

---

## 12. Testing Strategy

### 12.1 Unit Tests

**Location**: `src/commonTest/kotlin/com/runanywhere/sdk/llm/mlc/`

```kotlin
// MLCProviderTest.kt
class MLCProviderTest {

    @Test
    fun `canHandle should detect MLC models`() {
        val provider = MLCProvider()

        assertTrue(provider.canHandle("Phi-3-mini-4k-instruct-q4f16_1-MLC"))
        assertTrue(provider.canHandle("model-mlc-chat"))
        assertTrue(provider.canHandle("llama-3-mlc-compiled"))
        assertFalse(provider.canHandle("model.gguf"))
    }

    @Test
    fun `should declare correct features`() {
        val provider = MLCProvider()

        assertTrue(provider.supportedFeatures.contains("streaming"))
        assertTrue(provider.supportedFeatures.contains("gpu-acceleration-opencl"))
        assertTrue(provider.supportedFeatures.contains("multi-modal-text-image"))
    }

    @Test
    fun `estimateMemoryRequirements should be reasonable`() {
        val provider = MLCProvider()
        val model = ModelInfo(
            id = "test-model",
            name = "Test Model",
            parameters = 3_000_000_000L,  // 3B parameters
            contextLength = 4096
        )

        val memory = provider.estimateMemoryRequirements(model)
        val memoryMB = memory / 1024 / 1024

        // 3B params * 2 bytes (q4) = ~6GB + context overhead
        assertTrue(memoryMB in 6000..8000)
    }
}

// MLCServiceTest.kt
class MLCServiceTest {

    @Test
    fun `should initialize successfully with valid config`() = runTest {
        // This test requires native library - mark as @Ignore if not available
        val config = LLMConfiguration(
            modelId = "/path/to/test-model",
            frameworkOptions = mapOf("modelLib" to "test_lib")
        )
        val service = MLCService(config)

        // Test initialization (will throw if library not available)
        try {
            service.initialize()
            assertTrue(service.isReady)
        } catch (e: UnsatisfiedLinkError) {
            // Expected if native lib not available in test environment
            println("Native library not available in test environment")
        }
    }

    @Test
    fun `should throw error if not initialized`() = runTest {
        val config = LLMConfiguration(modelId = "/path/to/model")
        val service = MLCService(config)

        assertFailsWith<IllegalStateException> {
            service.generate("test", RunAnywhereGenerationOptions())
        }
    }
}
```

### 12.2 Integration Tests

**Location**: `src/androidUnitTest/kotlin/com/runanywhere/sdk/llm/mlc/`

```kotlin
// MLCIntegrationTest.kt
class MLCIntegrationTest {

    @Test
    fun `should register with ModuleRegistry`() {
        // Clear registry first
        ModuleRegistry.clear()

        // Register
        MLCModule.register()

        // Verify registration (only if native lib available)
        if (MLCModule.isAvailable) {
            assertTrue(ModuleRegistry.hasLLM)

            val provider = ModuleRegistry.llmProvider("test-mlc")
            assertNotNull(provider)
            assertEquals("MLC-LLM", provider.name)
        }
    }

    @Test
    fun `should create service via provider`() = runTest {
        MLCModule.register()

        if (!MLCModule.isAvailable) {
            println("MLC module not available, skipping test")
            return@runTest
        }

        val provider = ModuleRegistry.llmProvider("test-mlc")
        assertNotNull(provider)

        val config = LLMConfiguration(
            modelId = "/path/to/model",
            frameworkOptions = mapOf("modelLib" to "test_lib")
        )

        val service = provider.createLLMService(config)
        assertNotNull(service)
        assertTrue(service is MLCService)
    }
}
```

### 12.3 Model Loading Tests

```kotlin
@Test
fun `should load model successfully`() = runTest {
    // Requires actual model file
    val modelPath = "/sdcard/test-models/phi-3-mini-mlc"
    val modelLib = "phi_msft_q4f16_1"

    if (!File(modelPath).exists()) {
        println("Test model not found, skipping")
        return@runTest
    }

    val config = LLMConfiguration(
        modelId = modelPath,
        frameworkOptions = mapOf("modelLib" to modelLib)
    )

    val service = MLCService(config)
    service.initialize()

    assertTrue(service.isReady)
    assertEquals("phi-3-mini-mlc", service.currentModel)

    service.cleanup()
}
```

### 12.4 Streaming Tests

```kotlin
@Test
fun `should stream tokens correctly`() = runTest {
    val service = createInitializedService()  // Helper function

    val tokens = mutableListOf<String>()
    val options = RunAnywhereGenerationOptions(
        maxTokens = 20,
        temperature = 0.7f
    )

    service.streamGenerate("Count to 5:", options) { token ->
        tokens.add(token)
    }

    assertTrue(tokens.isNotEmpty())
    assertTrue(tokens.size <= 20)

    service.cleanup()
}

@Test
fun `should support cancellation`() = runTest {
    val service = createInitializedService()

    val job = launch {
        service.streamGenerate("Generate a very long story...", options) { token ->
            delay(10)  // Simulate processing
        }
    }

    delay(100)  // Let it start
    service.cancelCurrent()
    job.join()

    // Should complete without error
    assertTrue(true)
}
```

### 12.5 Performance Tests

```kotlin
@Test
fun `should achieve reasonable token throughput`() = runTest {
    val service = createInitializedService()

    val options = RunAnywhereGenerationOptions(maxTokens = 100)
    var tokenCount = 0
    val startTime = System.currentTimeMillis()

    service.streamGenerate("Generate some text", options) { token ->
        tokenCount++
    }

    val duration = System.currentTimeMillis() - startTime
    val tokensPerSecond = (tokenCount.toDouble() * 1000.0) / duration

    println("Performance: $tokensPerSecond tokens/sec")

    // Expect at least 5 tokens/sec on modern devices
    assertTrue(tokensPerSecond >= 5.0)
}
```

---

## 13. Example Usage

### 13.1 Basic Usage

```kotlin
import com.runanywhere.sdk.llm.mlc.*
import com.runanywhere.sdk.components.llm.LLMConfiguration
import com.runanywhere.sdk.models.RunAnywhereGenerationOptions
import kotlinx.coroutines.runBlocking

fun main() = runBlocking {
    // 1. Create configuration
    val config = LLMConfiguration(
        modelId = "/sdcard/models/Phi-3-mini-4k-instruct-q4f16_1-MLC",
        contextLength = 4096,
        temperature = 0.7,
        maxTokens = 256,
        frameworkOptions = mapOf(
            "modelLib" to "phi_msft_q4f16_1_686d8979c6ebf05d142d9081f1b87162"
        )
    )

    // 2. Create service
    val service = MLCService(config)

    // 3. Initialize
    service.initialize()
    println("Model ready: ${service.isReady}")

    // 4. Generate text (non-streaming)
    val options = RunAnywhereGenerationOptions(
        maxTokens = 100,
        temperature = 0.7f
    )

    val response = service.generate("What is the capital of France?", options)
    println("Response: $response")

    // 5. Cleanup
    service.cleanup()
}
```

### 13.2 Streaming Generation

```kotlin
fun streamingExample() = runBlocking {
    val config = LLMConfiguration(
        modelId = "/sdcard/models/phi-3-mini-mlc",
        frameworkOptions = mapOf("modelLib" to "phi_msft_q4f16_1")
    )

    val service = MLCService(config)
    service.initialize()

    val options = RunAnywhereGenerationOptions(
        maxTokens = 256,
        temperature = 0.8f
    )

    println("Generating...")
    service.streamGenerate("Write a short poem about coding:", options) { token ->
        print(token)  // Print each token as it arrives
    }
    println("\n\nGeneration complete!")

    service.cleanup()
}
```

### 13.3 Multi-Turn Conversation

```kotlin
fun conversationExample() = runBlocking {
    val service = MLCService(configuration)
    service.initialize()

    val conversation = mutableListOf<Message>()

    // Turn 1
    conversation.add(Message(MessageRole.USER, "Hello! Who are you?"))
    val input1 = LLMInput(
        messages = conversation,
        systemPrompt = "You are a helpful AI assistant."
    )
    val output1 = service.process(input1)
    conversation.add(Message(MessageRole.ASSISTANT, output1.text))
    println("Assistant: ${output1.text}")

    // Turn 2
    conversation.add(Message(MessageRole.USER, "What can you help me with?"))
    val input2 = LLMInput(messages = conversation)
    val output2 = service.process(input2)
    conversation.add(Message(MessageRole.ASSISTANT, output2.text))
    println("Assistant: ${output2.text}")

    println("Stats: ${output2.metadata.tokensPerSecond} tok/s")

    service.cleanup()
}
```

### 13.4 Streaming with Flow

```kotlin
fun flowStreamingExample() = runBlocking {
    val service = MLCService(configuration)
    service.initialize()

    val input = LLMInput(
        messages = listOf(Message(MessageRole.USER, "Explain quantum computing in simple terms"))
    )

    service.streamProcess(input).collect { chunk ->
        print(chunk.text)

        if (chunk.isComplete) {
            println("\n\nGeneration complete at chunk ${chunk.chunkIndex}")
        }
    }

    service.cleanup()
}
```

### 13.5 Via ModuleRegistry

```kotlin
fun registryExample() = runBlocking {
    // Register module (happens automatically on classpath)
    MLCModule.register()

    // Get provider
    val provider = ModuleRegistry.llmProvider("phi-3-mini-mlc")
    requireNotNull(provider) { "MLC provider not available" }

    // Create service via provider
    val config = LLMConfiguration(
        modelId = "/sdcard/models/phi-3-mini-mlc",
        frameworkOptions = mapOf("modelLib" to "phi_msft_q4f16_1")
    )

    val service = provider.createLLMService(config)
    service.initialize()

    // Use service
    val response = service.generate("Hello!", options)
    println(response)

    service.cleanup()
}
```

### 13.6 Complete Android Activity Example

```kotlin
class MLCDemoActivity : AppCompatActivity() {

    private lateinit var service: MLCService
    private val viewModel: MLCViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Check if MLC is available
        if (!MLCModule.isAvailable) {
            Toast.makeText(this, "MLC-LLM not available", Toast.LENGTH_LONG).show()
            finish()
            return
        }

        // Register module
        MLCModule.register()

        // Initialize service
        val modelPath = File(getExternalFilesDir(null), "Phi-3-mini-4k-instruct-q4f16_1-MLC").absolutePath
        val config = LLMConfiguration(
            modelId = modelPath,
            contextLength = 4096,
            temperature = 0.7,
            frameworkOptions = mapOf(
                "modelLib" to "phi_msft_q4f16_1_686d8979c6ebf05d142d9081f1b87162"
            )
        )

        service = MLCService(config)

        // Initialize in background
        lifecycleScope.launch {
            try {
                withContext(Dispatchers.IO) {
                    service.initialize()
                }
                Toast.makeText(this@MLCDemoActivity, "Model loaded", Toast.LENGTH_SHORT).show()
            } catch (e: Exception) {
                Toast.makeText(this@MLCDemoActivity, "Failed to load model: ${e.message}", Toast.LENGTH_LONG).show()
            }
        }
    }

    fun generateText(prompt: String) {
        lifecycleScope.launch {
            viewModel.responseText.value = ""

            val options = RunAnywhereGenerationOptions(
                maxTokens = 256,
                temperature = 0.7f
            )

            withContext(Dispatchers.IO) {
                service.streamGenerate(prompt, options) { token ->
                    lifecycleScope.launch(Dispatchers.Main) {
                        viewModel.responseText.value += token
                    }
                }
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        lifecycleScope.launch {
            withContext(Dispatchers.IO) {
                service.cleanup()
            }
        }
    }
}
```

---

## 14. Documentation Requirements

### 14.1 Module README.md

**Location**: `modules/runanywhere-llm-mlc/README.md`

```markdown
# MLC-LLM Module for RunAnywhere SDK

On-device LLM inference using MLC-LLM framework with GPU acceleration.

## Features

- **GPU Acceleration**: Leverages OpenCL for mobile GPU acceleration
- **Streaming Generation**: Token-by-token generation via Kotlin Flow
- **Multi-Modal Support**: Text and image inputs for vision-language models
- **Production-Ready**: Comprehensive error handling, logging, and resource management
- **Auto-Registration**: Seamlessly integrates via ModuleRegistry

## Requirements

- Android API 24+ (Android 5.1 Lollipop)
- Minimum 4GB RAM
- OpenCL support (recommended for GPU acceleration)
- MLC-compiled model files

## Installation

### Gradle (Kotlin DSL)

```kotlin
dependencies {
    implementation("com.runanywhere.sdk:runanywhere-llm-mlc:0.1.0")
}
```

### Maven

```xml
<dependency>
    <groupId>com.runanywhere.sdk</groupId>
    <artifactId>runanywhere-llm-mlc</artifactId>
    <version>0.1.0</version>
</dependency>
```

## Quick Start

```kotlin
// 1. Create configuration
val config = LLMConfiguration(
    modelId = "/sdcard/models/Phi-3-mini-4k-instruct-q4f16_1-MLC",
    contextLength = 4096,
    temperature = 0.7,
    frameworkOptions = mapOf(
        "modelLib" to "phi_msft_q4f16_1_686d8979"
    )
)

// 2. Create service
val service = MLCService(config)

// 3. Initialize
service.initialize()

// 4. Generate
val response = service.generate("Hello!", options)

// 5. Cleanup
service.cleanup()
```

## Model Support

### Supported Model Formats

- MLC-compiled models (`.mlc`, `-MLC` suffix)
- TVM-compiled models

### Supported Architectures

- Phi-3 series
- Llama 3.x
- Mistral 7B
- Qwen series
- Gemma series
- LLaVA (vision-language models)

### Obtaining Models

1. **Pre-compiled Models**: Download from [MLC-LLM Model Zoo](https://huggingface.co/mlc-ai)
2. **Compile Your Own**: Use MLC-LLM's model compiler (see [documentation](https://mlc.ai/mlc-llm/docs/compilation/compile_models.html))

## Usage Examples

### Streaming Generation

```kotlin
service.streamGenerate(prompt, options) { token ->
    print(token)  // Called for each token
}
```

### Multi-Turn Conversation

```kotlin
val messages = mutableListOf<Message>()
messages.add(Message(MessageRole.USER, "What is 2+2?"))
val output1 = service.process(LLMInput(messages = messages))
messages.add(Message(MessageRole.ASSISTANT, output1.text))

messages.add(Message(MessageRole.USER, "What about 3+3?"))
val output2 = service.process(LLMInput(messages = messages))
```

### Flow-Based Streaming

```kotlin
service.streamProcess(input).collect { chunk ->
    print(chunk.text)
    if (chunk.isComplete) {
        println("\nDone!")
    }
}
```

## Configuration Options

### Basic Configuration

```kotlin
LLMConfiguration(
    modelId: String,                  // Path to model directory
    contextLength: Int = 4096,        // Context window size
    temperature: Double = 0.7,        // Sampling temperature
    maxTokens: Int = 256,             // Max generation length
)
```

### MLC-Specific Options (frameworkOptions)

| Option | Type | Description | Default |
|--------|------|-------------|---------|
| `modelLib` | String | Model library name (required) | - |
| `deviceType` | String | "opencl" or "cpu" | "opencl" |
| `prefillChunkSize` | Int | Chunk size for prompt processing | 512 |
| `slidingWindowSize` | Int | Sliding window attention size | null |

### Example with All Options

```kotlin
val config = LLMConfiguration(
    modelId = "/sdcard/models/phi-3-mini-mlc",
    contextLength = 4096,
    temperature = 0.7,
    maxTokens = 512,
    useGPUIfAvailable = true,
    frameworkOptions = mapOf(
        "modelLib" to "phi_msft_q4f16_1",
        "deviceType" to "opencl",
        "prefillChunkSize" to 512,
        "slidingWindowSize" to 768
    )
)
```

## Performance

### Benchmarks (Pixel 6 Pro)

| Model | Size | Context | Tokens/sec | Memory |
|-------|------|---------|-----------|--------|
| Phi-3-mini-4k (q4f16_1) | 2.3GB | 4k | 15-20 | 3.5GB |
| Llama-3-8B (q4f16_1) | 4.5GB | 8k | 8-12 | 6GB |
| Mistral-7B (q4f16_1) | 4.1GB | 8k | 10-15 | 5.5GB |

### Optimization Tips

1. **Use GPU**: Ensure OpenCL is available for 3-5x speedup
2. **Quantization**: Use q4f16_1 quantization for best size/quality tradeoff
3. **Context Length**: Smaller contexts = faster inference
4. **Prefill Chunk**: Adjust `prefillChunkSize` based on context length

## Troubleshooting

### "Model lib must be specified"

**Solution**: Add `modelLib` to `frameworkOptions`:

```kotlin
frameworkOptions = mapOf(
    "modelLib" to "your_model_lib_name"
)
```

Find the model lib name in your model's `mlc-chat-config.json` file.

### "Native library not found"

**Solution**: Ensure `libtvm4j_runtime_packed.so` is included in your APK:

1. Check `libs/mlc4j/{ABI}/libtvm4j_runtime_packed.so` exists
2. Verify `jniLibs.srcDirs` in `build.gradle.kts`
3. Clean and rebuild

### Out of Memory

**Solution**:

1. Use a smaller model (fewer parameters)
2. Reduce context length
3. Close other apps
4. Use higher quantization (q4 instead of q8)

## API Reference

See [API Documentation](./docs/api.md) for complete API reference.

## License

Apache License 2.0

See [LICENSE](./LICENSE) for details.

## Credits

Built on top of:
- [MLC-LLM](https://github.com/mlc-ai/mlc-llm) - Apache 2.0 License
- [Apache TVM](https://tvm.apache.org/) - Apache 2.0 License
```

### 14.2 KDoc Documentation

All public classes and methods should have comprehensive KDoc:

```kotlin
/**
 * MLC-LLM Service for on-device inference
 *
 * Provides high-performance LLM inference using MLC-compiled models with GPU acceleration.
 * Supports streaming generation, multi-turn conversations, and multi-modal inputs.
 *
 * ## Usage
 *
 * ```kotlin
 * val config = LLMConfiguration(
 *     modelId = "/path/to/model",
 *     frameworkOptions = mapOf("modelLib" to "model_lib_name")
 * )
 *
 * val service = MLCService(config)
 * service.initialize()
 * val response = service.generate("Hello!", options)
 * service.cleanup()
 * ```
 *
 * ## Requirements
 *
 * - MLC-compiled model files
 * - Model library name (modelLib) in configuration
 * - Minimum Android API 24
 *
 * @property configuration LLM configuration including model path and parameters
 * @constructor Creates a new MLC service instance. Call [initialize] before use.
 *
 * @see LLMConfiguration
 * @see EnhancedLLMService
 */
actual class MLCService actual constructor(
    private val configuration: LLMConfiguration
) : EnhancedLLMService {

    /**
     * Initialize the service and load the model
     *
     * Loads the MLC-compiled model and prepares it for inference.
     * This is a blocking operation that may take several seconds.
     *
     * @param modelPath Optional path to model directory. If null, uses [configuration.modelId]
     * @throws IllegalArgumentException if no model path is provided
     * @throws IllegalStateException if model loading fails
     *
     * ## Example
     *
     * ```kotlin
     * service.initialize("/sdcard/models/phi-3-mini-mlc")
     * ```
     */
    actual override suspend fun initialize(modelPath: String?)

    // ... more KDoc for each method
}
```

### 14.3 Integration Guide

Create `docs/INTEGRATION_GUIDE.md` with:

1. **Setup Instructions**: Step-by-step integration
2. **Model Preparation**: How to obtain and prepare models
3. **Configuration Guide**: All configuration options explained
4. **Best Practices**: Performance optimization, error handling
5. **Common Patterns**: Example code for common use cases
6. **Troubleshooting**: Common issues and solutions

---

## 15. Implementation Phases

### Phase 1: Basic Structure and Build Setup (Week 1)

**Goal**: Module builds successfully, native library loading works

**Tasks**:
- [ ] Create module directory structure
- [ ] Set up `build.gradle.kts`
- [ ] Add to `settings.gradle.kts`
- [ ] Obtain mlc4j library files (JAR + .so)
- [ ] Place in `libs/mlc4j/`
- [ ] Test build: `./gradlew :modules:runanywhere-llm-mlc:build`
- [ ] Test native lib loading

**Deliverables**:
- Module builds without errors
- Native library loads successfully
- Basic project structure in place

### Phase 2: Provider and Service Skeleton (Week 1-2)

**Goal**: Module registers with ModuleRegistry, service can be created

**Tasks**:
- [ ] Implement `MLCModule.kt` (auto-registration)
- [ ] Implement `MLCModuleActual.kt` (checkNativeLibraryAvailable)
- [ ] Implement `MLCProvider.kt` (canHandle, features, etc.)
- [ ] Create `MLCService.kt` expect declaration
- [ ] Create `MLCService.kt` actual skeleton (empty methods)
- [ ] Test registration flow
- [ ] Write unit tests for provider

**Deliverables**:
- Module auto-registers on classpath inclusion
- Provider detected by ModuleRegistry
- Service can be instantiated (but not functional yet)
- Unit tests pass

### Phase 3: MLC Engine Integration (Week 2-3)

**Goal**: Basic model loading and generation works

**Tasks**:
- [ ] Implement `MLCEngine.kt` wrapper
- [ ] Implement `MLCService.initialize()`
- [ ] Implement `MLCService.generate()` (non-streaming)
- [ ] Test with a small model (e.g., Phi-3-mini)
- [ ] Add proper error handling
- [ ] Add logging throughout
- [ ] Implement `MLCService.cleanup()`

**Deliverables**:
- Can load and unload models
- Basic text generation works
- Error handling is robust
- Resource cleanup works correctly

### Phase 4: Streaming Implementation (Week 3-4)

**Goal**: Streaming generation via Flow works

**Tasks**:
- [ ] Implement `MLCService.streamGenerate()`
- [ ] Implement `MLCService.streamProcess()` (Flow-based)
- [ ] Map MLC responses to SDK types
- [ ] Handle cancellation
- [ ] Add performance metrics (tokens/sec)
- [ ] Test streaming with various prompts
- [ ] Write streaming unit tests

**Deliverables**:
- Token-by-token streaming works
- Flow-based API works
- Cancellation works
- Performance is acceptable (>5 tok/s)

### Phase 5: Enhanced Features (Week 4-5)

**Goal**: All EnhancedLLMService features implemented

**Tasks**:
- [ ] Implement `process()` with structured I/O
- [ ] Implement `loadModel()` with ModelInfo
- [ ] Implement `cancelCurrent()`
- [ ] Implement `getTokenCount()`
- [ ] Implement `fitsInContext()`
- [ ] Add multi-turn conversation support
- [ ] Test all features
- [ ] Write integration tests

**Deliverables**:
- All interface methods implemented
- Multi-turn conversations work
- Token counting is reasonable
- Integration tests pass

### Phase 6: Testing and Refinement (Week 5-6)

**Goal**: Production-ready quality

**Tasks**:
- [ ] Complete unit test coverage (>80%)
- [ ] Complete integration tests
- [ ] Performance testing and optimization
- [ ] Memory leak testing
- [ ] Error scenario testing
- [ ] Documentation review
- [ ] Code review and refactoring

**Deliverables**:
- All tests pass
- No memory leaks
- Performance is acceptable
- Documentation is complete
- Code is clean and maintainable

### Phase 7: Documentation and Examples (Week 6)

**Goal**: Module is documented and easy to use

**Tasks**:
- [ ] Complete README.md
- [ ] Complete KDoc for all public APIs
- [ ] Write INTEGRATION_GUIDE.md
- [ ] Create example applications
- [ ] Create troubleshooting guide
- [ ] Update main SDK documentation

**Deliverables**:
- Complete documentation
- Working examples
- Integration guide
- Troubleshooting guide

---

## 16. Key Differences from LlamaCPP

### 16.1 Model Format

| Aspect | LlamaCPP | MLC-LLM |
|--------|----------|---------|
| **Format** | GGUF, GGML | MLC-compiled (TVM) |
| **Detection** | `.gguf`, `.ggml` extensions | `-MLC` suffix, `mlc-` prefix |
| **Preparation** | Models are ready to use | Requires compilation step |
| **Portability** | Cross-platform (same file) | Platform-specific compilation |

**Implication**: MLC requires explicit model lib specification, LlamaCPP doesn't.

### 16.2 GPU Acceleration

| Aspect | LlamaCPP | MLC-LLM |
|--------|----------|---------|
| **Backend** | CPU-focused (Vulkan optional) | GPU-first (OpenCL) |
| **Configuration** | Optional GPU layers | GPU by default |
| **Performance** | Good on CPU | Excellent with GPU, slower on CPU |
| **Fallback** | Automatic | Automatic (CPU if no OpenCL) |

**Implication**: MLC benefits more from GPU, should check OpenCL availability.

### 16.3 Threading Model

| Aspect | LlamaCPP | MLC-LLM |
|--------|----------|---------|
| **Native Threads** | Manual management | Built-in (2 background threads) |
| **Kotlin Dispatcher** | Custom CoroutineDispatcher | Use Dispatchers.IO |
| **Thread Safety** | Manual synchronization | Built-in thread safety |

**Implication**: MLC is easier to integrate, less manual thread management.

### 16.4 Streaming API

| Aspect | LlamaCPP | MLC-LLM |
|--------|----------|---------|
| **Native API** | Token-by-token callback | OpenAI-style streaming |
| **Kotlin API** | Flow<String> | Channel<ChatCompletionStreamResponse> |
| **Response Format** | Raw token strings | Structured responses with metadata |

**Implication**: MLC provides richer response data out-of-the-box.

### 16.5 Configuration

| Aspect | LlamaCPP | MLC-LLM |
|--------|----------|---------|
| **Model Path** | Direct file path | Directory + modelLib |
| **Context Config** | Set at load time | Set in frameworkOptions |
| **Sampling** | Manual sampler creation | Automatic via temperature/top_p |

**Implication**: MLC is more automated, fewer manual configuration steps.

### 16.6 Source Set Organization

| Aspect | LlamaCPP | MLC-LLM |
|--------|----------|---------|
| **Source Sets** | `jvmAndroidMain` (shared) | `androidMain` (Android-only) |
| **JVM Support** | Yes (via JNI) | No (mobile-only) |
| **Native Build** | CMake external build | Pre-built libraries |

**Implication**: MLC is simpler (no CMake needed), but Android-only.

---

## 17. Potential Challenges & Solutions

### Challenge 1: Native Library Packaging

**Problem**: Native libraries (.so files) must be correctly packaged in the AAR

**Solution**:
1. Place libraries in `libs/mlc4j/{ABI}/` directory
2. Configure `jniLibs.srcDirs` in `build.gradle.kts`:
   ```kotlin
   sourceSets {
       getByName("main") {
           jniLibs.srcDirs("libs/mlc4j")
       }
   }
   ```
3. Test with: `./gradlew :modules:runanywhere-llm-mlc:assembleDebug`
4. Verify .so files are in AAR: `unzip -l build/outputs/aar/*.aar`

### Challenge 2: Model Lib Inference

**Problem**: MLC requires explicit model lib name, which isn't obvious from model path

**Solution**:
1. **Require explicit specification**: Make `modelLib` mandatory in `frameworkOptions`
2. **Parse from config**: Read from model's `mlc-chat-config.json` file:
   ```kotlin
   fun readModelLib(modelPath: String): String {
       val configFile = File(modelPath, "mlc-chat-config.json")
       val json = Json.parseToJsonElement(configFile.readText()).jsonObject
       return json["model_lib"]?.jsonPrimitive?.content
           ?: throw IllegalArgumentException("model_lib not found in config")
   }
   ```
3. **Document clearly**: Emphasize in docs that modelLib is required

### Challenge 3: Thread Safety

**Problem**: MLC engine manages its own threads, potential race conditions

**Solution**:
1. Use `synchronized` blocks in `MLCEngine` wrapper
2. Single instance pattern (singleton) for engine
3. Use `Dispatchers.IO` for all service methods
4. Test with concurrent requests

### Challenge 4: Memory Management

**Problem**: Large models can cause OOM errors on low-memory devices

**Solution**:
1. Memory estimation in provider's `validateModelCompatibility()`
2. Check available memory before loading:
   ```kotlin
   val availableMemory = Runtime.getRuntime().maxMemory()
   val required = provider.estimateMemoryRequirements(model)
   if (required > availableMemory * 0.8) {
       throw OutOfMemoryError("Insufficient memory for model")
   }
   ```
3. Proper cleanup in `service.cleanup()`
4. Test with large models on low-memory devices

### Challenge 5: JVM Support Limitations

**Problem**: MLC-LLM is primarily for mobile, JVM support unclear

**Solution**:
1. Use `androidMain` instead of `jvmAndroidMain`
2. Document as Android-only
3. If JVM support needed later, can add `jvmMain` with stubs:
   ```kotlin
   // jvmMain/MLCService.kt
   actual class MLCService actual constructor(config: LLMConfiguration) {
       init {
           throw UnsupportedOperationException(
               "MLC-LLM is only supported on Android"
           )
       }
   }
   ```

### Challenge 6: Model Compilation

**Problem**: Users need MLC-compiled models, not all models are pre-compiled

**Solution**:
1. **Document sources**: Point to MLC-AI HuggingFace (pre-compiled models)
2. **Compilation guide**: Link to MLC-LLM docs for compiling custom models
3. **Model validation**: Check for required files in `validateModelCompatibility()`:
   ```kotlin
   fun validateModelFiles(modelPath: String): Boolean {
       val requiredFiles = listOf(
           "mlc-chat-config.json",
           "params_shard_0.bin",
           "tokenizer.json"
       )
       return requiredFiles.all { File(modelPath, it).exists() }
   }
   ```

### Challenge 7: OpenCL Availability

**Problem**: Not all Android devices support OpenCL

**Solution**:
1. Check availability at runtime:
   ```kotlin
   actual fun checkOpenCLAvailable(): Boolean {
       return try {
           // Attempt to create OpenCL device
           val device = Device.opencl()
           true
       } catch (e: Exception) {
           false
       }
   }
   ```
2. Graceful fallback to CPU
3. Warn user if OpenCL not available:
   ```kotlin
   if (!checkOpenCLAvailable()) {
       logger.warn("OpenCL not available, falling back to CPU (slower)")
   }
   ```
4. Document performance expectations for CPU-only

### Challenge 8: Error Messages from Native Layer

**Problem**: Native errors may be cryptic or not surfaced properly

**Solution**:
1. Wrap all native calls in try-catch:
   ```kotlin
   try {
       engine.reload(modelPath, modelLib)
   } catch (e: Exception) {
       logger.error("Native error during reload", e)
       throw IllegalStateException(
           "Failed to load model: ${e.message}. " +
           "Check that model files are valid and modelLib is correct.",
           e
       )
   }
   ```
2. Add context to error messages
3. Log detailed error info
4. Provide troubleshooting hints in exceptions

### Challenge 9: Testing Without Models

**Problem**: Unit tests need models, but models are large (GB)

**Solution**:
1. **Mock provider tests**: Test provider logic without actual models
2. **Conditional integration tests**: Skip if model not available
   ```kotlin
   @Test
   fun testModelLoad() {
       assumeTrue("Model not available", File(modelPath).exists())
       // ... test code
   }
   ```
3. **Mock service**: Create test doubles for integration tests
4. **Document test requirements**: Specify test model requirements in README

### Challenge 10: Version Compatibility

**Problem**: MLC-LLM and TVM versions must match

**Solution**:
1. **Bundle specific versions**: Use pre-built mlc4j from specific MLC release
2. **Version tracking**: Document versions in `MLCModule`:
   ```kotlin
   object MLCModule {
       val mlcLLMVersion = "0.1.0"
       val tvmVersion = "0.13.0"
   }
   ```
3. **Version checks**: Add runtime version check if API provides it
4. **Clear documentation**: Specify compatible versions in README

---

## 18. Complete File Checklist

### Module Structure

```
☐ modules/runanywhere-llm-mlc/build.gradle.kts
   Purpose: Module build configuration (KMP, Android, dependencies)

☐ modules/runanywhere-llm-mlc/proguard-rules.pro
   Purpose: ProGuard rules for native libraries and TVM classes

☐ modules/runanywhere-llm-mlc/README.md
   Purpose: Module documentation and usage guide

☐ modules/runanywhere-llm-mlc/LICENSE
   Purpose: Apache 2.0 license file

☐ modules/runanywhere-llm-mlc/NOTICES
   Purpose: Third-party licenses (MLC-LLM, TVM)
```

### Source Files - commonMain

```
☐ src/commonMain/kotlin/com/runanywhere/sdk/llm/mlc/MLCModule.kt
   Purpose: AutoRegisteringModule implementation, module entry point

☐ src/commonMain/kotlin/com/runanywhere/sdk/llm/mlc/MLCProvider.kt
   Purpose: LLMServiceProvider implementation (model detection, features)

☐ src/commonMain/kotlin/com/runanywhere/sdk/llm/mlc/MLCService.kt
   Purpose: expect class declaration for EnhancedLLMService
```

### Source Files - androidMain

```
☐ src/androidMain/kotlin/com/runanywhere/sdk/llm/mlc/MLCModuleActual.kt
   Purpose: actual fun checkNativeLibraryAvailable() implementation

☐ src/androidMain/kotlin/com/runanywhere/sdk/llm/mlc/MLCService.kt
   Purpose: actual class MLCService - main service implementation

☐ src/androidMain/kotlin/com/runanywhere/sdk/llm/mlc/MLCEngine.kt
   Purpose: Wrapper around native MLCEngine (mlc4j)
```

### Test Files - commonTest

```
☐ src/commonTest/kotlin/com/runanywhere/sdk/llm/mlc/MLCProviderTest.kt
   Purpose: Unit tests for MLCProvider (canHandle, features, etc.)

☐ src/commonTest/kotlin/com/runanywhere/sdk/llm/mlc/MLCModuleTest.kt
   Purpose: Unit tests for MLCModule (registration, availability)
```

### Test Files - androidUnitTest

```
☐ src/androidUnitTest/kotlin/com/runanywhere/sdk/llm/mlc/MLCServiceTest.kt
   Purpose: Unit tests for MLCService (initialization, generation)

☐ src/androidUnitTest/kotlin/com/runanywhere/sdk/llm/mlc/MLCIntegrationTest.kt
   Purpose: Integration tests with ModuleRegistry

☐ src/androidUnitTest/kotlin/com/runanywhere/sdk/llm/mlc/MLCStreamingTest.kt
   Purpose: Streaming generation tests

☐ src/androidUnitTest/kotlin/com/runanywhere/sdk/llm/mlc/MLCPerformanceTest.kt
   Purpose: Performance and benchmarking tests
```

### Documentation

```
☐ docs/INTEGRATION_GUIDE.md
   Purpose: Detailed integration instructions

☐ docs/API_REFERENCE.md
   Purpose: Complete API documentation

☐ docs/TROUBLESHOOTING.md
   Purpose: Common issues and solutions

☐ docs/MODEL_PREPARATION.md
   Purpose: How to obtain and prepare MLC models

☐ docs/PERFORMANCE.md
   Purpose: Performance benchmarks and optimization tips
```

### Native Libraries

```
☐ libs/mlc4j/tvm4j_core.jar
   Purpose: TVM Java bindings (from mlc4j build)

☐ libs/mlc4j/arm64-v8a/libtvm4j_runtime_packed.so
   Purpose: Native TVM runtime for 64-bit ARM

☐ libs/mlc4j/armeabi-v7a/libtvm4j_runtime_packed.so
   Purpose: Native TVM runtime for 32-bit ARM (optional)
```

### Build Configuration

```
☐ sdk/runanywhere-kotlin/settings.gradle.kts (UPDATE)
   Purpose: Include MLC module in build

☐ modules/runanywhere-llm-mlc/.gitignore
   Purpose: Exclude build artifacts, local files
```

### Example Applications (Optional)

```
☐ examples/android/mlc-demo/
   Purpose: Complete Android app demonstrating MLC-LLM usage

☐ examples/android/mlc-demo/app/src/main/java/.../MLCDemoActivity.kt
   Purpose: Main activity with model loading and generation

☐ examples/android/mlc-demo/app/src/main/java/.../MLCViewModel.kt
   Purpose: ViewModel for state management
```

---

## Summary

This implementation plan provides a comprehensive, actionable roadmap for creating the MLC-LLM module in the runanywhere-kotlin SDK. The plan follows the established architectural patterns from the LlamaCPP module while adapting to MLC-LLM's specific requirements.

**Key Success Factors**:

1. **Follow Established Patterns**: Replicate LlamaCPP's proven architecture
2. **Leverage MLC's Strengths**: GPU acceleration, streaming, OpenAI compatibility
3. **Comprehensive Testing**: Unit, integration, and performance tests
4. **Clear Documentation**: Make it easy for developers to use
5. **Robust Error Handling**: Graceful fallbacks and helpful error messages
6. **Phase-Based Approach**: Incremental development with clear milestones

**Estimated Timeline**: 6 weeks for full implementation and testing

**Next Steps**:
1. Review and approve this plan
2. Obtain mlc4j library files
3. Begin Phase 1: Basic structure and build setup

---

**Document Version**: 1.0
**Last Updated**: October 11, 2025
**Author**: Claude (Anthropic)
**Status**: Ready for Implementation
