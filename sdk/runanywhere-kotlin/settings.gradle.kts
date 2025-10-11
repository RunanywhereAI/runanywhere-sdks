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
}

rootProject.name = "RunAnywhereKotlinSDK"

// Include JNI module
include(":jni")

// WhisperKit module - standalone STT module using WhisperJNI
include(":modules:runanywhere-whisperkit")

// LlamaCpp module - provides LLM capabilities via llama.cpp
include(":modules:runanywhere-llm-llamacpp")

// Other modules temporarily disabled due to build issues
// TODO: Fix module build configurations
// include(":modules:runanywhere-core")
// include(":modules:runanywhere-vad")
// include(":modules:runanywhere-llm")
// include(":modules:runanywhere-tts")
// include(":modules:runanywhere-speaker-diarization")
