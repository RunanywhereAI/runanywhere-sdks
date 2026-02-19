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
            from(files("../../../gradle/libs.versions.toml"))
        }
    }
}

rootProject.name = "RunAnywhereAI"
include(":app")

// SDK (local project dependency)
include(":runanywhere-kotlin")
project(":runanywhere-kotlin").projectDir = file("../../../sdk/runanywhere-kotlin")

// Backend modules
include(":runanywhere-core-llamacpp")
project(":runanywhere-core-llamacpp").projectDir =
    file("../../../sdk/runanywhere-kotlin/modules/runanywhere-core-llamacpp")

// ONNX module - STT, TTS, VAD adapter
include(":sdk:runanywhere-kotlin:modules:runanywhere-core-onnx")
project(":sdk:runanywhere-kotlin:modules:runanywhere-core-onnx").projectDir = file("../../../sdk/runanywhere-kotlin/modules/runanywhere-core-onnx")

// SDCPP module - stable-diffusion.cpp for diffusion image generation
include(":sdk:runanywhere-kotlin:modules:runanywhere-core-sdcpp")
project(":sdk:runanywhere-kotlin:modules:runanywhere-core-sdcpp").projectDir = file("../../../sdk/runanywhere-kotlin/modules/runanywhere-core-sdcpp")
include(":runanywhere-core-onnx")
project(":runanywhere-core-onnx").projectDir =
    file("../../../sdk/runanywhere-kotlin/modules/runanywhere-core-onnx")
