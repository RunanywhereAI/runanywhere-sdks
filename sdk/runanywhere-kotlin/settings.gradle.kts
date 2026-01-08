pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
    }
    versionCatalogs {
        create("libs") {
            from(files("../../gradle/libs.versions.toml"))
        }
    }
}

rootProject.name = "RunAnywhereKotlinSDK"

// Include JNI module
include(":jni")

// WhisperKit module - standalone STT module using WhisperJNI
include(":modules:runanywhere-whisperkit")

// Old LlamaCpp module removed - now using runanywhere-core-llamacpp
// which provides the same capabilities via runanywhere-core C++ with chat template support

// MLC-LLM module - temporarily disabled
// include(":modules:runanywhere-llm-mlc")

// =============================================================================
// RunAnywhere Core Modules (mirrors iOS XCFramework architecture)
// =============================================================================

// RunAnywhere Core Native module - UNIFIED native library package
// Contains ALL native libraries (JNI bridge + LlamaCpp + ONNX + dependencies)
// Similar to iOS RunAnywhereCoreBinary.xcframework - single binary with everything
include(":modules:runanywhere-core-native")

// NOTE: JNI bridge code (RunAnywhereBridge.kt, RunAnywhereLoader.kt) is now in the main SDK
// at src/jvmAndroidMain/kotlin/com/runanywhere/sdk/native/bridge/

// RunAnywhere Core LlamaCPP module - LLM backend adapter (pure Kotlin)
// Depends on main SDK (which includes native libs transitively)
// Provides: LlamaCppAdapter, LlamaCppService
include(":modules:runanywhere-core-llamacpp")

// RunAnywhere Core ONNX module - STT/TTS/VAD backend adapter (pure Kotlin)
// Depends on main SDK (which includes native libs transitively)
// Provides: ONNXAdapter, ONNXService
include(":modules:runanywhere-core-onnx")

// RunAnywhere Core WhisperCPP module - STT backend adapter (pure Kotlin)
// Uses whisper.cpp for GGML Whisper model inference
// Depends on main SDK (which includes native libs transitively)
// Provides: WhisperCPPServiceProvider, WhisperCPPCoreService
include(":modules:runanywhere-core-whispercpp")

// Other modules temporarily disabled due to build issues
// TODO: Fix module build configurations
// include(":modules:runanywhere-vad")
// include(":modules:runanywhere-llm")
// include(":modules:runanywhere-tts")
// include(":modules:runanywhere-speaker-diarization")
