/**
 * RunAnywhere Core LlamaCPP Module
 *
 * This module provides the LlamaCPP backend for LLM text generation.
 * It is SELF-CONTAINED with its own native libraries.
 *
 * Architecture (mirrors iOS RABackendLlamaCPP.xcframework):
 *   iOS:     LlamaCPPRuntime.swift -> RABackendLlamaCPP.xcframework
 *   Android: LlamaCPP.kt -> librunanywhere_llamacpp.so
 *
 * Native Libraries Included:
 *   - librunanywhere_llamacpp.so (~34MB) - LLM inference with llama.cpp
 *
 * This module is OPTIONAL - only include it if your app needs LLM capabilities.
 */

plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.detekt)
    alias(libs.plugins.ktlint)
    `maven-publish`
}

// =============================================================================
// Local vs Remote JNI Library Configuration (mirrors main SDK)
// =============================================================================
// Read from root project to ensure consistency with main SDK
val testLocal: Boolean = rootProject.findProperty("runanywhere.testLocal")?.toString()?.toBoolean()
    ?: project.findProperty("runanywhere.testLocal")?.toString()?.toBoolean()
    ?: false
val coreVersion: String = rootProject.findProperty("runanywhere.coreVersion")?.toString()
    ?: project.findProperty("runanywhere.coreVersion")?.toString()
    ?: "0.1.1"

logger.lifecycle("LlamaCPP Module: testLocal=$testLocal, coreVersion=$coreVersion")

// =============================================================================
// Detekt Configuration
// =============================================================================
detekt {
    buildUponDefaultConfig = true
    allRules = false
    config.setFrom(files("../../detekt.yml"))
    source.setFrom(
        "src/commonMain/kotlin",
        "src/jvmMain/kotlin",
        "src/jvmAndroidMain/kotlin",
        "src/androidMain/kotlin",
    )
}

// =============================================================================
// ktlint Configuration
// =============================================================================
ktlint {
    version.set("1.5.0")
    android.set(true)
    verbose.set(true)
    outputToConsole.set(true)
    enableExperimentalRules.set(false)
    filter {
        exclude("**/generated/**")
        include("**/kotlin/**")
    }
}

// =============================================================================
// Kotlin Multiplatform Configuration
// =============================================================================

kotlin {
    jvm {
        compilations.all {
            kotlinOptions.jvmTarget = "17"
        }
    }

    androidTarget {
        compilations.all {
            kotlinOptions.jvmTarget = "17"
        }
    }

    sourceSets {
        val commonMain by getting {
            dependencies {
                // Core SDK dependency for interfaces and models
                api(project.parent!!.parent!!)
                implementation(libs.kotlinx.coroutines.core)
                implementation(libs.kotlinx.serialization.json)
            }
        }

        val commonTest by getting {
            dependencies {
                implementation(kotlin("test"))
                implementation(libs.kotlinx.coroutines.test)
            }
        }

        // Shared JVM/Android code
        val jvmAndroidMain by creating {
            dependsOn(commonMain)
        }

        val jvmMain by getting {
            dependsOn(jvmAndroidMain)
        }

        val androidMain by getting {
            dependsOn(jvmAndroidMain)
        }

        val jvmTest by getting
        val androidUnitTest by getting
    }
}

// =============================================================================
// Android Configuration
// =============================================================================

