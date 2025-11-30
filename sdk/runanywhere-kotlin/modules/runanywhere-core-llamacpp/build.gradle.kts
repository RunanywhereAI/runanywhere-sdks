/**
 * RunAnywhere Core LlamaCPP Module
 *
 * This module provides the LlamaCPP backend for RunAnywhere Core.
 * It depends on runanywhere-core-jni for the shared JNI bridge.
 *
 * Architecture:
 *   LlamaCppCoreService -> RunAnywhereBridge (from jni module)
 *     -> librunanywhere_jni.so (from jni module)
 *     -> librunanywhere_bridge.so (from jni module)
 *     -> librunanywhere_llamacpp.so (THIS module)
 *     -> libomp.so, libc++_shared.so (THIS module)
 *
 * This module provides ONLY the LlamaCPP-specific native libraries:
 *   - librunanywhere_llamacpp.so (LlamaCPP backend implementation)
 *   - libomp.so (OpenMP for parallelization)
 *   - libc++_shared.so (C++ standard library)
 *
 * Build modes:
 *   - Remote (default): Downloads pre-built native libraries from GitHub releases
 *   - Local: Uses locally built libraries from runanywhere-core/dist/android/llamacpp
 *
 * To use local mode: ./gradlew build -Prunanywhere.testLocal=true
 */

import java.net.URL

plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.serialization)
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
// Project Path Resolution
// =============================================================================
// When included as a subproject in composite builds (e.g., from example app),
// the module path changes. This function resolves the correct path for sibling modules.
fun resolveModulePath(moduleName: String): String {
    // Try to find the module with different path prefixes
    val possiblePaths = listOf(
        ":modules:$moduleName",                           // When building SDK directly
        ":sdk:runanywhere-kotlin:modules:$moduleName",    // When included from example app
    )
    for (path in possiblePaths) {
        if (project.findProject(path) != null) {
            return path
        }
    }
    // Default to the most common path
    return ":modules:$moduleName"
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
            dependencies {
                // Use shared JNI bridge from the jni module
                api(project(resolveModulePath("runanywhere-core-jni")))
            }
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
                // Local mode: use locally built libraries from runanywhere-core/dist
                val distDir = runAnywhereCoreDir.resolve("dist/android/llamacpp")
                if (distDir.exists()) {
                    jniLibs.srcDirs(distDir)
                    logger.lifecycle("Using local native libraries from: $distDir")
                } else {
                    logger.warn("Local libraries not found at: $distDir")
                    logger.warn("Run: cd runanywhere-core && ./scripts/build-android-backend.sh llamacpp")
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
 * Task to download pre-built native libraries from GitHub releases
 */
val downloadNativeLibs by tasks.registering {
    description = "Downloads pre-built native libraries from GitHub releases"
    group = "build setup"

    val versionFile = file("$jniLibsDir/.version")
    val zipFile = file("$downloadedLibsDir/RunAnywhereLlamaCPP-android.zip")

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

        logger.lifecycle("Downloading native libraries version $nativeLibVersion...")

        val downloadUrl = "https://github.com/$githubOrg/$githubRepo/releases/download/v$nativeLibVersion/RunAnywhereLlamaCPP-android.zip"

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
            logger.error("Failed to download native libraries: ${e.message}")
            logger.error("URL: $downloadUrl")
            logger.lifecycle("")
            logger.lifecycle("Options:")
            logger.lifecycle("  1. Check that version $nativeLibVersion exists in the releases")
            logger.lifecycle("  2. Build locally: cd runanywhere-core && ./scripts/build-android-backend.sh llamacpp")
            logger.lifecycle("  3. Use local mode: ./gradlew build -Prunanywhere.testLocal=true")
            throw GradleException("Failed to download native libraries", e)
        }

        // Clear existing jniLibs
        jniLibsDir.deleteRecursively()
        jniLibsDir.mkdirs()

        // Extract the ZIP
        logger.lifecycle("Extracting native libraries...")
        copy {
            from(zipTree(zipFile))
            into(downloadedLibsDir)
        }

        // Move libraries to jniLibs directory
        // ZIP structure: <abi>/lib*.so -> jniLibs/<abi>/lib*.so
        downloadedLibsDir.listFiles()?.filter { it.isDirectory && it.name != "include" }?.forEach { abiDir ->
            val targetAbiDir = file("$jniLibsDir/${abiDir.name}")
            targetAbiDir.mkdirs()
            abiDir.listFiles()?.filter { it.extension == "so" }?.forEach { soFile ->
                soFile.copyTo(file("$targetAbiDir/${soFile.name}"), overwrite = true)
                logger.lifecycle("  Extracted: ${abiDir.name}/${soFile.name}")
            }
        }

        // Write version marker
        versionFile.writeText(nativeLibVersion)
        logger.lifecycle("Native libraries version $nativeLibVersion installed")
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
 * Task to print native library info
 */
val printNativeLibInfo by tasks.registering {
    description = "Prints information about native library configuration"
    group = "help"

    doLast {
        println()
        println("RunAnywhere Core LlamaCPP - Native Library Configuration")
        println("=" .repeat(60))
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
        println("Libraries:")
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
            description.set("Native LlamaCPP backend for RunAnywhere SDK via JNI")
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
