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
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
        mavenLocal()
    }
}

rootProject.name = "RunAnywhere"

// Kotlin Multiplatform SDK
include(":runanywhere-kotlin")
project(":runanywhere-kotlin").projectDir = file("sdk/runanywhere-kotlin")

// Backend modules
include(":runanywhere-core-llamacpp")
project(":runanywhere-core-llamacpp").projectDir =
    file("sdk/runanywhere-kotlin/modules/runanywhere-core-llamacpp")

include(":runanywhere-core-onnx")
project(":runanywhere-core-onnx").projectDir =
    file("sdk/runanywhere-kotlin/modules/runanywhere-core-onnx")

// Example apps (composite builds for IDE support)
includeBuild("examples/android/RunAnywhereAI")
includeBuild("examples/android/RunAnyWhereLora")
includeBuild("examples/intellij-plugin-demo/plugin")
