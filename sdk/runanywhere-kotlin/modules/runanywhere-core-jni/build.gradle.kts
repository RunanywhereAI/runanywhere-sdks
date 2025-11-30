/**
 * RunAnywhere Core JNI Module
 *
 * This module provides the unified JNI bridge to the RunAnywhere Core C++ library.
 * It contains the shared JNI bindings that work with ALL backends (ONNX, LlamaCPP, etc.).
 *
 * Architecture:
 *   Kotlin Service Layer -> RunAnywhereBridge (this module)
 *     -> Native Library (librunanywhere_jni.so) -> C API (runanywhere_bridge.h)
 *       -> Backend-specific libraries (via backend modules)
 *
 * This module provides:
 *   - librunanywhere_jni.so (JNI bridge)
 *   - librunanywhere_bridge.so (C API bridge)
 *
 * Backend modules (runanywhere-core-onnx, runanywhere-core-llamacpp) add their specific libraries.
 *
 * Build modes:
 *   - Remote (default): Downloads pre-built native libraries from GitHub releases
 *   - Local: Uses locally built libraries from runanywhere-core/dist/android/jni
 *
 * To use local mode: ./gradlew build -Prunanywhere.testLocal=true
 */

import java.net.URL

plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.library)
    `maven-publish`
}

// =============================================================================
// Configuration
// =============================================================================

// Version of pre-built native libraries to download
val nativeLibVersion = project.findProperty("runanywhere.native.version")?.toString()
    ?: file("VERSION").takeIf { it.exists() }?.readText()?.trim()
    ?: "0.0.1-dev"

// Use local build mode (requires runanywhere-core to be built locally)
val useLocalBuild = project.findProperty("runanywhere.testLocal")?.toString()?.toBoolean() ?: false

// GitHub configuration for downloads
val githubOrg = project.findProperty("runanywhere.github.org")?.toString() ?: "RunanywhereAI"
val githubRepo = project.findProperty("runanywhere.github.repo")?.toString() ?: "runanywhere-binaries"

// Local runanywhere-core path (for local builds)
val runAnywhereCoreDir = project.projectDir.resolve("../../../../../runanywhere-core")

// Native libraries directory
val jniLibsDir = file("src/main/jniLibs")
val downloadedLibsDir = file("build/downloaded-libs")

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
                // Core SDK dependency for result types (NativeTTSSynthesisResult, etc.)
                api(project.parent!!.parent!!)
                implementation(libs.kotlinx.coroutines.core)
            }
        }

        val commonTest by getting {
            dependencies {
                implementation(kotlin("test"))
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
    // Note: Can't use "native" in namespace (Java keyword), but Kotlin package name
    // MUST be com.runanywhere.sdk.native.bridge to match JNI function registration
    namespace = "com.runanywhere.sdk.jni.bridge"
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
                "proguard-rules.pro"
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
        jniLibs {
            useLegacyPackaging = true
        }
    }

    // Configure jniLibs source based on build mode
    sourceSets {
        getByName("main") {
            if (useLocalBuild) {
                // Local mode: use locally built JNI libraries from runanywhere-core/dist/android/jni
                val distDir = runAnywhereCoreDir.resolve("dist/android/jni")
                if (distDir.exists()) {
                    jniLibs.srcDirs(distDir)
                    logger.lifecycle("JNI module: Using local native libraries from: $distDir")
                } else {
                    logger.warn("JNI module: Local libraries not found at: $distDir")
                    logger.warn("Run: cd runanywhere-core && ./scripts/build-android.sh all")
                }
            } else {
                // Remote mode: use downloaded libraries
                jniLibs.srcDirs(jniLibsDir)
                logger.lifecycle("JNI module: Using downloaded native libraries from: $jniLibsDir")
            }
        }
    }
}

// =============================================================================
// Download Native Libraries Task
// =============================================================================

/**
 * Task to download pre-built JNI libraries from GitHub releases
 */
