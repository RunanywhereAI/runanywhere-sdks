# KMP SDK Modular Architecture Design

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [iOS SDK Modular Analysis](#ios-sdk-modular-analysis)
3. [KMP Modular Architecture Design](#kmp-modular-architecture-design)
4. [Module Specifications](#module-specifications)
5. [Gradle Multi-Module Setup](#gradle-multi-module-setup)
6. [Integration Patterns](#integration-patterns)
7. [Whisper JNI Module Design](#whisper-jni-module-design)
8. [Benefits Analysis](#benefits-analysis)
9. [Migration Path](#migration-path)
10. [Usage Examples](#usage-examples)
11. [Implementation Roadmap](#implementation-roadmap)

---

## Executive Summary

This document outlines a comprehensive modular architecture strategy for the RunAnywhere Kotlin Multiplatform (KMP) SDK that mirrors the iOS SDK's successful modular approach. The design introduces standalone modules for specific AI capabilities while maintaining a core SDK foundation, enabling developers to include only the functionality they need.

### Key Objectives

- **Reduced SDK Size**: Developers can include only required modules
- **Independent Updates**: Modules can be updated independently
- **Better Separation of Concerns**: Clear boundaries between AI capabilities
- **Easier Third-Party Integrations**: Well-defined interfaces for external providers
- **Platform Consistency**: Similar architecture patterns across iOS and Android/JVM

---

## iOS SDK Modular Analysis

### Current iOS Modular Structure

The iOS SDK demonstrates an effective modular architecture:

```
runanywhere-swift/
├── Sources/RunAnywhere/           # Core SDK
└── Modules/                       # Standalone modules
    ├── WhisperKitTranscription/   # STT module using WhisperKit
    ├── LLMSwift/                  # LLM integration module
    └── FluidAudioDiarization/     # Speaker diarization module
```

### Key Patterns from iOS SDK

1. **Separate SPM Packages**: Each module is its own Swift Package Manager package
2. **Core SDK Dependency**: Modules depend on the core SDK, not vice versa
3. **Service Provider Pattern**: Modules register service providers with the core SDK
4. **Clean Interfaces**: Well-defined protocols for integration
5. **Optional Dependencies**: Core SDK works without modules, gains functionality when present

### iOS Module Examples

#### WhisperKitTranscription Module
```swift
// Package.swift structure
dependencies: [
    .package(url: "https://github.com/argmaxinc/WhisperKit", exact: "0.13.1"),
    .package(name: "runanywhere-swift", path: "../../"),  // Core SDK dependency
]

// Service Provider Implementation
public class WhisperKitServiceProvider: STTServiceProvider {
    public func createSTTService(configuration: STTConfiguration) -> STTService
    public func canHandle(modelId: String) -> Bool
    public let name: String = "WhisperKit"
}
```

---

## KMP Modular Architecture Design

### Proposed Module Structure

```
runanywhere-kotlin/
├── modules/
│   ├── runanywhere-core/              # Core SDK functionality
│   ├── runanywhere-whisper-stt/       # Whisper STT module
│   ├── runanywhere-llm/               # LLM integration module
│   ├── runanywhere-speaker-diarization/ # Speaker identification module
│   ├── runanywhere-vad/               # Voice Activity Detection module
│   └── runanywhere-tts/               # Text-to-Speech module
└── examples/
    └── modular-integration/           # Integration examples
```

### Module Dependency Graph

```
                    ┌─────────────────────┐
                    │   Application       │
                    └─────────────────────┘
                             │
                             ▼
    ┌─────────────────────────────────────────────────────┐
    │                                                     │
    ▼                    ▼                    ▼           ▼
┌─────────────┐  ┌─────────────────┐  ┌──────────────┐  ┌──────────────┐
│whisper-stt  │  │       llm       │  │speaker-diariz│  │     vad      │
└─────────────┘  └─────────────────┘  └──────────────┘  └──────────────┘
    │                    │                    │              │
    └────────────────────┼────────────────────┼──────────────┘
                         ▼
              ┌─────────────────────┐
              │   runanywhere-core  │
              └─────────────────────┘
```

### Module Characteristics

1. **Standalone Publishing**: Each module publishes independently
2. **Core SDK Integration**: All modules depend on `runanywhere-core`
3. **Provider Pattern**: Modules register service providers
4. **Platform Support**: Full JVM, Android, and Native support where applicable
5. **Optional Dependencies**: Graceful degradation when modules are missing

---

## Module Specifications

### 1. `runanywhere-core` Module

**Purpose**: Foundation SDK with basic functionality and module registry

**Components**:
- `ModuleRegistry` - Plugin registration system
- `RunAnywhere` - Main SDK entry point
- Base service interfaces (`STTService`, `LLMService`, etc.)
- Configuration management
- Authentication and networking
- Telemetry and logging
- Memory management

**Gradle Coordinates**: `com.runanywhere.sdk:runanywhere-core:$version`

**Platform Support**: JVM, Android, Native

### 2. `runanywhere-whisper-stt` Module

**Purpose**: Speech-to-Text using whisper.cpp JNI bindings

**Components**:
- `WhisperSTTProvider` - Service provider implementation
- `WhisperSTTService` - Whisper-based STT service
- Native library management
- Model loading and inference
- Audio preprocessing

**Dependencies**:
- `runanywhere-core`
- `whisper-jni` native library
- Platform-specific audio libraries

**Gradle Coordinates**: `com.runanywhere.sdk:runanywhere-whisper-stt:$version`

**Platform Support**: JVM, Android (Linux ARM64/x64 native libraries)

### 3. `runanywhere-llm` Module

**Purpose**: Large Language Model integration

**Components**:
- `LLMProvider` - Service provider for LLM operations
- Multiple backend support (llama.cpp, ONNX Runtime, etc.)
- Model management and loading
- Generation options and streaming
- Context management

**Dependencies**:
- `runanywhere-core`
- Backend-specific libraries (llama.cpp, ONNX, etc.)

**Gradle Coordinates**: `com.runanywhere.sdk:runanywhere-llm:$version`

**Platform Support**: JVM, Android, Native

### 4. `runanywhere-speaker-diarization` Module

**Purpose**: Speaker identification and diarization

**Components**:
- `SpeakerDiarizationProvider` - Service provider
- Audio embedding extraction
- Speaker clustering algorithms
- Voice profile management
- Integration with STT for labeled transcripts

**Dependencies**:
- `runanywhere-core`
- Audio processing libraries

**Gradle Coordinates**: `com.runanywhere.sdk:runanywhere-speaker-diarization:$version`

**Platform Support**: JVM, Android

### 5. `runanywhere-vad` Module

**Purpose**: Voice Activity Detection

**Components**:
- `VADProvider` - Service provider implementation
- Energy-based VAD (cross-platform)
- ML-based VAD (platform-specific)
- Audio preprocessing and analysis

**Dependencies**:
- `runanywhere-core`
- Platform-specific VAD libraries (WebRTC on Android)

**Gradle Coordinates**: `com.runanywhere.sdk:runanywhere-vad:$version`

**Platform Support**: JVM, Android

### 6. `runanywhere-tts` Module

**Purpose**: Text-to-Speech synthesis

**Components**:
- `TTSProvider` - Service provider
- Platform-specific TTS engines
- Voice management
- Audio format handling

**Dependencies**:
- `runanywhere-core`
- Platform-specific TTS libraries

**Gradle Coordinates**: `com.runanywhere.sdk:runanywhere-tts:$version`

**Platform Support**: JVM, Android

---

## Gradle Multi-Module Setup

### Root Project Structure

```kotlin
// settings.gradle.kts
pluginManagement {
    repositories {
        google()
        gradlePluginPortal()
        mavenCentral()
    }
}

rootProject.name = "runanywhere-kotlin"

// Core module
include(":modules:runanywhere-core")

// Feature modules
include(":modules:runanywhere-whisper-stt")
include(":modules:runanywhere-llm")
include(":modules:runanywhere-speaker-diarization")
include(":modules:runanywhere-vad")
include(":modules:runanywhere-tts")

// Examples
include(":examples:modular-integration")
```

### Root Build Configuration

```kotlin
// build.gradle.kts (root)
plugins {
    alias(libs.plugins.kotlin.multiplatform) apply false
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.kotlin.serialization) apply false
    id("maven-publish")
}

allprojects {
    group = "com.runanywhere.sdk"
    version = "0.1.0"

    repositories {
        google()
        mavenCentral()
        mavenLocal()
    }
}

subprojects {
    apply(plugin = "maven-publish")

    publishing {
        publications {
            create<MavenPublication>("maven") {
                from(components["kotlin"])
                groupId = project.group.toString()
                version = project.version.toString()
            }
        }
    }
}
```

### Core Module Configuration

```kotlin
// modules/runanywhere-core/build.gradle.kts
plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.serialization)
}

kotlin {
    jvm()
    androidTarget()

    // Native targets for future iOS support
    iosArm64()
    iosX64()

    sourceSets {
        commonMain {
            dependencies {
                implementation(libs.kotlinx.coroutines.core)
                implementation(libs.kotlinx.serialization.json)
                implementation(libs.kotlinx.datetime)
            }
        }

        val jvmAndroidMain by creating {
            dependsOn(commonMain.get())
            dependencies {
                implementation(libs.okhttp)
                implementation(libs.gson)
            }
        }

        jvmMain {
            dependsOn(jvmAndroidMain)
        }

        androidMain {
            dependsOn(jvmAndroidMain)
            dependencies {
                implementation(libs.androidx.core.ktx)
                implementation(libs.androidx.room.runtime)
            }
        }
    }
}

android {
    namespace = "com.runanywhere.sdk.core"
    compileSdk = 36
    defaultConfig.minSdk = 24
}
```

### Feature Module Configuration Example

```kotlin
// modules/runanywhere-whisper-stt/build.gradle.kts
plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.library)
}

kotlin {
    jvm()
    androidTarget()

    sourceSets {
        commonMain {
            dependencies {
                api(project(":modules:runanywhere-core"))
                implementation(libs.kotlinx.coroutines.core)
            }
        }

        val jvmAndroidMain by creating {
            dependsOn(commonMain.get())
            dependencies {
                implementation(libs.whisper.jni)
            }
        }

        jvmMain {
            dependsOn(jvmAndroidMain)
        }

        androidMain {
            dependsOn(jvmAndroidMain)
        }
    }
}

android {
    namespace = "com.runanywhere.sdk.whisper"
    compileSdk = 36
    defaultConfig.minSdk = 24
}
```

---

## Integration Patterns

### 1. Service Provider Pattern

Core pattern for module integration with the SDK:

```kotlin
// Core SDK Interface
interface STTServiceProvider {
    suspend fun createSTTService(configuration: STTConfiguration): STTService
    fun canHandle(modelId: String): Boolean
    val name: String
    val priority: Int get() = 0 // For provider ordering
}

// Module Implementation
class WhisperSTTProvider : STTServiceProvider {
    override suspend fun createSTTService(configuration: STTConfiguration): STTService {
        return WhisperSTTService(configuration)
    }

    override fun canHandle(modelId: String): Boolean {
        return modelId.startsWith("whisper-")
    }

    override val name: String = "Whisper STT"
    override val priority: Int = 100 // Higher priority
}
```

### 2. Module Auto-Registration

Automatic module detection and registration:

```kotlin
// Auto-registration interface
interface AutoRegisteringModule {
    fun register()
    val isAvailable: Boolean
}

// Module implementation
object WhisperSTTModule : AutoRegisteringModule {
    override fun register() {
        ModuleRegistry.shared.registerSTT(WhisperSTTProvider())
    }

    override val isAvailable: Boolean
        get() = try {
            // Check if native libraries are available
            System.loadLibrary("whisper-jni")
            true
        } catch (e: UnsatisfiedLinkError) {
            false
        }
}

// Core SDK discovery
object ModuleDiscovery {
    fun discoverAndRegister() {
        val modules = listOf(
            "com.runanywhere.sdk.whisper.WhisperSTTModule",
            "com.runanywhere.sdk.llm.LLMModule",
            // ... other modules
        )

        modules.forEach { className ->
            try {
                val moduleClass = Class.forName(className)
                val module = moduleClass.kotlin.objectInstance as? AutoRegisteringModule
                if (module?.isAvailable == true) {
                    module.register()
                }
            } catch (e: ClassNotFoundException) {
                // Module not available, continue
            }
        }
    }
}
```

### 3. Graceful Degradation

Handle missing modules gracefully:

```kotlin
class STTComponent {
    suspend fun transcribe(audio: ByteArray): TranscriptionResult {
        val provider = ModuleRegistry.shared.sttProvider()
            ?: throw SDKError.serviceUnavailable("No STT provider available. Add runanywhere-whisper-stt dependency.")

        val service = provider.createSTTService(configuration)
        return service.transcribe(audio)
    }

    val isAvailable: Boolean
        get() = ModuleRegistry.shared.hasSTT
}
```

### 4. Plugin-Based Architecture

Support for custom implementations:

```kotlin
// Custom STT implementation
class CustomSTTProvider(private val apiEndpoint: String) : STTServiceProvider {
    override suspend fun createSTTService(configuration: STTConfiguration): STTService {
        return CloudSTTService(apiEndpoint, configuration)
    }

    override fun canHandle(modelId: String): Boolean = modelId == "custom-cloud"
    override val name: String = "Custom Cloud STT"
}

// Registration in application
RunAnywhere.initialize {
    ModuleRegistry.shared.registerSTT(CustomSTTProvider("https://api.example.com"))
}
```

---

## Whisper JNI Module Design

### Architecture Overview

```
runanywhere-whisper-stt/
├── src/
│   ├── commonMain/kotlin/
│   │   └── com/runanywhere/sdk/whisper/
│   │       ├── WhisperSTTProvider.kt
│   │       ├── WhisperConfiguration.kt
│   │       └── WhisperModels.kt
│   ├── jvmAndroidMain/kotlin/
│   │   └── com/runanywhere/sdk/whisper/
│   │       ├── WhisperSTTService.kt
│   │       ├── NativeLibraryLoader.kt
│   │       └── AudioProcessor.kt
│   ├── jvmMain/kotlin/
│   │   └── com/runanywhere/sdk/whisper/
│   │       └── JvmWhisperSTTService.kt
│   └── androidMain/kotlin/
│       └── com/runanywhere/sdk/whisper/
│           └── AndroidWhisperSTTService.kt
├── libs/
│   ├── jvm/
│   │   ├── libwhisper-jni-linux-x64.so
│   │   ├── libwhisper-jni-macos-x64.dylib
│   │   └── libwhisper-jni-windows-x64.dll
│   └── android/
│       ├── arm64-v8a/libwhisper-jni.so
│       └── x86_64/libwhisper-jni.so
└── build.gradle.kts
```

### Native Library Management

```kotlin
// NativeLibraryLoader.kt
object NativeLibraryLoader {
    private var loaded = false

    fun loadWhisperLibrary() {
        if (loaded) return

        try {
            when (Platform.type) {
                PlatformType.JVM -> loadJvmLibrary()
                PlatformType.ANDROID -> loadAndroidLibrary()
                else -> throw UnsupportedOperationException("Platform not supported")
            }
            loaded = true
        } catch (e: Exception) {
            throw SDKError.nativeLibraryError("Failed to load Whisper native library", e)
        }
    }

    private fun loadJvmLibrary() {
        val os = System.getProperty("os.name").lowercase()
        val arch = System.getProperty("os.arch")

        val libraryName = when {
            os.contains("linux") && arch.contains("64") -> "libwhisper-jni-linux-x64.so"
            os.contains("mac") && arch.contains("64") -> "libwhisper-jni-macos-x64.dylib"
            os.contains("windows") && arch.contains("64") -> "libwhisper-jni-windows-x64.dll"
            else -> throw UnsupportedOperationException("Unsupported platform: $os-$arch")
        }

        extractAndLoadLibrary(libraryName)
    }

    private fun loadAndroidLibrary() {
        System.loadLibrary("whisper-jni")
    }
}
```

### Whisper STT Service Implementation

```kotlin
// WhisperSTTService.kt
class WhisperSTTService(
    private val configuration: STTConfiguration
) : STTService {

    private var modelHandle: Long = 0

    override suspend fun initialize() {
        NativeLibraryLoader.loadWhisperLibrary()
        modelHandle = nativeInitialize(configuration.modelPath, configuration.language)
    }

    override suspend fun transcribe(audio: ByteArray): TranscriptionResult {
        if (modelHandle == 0L) {
            throw SDKError.notInitialized("Whisper model not initialized")
        }

        val result = withContext(Dispatchers.Default) {
            nativeTranscribe(modelHandle, audio, audio.size)
        }

        return TranscriptionResult(
            text = result.text,
            confidence = result.confidence,
            segments = result.segments.map { segment ->
                TranscriptionSegment(
                    text = segment.text,
                    startTime = segment.startMs.milliseconds,
                    endTime = segment.endMs.milliseconds,
                    confidence = segment.confidence
                )
            }
        )
    }

    override suspend fun cleanup() {
        if (modelHandle != 0L) {
            nativeCleanup(modelHandle)
            modelHandle = 0
        }
    }

    // Native method declarations
    private external fun nativeInitialize(modelPath: String, language: String): Long
    private external fun nativeTranscribe(handle: Long, audio: ByteArray, size: Int): NativeTranscriptionResult
    private external fun nativeCleanup(handle: Long)
}
```

### Memory Management

```kotlin
// WhisperMemoryManager.kt
class WhisperMemoryManager {
    private val activeModels = mutableMapOf<Long, String>()

    fun registerModel(handle: Long, modelPath: String) {
        activeModels[handle] = modelPath
        MemoryMonitor.shared.trackAllocation("whisper-model", estimateModelSize(modelPath))
    }

    fun unregisterModel(handle: Long) {
        val modelPath = activeModels.remove(handle)
        if (modelPath != null) {
            MemoryMonitor.shared.trackDeallocation("whisper-model", estimateModelSize(modelPath))
        }
    }

    private fun estimateModelSize(modelPath: String): Long {
        return File(modelPath).length()
    }
}
```

---

## Benefits Analysis

### 1. Reduced SDK Size

**Problem**: Current monolithic SDK includes all functionality, even if not used
**Solution**: Modular architecture allows selective inclusion

**Size Comparison**:
- Current monolithic SDK: ~50MB (including all native libraries)
- Core SDK only: ~5MB
- Core + Whisper STT: ~25MB
- Core + LLM: ~15MB
- Custom combinations based on needs

### 2. Independent Module Updates

**Problem**: SDK updates require full rebuilds and testing
**Solution**: Modules can be updated independently

**Benefits**:
- Faster security patches for specific modules
- New features in one module don't affect others
- Different stability levels (core stable, experimental modules)
- Third-party modules can follow their own release cycles

### 3. Better Separation of Concerns

**Problem**: Tight coupling between different AI capabilities
**Solution**: Clear module boundaries and interfaces

**Benefits**:
- Easier to understand and maintain each module
- Clear responsibility boundaries
- Easier to test individual capabilities
- Reduced cognitive load for developers

### 4. Easier Third-Party Integrations

**Problem**: Difficult for external providers to integrate
**Solution**: Well-defined service provider interfaces

**Benefits**:
- Cloud providers can create their own modules
- Hardware vendors can optimize for specific chips
- Community contributions become easier
- Custom implementations for enterprise needs

### 5. Platform Consistency

**Problem**: Different architecture patterns across platforms
**Solution**: Align with iOS modular approach

**Benefits**:
- Consistent developer experience
- Easier to maintain documentation
- Knowledge transfer between platforms
- Similar debugging and troubleshooting patterns

---

## Migration Path

### Phase 1: Core Module Extraction (Week 1-2)

1. **Create Core Module Structure**
   ```bash
   mkdir -p modules/runanywhere-core
   mkdir -p modules/runanywhere-core/src/{commonMain,jvmMain,androidMain}/kotlin
   ```

2. **Move Core Components**
   - Move `ModuleRegistry`, base interfaces, and common services to core
   - Update package names and dependencies
   - Create core module build.gradle.kts

3. **Update Root Project**
   - Configure multi-module build
   - Set up publishing for core module

### Phase 2: Whisper STT Module (Week 3-4)

1. **Extract Whisper Components**
   - Move STT-related code to whisper module
   - Implement service provider pattern
   - Bundle native libraries properly

2. **Integration Testing**
   - Test core + whisper module integration
   - Verify native library loading works
   - Performance regression testing

### Phase 3: Additional Modules (Week 5-8)

1. **Create Remaining Modules** (parallel development)
   - `runanywhere-llm`
   - `runanywhere-vad`
   - `runanywhere-speaker-diarization`
   - `runanywhere-tts`

2. **Provider Implementation**
   - Implement service providers for each module
   - Register providers with core registry
   - Test module combinations

### Phase 4: Examples and Documentation (Week 9-10)

1. **Create Integration Examples**
   - Minimal core-only example
   - Full-featured example with all modules
   - Custom integration examples

2. **Update Documentation**
   - Module-specific documentation
   - Integration guides
   - Migration instructions

### Phase 5: Legacy Support and Cleanup (Week 11-12)

1. **Legacy Compatibility Layer**
   - Create compatibility module that includes all features
   - Provide migration path for existing users
   - Deprecation warnings and timeline

2. **Publishing and Release**
   - Set up automated publishing for all modules
   - Version coordination strategy
   - Release notes and migration guide

---

## Usage Examples

### 1. Core-Only Usage

```kotlin
// build.gradle.kts
dependencies {
    implementation("com.runanywhere.sdk:runanywhere-core:0.1.0")
}

// Application code
val sdk = RunAnywhere.initialize {
    apiKey = "your-api-key"
}

// Only basic functionality available
println("Available modules: ${ModuleRegistry.shared.registeredModules}")
// Output: []

// STT not available
val sttAvailable = sdk.sttComponent.isAvailable
// Output: false
```

### 2. STT-Only Integration

```kotlin
// build.gradle.kts
dependencies {
    implementation("com.runanywhere.sdk:runanywhere-core:0.1.0")
    implementation("com.runanywhere.sdk:runanywhere-whisper-stt:0.1.0")
}

// Application code
val sdk = RunAnywhere.initialize {
    apiKey = "your-api-key"
}

// STT functionality available
val transcription = sdk.sttComponent.transcribe(audioData)
println("Transcript: ${transcription.text}")
```

### 3. Full-Featured Integration

```kotlin
// build.gradle.kts
dependencies {
    implementation("com.runanywhere.sdk:runanywhere-core:0.1.0")
    implementation("com.runanywhere.sdk:runanywhere-whisper-stt:0.1.0")
    implementation("com.runanywhere.sdk:runanywhere-llm:0.1.0")
    implementation("com.runanywhere.sdk:runanywhere-vad:0.1.0")
    implementation("com.runanywhere.sdk:runanywhere-speaker-diarization:0.1.0")
}

// Application code - Full voice AI pipeline
val sdk = RunAnywhere.initialize {
    apiKey = "your-api-key"
}

// Process voice input with full pipeline
val audioInput = captureAudio()

// Voice Activity Detection
val vadResult = sdk.vadComponent.detectSpeech(audioInput)
if (vadResult.hasSpeech) {

    // Speech-to-Text
    val transcription = sdk.sttComponent.transcribe(audioInput)

    // Speaker Diarization
    val speakers = sdk.speakerDiarizationComponent.identifySpeakers(audioInput, transcription)

    // LLM Processing
    val response = sdk.llmComponent.generate(transcription.text)

    println("Speakers: ${speakers.speakerCount}")
    println("Transcript: ${transcription.text}")
    println("Response: ${response.text}")
}
```

### 4. Custom Provider Integration

```kotlin
// Custom cloud STT provider
class AzureSTTProvider(private val apiKey: String) : STTServiceProvider {
    override suspend fun createSTTService(configuration: STTConfiguration): STTService {
        return AzureSTTService(apiKey, configuration)
    }

    override fun canHandle(modelId: String): Boolean {
        return modelId.startsWith("azure-")
    }

    override val name: String = "Azure STT"
    override val priority: Int = 50
}

// Application initialization
val sdk = RunAnywhere.initialize {
    apiKey = "your-api-key"

    // Register custom provider
    ModuleRegistry.shared.registerSTT(AzureSTTProvider("azure-key"))
}

// Use custom provider
val transcription = sdk.sttComponent.transcribe(audioData, "azure-whisper-v1")
```

### 5. Gradle Build Variants

```kotlin
// Development variant - all modules
dependencies {
    if (project.hasProperty("fullSdk")) {
        implementation("com.runanywhere.sdk:runanywhere-core:0.1.0")
        implementation("com.runanywhere.sdk:runanywhere-whisper-stt:0.1.0")
        implementation("com.runanywhere.sdk:runanywhere-llm:0.1.0")
        implementation("com.runanywhere.sdk:runanywhere-vad:0.1.0")
        implementation("com.runanywhere.sdk:runanywhere-speaker-diarization:0.1.0")
        implementation("com.runanywhere.sdk:runanywhere-tts:0.1.0")
    } else {
        // Production - minimal set
        implementation("com.runanywhere.sdk:runanywhere-core:0.1.0")
        implementation("com.runanywhere.sdk:runanywhere-whisper-stt:0.1.0")
    }
}
```

### 6. Module Availability Checks

```kotlin
class VoiceAssistant {
    private val sdk = RunAnywhere.instance

    fun processVoiceInput(audio: ByteArray) {
        // Check what's available and adapt behavior
        when {
            sdk.hasFullPipeline -> processWithFullPipeline(audio)
            sdk.hasSTTOnly -> processWithSTTOnly(audio)
            else -> showErrorMessage("Voice processing not available")
        }
    }

    private val RunAnywhere.hasFullPipeline: Boolean
        get() = sttComponent.isAvailable &&
                llmComponent.isAvailable &&
                vadComponent.isAvailable

    private val RunAnywhere.hasSTTOnly: Boolean
        get() = sttComponent.isAvailable
}
```

---

## Implementation Roadmap

### Quarter 1: Foundation and Core Module

**Week 1-2: Project Setup**
- [ ] Create multi-module Gradle structure
- [ ] Set up publishing infrastructure
- [ ] Define core interfaces and service registry
- [ ] Create integration test framework

**Week 3-4: Core Module**
- [ ] Extract core functionality from monolithic SDK
- [ ] Implement ModuleRegistry enhancements
- [ ] Create base service provider interfaces
- [ ] Set up automated testing

**Week 5-6: Documentation and Examples**
- [ ] Core module documentation
- [ ] Basic integration examples
- [ ] Developer guides for module creation

### Quarter 2: Primary Modules

**Week 7-10: Whisper STT Module**
- [ ] Extract STT functionality
- [ ] Implement WhisperSTTProvider
- [ ] Native library bundling and loading
- [ ] Platform-specific optimizations
- [ ] Integration testing with core

**Week 11-14: LLM Module**
- [ ] Extract LLM functionality
- [ ] Support multiple backends (llama.cpp, ONNX)
- [ ] Model management and loading
- [ ] Streaming generation support
- [ ] Performance optimization

### Quarter 3: Extended Modules

**Week 15-18: VAD and Speaker Diarization Modules**
- [ ] VAD module with multiple backends
- [ ] Speaker diarization implementation
- [ ] Audio processing optimizations
- [ ] Cross-module integration testing

**Week 19-22: TTS Module**
- [ ] TTS module with platform-specific backends
- [ ] Voice management
- [ ] Audio format support
- [ ] Quality and performance tuning

### Quarter 4: Polish and Release

**Week 23-26: Integration and Testing**
- [ ] Full integration testing across all modules
- [ ] Performance benchmarking
- [ ] Memory usage optimization
- [ ] Security review

**Week 27-30: Release Preparation**
- [ ] Complete documentation
- [ ] Migration guides
- [ ] Example applications
- [ ] Community feedback integration

**Week 31-32: Launch**
- [ ] Public release
- [ ] Blog posts and tutorials
- [ ] Community support setup
- [ ] Feedback collection and iteration

### Success Metrics

1. **Size Reduction**: 60%+ size reduction for typical use cases
2. **Build Time**: 40%+ faster builds for partial module usage
3. **Developer Experience**: Positive feedback on modular approach
4. **Adoption**: 70%+ of users adopt modular architecture within 6 months
5. **Third-Party Integration**: At least 3 community modules within 12 months

---

## Conclusion

The proposed modular architecture for the RunAnywhere KMP SDK provides significant benefits in terms of SDK size reduction, development flexibility, and maintainability. By following the successful patterns established in the iOS SDK and adapting them to the KMP ecosystem, we can create a more scalable and developer-friendly architecture.

The modular approach enables:

- **Selective functionality inclusion** reducing app size
- **Independent module updates** improving agility
- **Clear separation of concerns** enhancing maintainability
- **Third-party integration support** fostering ecosystem growth
- **Platform consistency** providing unified developer experience

The implementation roadmap provides a structured approach to migration while maintaining backward compatibility and ensuring a smooth transition for existing users. The proposed architecture positions the SDK for long-term growth and community contribution while maintaining the high-quality developer experience that developers expect.
