// RunAnywhere v2 — Kotlin frontend adapter. Single Gradle project that
// hosts the public API (sessions, catalog, EventBus, RAG/VLM/Diffusion/LoRA
// glue, backend register entry points). JNI bridge + native libs live in
// libracommons_core.so consumed via System.loadLibrary("racommons_core").

// The Kotlin SDK ships as both:
// (a) a standalone Gradle build — `cd sdk/kotlin && gradle build`
// (b) a subproject of a sample-app root (see
//     examples/android/RunAnywhereAI/settings.gradle.kts)
//
// Version resolution is left to pluginManagement so case (b) doesn't
// collide with the sample's version catalog. Case (a) relies on
// settings.gradle.kts here to inject the same versions.
plugins {
    kotlin("jvm")
    id("com.squareup.wire")
    id("org.jetbrains.dokka")
}

group = "com.runanywhere"
version = project.findProperty("v2Version") as? String ?: "2.0.0-SNAPSHOT"

// Standalone builds (`cd sdk/kotlin && gradle build`) need project-level
// repos. Sample-app builds declare repos via
// dependencyResolutionManagement in their settings.gradle.kts and set
// RepositoriesMode.FAIL_ON_PROJECT_REPOS — only declare repos here when
// we're the root project so we don't clash with that mode.
if (project == rootProject) {
    repositories {
        mavenCentral()
        google()
    }
}

dependencies {
    implementation("com.squareup.wire:wire-runtime:5.0.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
    implementation("org.json:json:20240303")

    testImplementation(kotlin("test"))
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.1")
}

// Generate Kotlin bindings from the monorepo-level proto3 schemas.
wire {
    sourcePath {
        srcDir("$rootDir/../../idl")
    }
    kotlin {
        out = "$buildDir/generated/wire"
    }
}

kotlin {
    sourceSets {
        main {
            kotlin.srcDir("$buildDir/generated/wire")
        }
    }
    jvmToolchain(17)
}

tasks.test {
    useJUnitPlatform()
}
