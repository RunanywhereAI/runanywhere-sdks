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
    }
    versionCatalogs {
        create("libs") {
            from(files("../../../gradle/libs.versions.toml"))
        }
    }
}

rootProject.name = "RunAnywhereAI"
include(":app")
include(":sdk-core")
project(":sdk-core").projectDir = file("../../../sdk/runanywhere-android/core")

include(":sdk-jni")
project(":sdk-jni").projectDir = file("../../../sdk/runanywhere-android/jni")
