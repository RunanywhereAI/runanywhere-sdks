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
        mavenLocal() // Add Maven Local to use the published SDK
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") } // For android-vad and other JitPack libraries
    }
    versionCatalogs {
        create("libs") {
            from(files("../../../gradle/libs.versions.toml"))
        }
    }
}

rootProject.name = "RunAnywhereAI"
include(":app")

// Include SDK as local project module
include(":sdk:runanywhere-kotlin")
project(":sdk:runanywhere-kotlin").projectDir = file("../../../sdk/runanywhere-kotlin")
include(":sdk:runanywhere-kotlin:jni")
project(":sdk:runanywhere-kotlin:jni").projectDir = file("../../../sdk/runanywhere-kotlin/jni")

// =============================================================================
// SDK Modules (mirrors iOS XCFramework architecture)
// =============================================================================

// RunAnywhere Core Native module - UNIFIED native library package
// Contains ALL native libs (similar to iOS RunAnywhereCoreBinary.xcframework)
include(":sdk:runanywhere-kotlin:modules:runanywhere-core-native")
project(":sdk:runanywhere-kotlin:modules:runanywhere-core-native").projectDir = file("../../../sdk/runanywhere-kotlin/modules/runanywhere-core-native")

// RunAnywhere Core LlamaCPP module - LLM text generation (pure Kotlin adapter)
include(":sdk:runanywhere-kotlin:modules:runanywhere-core-llamacpp")
project(":sdk:runanywhere-kotlin:modules:runanywhere-core-llamacpp").projectDir = file("../../../sdk/runanywhere-kotlin/modules/runanywhere-core-llamacpp")

// RunAnywhere Core ONNX module - STT, TTS, VAD (pure Kotlin adapter)
include(":sdk:runanywhere-kotlin:modules:runanywhere-core-onnx")
project(":sdk:runanywhere-kotlin:modules:runanywhere-core-onnx").projectDir = file("../../../sdk/runanywhere-kotlin/modules/runanywhere-core-onnx")
