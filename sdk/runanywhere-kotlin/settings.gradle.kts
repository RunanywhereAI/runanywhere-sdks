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

// RunAnywhere Core JNI module - shared Kotlin JNI bridge code (RunAnywhereBridge.kt)
// Provides JNI declarations used by all backend modules
include(":modules:runanywhere-core-jni")

// RunAnywhere Core LlamaCPP module - SELF-CONTAINED LLM backend
// Includes ALL native libs: JNI bridge + LlamaCPP
// Use: implementation(":modules:runanywhere-core-llamacpp")
include(":modules:runanywhere-core-llamacpp")

// RunAnywhere Core ONNX module - SELF-CONTAINED STT/TTS/VAD backend
// Includes ALL native libs: JNI bridge + ONNX Runtime + Sherpa-ONNX
// Use: implementation(":modules:runanywhere-core-onnx")
include(":modules:runanywhere-core-onnx")

// Other modules temporarily disabled due to build issues
// TODO: Fix module build configurations
// include(":modules:runanywhere-vad")
// include(":modules:runanywhere-llm")
// include(":modules:runanywhere-tts")
// include(":modules:runanywhere-speaker-diarization")
