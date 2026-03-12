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
    }
    versionCatalogs {
        create("libs") {
            from(files(File(settingsDir, "../../../gradle/libs.versions.toml")))
        }
    }
}

rootProject.name = "RunAnywhereAI"
include(":app")

// SDK (local project dependency)
include(":runanywhere-kotlin")
project(":runanywhere-kotlin").projectDir = file("../../../sdk/runanywhere-kotlin")

include(":runanywhere-core-llamacpp")
project(":runanywhere-core-llamacpp").projectDir =
    file("../../../sdk/runanywhere-kotlin/modules/runanywhere-core-llamacpp")

include(":runanywhere-core-onnx")
project(":runanywhere-core-onnx").projectDir =
    file("../../../sdk/runanywhere-kotlin/modules/runanywhere-core-onnx")

// Genie module - Qualcomm NPU-accelerated LLM (Snapdragon 8 Gen 2+)
// Now distributed as a closed-source AAR from Maven Central.
// Add the dependency in app/build.gradle.kts:
//   implementation("io.github.sanchitmonga22:runanywhere-genie-android:0.2.1")
