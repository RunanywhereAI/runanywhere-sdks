// sdk/kotlin — standalone settings. Host builds (e.g. examples/android/)
// that `include(":runanywhere-kotlin")` this project override this
// settings file with their own pluginManagement, so the block below
// only applies when running `cd sdk/kotlin && gradle build`.

pluginManagement {
    repositories {
        gradlePluginPortal()
        mavenCentral()
        google()
    }
    plugins {
        kotlin("jvm")             version "2.1.21"
        id("com.squareup.wire")   version "5.0.0"
        id("org.jetbrains.dokka") version "1.9.20"
    }
}

rootProject.name = "runanywhere-v2-kotlin"
