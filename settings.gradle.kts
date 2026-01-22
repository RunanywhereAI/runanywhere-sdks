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
        maven { url = uri("https://jitpack.io") } // Add JitPack for android-vad
        mavenLocal()
    }
}

rootProject.name = "RunAnywhere-Android"

// Include SDK modules
include(":runanywhere-kotlin")
include(":runanywhere-kotlin:jni")

// Include example apps as composite builds to keep them self-contained
includeBuild("examples/android/RunAnywhereAI")
includeBuild("examples/intellij-plugin-demo/plugin")
