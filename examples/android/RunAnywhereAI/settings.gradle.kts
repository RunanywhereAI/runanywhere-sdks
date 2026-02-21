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

include(":runanywhere-core-onnx")
project(":runanywhere-core-onnx").projectDir =
    file("../../../sdk/runanywhere-kotlin/modules/runanywhere-core-onnx")
