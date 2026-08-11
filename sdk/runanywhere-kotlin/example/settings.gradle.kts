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
}

rootProject.name = "runanywhere-minimal"
include(":app")

// Consume the Kotlin SDK from LOCAL SOURCE. `includeBuild` wires
// sdk/runanywhere-kotlin into this build, so `./gradlew :app:installDebug`
// rebuilds the SDK (and pulls its transitive runtime deps) with no AAR
// staging step. The coordinates below are placeholders that exist only to be
// substituted — nothing is ever resolved from a repository.
includeBuild("../../../sdk/runanywhere-kotlin") {
    dependencySubstitution {
        substitute(module("com.runanywhere:runanywhere-kotlin"))
            .using(project(":"))
        substitute(module("com.runanywhere:runanywhere-core-llamacpp"))
            .using(project(":modules:runanywhere-core-llamacpp"))
    }
}