android {
    namespace = "com.runanywhere.sdk.core.llamacpp"
    compileSdk = 36

    defaultConfig {
        minSdk = 24

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        ndk {
            // Target ARM 64-bit only (modern Android devices)
            abiFilters += listOf("arm64-v8a")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }

    // ==========================================================================
    // JNI Libraries Configuration - LlamaCPP Backend
    // ==========================================================================
    // This module bundles LlamaCPP-specific native libraries (~34MB):
    //   - librunanywhere_llamacpp.so (llama.cpp LLM inference)
    //
    // When testLocal=true: Use libs from src/androidMain/jniLibs/
    // When testLocal=false: Use libs from build/jniLibs/ (downloaded)
    // ==========================================================================
    sourceSets {
        getByName("main") {
            jniLibs.srcDirs(
                if (testLocal) "src/androidMain/jniLibs" else "build/jniLibs"
            )
        }
    }
}

// =============================================================================
// JNI Library Download Task (for testLocal=false mode)
// =============================================================================
tasks.register("downloadJniLibs") {
    group = "runanywhere"
    description = "Download LlamaCPP JNI libraries from GitHub releases"

    val outputDir = file("build/jniLibs")
    val tempDir = file("${layout.buildDirectory.get()}/jni-temp")
    val releaseBaseUrl = "https://github.com/RunanywhereAI/runanywhere-binaries/releases/download/core-v$coreVersion"
    val packageName = "RunAnywhereLlamaCPP-android-v$coreVersion.zip"

    outputs.dir(outputDir)

    doLast {
        if (testLocal) {
            logger.lifecycle("Skipping JNI download: testLocal=true")
            return@doLast
        }

        outputDir.deleteRecursively()
        tempDir.deleteRecursively()
        outputDir.mkdirs()
        tempDir.mkdirs()

        val zipUrl = "$releaseBaseUrl/$packageName"
        val tempZip = file("$tempDir/$packageName")

        logger.lifecycle("Downloading LlamaCPP JNI libraries...")
        logger.lifecycle("  URL: $zipUrl")

        try {
            ant.withGroovyBuilder {
                "get"("src" to zipUrl, "dest" to tempZip, "verbose" to false)
            }

            val extractDir = file("$tempDir/extracted")
            extractDir.mkdirs()
            ant.withGroovyBuilder {
                "unzip"("src" to tempZip, "dest" to extractDir)
            }

            // Copy ONLY LlamaCPP-specific .so files (exclude common libs that are in main SDK)
            val llamacppLibs = setOf("librunanywhere_llamacpp.so")

            extractDir.walkTopDown()
                .filter { it.isDirectory && it.name in listOf("arm64-v8a", "armeabi-v7a", "x86_64", "x86") }
                .forEach { abiDir ->
                    val targetAbiDir = file("$outputDir/${abiDir.name}")
                    targetAbiDir.mkdirs()

                    abiDir.listFiles()?.filter { it.extension == "so" && it.name in llamacppLibs }?.forEach { soFile ->
                        val targetFile = file("$targetAbiDir/${soFile.name}")
                        soFile.copyTo(targetFile, overwrite = true)
                        logger.lifecycle("  Copied: ${abiDir.name}/${soFile.name}")
                    }
                }

            tempDir.deleteRecursively()
            logger.lifecycle("✓ LlamaCPP JNI libraries ready")
        } catch (e: Exception) {
            logger.error("✗ Failed to download LlamaCPP libs: ${e.message}")
        }
    }
}

// Ensure JNI libs are available before Android build
tasks.matching { it.name.contains("merge") && it.name.contains("JniLibFolders") }.configureEach {
    if (!testLocal) {
        dependsOn("downloadJniLibs")
    }
}

// =============================================================================
// Include third-party licenses in JVM JAR
// =============================================================================

tasks.named<Jar>("jvmJar") {
    from(rootProject.file("THIRD_PARTY_LICENSES.md")) {
        into("META-INF")
    }
}

// =============================================================================
// Publishing Configuration
// =============================================================================

publishing {
    publications.withType<MavenPublication> {
        pom {
            name.set("RunAnywhere Core LlamaCPP Module")
            description.set("LlamaCPP backend for RunAnywhere SDK - LLM text generation (~34MB native libs)")
            url.set("https://github.com/RunanywhereAI/runanywhere-sdks")

            licenses {
                license {
                    name.set("The Apache License, Version 2.0")
                    url.set("http://www.apache.org/licenses/LICENSE-2.0.txt")
                }
            }

            developers {
                developer {
                    id.set("runanywhere")
                    name.set("RunAnywhere Team")
                    email.set("founders@runanywhere.ai")
                }
            }

            scm {
                connection.set("scm:git:git://github.com/RunanywhereAI/runanywhere-sdks.git")
                developerConnection.set("scm:git:ssh://github.com/RunanywhereAI/runanywhere-sdks.git")
                url.set("https://github.com/RunanywhereAI/runanywhere-sdks")
            }
        }
    }
}
