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
//
// Post-v2-cutover layout: the canonical Kotlin SDK lives at sdk/kotlin/
// (single Gradle project, no sub-modules). The legacy per-backend
// modules (runanywhere-core-llamacpp / runanywhere-core-onnx) collapsed
// into the main SDK — backend register entry points (LlamaCPP.register(),
// ONNX.register(), Genie.register(), WhisperKit.register()) are now
// regular calls on the main `com.runanywhere.sdk.public` package.
include(":runanywhere-kotlin")
project(":runanywhere-kotlin").projectDir = file("../../../sdk/kotlin")

// RAG pipeline is now part of the core SDK (not a separate module).
// Registration is handled by ragCreatePipeline(). See: RunAnywhere+RAG.jvmAndroid.kt

// Genie module - Qualcomm NPU-accelerated LLM (Snapdragon 8 Gen 2+)
// Now distributed as a closed-source AAR from a private repo.
// Add the dependency in app/build.gradle.kts:
//   implementation("io.github.sanchitmonga22:runanywhere-genie-android:0.2.1")
