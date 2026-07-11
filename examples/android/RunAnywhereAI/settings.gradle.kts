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
plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        mavenLocal() // RunAnywhere SDK published locally via publishToMavenLocal
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") } // SDK transitive deps: android-vad, PRDownloader
    }
}

rootProject.name = "RunAnywhere"
include(":app")