val downloadNativeLibs by tasks.registering {
    description = "Downloads pre-built JNI bridge libraries from GitHub releases"
    group = "build setup"

    val versionFile = file("$jniLibsDir/.version")
    val zipFile = file("$downloadedLibsDir/RunAnywhereJNI-android.zip")

    outputs.dir(jniLibsDir)
    outputs.upToDateWhen {
        versionFile.exists() && versionFile.readText().trim() == nativeLibVersion
    }

    doLast {
        if (useLocalBuild) {
            logger.lifecycle("Skipping download - using local build mode")
            return@doLast
        }

        val currentVersion = if (versionFile.exists()) versionFile.readText().trim() else ""
        if (currentVersion == nativeLibVersion) {
            logger.lifecycle("JNI libraries version $nativeLibVersion already downloaded")
            return@doLast
        }

        logger.lifecycle("Downloading JNI libraries version $nativeLibVersion...")

        val downloadUrl = "https://github.com/$githubOrg/$githubRepo/releases/download/v$nativeLibVersion/RunAnywhereJNI-android.zip"

        // Create download directory
        downloadedLibsDir.mkdirs()

        // Download the ZIP file
        try {
            logger.lifecycle("Downloading from: $downloadUrl")
            URL(downloadUrl).openStream().use { input ->
                zipFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            logger.lifecycle("Downloaded: ${zipFile.length() / 1024}KB")
        } catch (e: Exception) {
            logger.lifecycle("JNI libraries not available in release $nativeLibVersion")
            logger.lifecycle("This is normal - JNI bridge libraries are bundled with backend modules (ONNX, LlamaCPP)")
            logger.lifecycle("")
            logger.lifecycle("If you need standalone JNI libraries:")
            logger.lifecycle("  1. Check that version $nativeLibVersion includes RunAnywhereJNI-android.zip")
            logger.lifecycle("  2. Build locally: cd runanywhere-core && ./scripts/build-android.sh all")
            logger.lifecycle("  3. Use local mode: ./gradlew build -Prunanywhere.testLocal=true")

            // Create empty version file to mark as "attempted"
            jniLibsDir.mkdirs()
            versionFile.writeText(nativeLibVersion)
            return@doLast
        }

        // Clear existing jniLibs
        jniLibsDir.deleteRecursively()
        jniLibsDir.mkdirs()

        // Extract the ZIP
        logger.lifecycle("Extracting JNI libraries...")
        copy {
            from(zipTree(zipFile))
            into(downloadedLibsDir)
        }

        // Move libraries to jniLibs directory
        // ZIP structure: jni/<abi>/lib*.so -> jniLibs/<abi>/lib*.so
        val jniDir = file("$downloadedLibsDir/jni")
        if (jniDir.exists()) {
            jniDir.listFiles()?.filter { it.isDirectory && it.name != "include" }?.forEach { abiDir ->
                val targetAbiDir = file("$jniLibsDir/${abiDir.name}")
                targetAbiDir.mkdirs()
                abiDir.listFiles()?.filter { it.extension == "so" }?.forEach { soFile ->
                    soFile.copyTo(file("$targetAbiDir/${soFile.name}"), overwrite = true)
                    logger.lifecycle("  Extracted: ${abiDir.name}/${soFile.name}")
                }
            }
        }

        // Write version marker
        versionFile.writeText(nativeLibVersion)
        logger.lifecycle("JNI libraries version $nativeLibVersion installed")
    }
}

// Make preBuild depend on download task when not using local build
if (!useLocalBuild) {
    tasks.matching { it.name == "preBuild" }.configureEach {
        dependsOn(downloadNativeLibs)
    }
}

/**
 * Task to clean downloaded native libraries
 */
val cleanNativeLibs by tasks.registering(Delete::class) {
    description = "Removes downloaded JNI libraries"
    group = "build"
    delete(jniLibsDir)
    delete(downloadedLibsDir)
}

tasks.named("clean") {
    dependsOn(cleanNativeLibs)
}

/**
 * Task to print native library info
 */
val printNativeLibInfo by tasks.registering {
    description = "Prints information about JNI library configuration"
    group = "help"

    doLast {
        println()
        println("RunAnywhere Core JNI - Native Library Configuration")
        println("=" .repeat(60))
        println()
        println("Build Mode:        ${if (useLocalBuild) "LOCAL" else "REMOTE"}")
        println("Native Version:    $nativeLibVersion")
        println()
        println("Directories:")
        println("  jniLibs:         $jniLibsDir")
        if (useLocalBuild) {
            println("  runanywhere-core: $runAnywhereCoreDir")
            println("  dist dir:        ${runAnywhereCoreDir.resolve("dist/android/jni")}")
        }
        println()

        val versionFile = file("$jniLibsDir/.version")
        if (versionFile.exists()) {
            println("Installed Version: ${versionFile.readText().trim()}")
        } else {
            println("Installed Version: (not installed)")
        }

        println()
        println("Libraries (shared JNI bridge):")
        jniLibsDir.listFiles()?.filter { it.isDirectory }?.forEach { abiDir ->
            println("  ${abiDir.name}/")
            abiDir.listFiles()?.filter { it.extension == "so" }?.forEach { soFile ->
                println("    ${soFile.name} (${soFile.length() / 1024}KB)")
            }
        }
        println()
    }
}

// =============================================================================
// Publishing Configuration
// =============================================================================

publishing {
    publications.withType<MavenPublication> {
        pom {
            name.set("RunAnywhere Core JNI Module")
            description.set("Unified JNI bridge for RunAnywhere Core C++ library")
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
