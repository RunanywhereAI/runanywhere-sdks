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
        mavenLocal()
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
        // Keep this for the PDFBox-Android library
        maven { url = uri("https://oss.sonatype.org/content/repositories/releases/") }
    }
    versionCatalogs {
        create("libs") {
            // Using File(settingsDir, ...) makes the relative path absolute
            from(files(File(settingsDir, "../../../gradle/libs.versions.toml")))
        }
    }
}

rootProject.name = "RunAnywhereAI"
include(":app")

// SDK (local project dependency)
include(":runanywhere-kotlin")
project(":runanywhere-kotlin").projectDir = file("../../../sdk/runanywhere-kotlin")

// =============================================================================
// Backend Adapter Modules (Pure Kotlin - no native libs)
// =============================================================================
// These modules provide Kotlin adapters for specific AI backends.
// Native libraries are bundled in the main SDK (runanywhere-kotlin).

// LlamaCPP module - LLM text generation adapter
include(":runanywhere-core-llamacpp")
project(":runanywhere-core-llamacpp").projectDir =
    file("../../../sdk/runanywhere-kotlin/modules/runanywhere-core-llamacpp")

// ONNX module - STT, TTS, VAD adapter
include(":runanywhere-core-onnx")
project(":runanywhere-core-onnx").projectDir =
    file("../../../sdk/runanywhere-kotlin/modules/runanywhere-core-onnx")

// RAG module - Retrieval-Augmented Generation adapter
include(":runanywhere-core-rag")
project(":runanywhere-core-rag").projectDir =
    file("../../../sdk/runanywhere-kotlin/modules/runanywhere-core-rag")