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

// Include SDK modules
// RunAnywhere Core JNI module - unified JNI bridge for all backends (REQUIRED)
include(":sdk:runanywhere-kotlin:modules:runanywhere-core-jni")
project(":sdk:runanywhere-kotlin:modules:runanywhere-core-jni").projectDir = file("../../../sdk/runanywhere-kotlin/modules/runanywhere-core-jni")

// RunAnywhere Core LlamaCPP module - native LlamaCPP backend with chat template support
include(":sdk:runanywhere-kotlin:modules:runanywhere-core-llamacpp")
project(":sdk:runanywhere-kotlin:modules:runanywhere-core-llamacpp").projectDir = file("../../../sdk/runanywhere-kotlin/modules/runanywhere-core-llamacpp")

// Include RunAnywhere Core ONNX module - provides native ONNX Runtime backend via JNI
include(":sdk:runanywhere-kotlin:modules:runanywhere-core-onnx")
project(":sdk:runanywhere-kotlin:modules:runanywhere-core-onnx").projectDir = file("../../../sdk/runanywhere-kotlin/modules/runanywhere-core-onnx")
