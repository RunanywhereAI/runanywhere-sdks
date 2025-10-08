    # Kotlin SDK Text-to-Text Implementation Plan
## Alignment with Swift SDK - Detailed Roadmap

**Document Version:** 1.0
**Created:** 2025-10-08
**Target:** Achieve full text-to-text LLM parity with Swift SDK
**Architecture:** Monolithic Core + Thin Adapter Modules (Option 1)
**Estimated Timeline:** 12-15 days

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Architecture Overview](#architecture-overview)
3. [Phase 0: Module Structure Alignment](#phase-0-module-structure-alignment)
4. [Phase 1: SDK Initialization Parity](#phase-1-sdk-initialization-parity)
5. [Phase 2: Model Management Parity](#phase-2-model-management-parity)
6. [Phase 3: LLM Generation APIs Parity](#phase-3-llm-generation-apis-parity)
7. [Phase 4: LLM Component Architecture](#phase-4-llm-component-architecture)
8. [Phase 5: Testing & Validation](#phase-5-testing--validation)
9. [Implementation Checklist](#implementation-checklist)
10. [Success Criteria](#success-criteria)

---

## Executive Summary

### Current State
- **Kotlin SDK:** 85% complete, 8-step bootstrap, explicit initialization
- **Swift SDK:** 90% complete, 5-step init, lazy registration
- **Gap:** 47 differences across 8 priority levels (from gap analysis)

### Target State
- Kotlin SDK matches Swift SDK API surface 95%+ for text-to-text generation
- Module structure mirrors Swift (Core SDK + LlamaCpp adapter module)
- Simplified initialization (lazy registration option)
- Full feature parity for model management and LLM generation

### Key Changes
1. **Module Restructure:** Move LlamaCpp to separate adapter module
2. **Lazy Registration:** Add automatic device registration on first API call
3. **API Alignment:** Match Swift method signatures and parameter names
4. **Download Improvements:** Add checksum verification, enhanced progress
5. **Generation Options:** Align parameter sets between SDKs

### Timeline Overview

| Phase | Duration | Focus | Deliverable |
|-------|----------|-------|-------------|
| **Phase 0** | 2 days | Module structure | Separated modules, clean boundaries |
| **Phase 1** | 2 days | Initialization | Lazy registration working |
| **Phase 2** | 3 days | Model management | Download parity with Swift |
| **Phase 3** | 2 days | Generation APIs | API surface matches Swift |
| **Phase 4** | 2 days | Component architecture | LLMComponent refactored |
| **Phase 5** | 2 days | Testing | All features validated |
| **Total** | **13 days** | End-to-end | Production-ready SDK |

---

## Architecture Overview

### Target Architecture (Option 1: Monolithic Core + Thin Adapter Modules)

```
runanywhere-kotlin/                          # CORE SDK MODULE
├── build.gradle.kts                         # Core SDK build config
├── src/
│   ├── commonMain/kotlin/com/runanywhere/sdk/
│   │   ├── public/
│   │   │   └── RunAnywhere.kt               # ✅ Main SDK API (keep)
│   │   ├── components/
│   │   │   ├── base/
│   │   │   │   └── BaseComponent.kt         # ✅ Keep in core
│   │   │   ├── llm/
│   │   │   │   ├── LLMComponent.kt          # ✅ Keep (orchestrator)
│   │   │   │   ├── LLMService.kt            # ✅ Keep (interface)
│   │   │   │   ├── LLMServiceProvider.kt    # ✅ Keep (provider interface)
│   │   │   │   └── LLMConfiguration.kt      # ✅ Keep (config models)
│   │   │   ├── stt/                         # ⏸️ Keep for Phase 2
│   │   │   ├── vad/                         # ⏸️ Keep for Phase 2
│   │   │   └── tts/                         # ⏸️ Keep for Phase 2
│   │   ├── models/
│   │   │   ├── ModelInfo.kt                 # ✅ Keep
│   │   │   ├── ModelManager.kt              # ✅ Keep
│   │   │   ├── ModelRegistry.kt             # ✅ Keep
│   │   │   ├── ModelLoadingService.kt       # ✅ Keep
│   │   │   └── GenerationOptions.kt         # ✅ Keep (align params)
│   │   ├── services/
│   │   │   ├── download/
│   │   │   │   └── DownloadService.kt       # ✅ Keep (enhance)
│   │   │   ├── network/
│   │   │   │   └── NetworkService.kt        # ✅ Keep
│   │   │   ├── authentication/
│   │   │   │   └── AuthenticationService.kt # ✅ Keep
│   │   │   └── configuration/
│   │   │       └── ConfigurationService.kt  # ✅ Keep
│   │   ├── foundation/
│   │   │   ├── ServiceContainer.kt          # ✅ Keep (simplify bootstrap)
│   │   │   ├── ModuleRegistry.kt            # ✅ Keep
│   │   │   └── EventBus.kt                  # ✅ Keep (fix kotlinx.datetime)
│   │   └── providers/
│   │       └── LLMServiceProvider.kt        # ✅ Keep (interface)
│   ├── jvmAndroidMain/                      # Shared JVM+Android
│   │   └── platform/
│   │       ├── FileSystem.kt                # ✅ Keep
│   │       ├── HttpClient.kt                # ✅ Keep
│   │       └── Crypto.kt                    # ✅ Add (for checksums)
│   ├── jvmMain/                             # JVM-only
│   │   └── platform/
│   │       ├── JvmPlatformContext.kt        # ✅ Keep
│   │       └── JvmSecureStorage.kt          # ✅ Keep
│   └── androidMain/                         # Android-only
│       └── platform/
│           ├── AndroidPlatformContext.kt    # ✅ Keep
│           └── AndroidSecureStorage.kt      # ✅ Keep
│
└── modules/                                  # ADAPTER MODULES
    │
    ├── runanywhere-llm-llamacpp/            # ✨ REFACTOR THIS MODULE
    │   ├── build.gradle.kts                 # KMP build (JVM + Android)
    │   ├── src/
    │   │   ├── commonMain/
    │   │   │   ├── LlamaCppServiceProvider.kt    # ✅ Implements LLMServiceProvider
    │   │   │   └── LlamaCppConfiguration.kt      # ✅ Module-specific config
    │   │   ├── jvmAndroidMain/
    │   │   │   ├── LlamaCppService.kt            # ✅ Actual implementation
    │   │   │   └── LlamaCppNative.kt             # ✅ JNI bindings
    │   │   ├── jvmMain/                          # JVM-specific loading
    │   │   └── androidMain/                      # Android-specific loading
    │   └── native/                          # C++ JNI wrapper
    │       └── llama-jni/
    │           ├── CMakeLists.txt
    │           ├── llama_jni.cpp
    │           └── llama.cpp/               # Git submodule
    │
    ├── runanywhere-stt-whisper/             # ⏸️ DEFERRED (Phase 2)
    │   └── (similar structure)
    │
    └── runanywhere-core/                    # ⚠️ REMOVE/MERGE
        └── (utilities - merge into main SDK)
```

### Key Architectural Decisions

**Decision 1: Where does LlamaCpp live?**
- ✅ **CHOSEN:** Separate module (`modules/runanywhere-llm-llamacpp/`)
- **Reason:** Matches Swift SDK structure (core + modules pattern)
- **Benefit:** Optional dependency, can swap providers easily

**Decision 2: What goes in commonMain?**
- ✅ **ALL business logic, interfaces, models**
- ✅ **NO platform-specific code, NO native library code**
- ✅ **LLMComponent, LLMService interface, LLMServiceProvider interface**

**Decision 3: What goes in modules?**
- ✅ **Provider implementations** (LlamaCppServiceProvider)
- ✅ **Service implementations** (LlamaCppService)
- ✅ **Native bindings** (LlamaCppNative, JNI)
- ✅ **Module-specific configuration**

**Decision 4: How does registration work?**
- ✅ **Auto-registration** in module init block
- ✅ **ModuleRegistry** in core SDK
- ✅ **Components** discover providers via registry

---

## Phase 0: Module Structure Alignment

**Duration:** 2 days
**Goal:** Restructure Kotlin SDK to match Swift's core + modules pattern
**Status:** 🔴 Required before any other work

### 0.1 Current Module Issues

**Problem 1: LlamaCpp code is mixed with core SDK**
```kotlin
// Current: LlamaCpp provider is disabled in settings.gradle.kts
// include(":modules:runanywhere-llm-llamacpp")  // COMMENTED OUT

// Files exist but not built:
modules/runanywhere-llm-llamacpp/src/jvmAndroidMain/kotlin/
  ├── LlamaCppService.kt          # Exists but not compiled
  ├── LlamaCppNative.kt           # Exists but not compiled
  └── LlamaCppModuleActual.kt     # Exists but not compiled
```

**Problem 2: Core SDK has no clean LLM abstraction**
```kotlin
// Current: LLMComponent is in core, but tightly coupled
src/commonMain/kotlin/com/runanywhere/sdk/components/llm/
  ├── LLMComponent.kt             # Should stay
  ├── LLMService.kt               # Should stay (interface)
  ├── LLMConfiguration.kt         # Should stay
  └── ??? - Missing provider interface in core
```

### 0.2 Module Restructure Plan

#### Step 0.2.1: Enable LlamaCpp Module (30 minutes)

**File:** `settings.gradle.kts`

```kotlin
// BEFORE:
// include(":modules:runanywhere-llm-llamacpp")  // Disabled

// AFTER:
include(":modules:runanywhere-llm-llamacpp")
```

**Verify:**
```bash
cd sdk/runanywhere-kotlin
./gradlew :modules:runanywhere-llm-llamacpp:build
```

**Expected Output:** Module builds successfully (even if native lib missing)

---

#### Step 0.2.2: Create LLMServiceProvider Interface in Core (1 hour)

**File:** `src/commonMain/kotlin/com/runanywhere/sdk/components/llm/LLMServiceProvider.kt`

**Current State:** Interface exists but may need alignment with Swift

**Required Interface (aligned with Swift SDK):**

```kotlin
package com.runanywhere.sdk.components.llm

import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.HardwareConfiguration
import com.runanywhere.sdk.models.LLMFramework

/**
 * Provider interface for LLM services.
 * Matches Swift SDK's LLMServiceProvider protocol.
 */
interface LLMServiceProvider {
    /**
     * Provider name (e.g., "LlamaCpp", "MLX", "OpenAI")
     */
    val name: String

    /**
     * Framework this provider uses
     */
    val framework: LLMFramework

    /**
     * Supported features (e.g., "streaming", "gpu-acceleration")
     */
    val supportedFeatures: Set<String>

    /**
     * Create an LLM service instance with the given configuration.
     *
     * @param configuration LLM configuration parameters
     * @return LLMService implementation
     */
    suspend fun createLLMService(configuration: LLMConfiguration): LLMService

    /**
     * Check if this provider can handle the given model ID.
     *
     * @param modelId Model identifier (e.g., "llama-2-7b", "*.gguf")
     * @return true if this provider can load this model
     */
    fun canHandle(modelId: String?): Boolean

    // ADVANCED FEATURES (Swift SDK has these):

    /**
     * Validate model compatibility with this provider.
     */
    fun validateModelCompatibility(model: ModelInfo): ModelCompatibilityResult

    /**
     * Download model with progress tracking.
     * Note: Usually delegated to ModelManager, but provider can override.
     */
    suspend fun downloadModel(modelId: String, onProgress: (Float) -> Unit): ModelInfo

    /**
     * Estimate memory requirements for a model.
     */
    fun estimateMemoryRequirements(model: ModelInfo): Long

    /**
     * Get optimal hardware configuration for a model.
     */
    fun getOptimalConfiguration(model: ModelInfo): HardwareConfiguration
}

/**
 * Result of model compatibility validation
 */
sealed class ModelCompatibilityResult {
    object Compatible : ModelCompatibilityResult()
    data class Incompatible(val reason: String) : ModelCompatibilityResult()
    data class Warning(val message: String) : ModelCompatibilityResult()
}
```

**Verify:** Core SDK compiles with new interface

---

#### Step 0.2.3: Move LlamaCpp Implementation to Module (2 hours)

**Target Structure:**
```
modules/runanywhere-llm-llamacpp/
├── build.gradle.kts
├── src/
│   ├── commonMain/kotlin/com/runanywhere/sdk/llm/llamacpp/
│   │   ├── LlamaCppServiceProvider.kt       # NEW: Provider implementation
│   │   └── LlamaCppModule.kt                 # NEW: Auto-registration
│   ├── jvmAndroidMain/kotlin/com/runanywhere/sdk/llm/llamacpp/
│   │   ├── LlamaCppService.kt                # MOVE: From core
│   │   ├── LlamaCppNative.kt                 # MOVE: From core
│   │   └── LlamaCppConfiguration.kt          # NEW: Module config
│   ├── jvmMain/
│   │   └── ... (JVM-specific loading)
│   └── androidMain/
│       └── ... (Android-specific loading)
└── native/llama-jni/
    ├── CMakeLists.txt
    ├── src/llama_jni.cpp
    └── llama.cpp/                            # Git submodule (add later)
```

**Action Items:**

**0.2.3.1 - Create LlamaCppServiceProvider (commonMain)**

**File:** `modules/runanywhere-llm-llamacpp/src/commonMain/kotlin/com/runanywhere/sdk/llm/llamacpp/LlamaCppServiceProvider.kt`

```kotlin
package com.runanywhere.sdk.llm.llamacpp

import com.runanywhere.sdk.components.llm.LLMService
import com.runanywhere.sdk.components.llm.LLMServiceProvider
import com.runanywhere.sdk.components.llm.LLMConfiguration
import com.runanywhere.sdk.components.llm.ModelCompatibilityResult
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.LLMFramework
import com.runanywhere.sdk.models.HardwareConfiguration

/**
 * LlamaCpp provider for LLM services.
 * Matches Swift SDK's LLMSwiftServiceProvider.
 */
class LlamaCppServiceProvider : LLMServiceProvider {

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

    override suspend fun createLLMService(configuration: LLMConfiguration): LLMService {
        // Delegate to actual implementation (jvmAndroidMain)
        return LlamaCppService(configuration)
    }

    override fun canHandle(modelId: String?): Boolean {
        if (modelId == null) return true // Default provider

        val modelIdLower = modelId.lowercase()
        return modelIdLower.contains("llama") ||
               modelIdLower.endsWith(".gguf") ||
               modelIdLower.endsWith(".ggml") ||
               modelIdLower.contains("mistral") ||
               modelIdLower.contains("mixtral") ||
               modelIdLower.contains("phi") ||
               modelIdLower.contains("gemma") ||
               modelIdLower.contains("qwen")
    }

    override fun validateModelCompatibility(model: ModelInfo): ModelCompatibilityResult {
        // Check format
        if (model.format != ModelFormat.GGUF && model.format != ModelFormat.GGML) {
            return ModelCompatibilityResult.Incompatible(
                "LlamaCpp only supports GGUF/GGML formats, got: ${model.format}"
            )
        }

        // Check size
        val modelSizeMB = (model.downloadSize ?: 0L) / 1024 / 1024
        if (modelSizeMB > 10_000) {
            return ModelCompatibilityResult.Warning(
                "Model is very large (${modelSizeMB}MB), may not fit in memory"
            )
        }

        return ModelCompatibilityResult.Compatible
    }

    override suspend fun downloadModel(modelId: String, onProgress: (Float) -> Unit): ModelInfo {
        // Delegate to ModelManager (standard implementation)
        throw NotImplementedError("Use ModelManager.downloadModel() instead")
    }

    override fun estimateMemoryRequirements(model: ModelInfo): Long {
        val modelSize = model.downloadSize ?: 8_000_000_000L
        val contextMemory = (model.contextLength ?: 2048) * 4L * 1024 // 4 bytes per token
        val kvCacheMemory = contextMemory * 2 // KV cache overhead

        return modelSize + contextMemory + kvCacheMemory
    }

    override fun getOptimalConfiguration(model: ModelInfo): HardwareConfiguration {
        val modelSizeMB = (model.downloadSize ?: 0L) / 1024 / 1024

        return HardwareConfiguration(
            preferGPU = true,
            minMemoryMB = (estimateMemoryRequirements(model) / 1024 / 1024).toInt(),
            recommendedThreads = minOf(Runtime.getRuntime().availableProcessors(), 8),
            useMmap = true,
            lockMemory = modelSizeMB < 4096,
            enableFlashAttention = model.contextLength ?: 2048 > 4096
        )
    }
}
```

**0.2.3.2 - Create Auto-Registration Module (commonMain)**

**File:** `modules/runanywhere-llm-llamacpp/src/commonMain/kotlin/com/runanywhere/sdk/llm/llamacpp/LlamaCppModule.kt`

```kotlin
package com.runanywhere.sdk.llm.llamacpp

import com.runanywhere.sdk.foundation.ModuleRegistry

/**
 * LlamaCpp module initialization.
 * Auto-registers the LlamaCpp provider on module load.
 */
object LlamaCppModule {

    private var isRegistered = false

    /**
     * Register LlamaCpp provider with the SDK.
     * Safe to call multiple times (idempotent).
     */
    fun register() {
        if (isRegistered) return

        ModuleRegistry.registerLLM(LlamaCppServiceProvider())
        isRegistered = true
    }

    init {
        // Auto-register when module is loaded
        register()
    }
}
```

**0.2.3.3 - Update Module build.gradle.kts**

**File:** `modules/runanywhere-llm-llamacpp/build.gradle.kts`

```kotlin
plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.library)
    `maven-publish`
}

group = "com.runanywhere.sdk"
version = "0.1.0"

kotlin {
    jvm {
        compilations.all {
            kotlinOptions.jvmTarget = "17"
        }
    }

    androidTarget {
        publishLibraryVariants("release", "debug")
        compilations.all {
            kotlinOptions.jvmTarget = "17"
        }
    }

    sourceSets {
        val commonMain by getting {
            dependencies {
                // CRITICAL: Depend on core SDK
                api(project(":"))

                implementation(libs.kotlinx.coroutines.core)
                implementation(libs.kotlinx.serialization.json)
            }
        }

        val commonTest by getting {
            dependencies {
                implementation(kotlin("test"))
            }
        }

        val jvmAndroidMain by creating {
            dependsOn(commonMain)
            dependencies {
                // JNI bindings shared between JVM and Android
            }
        }

        val jvmMain by getting {
            dependsOn(jvmAndroidMain)
        }

        val androidMain by getting {
            dependsOn(jvmAndroidMain)
        }
    }
}

android {
    namespace = "com.runanywhere.sdk.llm.llamacpp"
    compileSdk = 34

    defaultConfig {
        minSdk = 24
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

// Task to build native library (optional, run manually)
tasks.register("buildNative") {
    group = "build"
    description = "Build native llama.cpp library"

    doLast {
        exec {
            workingDir("native/llama-jni")
            commandLine("./build-native.sh")
        }
    }
}

publishing {
    publications {
        create<MavenPublication>("jvm") {
            groupId = "com.runanywhere.sdk"
            artifactId = "runanywhere-llm-llamacpp-jvm"
            version = "0.1.0"
            from(components["jvm"])
        }

        create<MavenPublication>("android") {
            groupId = "com.runanywhere.sdk"
            artifactId = "runanywhere-llm-llamacpp-android"
            version = "0.1.0"
            from(components["release"])
        }
    }
}
```

---

#### Step 0.2.4: Verify Module Separation (30 minutes)

**Build Commands:**
```bash
cd sdk/runanywhere-kotlin

# Build core SDK
./gradlew :build

# Build LlamaCpp module
./gradlew :modules:runanywhere-llm-llamacpp:build

# Build everything
./gradlew build
```

**Expected Output:**
```
> Task :build SUCCESS
> Task :modules:runanywhere-llm-llamacpp:build SUCCESS

BUILD SUCCESSFUL in 30s
```

**Verification Checklist:**
- [ ] Core SDK builds without LlamaCpp
- [ ] LlamaCpp module depends on core SDK
- [ ] LlamaCppServiceProvider implements LLMServiceProvider
- [ ] Auto-registration works (LlamaCppModule.init called)
- [ ] No circular dependencies

---

### 0.3 Clean Up Deprecated Code (1 hour)

#### Remove/Merge runanywhere-core module

**File:** `settings.gradle.kts`

```kotlin
// BEFORE:
// include(":modules:runanywhere-core")

// AFTER:
// (removed)
```

**Action:** Merge any utilities from `runanywhere-core` into main SDK's `commonMain/kotlin/com/runanywhere/sdk/utils/`

---

### 0.4 Update Root build.gradle.kts (30 minutes)

**File:** `build.gradle.kts` (root)

```kotlin
// Ensure core SDK does NOT depend on modules
// Modules depend on core SDK

dependencies {
    // NO module dependencies here
}
```

**File:** `modules/runanywhere-llm-llamacpp/build.gradle.kts`

```kotlin
dependencies {
    // Module depends on core
    api(project(":"))
}
```

---

### Phase 0 Deliverables

**Deliverable 0.1:** Clean module structure
- ✅ Core SDK in `src/commonMain` (no LlamaCpp code)
- ✅ LlamaCpp in `modules/runanywhere-llm-llamacpp/`
- ✅ LlamaCppServiceProvider implements LLMServiceProvider
- ✅ Auto-registration working

**Deliverable 0.2:** Build verification
- ✅ `./gradlew :build` (core only) - SUCCESS
- ✅ `./gradlew :modules:runanywhere-llm-llamacpp:build` - SUCCESS
- ✅ No circular dependencies

**Deliverable 0.3:** Documentation
- ✅ Update `ARCHITECTURE.md` with new structure
- ✅ Update `MODULE-STRUCTURE.md` (create if missing)

**Success Criteria:**
```bash
cd sdk/runanywhere-kotlin
./gradlew clean build
# All modules build successfully
# No compilation errors
# Module separation is clean
```

---

## Phase 1: SDK Initialization Parity

**Duration:** 2 days
**Goal:** Match Swift SDK's simple 5-step init + lazy registration
**Priority:** 🔴 Critical (from gap analysis Priority 1)

### Current State vs Target

**Swift SDK (Target):**
```swift
// 5-step lightweight init (no network)
try RunAnywhere.initialize(
    apiKey: "key",
    baseURL: "https://api.example.com",
    environment: .production
)

// Lazy device registration on first API call
let response = try await RunAnywhere.generate("Hello") // Registers automatically
```

**Kotlin SDK (Current):**
```kotlin
// Initialize platform context
RunAnywhere.initialize(platformContext, environment, apiKey, baseURL)

// Explicit 8-step bootstrap (requires network)
RunAnywhere.bootstrapDevelopmentMode(params)

// Manual registration
```

### 1.1 Simplify Initialization (4 hours)

#### Step 1.1.1: Add Lazy Registration Function

**File:** `src/commonMain/kotlin/com/runanywhere/sdk/public/RunAnywhere.kt`

**Add this function:**

```kotlin
/**
 * Ensure device is registered with backend.
 * Called automatically on first API usage (lazy registration).
 * Matches Swift SDK's ensureDeviceRegistered() pattern.
 *
 * @param maxRetries Maximum retry attempts (default: 3)
 * @throws SDKError.NetworkError if registration fails after retries
 */
private suspend fun ensureDeviceRegistered(maxRetries: Int = 3): Unit {
    // Check if already registered
    if (_isDeviceRegistered.value) {
        return
    }

    // Lock to prevent concurrent registration attempts
    deviceRegistrationMutex.withLock {
        // Double-check after acquiring lock
        if (_isDeviceRegistered.value) {
            return
        }

        // In development mode, use mock device ID
        if (_environment == SDKEnvironment.DEVELOPMENT) {
            logger.info("Development mode: Using mock device ID")
            _isDeviceRegistered.value = true
            return
        }

        // Attempt registration with exponential backoff
        var attempt = 0
        var lastError: Exception? = null

        while (attempt < maxRetries) {
            try {
                logger.info("Attempting device registration (attempt ${attempt + 1}/$maxRetries)")

                // Call authentication service to register device
                ServiceContainer.shared.authenticationService?.registerDevice()

                // Success
                _isDeviceRegistered.value = true
                logger.info("✅ Device registered successfully")

                // Publish event
                EventBus.publish(SDKInitializationEvent.DeviceRegistered)

                return

            } catch (e: Exception) {
                lastError = e
                attempt++

                if (attempt < maxRetries) {
                    // Exponential backoff: 1s, 2s, 4s
                    val delayMs = (1000L * (1 shl attempt))
                    logger.warn("Device registration failed, retrying in ${delayMs}ms: ${e.message}")
                    delay(delayMs)
                } else {
                    logger.error("Device registration failed after $maxRetries attempts", e)
                }
            }
        }

        // If we get here, registration failed
        // In development mode, continue with mock ID
        if (_environment == SDKEnvironment.DEVELOPMENT) {
            logger.warn("Device registration failed in dev mode, continuing with mock ID")
            _isDeviceRegistered.value = true
        } else {
            throw SDKError.NetworkError("Device registration failed after $maxRetries attempts: ${lastError?.message}")
        }
    }
}

// Add mutex for thread-safe registration
private val deviceRegistrationMutex = Mutex()
private val _isDeviceRegistered = MutableStateFlow(false)

companion object {
    /**
     * Check if device is registered (for testing/debugging)
     */
    fun isDeviceRegistered(): Boolean = _isDeviceRegistered.value
}
```

#### Step 1.1.2: Update generate() to Call ensureDeviceRegistered()

**File:** `src/commonMain/kotlin/com/runanywhere/sdk/public/RunAnywhere.kt`

**Before:**
```kotlin
override suspend fun generate(
    prompt: String,
    options: RunAnywhereGenerationOptions?
): String {
    if (!_isSDKInitialized.value) {
        throw SDKError.NotInitialized
    }

    // Missing: No lazy registration check

    val generationService = ServiceContainer.shared.generationService
    val result = generationService.generate(prompt, options ?: RunAnywhereGenerationOptions.DEFAULT)
    return result.text
}
```

**After:**
```kotlin
override suspend fun generate(
    prompt: String,
    options: RunAnywhereGenerationOptions?
): String {
    // Check initialization
    if (!_isSDKInitialized.value) {
        throw SDKError.NotInitialized("SDK not initialized. Call RunAnywhere.initialize() first.")
    }

    // ✨ NEW: Lazy device registration (matches Swift SDK)
    ensureDeviceRegistered()

    // Proceed with generation
    val generationService = ServiceContainer.shared.generationService
    val result = generationService.generate(
        prompt = prompt,
        options = options ?: RunAnywhereGenerationOptions.DEFAULT
    )

    return result.text
}
```

#### Step 1.1.3: Update Other Public APIs

**Add `ensureDeviceRegistered()` to:**
- `chat(prompt: String)`
- `generateStream(prompt, options)`
- `transcribe(audioData: ByteArray)`
- `availableModels()`
- `downloadModel(modelId: String)`
- `loadModel(modelId: String)`

**Pattern:**
```kotlin
suspend fun anyPublicAPI(...) {
    ensureSDKInitialized()      // Throw if not initialized
    ensureDeviceRegistered()     // Register on first call (lazy)
    // ... proceed with operation
}
```

---

### 1.2 Make bootstrap() Optional (2 hours)

#### Current Problem
```kotlin
// Current: bootstrap() is required
RunAnywhere.initialize(...)
RunAnywhere.bootstrap(params)  // MUST call this
```

#### Target State
```kotlin
// Target: bootstrap() is optional (for advanced users)
RunAnywhere.initialize(...)
// Can immediately use generate() - bootstrap happens lazily
RunAnywhere.generate("Hello")  // Works without explicit bootstrap
```

#### Step 1.2.1: Add Lazy Bootstrap Helper

**File:** `src/commonMain/kotlin/com/runanywhere/sdk/foundation/ServiceContainer.kt`

```kotlin
/**
 * Ensure service container is bootstrapped.
 * Called automatically by public APIs if bootstrap() wasn't called explicitly.
 */
suspend fun ensureBootstrapped() {
    if (isBootstrapped.value) {
        return
    }

    bootstrapMutex.withLock {
        if (isBootstrapped.value) {
            return
        }

        // Auto-bootstrap with default params
        logger.info("Auto-bootstrapping SDK with default parameters")

        val params = SDKInitParams(
            enableAnalytics = true,
            enableCostTracking = false,
            cacheConfig = CacheConfig.default(),
            componentConfigs = emptyList()
        )

        if (environment == SDKEnvironment.DEVELOPMENT) {
            bootstrapDevelopmentMode(params)
        } else {
            bootstrap(params)
        }
    }
}

private val bootstrapMutex = Mutex()
private val isBootstrapped = MutableStateFlow(false)
```

#### Step 1.2.2: Update bootstrap() to Set Flag

**File:** `src/commonMain/kotlin/com/runanywhere/sdk/foundation/ServiceContainer.kt`

```kotlin
suspend fun bootstrap(params: SDKInitParams): ConfigurationData {
    // ... existing bootstrap logic ...

    // At the end:
    isBootstrapped.value = true
    return configurationData
}

suspend fun bootstrapDevelopmentMode(params: SDKInitParams): ConfigurationData {
    // ... existing bootstrap logic ...

    // At the end:
    isBootstrapped.value = true
    return configurationData
}
```

#### Step 1.2.3: Call ensureBootstrapped() Before Operations

**File:** `src/commonMain/kotlin/com/runanywhere/sdk/services/generation/GenerationService.kt`

```kotlin
suspend fun generate(prompt: String, options: RunAnywhereGenerationOptions): GenerationResult {
    // Ensure container is bootstrapped
    ServiceContainer.shared.ensureBootstrapped()

    // ... rest of generation logic
}
```

---

### 1.3 Fix EventBus kotlinx.datetime Issue (1 hour)

#### Current Problem
```kotlin
// File: src/commonMain/kotlin/com/runanywhere/sdk/events/SDKEvent.kt
@file:OptIn(kotlin.time.ExperimentalTime::class)  // ❌ WRONG
import kotlinx.datetime.Instant  // ✅ CORRECT

// Problem: Mixing kotlin.time and kotlinx.datetime
```

#### Solution

**File:** `src/commonMain/kotlin/com/runanywhere/sdk/events/SDKEvent.kt`

**Before:**
```kotlin
@file:OptIn(kotlin.time.ExperimentalTime::class)  // ❌ Remove this

import kotlinx.datetime.Instant
import kotlin.time.Duration  // ❌ Causes conflict
```

**After:**
```kotlin
// Remove kotlin.time imports entirely
// Use ONLY kotlinx.datetime

import kotlinx.datetime.Instant
import kotlinx.datetime.Clock
// DO NOT import kotlin.time.*
```

**Update all event classes:**
```kotlin
sealed class SDKEvent {
    // Use kotlinx.datetime.Instant consistently
    abstract val timestamp: Instant

    companion object {
        fun now(): Instant = Clock.System.now()
    }
}

data class SDKInitializationEvent(
    val stage: InitializationStage,
    override val timestamp: Instant = SDKEvent.now()
) : SDKEvent()
```

**Verify:** All `EventBus.publish()` calls work without errors

---

### 1.4 Align Initialization Method Signatures (2 hours)

#### Target: Match Swift SDK API

**Swift SDK:**
```swift
static func initialize(
    apiKey: String,
    baseURL: URL,
    environment: SDKEnvironment
) throws
```

**Kotlin SDK (Update):**

**File:** `src/commonMain/kotlin/com/runanywhere/sdk/public/RunAnywhere.kt`

**Add overload to match Swift:**
```kotlin
/**
 * Initialize SDK with minimal parameters.
 * Matches Swift SDK's initialize() signature.
 *
 * @param apiKey API key for authentication
 * @param baseURL Base URL for API endpoints (e.g., "https://api.example.com")
 * @param environment Development, Staging, or Production
 * @throws SDKError.InvalidAPIKey if API key is invalid
 */
suspend fun initialize(
    apiKey: String,
    baseURL: String,
    environment: SDKEnvironment
) {
    // Validate API key (skip in dev mode)
    if (environment != SDKEnvironment.DEVELOPMENT) {
        ValidationService.validateApiKey(apiKey)
    }

    // Initialize logging
    initializeLogging(environment)

    // Store credentials securely
    secureStorage.store("api_key", apiKey)
    secureStorage.store("base_url", baseURL)
    secureStorage.store("environment", environment.name)

    // Initialize local database
    initializeDatabase()

    // Setup local services only (no network calls)
    setupLocalServices()

    // Mark as initialized
    _isSDKInitialized.value = true
    _environment = environment

    logger.info("✅ SDK initialized successfully (environment: ${environment.name})")

    // Publish event
    EventBus.publish(SDKInitializationEvent.Completed)
}

// Keep existing initialize() for backward compatibility
suspend fun initialize(
    platformContext: PlatformContext,
    environment: SDKEnvironment,
    apiKey: String?,
    baseURL: String?
) {
    // Call new initialize()
    initialize(
        apiKey = apiKey ?: "",
        baseURL = baseURL ?: "",
        environment = environment
    )

    // Platform-specific setup
    platformContext.initialize()
}
```

---

### Phase 1 Deliverables

**Deliverable 1.1:** Lazy registration
- ✅ `ensureDeviceRegistered()` function added
- ✅ Called automatically on first API usage
- ✅ Retry logic with exponential backoff (3 retries)
- ✅ Development mode fallback to mock device ID

**Deliverable 1.2:** Optional bootstrap
- ✅ `ensureBootstrapped()` function added
- ✅ Auto-bootstrap with default params
- ✅ `bootstrap()` remains available for advanced config

**Deliverable 1.3:** EventBus fixed
- ✅ kotlinx.datetime conflict resolved
- ✅ All `EventBus.publish()` calls work

**Deliverable 1.4:** API alignment
- ✅ `initialize(apiKey, baseURL, environment)` matches Swift
- ✅ Backward compatibility maintained

**Success Criteria:**
```kotlin
// This should work (matches Swift SDK):
runBlocking {
    RunAnywhere.initialize(
        apiKey = "test-key",
        baseURL = "https://api.example.com",
        environment = SDKEnvironment.DEVELOPMENT
    )

    // No explicit bootstrap needed
    val result = RunAnywhere.generate("Hello, world!")

    // Device registration happened automatically
    assert(RunAnywhere.isDeviceRegistered())
}
```

---

## Phase 2: Model Management Parity

**Duration:** 3 days
**Goal:** Match Swift SDK's model download, verification, and management
**Priority:** 🔴 Critical (from gap analysis Priority 2)

### 2.1 Enhanced Download Progress (4 hours)

#### Current State
```kotlin
// Returns only percentage (Float)
suspend fun downloadModel(modelId: String): Flow<Float>
```

#### Target State (Match Swift)
```kotlin
// Returns detailed progress metadata
suspend fun downloadModel(modelId: String): Flow<DownloadProgress>

data class DownloadProgress(
    val bytesDownloaded: Long,
    val totalBytes: Long,
    val percentComplete: Float,
    val state: DownloadState,
    val speed: Long?,                      // Bytes per second
    val estimatedTimeRemaining: Long?,     // Seconds
    val currentFile: String?
)
```

#### Step 2.1.1: Update DownloadProgress Model

**File:** `src/commonMain/kotlin/com/runanywhere/sdk/services/download/DownloadProgress.kt`

**Current:**
```kotlin
data class DownloadProgress(
    val bytesDownloaded: Long,
    val totalBytes: Long,
    val state: DownloadState,
    val speed: Long? = null,              // Has it but not exposed
    val estimatedTimeRemaining: Long? = null  // Has it but not exposed
) {
    val percentComplete: Float
        get() = if (totalBytes > 0) (bytesDownloaded.toFloat() / totalBytes) else 0f
}
```

**After (Enhanced):**
```kotlin
/**
 * Download progress information.
 * Matches Swift SDK's DownloadProgress structure.
 */
data class DownloadProgress(
    val bytesDownloaded: Long,
    val totalBytes: Long,
    val state: DownloadState,
    val speed: Long? = null,                      // Bytes per second (now exposed)
    val estimatedTimeRemaining: Long? = null,     // Seconds remaining (now exposed)
    val currentFile: String? = null               // For multi-file downloads
) {
    val percentComplete: Float
        get() = if (totalBytes > 0) (bytesDownloaded.toFloat() / totalBytes) else 0f

    companion object {
        /**
         * Create initial progress (0%)
         */
        fun initial(totalBytes: Long, fileName: String? = null): DownloadProgress {
            return DownloadProgress(
                bytesDownloaded = 0L,
                totalBytes = totalBytes,
                state = DownloadState.Pending,
                speed = null,
                estimatedTimeRemaining = null,
                currentFile = fileName
            )
        }
    }
}

enum class DownloadState {
    Pending,
    Downloading,
    Paused,
    Completed,
    Failed,
    Cancelled
}
```

#### Step 2.1.2: Update KtorDownloadService to Calculate Speed/ETA

**File:** `src/commonMain/kotlin/com/runanywhere/sdk/services/download/KtorDownloadService.kt`

**Add speed/ETA calculation:**

```kotlin
class KtorDownloadService(
    private val configuration: DownloadConfiguration,
    private val fileSystem: FileSystem
) : DownloadService {

    override fun downloadModelStream(model: ModelInfo): Flow<DownloadProgress> = flow {
        val downloadURL = model.downloadURL ?: throw DownloadError.InvalidURL
        val destinationPath = getDestinationPath(model.id)
        val totalBytes = model.downloadSize ?: 0L

        // Emit initial progress
        emit(DownloadProgress.initial(totalBytes, model.name))

        // Track download metrics
        var bytesDownloaded = 0L
        var lastEmitTime = System.currentTimeMillis()
        var lastEmitBytes = 0L

        val response = httpClient.prepareGet(downloadURL).execute()

        if (!response.status.isSuccess()) {
            throw mapHttpError(response.status.value)
        }

        val channel = response.bodyAsChannel()
        val buffer = ByteArray(configuration.chunkSize)

        while (!channel.isClosedForRead) {
            val bytesRead = channel.readAvailable(buffer, 0, buffer.size)
            if (bytesRead <= 0) break

            // Write to file
            fileSystem.appendBytes(destinationPath, buffer, bytesRead)

            bytesDownloaded += bytesRead

            // Calculate speed and ETA (emit every 100ms minimum)
            val now = System.currentTimeMillis()
            val timeSinceLastEmit = now - lastEmitTime

            if (timeSinceLastEmit >= 100) {
                val bytesSinceLastEmit = bytesDownloaded - lastEmitBytes
                val speed = if (timeSinceLastEmit > 0) {
                    (bytesSinceLastEmit * 1000) / timeSinceLastEmit // Bytes per second
                } else {
                    null
                }

                val eta = if (speed != null && speed > 0) {
                    (totalBytes - bytesDownloaded) / speed // Seconds remaining
                } else {
                    null
                }

                // Emit progress with metadata
                val progress = DownloadProgress(
                    bytesDownloaded = bytesDownloaded,
                    totalBytes = totalBytes,
                    state = DownloadState.Downloading,
                    speed = speed,
                    estimatedTimeRemaining = eta,
                    currentFile = model.name
                )
                emit(progress)

                lastEmitTime = now
                lastEmitBytes = bytesDownloaded
            }
        }

        // Final progress
        emit(DownloadProgress(
            bytesDownloaded = bytesDownloaded,
            totalBytes = totalBytes,
            state = DownloadState.Completed,
            speed = null,
            estimatedTimeRemaining = 0,
            currentFile = model.name
        ))
    }
}
```

#### Step 2.1.3: Update RunAnywhere.downloadModel() Signature

**File:** `src/commonMain/kotlin/com/runanywhere/sdk/public/RunAnywhere.kt`

**Before:**
```kotlin
override suspend fun downloadModel(modelId: String): Flow<Float>
```

**After:**
```kotlin
/**
 * Download a model with detailed progress tracking.
 * Matches Swift SDK's downloadModelWithProgress() API.
 *
 * @param modelId Model identifier to download
 * @return Flow of DownloadProgress with speed, ETA, and state
 */
override suspend fun downloadModel(modelId: String): Flow<DownloadProgress> {
    ensureSDKInitialized()
    ensureDeviceRegistered()

    val modelInfo = ServiceContainer.shared.modelRegistry.getModel(modelId)
        ?: throw SDKError.ModelNotFound(modelId)

    // Return full DownloadProgress flow
    return ServiceContainer.shared.downloadService.downloadModelStream(modelInfo)
}

/**
 * Download a model with simple percentage updates (convenience method).
 * For backward compatibility.
 *
 * @param modelId Model identifier to download
 * @return Flow of percentage (0.0 to 1.0)
 */
suspend fun downloadModelSimple(modelId: String): Flow<Float> {
    return downloadModel(modelId).map { it.percentComplete }
}
```

---

### 2.2 Add Checksum Verification (3 hours)

#### Current State
```kotlin
// ModelManager downloads but DOES NOT verify checksums
suspend fun downloadModel(modelInfo: ModelInfo, onProgress: (DownloadProgress) -> Unit): String {
    val localPath = downloadService.downloadModel(modelInfo, onProgress)
    // MISSING: No checksum verification
    return localPath
}
```

#### Target State (Match Swift)
```kotlin
suspend fun downloadModel(modelInfo: ModelInfo, onProgress: (DownloadProgress) -> Unit): String {
    // Download
    val localPath = downloadService.downloadModel(modelInfo, onProgress)

    // Verify checksum
    validateModel(localPath, modelInfo.sha256Checksum)

    return localPath
}
```

#### Step 2.2.1: Add Checksum Calculation (Platform-Specific)

**File:** `src/jvmAndroidMain/kotlin/com/runanywhere/sdk/platform/Crypto.kt`

```kotlin
package com.runanywhere.sdk.platform

import java.io.File
import java.security.MessageDigest

/**
 * Calculate SHA-256 checksum of a file.
 *
 * @param filePath Path to file
 * @return Hex string of SHA-256 hash
 */
expect suspend fun calculateSHA256(filePath: String): String

/**
 * Calculate MD5 checksum of a file.
 *
 * @param filePath Path to file
 * @return Hex string of MD5 hash
 */
expect suspend fun calculateMD5(filePath: String): String

/**
 * Shared implementation for JVM and Android
 */
internal suspend fun calculateChecksum(filePath: String, algorithm: String): String {
    return withContext(Dispatchers.IO) {
        val file = File(filePath)
        val digest = MessageDigest.getInstance(algorithm)

        file.inputStream().use { input ->
            val buffer = ByteArray(8192)
            var bytesRead: Int

            while (input.read(buffer).also { bytesRead = it } != -1) {
                digest.update(buffer, 0, bytesRead)
            }
        }

        // Convert to hex string
        digest.digest().joinToString("") { "%02x".format(it) }
    }
}
```

**File:** `src/jvmMain/kotlin/com/runanywhere/sdk/platform/Crypto.kt`

```kotlin
package com.runanywhere.sdk.platform

actual suspend fun calculateSHA256(filePath: String): String {
    return calculateChecksum(filePath, "SHA-256")
}

actual suspend fun calculateMD5(filePath: String): String {
    return calculateChecksum(filePath, "MD5")
}
```

**File:** `src/androidMain/kotlin/com/runanywhere/sdk/platform/Crypto.kt`

```kotlin
package com.runanywhere.sdk.platform

actual suspend fun calculateSHA256(filePath: String): String {
    return calculateChecksum(filePath, "SHA-256")
}

actual suspend fun calculateMD5(filePath: String): String {
    return calculateChecksum(filePath, "MD5")
}
```

#### Step 2.2.2: Add ModelIntegrityVerifier (Already Exists, Just Use It)

**File:** `src/commonMain/kotlin/com/runanywhere/sdk/models/ModelIntegrityVerifier.kt`

This already exists in the codebase! Just need to ensure it's called.

**Verify implementation:**
```kotlin
class ModelIntegrityVerifier(private val fileSystem: FileSystem) {

    suspend fun verifyModel(modelInfo: ModelInfo, filePath: String): VerificationResult {
        // Check file size
        modelInfo.downloadSize?.let { expectedSize ->
            val actualSize = fileSystem.fileSize(filePath)
            if (actualSize != expectedSize) {
                return VerificationResult.Failed("File size mismatch")
            }
        }

        // Verify SHA256
        modelInfo.sha256Checksum?.let { expectedSha256 ->
            val actualSha256 = calculateSHA256(filePath)
            if (actualSha256 != expectedSha256.lowercase()) {
                return VerificationResult.Failed("SHA256 mismatch")
            }
            return VerificationResult.Success
        }

        // Verify MD5 (fallback)
        modelInfo.md5Checksum?.let { expectedMd5 ->
            val actualMd5 = calculateMD5(filePath)
            if (actualMd5 != expectedMd5.lowercase()) {
                return VerificationResult.Failed("MD5 mismatch")
            }
            return VerificationResult.Success
        }

        return VerificationResult.Success
    }
}

sealed class VerificationResult {
    object Success : VerificationResult()
    data class Failed(val reason: String) : VerificationResult()
}
```

#### Step 2.2.3: Use ModelIntegrityVerifier in ModelManager

**File:** `src/commonMain/kotlin/com/runanywhere/sdk/models/ModelManager.kt`

**Before:**
```kotlin
suspend fun downloadModel(modelInfo: ModelInfo, onProgress: (DownloadProgress) -> Unit): String {
    val localPath = downloadService.downloadModel(modelInfo, onProgress)
    // MISSING: No checksum verification
    return localPath
}
```

**After:**
```kotlin
suspend fun downloadModel(modelInfo: ModelInfo, onProgress: (DownloadProgress) -> Unit): String {
    logger.info("⬇️ Downloading model: ${modelInfo.id}")

    val localPath = downloadService.downloadModel(modelInfo, onProgress)

    logger.info("✅ Download complete, verifying integrity...")

    // Verify integrity
    when (val verificationResult = integrityVerifier.verifyModel(modelInfo, localPath)) {
        is VerificationResult.Success -> {
            logger.info("✅ Model integrity verification passed")
        }
        is VerificationResult.Failed -> {
            // Delete corrupted file
            fileSystem.delete(localPath)
            throw SDKError.ChecksumMismatch(
                expected = modelInfo.sha256Checksum ?: modelInfo.md5Checksum ?: "unknown",
                actual = "corrupted",
                reason = verificationResult.reason
            )
        }
    }

    return localPath
}
```

---

### 2.3 Add Model Unloading API (2 hours)

#### Current State
```kotlin
// No unloadModel() API anywhere in Kotlin SDK
```

#### Target State (Match Swift)
```swift
// Swift SDK has:
public func unloadModel() async throws
```

#### Step 2.3.1: Add unloadModel() to LLMComponent

**File:** `src/commonMain/kotlin/com/runanywhere/sdk/components/llm/LLMComponent.kt`

**Add method:**

```kotlin
/**
 * Unload the currently loaded model from memory.
 * Matches Swift SDK's unloadModel() API.
 *
 * @throws SDKError.ComponentNotReady if no model is loaded
 */
suspend fun unloadModel() {
    val llmService = service?.wrappedService
        ?: throw SDKError.ComponentNotReady("LLM service not initialized")

    logger.info("Unloading model: $currentModelInfo")

    // Call service to unload
    llmService.unloadModel()

    // Clear service reference
    service = null
    currentModelInfo = null

    // Publish event
    EventBus.publish(SDKModelEvent.ModelUnloaded(configuration.modelId ?: "unknown"))

    logger.info("✅ Model unloaded successfully")
}
```

#### Step 2.3.2: Add unloadModel() to LLMService Interface

**File:** `src/commonMain/kotlin/com/runanywhere/sdk/components/llm/LLMService.kt`

**Add method to interface:**

```kotlin
interface LLMService {
    // ... existing methods ...

    /**
     * Unload the currently loaded model from memory.
     */
    suspend fun unloadModel()
}
```

#### Step 2.3.3: Implement in LlamaCppService

**File:** `modules/runanywhere-llm-llamacpp/src/jvmAndroidMain/kotlin/LlamaCppService.kt`

**Add implementation:**

```kotlin
override suspend fun unloadModel() {
    if (contextHandle != 0L) {
        LlamaCppNative.llamaFree(contextHandle)
        contextHandle = 0L
        logger.info("✅ LlamaCpp model unloaded")
    }
}
```

#### Step 2.3.4: Add unloadModel() to RunAnywhere Public API

**File:** `src/commonMain/kotlin/com/runanywhere/sdk/public/RunAnywhere.kt`

**Add method:**

```kotlin
/**
 * Unload the currently loaded model from memory.
 * Matches Swift SDK's public API.
 */
suspend fun unloadModel() {
    ensureSDKInitialized()

    val llmComponent = ServiceContainer.shared.llmComponent
    llmComponent.unloadModel()

    // Clear current model reference
    _currentModel = null
}

// Add property to track current model
private var _currentModel: ModelInfo? = null

/**
 * Currently loaded model (matches Swift SDK)
 */
val currentModel: ModelInfo?
    get() = _currentModel
```

---

### 2.4 Add Current Model Tracking (1 hour)

#### Step 2.4.1: Track Current Model in loadModel()

**File:** `src/commonMain/kotlin/com/runanywhere/sdk/public/RunAnywhere.kt`

**Update loadModel():**

```kotlin
override suspend fun loadModel(modelId: String): Boolean {
    ensureSDKInitialized()
    ensureDeviceRegistered()

    EventBus.publish(SDKModelEvent.LoadStarted(modelId))

    val loadingService = ServiceContainer.shared.modelLoadingService
    val handle = loadingService.loadModel(modelId)

    // ✨ NEW: Track current model
    _currentModel = ServiceContainer.shared.modelRegistry.getModel(modelId)

    EventBus.publish(SDKModelEvent.LoadCompleted(modelId))

    return true
}
```

---

### 2.5 Add Offline Model Loading (2 hours)

#### Current State
```kotlin
// Only supports downloaded models from internet
```

#### Target State (Match Swift)
```swift
// Swift can load models from app bundle
let bundlePath = Bundle.main.path(forResource: "llama-2-7b", ofType: "gguf")
try await loadModel(localPath: bundlePath)
```

#### Step 2.5.1: Add loadModelFromPath() API

**File:** `src/commonMain/kotlin/com/runanywhere/sdk/public/RunAnywhere.kt`

**Add method:**

```kotlin
/**
 * Load a model from a local file path.
 * Useful for bundled models or custom model locations.
 * Matches Swift SDK's loadModel(localPath:) API.
 *
 * @param localPath Absolute path to model file
 * @param modelId Optional model ID (defaults to filename)
 * @throws SDKError.FileNotFound if file doesn't exist
 */
suspend fun loadModelFromPath(localPath: String, modelId: String? = null): Boolean {
    ensureSDKInitialized()
    ensureDeviceRegistered()

    // Verify file exists
    if (!fileSystem.exists(localPath)) {
        throw SDKError.FileNotFound("Model file not found: $localPath")
    }

    // Create ModelInfo from local path
    val inferredModelId = modelId ?: File(localPath).nameWithoutExtension
    val modelInfo = ModelInfo(
        id = inferredModelId,
        name = inferredModelId,
        category = ModelCategory.LANGUAGE,
        format = inferModelFormat(localPath),
        localPath = localPath,
        downloadURL = null,
        downloadSize = fileSystem.fileSize(localPath)
    )

    // Register in registry (so component can find it)
    ServiceContainer.shared.modelRegistry.registerModel(modelInfo)

    // Load normally
    return loadModel(inferredModelId)
}

/**
 * Infer model format from file extension
 */
private fun inferModelFormat(path: String): ModelFormat {
    return when {
        path.endsWith(".gguf", ignoreCase = true) -> ModelFormat.GGUF
        path.endsWith(".ggml", ignoreCase = true) -> ModelFormat.GGML
        path.endsWith(".safetensors", ignoreCase = true) -> ModelFormat.SAFETENSORS
        else -> ModelFormat.GGUF // Default
    }
}
```

#### Step 2.5.2: Add Asset Loading for Android

**File:** `src/androidMain/kotlin/com/runanywhere/sdk/platform/AndroidAssetLoader.kt`

```kotlin
package com.runanywhere.sdk.platform

import android.content.Context

/**
 * Load models from Android assets folder.
 */
object AndroidAssetLoader {

    /**
     * Copy model from assets to cache directory.
     *
     * @param context Android context
     * @param assetPath Path in assets (e.g., "models/llama-2-7b.gguf")
     * @return Absolute path to copied file in cache
     */
    suspend fun loadModelFromAssets(context: Context, assetPath: String): String {
        val cacheDir = context.cacheDir
        val fileName = File(assetPath).name
        val outputFile = File(cacheDir, fileName)

        // Copy from assets to cache
        context.assets.open(assetPath).use { input ->
            outputFile.outputStream().use { output ->
                input.copyTo(output)
            }
        }

        return outputFile.absolutePath
    }
}
```

**Usage:**
```kotlin
// In Android app:
val localPath = AndroidAssetLoader.loadModelFromAssets(context, "models/llama-2-7b.gguf")
RunAnywhere.loadModelFromPath(localPath)
```

---

### Phase 2 Deliverables

**Deliverable 2.1:** Enhanced download progress
- ✅ `DownloadProgress` includes speed and ETA
- ✅ `downloadModel()` returns `Flow<DownloadProgress>`
- ✅ Backward compatibility with `downloadModelSimple()`

**Deliverable 2.2:** Checksum verification
- ✅ `calculateSHA256()` and `calculateMD5()` implemented
- ✅ `ModelIntegrityVerifier` used in `ModelManager`
- ✅ Corrupted files deleted automatically

**Deliverable 2.3:** Model unloading
- ✅ `unloadModel()` in `LLMComponent`
- ✅ `unloadModel()` in `RunAnywhere` public API
- ✅ Events published on unload

**Deliverable 2.4:** Current model tracking
- ✅ `currentModel` property matches Swift
- ✅ Updated on `loadModel()` and `unloadModel()`

**Deliverable 2.5:** Offline loading
- ✅ `loadModelFromPath()` for bundled models
- ✅ Android asset loading support

**Success Criteria:**
```kotlin
// Download with progress
RunAnywhere.downloadModel("llama-2-7b").collect { progress ->
    println("${progress.percentComplete * 100}%")
    println("Speed: ${progress.speed} bytes/sec")
    println("ETA: ${progress.estimatedTimeRemaining} seconds")
}

// Load from local path
RunAnywhere.loadModelFromPath("/path/to/model.gguf")

// Check current model
val current = RunAnywhere.currentModel
println("Using: ${current?.name}")

// Unload model
RunAnywhere.unloadModel()
```

---

## Phase 3: LLM Generation APIs Parity

**Duration:** 2 days
**Goal:** Match Swift SDK's generation options and API surface
**Priority:** 🔴 Critical (from gap analysis Priority 3)

### 3.1 Align Generation Options (3 hours)

#### Current State Comparison

**Swift SDK (9 parameters):**
```swift
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

**Kotlin SDK (14 parameters - has MORE):**
```kotlin
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

    // KOTLIN HAS THESE EXTRAS (keep them):
    val topK: Int? = null,
    val repetitionPenalty: Float? = null,
    val frequencyPenalty: Float? = null,
    val presencePenalty: Float? = null,
    val seed: Int? = null,
    val contextLength: Int? = null
)
```

**Analysis:**
- ✅ Kotlin has ALL Swift parameters
- ✅ Kotlin has 6 additional parameters
- ✅ **NO CHANGES NEEDED** - Kotlin is already a superset

**Action:** Document this as a STRENGTH in gap analysis

#### Step 3.1.1: Verify Parameter Defaults Match

**File:** `src/commonMain/kotlin/com/runanywhere/sdk/models/GenerationOptions.kt`

**Verify defaults match Swift:**

| Parameter | Swift Default | Kotlin Default | Match? |
|-----------|--------------|----------------|--------|
| `maxTokens` | 100 | 100 | ✅ |
| `temperature` | 0.7 | 0.7f | ✅ |
| `topP` | 1.0 | 1.0f | ✅ |
| `enableRealTimeTracking` | true | true | ✅ |
| `stopSequences` | [] | emptyList() | ✅ |
| `streamingEnabled` | false | false | ✅ |
| `preferredExecutionTarget` | nil | null | ✅ |
| `structuredOutput` | nil | null | ✅ |
| `systemPrompt` | nil | null | ✅ |

**Result:** ✅ All defaults match

---

### 3.2 Add ensureDeviceRegistered() to Generation APIs (1 hour)

#### Already Done in Phase 1!

**Verify these methods call `ensureDeviceRegistered()`:**
- ✅ `chat(prompt: String)`
- ✅ `generate(prompt: String, options: RunAnywhereGenerationOptions?)`
- ✅ `generateStream(prompt: String, options: RunAnywhereGenerationOptions?)`

**Example from Phase 1:**
```kotlin
override suspend fun generate(prompt: String, options: RunAnywhereGenerationOptions?): String {
    ensureSDKInitialized()
    ensureDeviceRegistered()  // ✅ Added in Phase 1

    val result = generationService.generate(prompt, options ?: RunAnywhereGenerationOptions.DEFAULT)
    return result.text
}
```

---

### 3.3 Streaming API Alignment (2 hours)

#### Current State

**Swift (AsyncThrowingStream):**
```swift
public static func generateStream(
    _ prompt: String,
    options: RunAnywhereGenerationOptions?
) -> AsyncThrowingStream<String, Error> {
    // Returns tokens one by one
}
```

**Kotlin (Flow):**
```kotlin
override fun generateStream(
    prompt: String,
    options: RunAnywhereGenerationOptions?
): Flow<String> {
    // Returns tokens one by one
}
```

**Analysis:**
- ✅ Both use reactive streams (AsyncThrowingStream vs Flow)
- ✅ Both return `String` tokens
- ✅ **API surface matches** - no changes needed

**Note:** AsyncThrowingStream vs Flow is acceptable (platform idioms)

---

### 3.4 Add Conversation Context Management (2 hours)

#### Current State

**Kotlin has conversation context in LLMComponent:**
```kotlin
class LLMComponent {
    fun getConversationContext(): Context?
    fun setConversationContext(context: Context?)
    fun clearConversationContext()

    suspend fun generateWithHistory(
        messages: List<Message>,
        systemPrompt: String?
    ): LLMOutput
}
```

**Swift SDK:**
```swift
// No public conversation history API
// Only LLMComponent has internal context
```

**Analysis:**
- ✅ Kotlin BETTER than Swift in this area
- ✅ Keep Kotlin's conversation APIs
- ✅ Document as STRENGTH

**Action:** Expose conversation APIs in public RunAnywhere API

#### Step 3.4.1: Add Conversation APIs to RunAnywhere

**File:** `src/commonMain/kotlin/com/runanywhere/sdk/public/RunAnywhere.kt`

**Add methods:**

```kotlin
/**
 * Generate text with conversation history.
 * Kotlin SDK extension - not in Swift SDK.
 *
 * @param messages Conversation history
 * @param systemPrompt Optional system prompt
 * @param options Generation options
 * @return Generated text
 */
suspend fun generateWithHistory(
    messages: List<Message>,
    systemPrompt: String? = null,
    options: RunAnywhereGenerationOptions? = null
): String {
    ensureSDKInitialized()
    ensureDeviceRegistered()

    val llmComponent = ServiceContainer.shared.llmComponent
    val result = llmComponent.generateWithHistory(messages, systemPrompt)

    return result.text
}

/**
 * Clear conversation context.
 */
suspend fun clearConversationContext() {
    ensureSDKInitialized()

    val llmComponent = ServiceContainer.shared.llmComponent
    llmComponent.clearConversationContext()
}
```

---

### 3.5 Add Token Counting API (1 hour)

#### Current State

**Kotlin has token counting in LLMComponent:**
```kotlin
class LLMComponent {
    fun getTokenCount(text: String): Int
    fun fitsInContext(prompt: String, maxTokens: Int): Boolean
}
```

**Swift SDK:**
```swift
// No public token counting API
// Only internal in LLMComponent
```

**Analysis:**
- ✅ Kotlin BETTER than Swift
- ✅ Keep Kotlin's token APIs
- ✅ Document as STRENGTH

#### Step 3.5.1: Expose Token Counting in Public API

**File:** `src/commonMain/kotlin/com/runanywhere/sdk/public/RunAnywhere.kt`

**Add methods:**

```kotlin
/**
 * Estimate token count for text.
 * Kotlin SDK extension - not in Swift SDK.
 *
 * @param text Text to estimate
 * @return Estimated token count
 */
suspend fun estimateTokens(text: String): Int {
    ensureSDKInitialized()

    val llmComponent = ServiceContainer.shared.llmComponent
    return llmComponent.getTokenCount(text)
}

/**
 * Check if prompt fits in context window.
 *
 * @param prompt Prompt text
 * @param maxTokens Max tokens to generate
 * @return true if fits in context
 */
suspend fun fitsInContext(prompt: String, maxTokens: Int): Boolean {
    ensureSDKInitialized()

    val llmComponent = ServiceContainer.shared.llmComponent
    return llmComponent.fitsInContext(prompt, maxTokens)
}
```

---

### Phase 3 Deliverables

**Deliverable 3.1:** Generation options aligned
- ✅ Kotlin has ALL Swift parameters + 6 extras
- ✅ Defaults match Swift SDK
- ✅ Documented as STRENGTH

**Deliverable 3.2:** Lazy registration in all APIs
- ✅ Already done in Phase 1

**Deliverable 3.3:** Streaming API verified
- ✅ Flow matches AsyncThrowingStream semantically
- ✅ API surface matches

**Deliverable 3.4:** Conversation context exposed
- ✅ `generateWithHistory()` in public API
- ✅ `clearConversationContext()` in public API
- ✅ Kotlin BETTER than Swift

**Deliverable 3.5:** Token counting exposed
- ✅ `estimateTokens()` in public API
- ✅ `fitsInContext()` in public API
- ✅ Kotlin BETTER than Swift

**Success Criteria:**
```kotlin
// Basic generation
val response = RunAnywhere.generate("Hello", options = null)

// Streaming
RunAnywhere.generateStream("Tell me a story").collect { token ->
    print(token)
}

// Conversation history
val messages = listOf(
    Message(MessageRole.USER, "What is 2+2?"),
    Message(MessageRole.ASSISTANT, "4"),
    Message(MessageRole.USER, "And 4+4?")
)
val answer = RunAnywhere.generateWithHistory(messages)

// Token counting
val tokenCount = RunAnywhere.estimateTokens("Hello, world!")
val fits = RunAnywhere.fitsInContext("Long prompt...", maxTokens = 100)
```

---

## Phase 4: LLM Component Architecture

**Duration:** 2 days
**Goal:** Refine LLMComponent to match Swift patterns
**Priority:** 🔴 Critical (from gap analysis Priority 4)

### 4.1 Component State Alignment (2 hours)

#### Current State Comparison

**Swift (4 states - simpler):**
```swift
public enum ComponentState: String, Sendable {
    case notInitialized = "not_initialized"
    case initializing = "initializing"
    case ready = "ready"
    case failed = "failed"
}
```

**Kotlin (9 states - includes downloads):**
```kotlin
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
```

**Decision:**
- ✅ **KEEP Kotlin's approach** (more detailed)
- ✅ Download states are useful for progress tracking
- ✅ Document as DIFFERENT but VALID

**Rationale:**
- Swift delegates downloads to ModelLoadingService
- Kotlin handles downloads in component
- Both approaches work, Kotlin gives more visibility

**Action:** No changes needed, document difference

---

### 4.2 Provider Pattern Verification (2 hours)

#### Verify Provider Interface Matches Swift

**Swift (Protocol):**
```swift
public protocol LLMServiceProvider {
    var name: String { get }
    var framework: LLMFramework { get }

    func createLLMService(configuration: LLMConfiguration) async throws -> LLMService
    func canHandle(modelId: String?) -> Bool
}
```

**Kotlin (Interface) - Already done in Phase 0:**
```kotlin
interface LLMServiceProvider {
    val name: String
    val framework: LLMFramework
    val supportedFeatures: Set<String>  // Kotlin has MORE

    suspend fun createLLMService(configuration: LLMConfiguration): LLMService
    fun canHandle(modelId: String?): Boolean

    // Kotlin has additional advanced features:
    fun validateModelCompatibility(model: ModelInfo): ModelCompatibilityResult
    suspend fun downloadModel(modelId: String, onProgress: (Float) -> Unit): ModelInfo
    fun estimateMemoryRequirements(model: ModelInfo): Long
    fun getOptimalConfiguration(model: ModelInfo): HardwareConfiguration
}
```

**Analysis:**
- ✅ Kotlin has ALL Swift methods
- ✅ Kotlin has 4 additional advanced methods
- ✅ **Kotlin BETTER than Swift**

**Action:** Document as STRENGTH, no changes needed

---

### 4.3 Component Initialization Flow (3 hours)

#### Verify Flow Matches Swift Pattern

**Swift:**
```swift
@MainActor
public final class LLMComponent: BaseComponent<LLMService> {

    public override func createService() async throws -> LLMService {
        // Get provider from registry
        let provider = ModuleRegistry.shared.llmProvider(for: configuration.modelId)

        guard let provider = provider else {
            throw SDKError.componentNotAvailable("No LLM provider")
        }

        // Provider creates service
        let service = try await provider.createLLMService(configuration: configuration)

        return service
    }
}
```

**Kotlin (Current):**
```kotlin
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
}
```

**Analysis:**
- ⚠️ Kotlin downloads in component (Swift delegates to ModelLoadingService)
- ✅ Both use ModuleRegistry to find provider
- ✅ Both call `provider.createLLMService()`

**Decision:**
- ✅ **KEEP Kotlin's approach** (more self-contained)
- ✅ Consider extracting download to separate method for clarity

#### Step 4.3.1: Refactor Download Logic for Clarity

**File:** `src/commonMain/kotlin/com/runanywhere/sdk/components/llm/LLMComponent.kt`

**Refactor createService():**

```kotlin
override suspend fun createService(): LLMServiceWrapper {
    // 1. Ensure model is available (download if needed)
    ensureModelAvailable()

    // 2. Get provider from registry
    val provider = ModuleRegistry.llmProvider(configuration.modelId)
        ?: throw SDKError.ComponentNotAvailable(
            "No LLM provider available for model: ${configuration.modelId}"
        )

    // 3. Create service via provider
    val llmService = provider.createLLMService(configuration)

    // 4. Wrap and return
    return LLMServiceWrapper(llmService)
}

/**
 * Ensure model is available locally (download if needed).
 * Separated for clarity.
 */
private suspend fun ensureModelAvailable() {
    val modelId = configuration.modelId ?: return

    val modelInfo = serviceContainer?.modelRegistry?.getModel(modelId)
        ?: throw SDKError.ModelNotFound(modelId)

    // Check if already downloaded
    if (isModelDownloaded(modelInfo.id)) {
        logger.info("✅ Model already downloaded: ${modelInfo.id}")
        return
    }

    // Download with progress tracking
    transitionTo(ComponentState.DOWNLOAD_REQUIRED)
    transitionTo(ComponentState.DOWNLOADING)

    try {
        downloadModel(modelInfo.id)
        transitionTo(ComponentState.DOWNLOADED)
        logger.info("✅ Model downloaded: ${modelInfo.id}")
    } catch (e: Exception) {
        transitionTo(ComponentState.FAILED)
        throw SDKError.ModelDownloadFailed("Failed to download model: ${modelInfo.id}", e)
    }
}
```

---

### 4.4 Error Handling Alignment (1 hour)

#### Verify Error Types Match

**Swift (Enum with Associated Values):**
```swift
public enum SDKError: Error, Sendable {
    case notInitialized
    case invalidAPIKey(String)
    case componentNotAvailable(String)
    case checksumMismatch(expected: String, actual: String)
}
```

**Kotlin (Sealed Class Hierarchy):**
```kotlin
sealed class SDKError(message: String) : Exception(message) {
    object NotInitialized : SDKError("SDK not initialized")
    data class InvalidAPIKey(val key: String) : SDKError("Invalid API key")
    data class ComponentNotAvailable(val component: String) : SDKError("Component not available")
    data class ChecksumMismatch(val expected: String, val actual: String, val reason: String) :
        SDKError("Checksum mismatch")
}
```

**Analysis:**
- ✅ Both use type-safe error handling
- ✅ Different approaches (Swift enum vs Kotlin sealed class)
- ✅ **Both are idiomatic for their platforms**

**Action:** No changes needed, document as DIFFERENT but VALID

---

### Phase 4 Deliverables

**Deliverable 4.1:** Component states documented
- ✅ Kotlin uses 9 states (more detailed than Swift's 4)
- ✅ Documented as DIFFERENT but VALID
- ✅ No changes needed

**Deliverable 4.2:** Provider pattern verified
- ✅ Kotlin has ALL Swift methods + 4 advanced methods
- ✅ Documented as STRENGTH

**Deliverable 4.3:** Initialization flow refactored
- ✅ Download logic extracted to `ensureModelAvailable()`
- ✅ Clearer separation of concerns
- ✅ Both Swift and Kotlin patterns respected

**Deliverable 4.4:** Error handling verified
- ✅ Both use type-safe errors
- ✅ Platform-appropriate patterns
- ✅ Documented as DIFFERENT but VALID

**Success Criteria:**
```kotlin
// Component initialization works seamlessly
val llmComponent = LLMComponent(LLMConfiguration(modelId = "llama-2-7b"))
llmComponent.initialize()  // Downloads model if needed, finds provider, creates service

// Error handling is type-safe
try {
    llmComponent.initialize()
} catch (e: SDKError.ComponentNotAvailable) {
    println("No provider for model: ${e.component}")
} catch (e: SDKError.ModelNotFound) {
    println("Model not found: ${e.modelId}")
}
```

---

## Phase 5: Testing & Validation

**Duration:** 2 days
**Goal:** Verify all changes work end-to-end
**Priority:** 🔴 Critical

### 5.1 Unit Tests (1 day)

#### Create Test Suite for New Features

**File:** `src/commonTest/kotlin/com/runanywhere/sdk/LazyRegistrationTest.kt`

```kotlin
package com.runanywhere.sdk

import kotlinx.coroutines.test.runTest
import kotlin.test.*

class LazyRegistrationTest {

    @Test
    fun testLazyDeviceRegistration() = runTest {
        // Initialize SDK
        RunAnywhere.initialize(
            apiKey = "test-key",
            baseURL = "https://api.example.com",
            environment = SDKEnvironment.DEVELOPMENT
        )

        // Should NOT be registered yet
        assertFalse(RunAnywhere.isDeviceRegistered())

        // First API call should trigger registration
        RunAnywhere.generate("Hello")

        // Should be registered now
        assertTrue(RunAnywhere.isDeviceRegistered())
    }

    @Test
    fun testRegistrationRetry() = runTest {
        // Test retry logic with failing network
        // ...
    }
}
```

**File:** `src/commonTest/kotlin/com/runanywhere/sdk/ChecksumVerificationTest.kt`

```kotlin
class ChecksumVerificationTest {

    @Test
    fun testSHA256Verification() = runTest {
        val modelInfo = ModelInfo(
            id = "test-model",
            name = "Test Model",
            sha256Checksum = "abc123...",
            downloadSize = 1024L
        )

        // Download should verify checksum
        // ...
    }

    @Test
    fun testChecksumMismatchThrows() = runTest {
        // Should throw ChecksumMismatch error
        // ...
    }
}
```

**File:** `src/commonTest/kotlin/com/runanywhere/sdk/DownloadProgressTest.kt`

```kotlin
class DownloadProgressTest {

    @Test
    fun testDownloadProgressMetadata() = runTest {
        val progressList = mutableListOf<DownloadProgress>()

        RunAnywhere.downloadModel("test-model").collect { progress ->
            progressList.add(progress)
        }

        // Verify progress includes speed and ETA
        val lastProgress = progressList.last()
        assertNotNull(lastProgress.speed)
        assertNotNull(lastProgress.estimatedTimeRemaining)
    }
}
```

---

### 5.2 Integration Tests (1 day)

#### Test End-to-End Flows

**File:** `src/jvmTest/kotlin/com/runanywhere/sdk/EndToEndTest.kt`

```kotlin
class EndToEndTest {

    @Test
    fun testFullTextGenerationFlow() = runTest {
        // 1. Initialize SDK
        RunAnywhere.initialize(
            apiKey = "test-key",
            baseURL = "https://api.example.com",
            environment = SDKEnvironment.DEVELOPMENT
        )

        // 2. Load model (should download if needed)
        RunAnywhere.loadModel("llama-2-7b")

        // 3. Generate text (should register device lazily)
        val response = RunAnywhere.generate("Hello, world!")

        // 4. Verify response
        assertTrue(response.isNotEmpty())

        // 5. Verify device registered
        assertTrue(RunAnywhere.isDeviceRegistered())

        // 6. Verify current model tracked
        assertNotNull(RunAnywhere.currentModel)
        assertEquals("llama-2-7b", RunAnywhere.currentModel?.id)
    }

    @Test
    fun testStreamingGeneration() = runTest {
        RunAnywhere.initialize(...)
        RunAnywhere.loadModel("llama-2-7b")

        val tokens = mutableListOf<String>()
        RunAnywhere.generateStream("Tell me a story").collect { token ->
            tokens.add(token)
        }

        assertTrue(tokens.isNotEmpty())
        assertTrue(tokens.size > 1) // Multiple tokens
    }

    @Test
    fun testModelUnloading() = runTest {
        RunAnywhere.initialize(...)
        RunAnywhere.loadModel("llama-2-7b")

        assertNotNull(RunAnywhere.currentModel)

        RunAnywhere.unloadModel()

        assertNull(RunAnywhere.currentModel)
    }
}
```

---

### 5.3 Manual Validation (4 hours)

#### Create Test Script

**File:** `sdk/runanywhere-kotlin/scripts/test-text-generation.sh`

```bash
#!/bin/bash

# Test script for text-to-text generation parity
set -e

echo "=== Kotlin SDK Text-to-Text Generation Test ==="

# 1. Build SDK
echo "Building SDK..."
./gradlew :build
./gradlew :modules:runanywhere-llm-llamacpp:build

# 2. Publish to Maven Local
echo "Publishing to Maven Local..."
./gradlew publishToMavenLocal

# 3. Run JVM test app
echo "Running JVM test app..."
cd ../../examples/test-app-jvm
./gradlew run

echo "✅ All tests passed!"
```

#### Create Simple Test App

**File:** `examples/test-app-jvm/src/main/kotlin/TestApp.kt`

```kotlin
package com.runanywhere.test

import com.runanywhere.sdk.RunAnywhere
import com.runanywhere.sdk.SDKEnvironment
import kotlinx.coroutines.runBlocking

fun main() = runBlocking {
    println("=== Kotlin SDK Text Generation Test ===")

    // 1. Initialize (should be simple)
    println("\n1. Initializing SDK...")
    RunAnywhere.initialize(
        apiKey = "test-key",
        baseURL = "https://api.example.com",
        environment = SDKEnvironment.DEVELOPMENT
    )
    println("✅ SDK initialized")

    // 2. Load model (should download if needed)
    println("\n2. Loading model...")
    RunAnywhere.loadModel("llama-2-7b-q4")
    println("✅ Model loaded: ${RunAnywhere.currentModel?.name}")

    // 3. Generate text (should register device lazily)
    println("\n3. Generating text...")
    val response = RunAnywhere.generate("What is the capital of France?")
    println("Response: $response")
    println("✅ Device registered: ${RunAnywhere.isDeviceRegistered()}")

    // 4. Stream generation
    println("\n4. Streaming generation...")
    print("Response: ")
    RunAnywhere.generateStream("Tell me a short joke").collect { token ->
        print(token)
    }
    println("\n✅ Streaming works")

    // 5. Test download progress
    println("\n5. Testing download progress...")
    RunAnywhere.downloadModel("another-model").collect { progress ->
        println("Downloaded: ${progress.percentComplete * 100}% " +
                "(${progress.speed} bytes/sec, " +
                "ETA: ${progress.estimatedTimeRemaining}s)")
    }
    println("✅ Download progress works")

    // 6. Unload model
    println("\n6. Unloading model...")
    RunAnywhere.unloadModel()
    println("✅ Model unloaded, current model: ${RunAnywhere.currentModel}")

    println("\n🎉 All tests passed!")
}
```

---

### 5.4 Performance Benchmarking (2 hours)

#### Compare Kotlin vs Swift Performance

**File:** `sdk/runanywhere-kotlin/scripts/benchmark.kt`

```kotlin
import kotlinx.coroutines.runBlocking
import kotlin.system.measureTimeMillis

fun main() = runBlocking {
    println("=== Performance Benchmark ===")

    RunAnywhere.initialize(...)
    RunAnywhere.loadModel("llama-2-7b")

    // Benchmark 1: Initialization time
    val initTime = measureTimeMillis {
        RunAnywhere.initialize(...)
    }
    println("Initialization: ${initTime}ms")

    // Benchmark 2: Model loading time
    val loadTime = measureTimeMillis {
        RunAnywhere.loadModel("llama-2-7b")
    }
    println("Model loading: ${loadTime}ms")

    // Benchmark 3: First token time
    var firstTokenTime: Long = 0
    val totalTime = measureTimeMillis {
        var firstToken = true
        RunAnywhere.generateStream("Hello").collect { token ->
            if (firstToken) {
                firstTokenTime = System.currentTimeMillis()
                firstToken = false
            }
        }
    }
    println("Time to first token: ${firstTokenTime}ms")
    println("Total generation time: ${totalTime}ms")

    // Compare with Swift SDK (manual comparison)
    println("\nSwift SDK benchmarks (for comparison):")
    println("Initialization: ~50ms")
    println("Model loading: ~500ms")
    println("Time to first token: ~200ms")
}
```

---

### Phase 5 Deliverables

**Deliverable 5.1:** Unit test suite
- ✅ LazyRegistrationTest
- ✅ ChecksumVerificationTest
- ✅ DownloadProgressTest
- ✅ All tests pass

**Deliverable 5.2:** Integration tests
- ✅ EndToEndTest covers full flow
- ✅ Streaming generation tested
- ✅ Model unloading tested

**Deliverable 5.3:** Manual validation
- ✅ Test app runs successfully
- ✅ All features work as expected
- ✅ No regressions

**Deliverable 5.4:** Performance benchmarks
- ✅ Benchmarks run
- ✅ Compared to Swift SDK
- ✅ Performance is comparable

**Success Criteria:**
```bash
# All tests pass
./gradlew test
# > Task :test PASSED

# Test app runs
cd examples/test-app-jvm
./gradlew run
# 🎉 All tests passed!

# Benchmarks show good performance
./gradlew benchmark
# Initialization: ~60ms (vs Swift ~50ms) ✅
# Model loading: ~550ms (vs Swift ~500ms) ✅
# TTFT: ~220ms (vs Swift ~200ms) ✅
```

---

## Implementation Checklist

### Phase 0: Module Structure ✅
- [ ] Enable LlamaCpp module in `settings.gradle.kts`
- [ ] Create `LLMServiceProvider` interface in core SDK
- [ ] Move `LlamaCppService` to module
- [ ] Create `LlamaCppServiceProvider` implementation
- [ ] Create `LlamaCppModule` auto-registration
- [ ] Update module `build.gradle.kts`
- [ ] Verify builds (core + module)
- [ ] Remove/merge `runanywhere-core` module
- [ ] Update documentation

### Phase 1: Initialization ✅
- [ ] Add `ensureDeviceRegistered()` function
- [ ] Add retry logic with exponential backoff
- [ ] Update `generate()` to call `ensureDeviceRegistered()`
- [ ] Update all public APIs to call `ensureDeviceRegistered()`
- [ ] Add `ensureBootstrapped()` to ServiceContainer
- [ ] Make `bootstrap()` optional
- [ ] Fix EventBus kotlinx.datetime issue
- [ ] Add `initialize(apiKey, baseURL, environment)` overload
- [ ] Verify lazy registration works

### Phase 2: Model Management ✅
- [ ] Update `DownloadProgress` model with speed/ETA
- [ ] Update `KtorDownloadService` to calculate speed/ETA
- [ ] Change `downloadModel()` return type to `Flow<DownloadProgress>`
- [ ] Add `downloadModelSimple()` for backward compatibility
- [ ] Add `calculateSHA256()` and `calculateMD5()` platform functions
- [ ] Use `ModelIntegrityVerifier` in `ModelManager`
- [ ] Add `unloadModel()` to `LLMComponent`
- [ ] Add `unloadModel()` to `LLMService` interface
- [ ] Implement `unloadModel()` in `LlamaCppService`
- [ ] Add `unloadModel()` to `RunAnywhere` public API
- [ ] Add `currentModel` property tracking
- [ ] Add `loadModelFromPath()` for offline models
- [ ] Add Android asset loading support

### Phase 3: Generation APIs ✅
- [ ] Verify generation options match Swift defaults
- [ ] Verify `ensureDeviceRegistered()` in all generation APIs
- [ ] Verify streaming API matches Swift semantics
- [ ] Add `generateWithHistory()` to public API
- [ ] Add `clearConversationContext()` to public API
- [ ] Add `estimateTokens()` to public API
- [ ] Add `fitsInContext()` to public API

### Phase 4: Component Architecture ✅
- [ ] Document component state differences (9 vs 4 states)
- [ ] Verify provider interface matches Swift
- [ ] Refactor `createService()` to extract download logic
- [ ] Add `ensureModelAvailable()` helper
- [ ] Verify error handling patterns
- [ ] Document architectural differences

### Phase 5: Testing ✅
- [ ] Write unit tests for lazy registration
- [ ] Write unit tests for checksum verification
- [ ] Write unit tests for download progress
- [ ] Write integration test for end-to-end flow
- [ ] Write integration test for streaming
- [ ] Write integration test for model unloading
- [ ] Create manual test script
- [ ] Create simple test app
- [ ] Run performance benchmarks
- [ ] Compare with Swift SDK

---

## Success Criteria

### Functional Criteria

**1. Initialization matches Swift SDK:**
```kotlin
// Simple initialization (no network)
RunAnywhere.initialize(
    apiKey = "key",
    baseURL = "https://api.example.com",
    environment = SDKEnvironment.DEVELOPMENT
)

// Lazy registration on first API call
val response = RunAnywhere.generate("Hello") // Registers automatically
assert(RunAnywhere.isDeviceRegistered())
```

**2. Model management matches Swift SDK:**
```kotlin
// Download with detailed progress
RunAnywhere.downloadModel("llama-2-7b").collect { progress ->
    println("${progress.percentComplete * 100}%")
    println("Speed: ${progress.speed} bytes/sec")
    println("ETA: ${progress.estimatedTimeRemaining}s")
}

// Load from local path
RunAnywhere.loadModelFromPath("/path/to/model.gguf")

// Current model tracking
val current = RunAnywhere.currentModel
println("Using: ${current?.name}")

// Unload model
RunAnywhere.unloadModel()
assert(RunAnywhere.currentModel == null)
```

**3. Generation APIs match Swift SDK:**
```kotlin
// Simple chat
val response = RunAnywhere.chat("Hello")

// Streaming
RunAnywhere.generateStream("Tell me a story").collect { token ->
    print(token)
}

// With options
val options = RunAnywhereGenerationOptions(
    temperature = 0.7f,
    maxTokens = 500,
    topP = 0.9f
)
val response = RunAnywhere.generate("Prompt", options)

// Conversation history (Kotlin advantage)
val messages = listOf(
    Message(MessageRole.USER, "What is 2+2?"),
    Message(MessageRole.ASSISTANT, "4"),
    Message(MessageRole.USER, "And 4+4?")
)
val answer = RunAnywhere.generateWithHistory(messages)

// Token counting (Kotlin advantage)
val tokens = RunAnywhere.estimateTokens("Hello, world!")
val fits = RunAnywhere.fitsInContext("Long prompt...", maxTokens = 100)
```

**4. Module structure matches Swift SDK:**
```
✅ Core SDK (runanywhere-kotlin/) - NO native code
✅ LlamaCpp module (modules/runanywhere-llm-llamacpp/) - native bindings
✅ Auto-registration working
✅ Clean separation of concerns
```

### Quality Criteria

**1. All builds succeed:**
```bash
./gradlew :build                               # ✅ SUCCESS
./gradlew :modules:runanywhere-llm-llamacpp:build # ✅ SUCCESS
./gradlew build                                # ✅ SUCCESS (all modules)
```

**2. All tests pass:**
```bash
./gradlew test                                 # ✅ 100% pass rate
```

**3. No regressions:**
```bash
# Existing functionality still works
./gradlew :examples:android:RunAnywhereAI:build # ✅ SUCCESS
```

**4. Performance is comparable to Swift:**
```
Initialization: ~60ms (vs Swift ~50ms)  ✅ Within 20%
Model loading: ~550ms (vs Swift ~500ms)  ✅ Within 10%
TTFT: ~220ms (vs Swift ~200ms)           ✅ Within 10%
```

### Documentation Criteria

**1. Architecture documented:**
- ✅ Updated `ARCHITECTURE.md` with new module structure
- ✅ Created `MODULE-STRUCTURE.md` (if missing)
- ✅ Documented design decisions

**2. API differences documented:**
- ✅ Kotlin advantages documented (conversation, token counting)
- ✅ Architectural differences explained (state machine, downloads)
- ✅ Platform idioms respected (Flow vs AsyncThrowingStream)

**3. Migration guide created:**
- ✅ Guide for apps using old initialization
- ✅ Backward compatibility notes
- ✅ Breaking changes (if any)

---

## Timeline Summary

| Day | Phase | Tasks | Deliverables |
|-----|-------|-------|--------------|
| **Day 1** | Phase 0 (Part 1) | Enable module, create provider interface | Module structure started |
| **Day 2** | Phase 0 (Part 2) | Move LlamaCpp to module, verify builds | Clean module separation |
| **Day 3** | Phase 1 (Part 1) | Lazy registration, fix EventBus | Lazy registration working |
| **Day 4** | Phase 1 (Part 2) | Optional bootstrap, API alignment | Initialization matches Swift |
| **Day 5** | Phase 2 (Part 1) | Download progress, checksums | Enhanced downloads |
| **Day 6** | Phase 2 (Part 2) | Model unloading, current model tracking | Model management complete |
| **Day 7** | Phase 2 (Part 3) | Offline loading, asset support | All model features working |
| **Day 8** | Phase 3 | Generation options, conversation APIs | Generation APIs complete |
| **Day 9** | Phase 4 | Component architecture refinement | LLMComponent refactored |
| **Day 10** | Phase 5 (Part 1) | Unit tests, integration tests | Test suite complete |
| **Day 11** | Phase 5 (Part 2) | Manual validation, test app | End-to-end validation |
| **Day 12** | Phase 5 (Part 3) | Performance benchmarking | Performance verified |
| **Day 13** | Buffer | Bug fixes, documentation | Ready for production |

**Total Duration:** 13 days (with 1-day buffer)

---

## Appendix A: Key Files Modified

### Core SDK Files

**Modified:**
- `src/commonMain/kotlin/com/runanywhere/sdk/public/RunAnywhere.kt` - Main API
- `src/commonMain/kotlin/com/runanywhere/sdk/foundation/ServiceContainer.kt` - Lazy bootstrap
- `src/commonMain/kotlin/com/runanywhere/sdk/events/SDKEvent.kt` - Fix datetime issue
- `src/commonMain/kotlin/com/runanywhere/sdk/components/llm/LLMComponent.kt` - Refactor createService()
- `src/commonMain/kotlin/com/runanywhere/sdk/components/llm/LLMServiceProvider.kt` - Enhanced interface
- `src/commonMain/kotlin/com/runanywhere/sdk/services/download/DownloadProgress.kt` - Add metadata
- `src/commonMain/kotlin/com/runanywhere/sdk/services/download/KtorDownloadService.kt` - Calculate speed/ETA
- `src/commonMain/kotlin/com/runanywhere/sdk/models/ModelManager.kt` - Add checksum verification
- `src/jvmAndroidMain/kotlin/com/runanywhere/sdk/platform/Crypto.kt` - Add checksum functions

**New Files:**
- `src/commonMain/kotlin/com/runanywhere/sdk/components/llm/LLMServiceProvider.kt` - Provider interface
- `src/jvmMain/kotlin/com/runanywhere/sdk/platform/Crypto.kt` - JVM crypto
- `src/androidMain/kotlin/com/runanywhere/sdk/platform/Crypto.kt` - Android crypto
- `src/androidMain/kotlin/com/runanywhere/sdk/platform/AndroidAssetLoader.kt` - Asset loading

### Module Files

**New Files:**
- `modules/runanywhere-llm-llamacpp/src/commonMain/kotlin/LlamaCppServiceProvider.kt`
- `modules/runanywhere-llm-llamacpp/src/commonMain/kotlin/LlamaCppModule.kt`
- `modules/runanywhere-llm-llamacpp/build.gradle.kts` - Updated

**Modified:**
- `modules/runanywhere-llm-llamacpp/src/jvmAndroidMain/kotlin/LlamaCppService.kt` - Add unloadModel()

### Configuration Files

**Modified:**
- `settings.gradle.kts` - Enable LlamaCpp module
- `build.gradle.kts` (root) - Update dependencies

---

## Appendix B: Migration Guide for Apps

### For Apps Using Old Initialization

**Old Way:**
```kotlin
// Old initialization (still works for backward compatibility)
RunAnywhere.initialize(platformContext, environment, apiKey, baseURL)
RunAnywhere.bootstrap(SDKInitParams(...))
```

**New Way (Recommended):**
```kotlin
// New simplified initialization
RunAnywhere.initialize(
    apiKey = "your-key",
    baseURL = "https://api.example.com",
    environment = SDKEnvironment.DEVELOPMENT
)

// No explicit bootstrap needed - happens automatically
```

### Breaking Changes

**None!** All changes are backward compatible.

### Deprecations

**None at this time.** Old APIs remain supported.

---

## Appendix C: Comparison Matrix

| Feature | Swift SDK | Kotlin SDK (Before) | Kotlin SDK (After) | Status |
|---------|-----------|---------------------|--------------------| -------|
| **Initialization** | 5-step, no network | 8-step, requires network | 5-step, lazy registration | ✅ PARITY |
| **Device Registration** | Lazy (automatic) | Explicit (manual) | Lazy (automatic) | ✅ PARITY |
| **Module Structure** | Core + Modules | Mixed | Core + Modules | ✅ PARITY |
| **Download Progress** | Speed, ETA, state | Percentage only | Speed, ETA, state | ✅ PARITY |
| **Checksum Verification** | ✅ SHA256 | ❌ Missing | ✅ SHA256/MD5 | ✅ PARITY |
| **Model Unloading** | ✅ Has API | ❌ Missing | ✅ Has API | ✅ PARITY |
| **Current Model** | ✅ Tracked | ❌ Not tracked | ✅ Tracked | ✅ PARITY |
| **Offline Loading** | ✅ Bundle support | ❌ Missing | ✅ Path/asset support | ✅ PARITY |
| **Generation Options** | 9 params | 14 params | 14 params | ✅ ADVANTAGE |
| **Conversation API** | ❌ Missing | ✅ Has it | ✅ Has it | ✅ ADVANTAGE |
| **Token Counting** | ❌ Missing | ✅ Has it | ✅ Has it | ✅ ADVANTAGE |
| **EventBus** | ✅ Working | 🔴 Broken | ✅ Fixed | ✅ PARITY |
| **Component States** | 4 states | 9 states | 9 states | ✅ ADVANTAGE |
| **Provider Interface** | 4 methods | 8 methods | 8 methods | ✅ ADVANTAGE |

**Overall:** ✅ **Full parity achieved + 5 advantages over Swift SDK**

---

## Document End

This plan provides a complete, step-by-step guide to aligning the Kotlin SDK with Swift SDK for text-to-text generation. Follow each phase sequentially, and verify deliverables at each checkpoint.

**Next Steps:**
1. Review this plan with the team
2. Begin Phase 0 immediately
3. Track progress using the Implementation Checklist
4. Update this document as you discover edge cases

Good luck! 🚀
