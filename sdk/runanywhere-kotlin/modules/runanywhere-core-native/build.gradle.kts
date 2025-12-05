/**
 * RunAnywhere Core Native Module - Unified Native Library Package
 *
 * This module provides a SINGLE UNIFIED native library package for RunAnywhere Core.
 * It mirrors the iOS XCFramework approach - a single binary package with everything.
 *
 * Architecture (mirrors iOS):
 *   iOS:     RunAnywhereCoreBinary.xcframework (single binary)
 *   Android: runanywhere-core-native AAR (unified native package)
 *
 * The unified package contains all required native libraries with a single JNI entry point.
 * All backend libraries (ONNX, LlamaCPP) are included in the unified archive.
 *
 * Build modes:
 *   - Remote (default): Downloads pre-built unified library from GitHub releases
 *   - Local: Uses locally built libraries from runanywhere-core/dist/android/unified
 *
 * To use local mode: ./gradlew build -Prunanywhere.testLocal=true
 */

import java.net.URL

plugins {
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

// Use local build mode (requires runanywhere-core to be built locally with 'all' backends)
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
// Android Configuration
// =============================================================================

android {
    namespace = "com.runanywhere.sdk.core.nativelibs"
    compileSdk = 36

    defaultConfig {
        minSdk = 24

        ndk {
            // Target ARM 64-bit only (modern Android devices)
            abiFilters += listOf("arm64-v8a")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt")
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
            // Use legacy packaging to extract libraries to filesystem
            // Required for proper symbol resolution with RTLD_GLOBAL
            useLegacyPackaging = true
        }
    }

    // Configure jniLibs source based on build mode
    sourceSets {
        getByName("main") {
            if (useLocalBuild) {
                // Local mode: use locally built libraries from runanywhere-core/dist/android/unified
                val unifiedDistDir = runAnywhereCoreDir.resolve("dist/android/unified")
                if (unifiedDistDir.exists()) {
                    jniLibs.srcDirs(unifiedDistDir)
                    logger.lifecycle("Using local unified native libraries from: $unifiedDistDir")
                } else {
                    // Fallback: combine jni + llamacpp + onnx directories
                    val jniDir = runAnywhereCoreDir.resolve("dist/android/jni")
                    val llamacppDir = runAnywhereCoreDir.resolve("dist/android/llamacpp")
                    val onnxDir = runAnywhereCoreDir.resolve("dist/android/onnx")

                    val sourceDirs = mutableListOf<File>()
                    if (jniDir.exists()) sourceDirs.add(jniDir)
                    if (llamacppDir.exists()) sourceDirs.add(llamacppDir)
                    if (onnxDir.exists()) sourceDirs.add(onnxDir)

                    if (sourceDirs.isNotEmpty()) {
                        jniLibs.srcDirs(sourceDirs)
                        logger.lifecycle("Using local native libraries from: ${sourceDirs.joinToString(", ")}")
                    } else {
                        logger.warn("Local libraries not found. Run: cd runanywhere-core && ./scripts/android/build.sh all")
                    }
                }
            } else {
                // Remote mode: use downloaded libraries
                jniLibs.srcDirs(jniLibsDir)
                logger.lifecycle("Using downloaded native libraries from: $jniLibsDir")
            }
        }
    }
}

// =============================================================================
// Download Native Libraries Task
// =============================================================================

/**
 * Task to download pre-built unified native library from GitHub releases.
 *
 * Downloads a SINGLE unified archive that contains all backends (ONNX, LlamaCPP)
 * with a unified bridge. This is the recommended approach for production.
 */
val downloadNativeLibs by tasks.registering {
    description = "Downloads pre-built unified native library from GitHub releases"
    group = "build setup"

    val versionFile = file("$jniLibsDir/.version")

    // Extract just the commit hash from version (e.g., "0.0.1-dev.2cd70fc" -> "2cd70fc")
    val shortVersion = nativeLibVersion.substringAfterLast(".")

    // Unified archive with all backends in one package
    val unifiedArchive = "RunAnywhereUnified-android-${shortVersion}.zip"

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
            logger.lifecycle("Native libraries version $nativeLibVersion already downloaded")
            return@doLast
        }

        logger.lifecycle("Downloading unified native library version $nativeLibVersion...")

        // Create download directory
        downloadedLibsDir.mkdirs()

        // Clear existing jniLibs
        jniLibsDir.deleteRecursively()
        jniLibsDir.mkdirs()

        // Download unified archive
        val unifiedUrl = "https://github.com/$githubOrg/$githubRepo/releases/download/v$nativeLibVersion/$unifiedArchive"
        val unifiedZipFile = file("$downloadedLibsDir/$unifiedArchive")

        try {
            logger.lifecycle("Downloading unified archive: $unifiedArchive")
            logger.lifecycle("URL: $unifiedUrl")
            URL(unifiedUrl).openStream().use { input ->
                unifiedZipFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            logger.lifecycle("Downloaded: ${unifiedZipFile.length() / 1024}KB")

            // Extract unified archive directly to jniLibs
            logger.lifecycle("Extracting unified archive...")
            copy {
                from(zipTree(unifiedZipFile))
                into(jniLibsDir)
            }

            // List extracted files
            jniLibsDir.listFiles()?.filter { it.isDirectory }?.forEach { abiDir ->
                logger.lifecycle("  ${abiDir.name}/")
                abiDir.listFiles()?.filter { it.extension == "so" }?.forEach { soFile ->
                    logger.lifecycle("    ${soFile.name} (${soFile.length() / 1024}KB)")
                }
            }

            logger.lifecycle("✅ Unified native library installed successfully")
        } catch (e: Exception) {
            logger.error("Failed to download unified native library: ${e.message}")
            logger.error("Download URL: $unifiedUrl")
            logger.error("")
            logger.error("Resolution options:")
            logger.error("  1. Check that version $nativeLibVersion exists in GitHub releases")
            logger.error("  2. Build locally: cd runanywhere-core && ./scripts/android/build.sh all")
            logger.error("  3. Use local mode: ./gradlew build -Prunanywhere.testLocal=true")
            throw GradleException("Failed to download unified native library: $unifiedArchive", e)
        }

        // Write version marker
        versionFile.writeText(nativeLibVersion)
        logger.lifecycle("Unified native library version $nativeLibVersion installed")
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
    description = "Removes downloaded native libraries"
    group = "build"
    delete(jniLibsDir)
    delete(downloadedLibsDir)
}

tasks.named("clean") {
    dependsOn(cleanNativeLibs)
}

/**
 * Task to print unified native library info
 */
val printNativeLibInfo by tasks.registering {
    description = "Prints information about unified native library configuration"
    group = "help"

    doLast {
        println()
        println("RunAnywhere Core Native - Unified Native Library Package")
        println("=".repeat(60))
        println()
        println("This module provides a SINGLE UNIFIED native library package.")
        println("Similar to iOS XCFramework, this is a single binary package.")
        println()
        println("Build Mode:        ${if (useLocalBuild) "LOCAL" else "REMOTE"}")
        println("Native Version:    $nativeLibVersion")
        println("GitHub Org:        $githubOrg")
        println("GitHub Repo:       $githubRepo")
        println()
        println("Directories:")
        println("  jniLibs:         $jniLibsDir")
        println("  downloaded:      $downloadedLibsDir")
        if (useLocalBuild) {
            println("  runanywhere-core: $runAnywhereCoreDir")
        }
        println()

        val versionFile = file("$jniLibsDir/.version")
        if (versionFile.exists()) {
            println("Installed Version: ${versionFile.readText().trim()}")
        } else {
            println("Installed Version: (not installed)")
        }

        println()
        println("Unified Library Contents:")
        jniLibsDir.listFiles()?.filter { it.isDirectory }?.forEach { abiDir ->
            println("  ${abiDir.name}/")
            abiDir.listFiles()?.filter { it.extension == "so" }?.sortedBy { it.name }?.forEach { soFile ->
                println("    ${soFile.name} (${soFile.length() / 1024}KB)")
            }
        }
        println()
    }
}

// =============================================================================
// Publishing Configuration
// =============================================================================

afterEvaluate {
    publishing {
        publications {
            register<MavenPublication>("release") {
                groupId = "com.runanywhere.sdk"
                artifactId = "runanywhere-core-native"
                version = nativeLibVersion

                from(components.findByName("release"))

                pom {
                    name.set("RunAnywhere Core Native")
                    description.set("Unified native libraries for RunAnywhere SDK (all backends)")
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
    }
}
