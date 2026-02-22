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
        // Keep this for the PDFBox-Android library
        maven { url = uri("https://oss.sonatype.org/content/repositories/releases/") }
        mavenLocal()
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

// =============================================================================
// SDK Inclusion (Local Development)
// =============================================================================
// Include the main SDK module - JNI libraries are bundled directly in the SDK
// When testLocal=false (default), libs are downloaded from GitHub releases
// When testLocal=true, libs are built locally via ./scripts/build-local.sh
// =============================================================================

// Main SDK - includes JNI libraries for all AI capabilities
include(":sdk:runanywhere-kotlin")
project(":sdk:runanywhere-kotlin").projectDir = file("../../../sdk/runanywhere-kotlin")

// =============================================================================
// Backend Adapter Modules (Pure Kotlin - no native libs)
// =============================================================================
// These modules provide Kotlin adapters for specific AI backends.
// Native libraries are bundled in the main SDK (runanywhere-kotlin).

// LlamaCPP module - LLM text generation adapter
include(":sdk:runanywhere-kotlin:modules:runanywhere-core-llamacpp")
project(":sdk:runanywhere-kotlin:modules:runanywhere-core-llamacpp").projectDir = file("../../../sdk/runanywhere-kotlin/modules/runanywhere-core-llamacpp")

// ONNX module - STT, TTS, VAD adapter
include(":sdk:runanywhere-kotlin:modules:runanywhere-core-onnx")
project(":sdk:runanywhere-kotlin:modules:runanywhere-core-onnx").projectDir = file("../../../sdk/runanywhere-kotlin/modules/runanywhere-core-onnx")

// RAG module - Retrieval-Augmented Generation adapter
include(":sdk:runanywhere-kotlin:modules:runanywhere-core-rag")
project(":sdk:runanywhere-kotlin:modules:runanywhere-core-rag").projectDir = file("../../../sdk/runanywhere-kotlin/modules/runanywhere-core-rag")