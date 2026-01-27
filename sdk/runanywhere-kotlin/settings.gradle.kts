pluginManagement {
    // Include build-logic for convention plugins (shared build utilities)
    includeBuild("build-logic")

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

// =============================================================================
// RunAnywhere Backend Modules (mirrors iOS Swift Package architecture)
// =============================================================================

// Native libs (.so files) are built from runanywhere-commons and included
// directly in the main SDK's jniLibs folder. No separate native module needed.
// See: runanywhere-commons/scripts/build-android.sh

// LlamaCPP module - thin wrapper that calls C++ backend registration
// Single file: LlamaCPP.kt which calls rac_backend_llamacpp_register()
// Matches iOS: Sources/LlamaCPPRuntime/LlamaCPP.swift
include(":modules:runanywhere-core-llamacpp")

// ONNX module - thin wrapper that calls C++ backend registration
// Single file: ONNX.kt which calls rac_backend_onnx_register()
// Matches iOS: Sources/ONNXRuntime/ONNX.swift
include(":modules:runanywhere-core-onnx")
