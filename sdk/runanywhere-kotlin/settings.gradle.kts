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

// LlamaCpp module - provides LLM capabilities via llama.cpp
include(":modules:runanywhere-llm-llamacpp")

// MLC-LLM module - provides LLM capabilities via MLC-LLM framework
// Note: This module depends on mlc4j (MLC-LLM native library) which is included conditionally
include(":modules:runanywhere-llm-mlc")

// MLC4J - Native MLC-LLM library (Git submodule inside MLC module)
// Similar to llama.cpp structure: sdk/runanywhere-kotlin/modules/runanywhere-llm-mlc/mlc-llm
// Only included if the submodule is initialized
// To set up: git submodule update --init --recursive
val mlc4jDir = file("modules/runanywhere-llm-mlc/mlc-llm/android/mlc4j")
if (mlc4jDir.exists()) {
    include(":mlc4j")
    project(":mlc4j").projectDir = mlc4jDir
    println("✓ mlc4j found - MLC-LLM module will be fully functional")
} else {
    println("⚠ mlc4j not found at ${mlc4jDir.absolutePath}")
    println("  To enable MLC-LLM support, run: git submodule update --init --recursive")
}

// Other modules temporarily disabled due to build issues
// TODO: Fix module build configurations
// include(":modules:runanywhere-core")
// include(":modules:runanywhere-vad")
// include(":modules:runanywhere-llm")
// include(":modules:runanywhere-tts")
// include(":modules:runanywhere-speaker-diarization")
