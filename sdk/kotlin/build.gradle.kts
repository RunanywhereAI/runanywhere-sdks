// RunAnywhere v2 — Kotlin frontend adapter. Single Gradle project that
// hosts the public API (sessions, catalog, EventBus, RAG/VLM/Diffusion/LoRA
// glue, backend register entry points). JNI bridge + native libs live in
// libracommons_core.so consumed via System.loadLibrary("racommons_core").

plugins {
    kotlin("jvm") version "2.1.21"
    id("com.squareup.wire") version "5.0.0"
    id("org.jetbrains.dokka") version "1.9.20"
}

group = "com.runanywhere"
version = project.findProperty("v2Version") as? String ?: "2.0.0-SNAPSHOT"

repositories {
    mavenCentral()
    google()
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
