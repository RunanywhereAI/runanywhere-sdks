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
        maven { url = uri("https://jitpack.io") } // Add JitPack for android-vad
    }
}

rootProject.name = "RunAnywhere-Android"

// Include SDK modules
include(":sdk:runanywhere-kotlin")
include(":sdk:runanywhere-kotlin:jni")

// Include example apps
include(":examples:android-stt-demo")
include(":examples:intellij-plugin-demo")
