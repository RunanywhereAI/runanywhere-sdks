// Clean Gradle script for KMP SDK

plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.detekt)
    alias(libs.plugins.ktlint)
    id("maven-publish")
    signing
}

// =============================================================================
// Detekt Configuration
// =============================================================================
detekt {
    buildUponDefaultConfig = true
    allRules = false
    config.setFrom(files("detekt.yml"))
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

// Maven Central group ID - must match verified Sonatype namespace
// Using io.github.sanchitmonga22 (verified) until com.runanywhere is verified
// Once com.runanywhere is verified, change to: "com.runanywhere"
val isJitPack = System.getenv("JITPACK") == "true"
val usePendingNamespace = System.getenv("USE_RUNANYWHERE_NAMESPACE")?.toBoolean() ?: false
group =
    when {
        isJitPack -> "com.github.RunanywhereAI.runanywhere-sdks"
        usePendingNamespace -> "com.runanywhere" // Use after DNS verification completes
        else -> "io.github.sanchitmonga22" // Currently verified namespace
    }

// Version resolution priority:
// 1. SDK_VERSION env var (set by our CI/CD from git tag)
// 2. VERSION env var (set by JitPack from git tag)
// 3. Default fallback for local development
val resolvedVersion =
    System.getenv("SDK_VERSION")?.removePrefix("v")
        ?: System.getenv("VERSION")?.removePrefix("v")
        ?: "0.1.5-SNAPSHOT"
version = resolvedVersion

// Log version for debugging
logger.lifecycle("RunAnywhere SDK version: $resolvedVersion (JitPack=$isJitPack)")

// =============================================================================
// Local vs Remote JNI Library Configuration
// =============================================================================
// testLocal = true  → Use locally built JNI libs from src/androidMain/jniLibs/
//                     Run: ./scripts/build-kotlin.sh --setup for first-time setup
//
// testLocal = false → Download pre-built JNI libs from GitHub releases (default)
//                     Downloads from: https://github.com/RunanywhereAI/runanywhere-sdks/releases
//
// rebuildCommons = true → Force rebuild of runanywhere-commons C++ code
//                         Use when you've made changes to C++ source
//
// Mirrors Swift SDK's Package.swift testLocal pattern
// =============================================================================
// IMPORTANT: Check rootProject first to support composite builds (e.g., when SDK is included from example app)
// This ensures the app's gradle.properties takes precedence over the SDK's default
val testLocal: Boolean =
    rootProject.findProperty("runanywhere.testLocal")?.toString()?.toBoolean()
        ?: project.findProperty("runanywhere.testLocal")?.toString()?.toBoolean()
        ?: false

// Force rebuild of runanywhere-commons when true
val rebuildCommons: Boolean =
    rootProject.findProperty("runanywhere.rebuildCommons")?.toString()?.toBoolean()
        ?: project.findProperty("runanywhere.rebuildCommons")?.toString()?.toBoolean()
        ?: false

// =============================================================================
// Native Library Version for Downloads
// =============================================================================
// When testLocal=false, native libraries are downloaded from GitHub unified releases.
// The native lib version should match the SDK version for consistency.
// Format: https://github.com/RunanywhereAI/runanywhere-sdks/releases/tag/v{version}
//
// Assets per ABI:
//   - RACommons-android-{abi}-v{version}.zip
//   - RABackendLLAMACPP-android-{abi}-v{version}.zip
//   - RABackendONNX-android-{abi}-v{version}.zip
// =============================================================================
val nativeLibVersion: String =
    rootProject.findProperty("runanywhere.nativeLibVersion")?.toString()
        ?: project.findProperty("runanywhere.nativeLibVersion")?.toString()
        ?: resolvedVersion // Default to SDK version

// Log the build mode
logger.lifecycle("RunAnywhere SDK: testLocal=$testLocal, nativeLibVersion=$nativeLibVersion")

// =============================================================================
// Project Path Resolution
// =============================================================================
// When included as a subproject in composite builds (e.g., from example app or Android Studio),
// the module path changes. This function constructs the full absolute path for sibling modules
// based on the current project's location in the hierarchy.
//
// Examples:
// - When SDK is root project: path = ":" → module path = ":modules:$moduleName"
// - When SDK is at ":sdk:runanywhere-kotlin": path → ":sdk:runanywhere-kotlin:modules:$moduleName"
fun resolveModulePath(moduleName: String): String {
    val basePath = project.path
    val computedPath =
        if (basePath == ":") {
            ":modules:$moduleName"
        } else {
            "$basePath:modules:$moduleName"
        }

    // Try to find the project using rootProject to handle Android Studio sync ordering
    val foundProject = rootProject.findProject(computedPath)
    if (foundProject != null) {
        return computedPath
    }

    // Fallback: Try just :modules:$moduleName (when SDK is at non-root but modules are siblings)
    val simplePath = ":modules:$moduleName"
    if (rootProject.findProject(simplePath) != null) {
        return simplePath
    }

    // Return computed path (will fail with clear error if not found)
    return computedPath
}

kotlin {
    // Use Java 17 toolchain across targets
    jvmToolchain(17)

    // JVM target for IntelliJ plugins and general JVM usage
    jvm {
        compilations.all {
            compilerOptions.configure {
                freeCompilerArgs.add("-Xsuppress-version-warnings")
            }
        }
        testRuns["test"].executionTask.configure {
            useJUnitPlatform()
        }
    }

    // Android target
    androidTarget {
        // Enable publishing Android AAR to Maven
        publishLibraryVariants("release")

        // Set correct artifact ID for Android publication
        mavenPublication {
            artifactId = "runanywhere-sdk-android"
        }

        compilations.all {
            compilerOptions.configure {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                freeCompilerArgs.add("-Xsuppress-version-warnings")
                freeCompilerArgs.add("-Xno-param-assertions")
            }
        }
    }

    // Native targets (temporarily disabled)
    // linuxX64()
    // macosX64()
    // macosArm64()
    // mingwX64()

    sourceSets {
        // Common source set
        commonMain {
            dependencies {
                implementation(libs.kotlinx.coroutines.core)
                implementation(libs.kotlinx.serialization.json)
                implementation(libs.kotlinx.datetime)

                // Ktor for networking
                implementation(libs.ktor.client.core)
                implementation(libs.ktor.client.content.negotiation)
                implementation(libs.ktor.client.logging)
                implementation(libs.ktor.serialization.kotlinx.json)

                // Okio for file system operations (replaces Files library from iOS)
                implementation(libs.okio)
            }
        }

        commonTest {
            dependencies {
                implementation(kotlin("test"))
                implementation(libs.kotlinx.coroutines.test)
                // Okio FakeFileSystem for testing
                implementation(libs.okio.fakefilesystem)
            }
        }

        // JVM + Android shared
        val jvmAndroidMain by creating {
            dependsOn(commonMain.get())
            dependencies {
                implementation(libs.whisper.jni)
                implementation(libs.okhttp)
                implementation(libs.okhttp.logging)
                implementation(libs.gson)
                implementation(libs.commons.io)
                implementation(libs.commons.compress)
                implementation(libs.ktor.client.okhttp)
                // Error tracking - Sentry (matches iOS SDK SentryDestination)
                implementation(libs.sentry)
            }
        }

        jvmMain {
            dependsOn(jvmAndroidMain)
        }

        jvmTest {
            dependencies {
                implementation(libs.junit)
                implementation(libs.mockk)
            }
        }

        androidMain {
            dependsOn(jvmAndroidMain)
            dependencies {
                // Native libs (.so files) are included directly in jniLibs/
                // Built from runanywhere-commons/scripts/build-android.sh

                implementation(libs.androidx.core.ktx)
                implementation(libs.kotlinx.coroutines.android)
                implementation(libs.android.vad.webrtc)
                implementation(libs.prdownloader)
                implementation(libs.androidx.work.runtime.ktx)
                implementation(libs.androidx.security.crypto)
                implementation(libs.retrofit)
                implementation(libs.retrofit.gson)
            }
        }

        androidUnitTest {
            dependencies {
                implementation(libs.junit)
                implementation(libs.mockk)
            }
        }
    }
}

android {
    namespace = "com.runanywhere.sdk.kotlin"
    compileSdk = 35

    defaultConfig {
        minSdk = 24
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        consumerProguardFiles("consumer-rules.pro")
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

    // ==========================================================================
    // JNI Libraries Configuration - ALL LIBS (Commons + Backends)
    // ==========================================================================
    // This SDK downloads and bundles all JNI libraries:
    //
    // From RACommons (commons-v{commonsVersion}):
    //   - librac_commons.so - RAC Commons infrastructure
    //   - librac_commons_jni.so - RAC Commons JNI bridge
    //   - libc++_shared.so - C++ STL (shared by all backends)
    //
    // From RABackendLlamaCPP (core-v{coreVersion}):
    //   - librac_backend_llamacpp_jni.so - LlamaCPP JNI bridge
    //   - librunanywhere_llamacpp.so - LlamaCPP backend
    //   - libllama.so, libcommon.so - llama.cpp core
    //
    // From RABackendONNX (core-v{coreVersion}):
    //   - librac_backend_onnx_jni.so - ONNX JNI bridge
    //   - librunanywhere_onnx.so - ONNX backend
    //   - libonnxruntime.so - ONNX Runtime
    //   - libsherpa-onnx-*.so - Sherpa ONNX (STT/TTS/VAD)
    // ==========================================================================
    // JNI libs are placed in src/androidMain/jniLibs/ (standard KMP location)
    // This is automatically included by the KMP Android plugin
    // ==========================================================================

    // Prevent packaging duplicates
    packaging {
        jniLibs {
            // Pick first if duplicates somehow still occur
            pickFirsts.add("**/*.so")
        }
    }
}

// =============================================================================
// Local JNI Build Task (for testLocal=true mode)
// =============================================================================
// Smart build task that:
// - Skips rebuild if JNI libs exist and C++ source hasn't changed
// - Forces rebuild if rebuildCommons=true
// - Uses build-kotlin.sh --setup for first-time setup
// - Uses build-local.sh for subsequent builds
//
// Usage:
//   ./gradlew buildLocalJniLibs                              # Build if needed
//   ./gradlew buildLocalJniLibs -Prunanywhere.rebuildCommons=true  # Force rebuild
// =============================================================================
tasks.register<Exec>("buildLocalJniLibs") {
    group = "runanywhere"
    description = "Build JNI libraries locally from runanywhere-commons (when testLocal=true)"

    val jniLibsDir = file("src/androidMain/jniLibs")
    val llamaCppJniLibsDir = file("modules/runanywhere-core-llamacpp/src/androidMain/jniLibs")
    val onnxJniLibsDir = file("modules/runanywhere-core-onnx/src/androidMain/jniLibs")
    val buildMarker = file(".commons-build-marker")
    val buildKotlinScript = file("scripts/build-kotlin.sh")
    val buildLocalScript = file("scripts/build-local.sh")

    // Only enable this task when testLocal=true
    onlyIf { testLocal }

    workingDir = projectDir

    // Set environment
    environment(
        "ANDROID_NDK_HOME",
        System.getenv("ANDROID_NDK_HOME") ?: "${System.getProperty("user.home")}/Library/Android/sdk/ndk/27.0.12077973",
    )

    doFirst {
        logger.lifecycle("")
        logger.lifecycle("═══════════════════════════════════════════════════════════════")
        logger.lifecycle(" RunAnywhere JNI Libraries (testLocal=true)")
        logger.lifecycle("═══════════════════════════════════════════════════════════════")
        logger.lifecycle("")

        // Check if we have existing libs
        val hasMainLibs = jniLibsDir.resolve("arm64-v8a/libc++_shared.so").exists()
        val hasLlamaCppLibs = llamaCppJniLibsDir.resolve("arm64-v8a/librac_backend_llamacpp_jni.so").exists()
        val hasOnnxLibs = onnxJniLibsDir.resolve("arm64-v8a/librac_backend_onnx_jni.so").exists()
        val allLibsExist = hasMainLibs && hasLlamaCppLibs && hasOnnxLibs

        if (allLibsExist && !rebuildCommons) {
            logger.lifecycle("✅ JNI libraries already exist - skipping build")
            logger.lifecycle("   (use -Prunanywhere.rebuildCommons=true to force rebuild)")
            logger.lifecycle("")
            // Skip the exec by setting a dummy command
            commandLine("echo", "JNI libs up to date")
        } else if (!allLibsExist) {
            // First time setup - use build-kotlin.sh --setup
            logger.lifecycle("🆕 First-time setup: Running build-kotlin.sh --setup")
            logger.lifecycle("   This will download dependencies and build everything...")
            logger.lifecycle("")
            commandLine("bash", buildKotlinScript.absolutePath, "--setup", "--skip-build")
        } else if (rebuildCommons) {
            // Force rebuild - use build-kotlin.sh with --rebuild-commons
            logger.lifecycle("🔄 Rebuild requested: Running build-kotlin.sh --rebuild-commons")
            logger.lifecycle("")
            commandLine("bash", buildKotlinScript.absolutePath, "--local", "--rebuild-commons", "--skip-build")
        }
    }

    doLast {
        // Verify the build succeeded for all modules
        fun countLibs(dir: java.io.File, moduleName: String): Int {
            if (!dir.exists()) return 0
            val soFiles = dir.walkTopDown().filter { it.extension == "so" }.toList()
            if (soFiles.isNotEmpty()) {
                logger.lifecycle("")
                logger.lifecycle("✓ $moduleName: ${soFiles.size} .so files")
                soFiles.groupBy { it.parentFile.name }.forEach { (abi, files) ->
                    logger.lifecycle("  $abi: ${files.map { it.name }.joinToString(", ")}")
                }
            }
            return soFiles.size
        }

        val mainCount = countLibs(jniLibsDir, "Main SDK (Commons)")
        val llamaCppCount = countLibs(llamaCppJniLibsDir, "LlamaCPP Module")
        val onnxCount = countLibs(onnxJniLibsDir, "ONNX Module")

        if (mainCount == 0 && testLocal) {
            throw GradleException(
                """
                Local JNI build failed: No .so files found in $jniLibsDir

                Run first-time setup:
                  ./scripts/build-kotlin.sh --setup

                Or download from releases:
                  ./gradlew -Prunanywhere.testLocal=false assembleDebug
                """.trimIndent(),
            )
        }

        if (mainCount > 0) {
            logger.lifecycle("")
            logger.lifecycle("═══════════════════════════════════════════════════════════════")
            logger.lifecycle(" Total: ${mainCount + llamaCppCount + onnxCount} native libraries")
            logger.lifecycle("═══════════════════════════════════════════════════════════════")
        }
    }
}

// =============================================================================
// Setup Task - First-time local development setup
// =============================================================================
// Convenience task for first-time setup. Equivalent to:
//   ./scripts/build-kotlin.sh --setup
// =============================================================================
tasks.register<Exec>("setupLocalDevelopment") {
    group = "runanywhere"
    description = "First-time setup: download dependencies, build commons, copy JNI libs"

    workingDir = projectDir
    commandLine("bash", "scripts/build-kotlin.sh", "--setup", "--skip-build")

    environment(
        "ANDROID_NDK_HOME",
        System.getenv("ANDROID_NDK_HOME") ?: "${System.getProperty("user.home")}/Library/Android/sdk/ndk/27.0.12077973",
    )

    doFirst {
        logger.lifecycle("")
        logger.lifecycle("═══════════════════════════════════════════════════════════════")
        logger.lifecycle(" RunAnywhere SDK - First-Time Local Development Setup")
        logger.lifecycle("═══════════════════════════════════════════════════════════════")
        logger.lifecycle("")
        logger.lifecycle("This will:")
        logger.lifecycle("  1. Download dependencies (Sherpa-ONNX, etc.)")
        logger.lifecycle("  2. Build runanywhere-commons for Android")
        logger.lifecycle("  3. Copy JNI libraries to module directories")
        logger.lifecycle("  4. Set testLocal=true in gradle.properties")
        logger.lifecycle("")
        logger.lifecycle("This may take 10-15 minutes on first run...")
        logger.lifecycle("")
    }

    doLast {
        logger.lifecycle("")
        logger.lifecycle("✅ Setup complete! You can now build with:")
        logger.lifecycle("   ./gradlew assembleDebug")
        logger.lifecycle("")
    }
}

// =============================================================================
// Rebuild Commons Task - For when C++ code changes
// =============================================================================
tasks.register<Exec>("rebuildCommons") {
    group = "runanywhere"
    description = "Rebuild runanywhere-commons C++ code (use after making C++ changes)"

    workingDir = projectDir
    commandLine("bash", "scripts/build-kotlin.sh", "--local", "--rebuild-commons", "--skip-build")

    environment(
        "ANDROID_NDK_HOME",
        System.getenv("ANDROID_NDK_HOME") ?: "${System.getProperty("user.home")}/Library/Android/sdk/ndk/27.0.12077973",
    )

    doFirst {
        logger.lifecycle("")
        logger.lifecycle("═══════════════════════════════════════════════════════════════")
        logger.lifecycle(" Rebuilding runanywhere-commons C++ code")
        logger.lifecycle("═══════════════════════════════════════════════════════════════")
        logger.lifecycle("")
    }
}

// =============================================================================
// JNI Library Download Task (for testLocal=false mode)
// =============================================================================
// Downloads ALL JNI libraries from GitHub releases:
//   - Commons: https://github.com/RunanywhereAI/runanywhere-sdks/releases/tag/commons-v{version}
//     - librac_commons.so - RAC Commons infrastructure
//     - librac_commons_jni.so - RAC Commons JNI bridge
//   - Core backends: https://github.com/RunanywhereAI/runanywhere-sdks/releases/tag/core-v{version}
//     - librac_backend_llamacpp_jni.so - LLM inference (llama.cpp)
//     - librac_backend_onnx_jni.so - STT/TTS/VAD (Sherpa ONNX)
//     - libonnxruntime.so - ONNX Runtime
//     - libsherpa-onnx-*.so - Sherpa ONNX components
//   - libc++_shared.so - C++ STL (shared)
// =============================================================================
tasks.register("downloadJniLibs") {
    group = "runanywhere"
    description = "Download JNI libraries from GitHub releases (when testLocal=false)"

    // Only run when NOT using local libs
    onlyIf { !testLocal }

    // Use standard KMP location for jniLibs
    val outputDir = file("src/androidMain/jniLibs")
    val tempDir = file("${layout.buildDirectory.get()}/jni-temp")

    // GitHub unified release URL - all assets are in one release
    // Format: https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v{version}/{asset}
    val releaseBaseUrl = "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v$nativeLibVersion"

    // ABIs to download - arm64-v8a covers ~85% of devices
    // Add more ABIs here if needed: "armeabi-v7a", "x86_64"
    val targetAbis = listOf("arm64-v8a", "armeabi-v7a", "x86_64")

    // Package types to download for each ABI
    val packageTypes =
        listOf(
            "RACommons-android", // Core infrastructure + JNI bridge
            "RABackendLLAMACPP-android", // LLM inference (llama.cpp)
            "RABackendONNX-android", // STT/TTS/VAD (Sherpa ONNX)
        )

    outputs.dir(outputDir)

    doLast {
        if (testLocal) {
            logger.lifecycle("Skipping JNI download: testLocal=true (using local libs)")
            return@doLast
        }

        // Check if libs already exist (CI pre-populates build/jniLibs/)
        val existingLibs = outputDir.walkTopDown().filter { it.extension == "so" }.count()
        if (existingLibs > 0) {
            logger.lifecycle("Skipping JNI download: $existingLibs .so files already in $outputDir (CI mode)")
            return@doLast
        }

        // Clean output directories (only if empty)
        outputDir.deleteRecursively()
        tempDir.deleteRecursively()
        outputDir.mkdirs()
        tempDir.mkdirs()

        logger.lifecycle("")
        logger.lifecycle("═══════════════════════════════════════════════════════════════")
        logger.lifecycle(" Downloading JNI libraries (testLocal=false)")
        logger.lifecycle("═══════════════════════════════════════════════════════════════")
        logger.lifecycle("")
        logger.lifecycle("Native lib version: v$nativeLibVersion")
        logger.lifecycle("Target ABIs: ${targetAbis.joinToString(", ")}")
        logger.lifecycle("")

        var totalDownloaded = 0

        targetAbis.forEach { abi ->
            val abiOutputDir = file("$outputDir/$abi")
            abiOutputDir.mkdirs()

            packageTypes.forEach { packageType ->
                // Asset naming: {PackageType}-{abi}-v{version}.zip
                val packageName = "$packageType-$abi-v$nativeLibVersion.zip"
                val zipUrl = "$releaseBaseUrl/$packageName"
                val tempZip = file("$tempDir/$packageName")

                logger.lifecycle("▶ Downloading: $packageName")

                try {
                    // Download the zip
                    ant.withGroovyBuilder {
                        "get"("src" to zipUrl, "dest" to tempZip, "verbose" to false)
                    }

                    // Extract to temp directory
                    val extractDir = file("$tempDir/extracted-${packageName.replace(".zip", "")}")
                    extractDir.mkdirs()
                    ant.withGroovyBuilder {
                        "unzip"("src" to tempZip, "dest" to extractDir)
                    }

                    // Copy all .so files (they may be in subdirectories like jni/, onnx/, llamacpp/)
                    extractDir
                        .walkTopDown()
                        .filter { it.extension == "so" }
                        .forEach { soFile ->
                            val targetFile = file("$abiOutputDir/${soFile.name}")
                            if (!targetFile.exists()) {
                                soFile.copyTo(targetFile, overwrite = true)
                                logger.lifecycle("  ✓ ${soFile.name}")
                                totalDownloaded++
                            }
                        }

                    // Clean up temp zip
                    tempZip.delete()
                } catch (e: Exception) {
                    logger.warn("  ⚠ Failed to download $packageName: ${e.message}")
                }
            }
            logger.lifecycle("")
        }

        // Clean up temp directory
        tempDir.deleteRecursively()

        // Verify output
        val totalLibs = outputDir.walkTopDown().filter { it.extension == "so" }.count()
        val abiDirs = outputDir.listFiles()?.filter { it.isDirectory }?.map { it.name } ?: emptyList()

        logger.lifecycle("═══════════════════════════════════════════════════════════════")
        logger.lifecycle("✓ JNI libraries ready: $totalLibs .so files")
        logger.lifecycle("  ABIs: ${abiDirs.joinToString(", ")}")
        logger.lifecycle("  Output: $outputDir")
        logger.lifecycle("═══════════════════════════════════════════════════════════════")

        // List libraries per ABI
        abiDirs.forEach { abi ->
            val libs = file("$outputDir/$abi").listFiles()?.filter { it.extension == "so" }?.map { it.name } ?: emptyList()
            logger.lifecycle("$abi (${libs.size} libs):")
            libs.sorted().forEach { lib ->
                val size = file("$outputDir/$abi/$lib").length() / 1024
                logger.lifecycle("  - $lib (${size}KB)")
            }
        }
    }
}

// Ensure JNI libs are available before Android build
tasks.matching { it.name.contains("merge") && it.name.contains("JniLibFolders") }.configureEach {
    if (testLocal) {
        dependsOn("buildLocalJniLibs")
    } else {
        dependsOn("downloadJniLibs")
    }
}

// Also ensure preBuild triggers JNI lib preparation
tasks.matching { it.name == "preBuild" }.configureEach {
    if (testLocal) {
        dependsOn("buildLocalJniLibs")
    } else {
        dependsOn("downloadJniLibs")
    }
}

// Include third-party licenses in JVM JAR
tasks.named<Jar>("jvmJar") {
    from(rootProject.file("THIRD_PARTY_LICENSES.md")) {
        into("META-INF")
    }
}

// =============================================================================
// Maven Central Publishing Configuration
// =============================================================================
// Consumer usage (after publishing):
//   implementation("com.runanywhere:runanywhere-sdk:1.0.0")
// =============================================================================

// Get publishing credentials from environment or gradle.properties
val mavenCentralUsername: String? =
    System.getenv("MAVEN_CENTRAL_USERNAME")
        ?: project.findProperty("mavenCentral.username") as String?
val mavenCentralPassword: String? =
    System.getenv("MAVEN_CENTRAL_PASSWORD")
        ?: project.findProperty("mavenCentral.password") as String?

// GPG signing configuration
val signingKeyId: String? =
    System.getenv("GPG_KEY_ID")
        ?: project.findProperty("signing.keyId") as String?
val signingPassword: String? =
    System.getenv("GPG_SIGNING_PASSWORD")
        ?: project.findProperty("signing.password") as String?
val signingKey: String? =
    System.getenv("GPG_SIGNING_KEY")
        ?: project.findProperty("signing.key") as String?

publishing {
    publications.withType<MavenPublication> {
        // Artifact naming for Maven Central
        // Main artifact: com.runanywhere:runanywhere-sdk:1.0.0
        artifactId =
            when (name) {
                "kotlinMultiplatform" -> "runanywhere-sdk"
                "androidRelease" -> "runanywhere-sdk-android"
                "jvm" -> "runanywhere-sdk-jvm"
                else -> "runanywhere-sdk-$name"
            }

        // POM metadata (required by Maven Central)
        pom {
            name.set("RunAnywhere SDK")
            description.set("Privacy-first, on-device AI SDK for Kotlin/JVM and Android. Includes core infrastructure and common native libraries.")
            url.set("https://runanywhere.ai")
            inceptionYear.set("2024")

            licenses {
                license {
                    name.set("The Apache License, Version 2.0")
                    url.set("https://www.apache.org/licenses/LICENSE-2.0.txt")
                    distribution.set("repo")
                }
            }

            developers {
                developer {
                    id.set("runanywhere")
                    name.set("RunAnywhere Team")
                    email.set("founders@runanywhere.ai")
                    organization.set("RunAnywhere AI")
                    organizationUrl.set("https://runanywhere.ai")
                }
            }

            scm {
                connection.set("scm:git:git://github.com/RunanywhereAI/runanywhere-sdks.git")
                developerConnection.set("scm:git:ssh://github.com/RunanywhereAI/runanywhere-sdks.git")
                url.set("https://github.com/RunanywhereAI/runanywhere-sdks")
            }

            issueManagement {
                system.set("GitHub Issues")
                url.set("https://github.com/RunanywhereAI/runanywhere-sdks/issues")
            }
        }
    }

    repositories {
        // Maven Central (Sonatype Central Portal - new API)
        maven {
            name = "MavenCentral"
            url = uri("https://ossrh-staging-api.central.sonatype.com/service/local/staging/deploy/maven2/")
            credentials {
                username = mavenCentralUsername
                password = mavenCentralPassword
            }
        }

        // Sonatype Snapshots (Central Portal)
        maven {
            name = "SonatypeSnapshots"
            url = uri("https://central.sonatype.com/repository/maven-snapshots/")
            credentials {
                username = mavenCentralUsername
                password = mavenCentralPassword
            }
        }

        // GitHub Packages (backup/alternative)
        maven {
            name = "GitHubPackages"
            url = uri("https://maven.pkg.github.com/RunanywhereAI/runanywhere-sdks")
            credentials {
                username = project.findProperty("gpr.user") as String? ?: System.getenv("GITHUB_ACTOR")
                password = project.findProperty("gpr.token") as String? ?: System.getenv("GITHUB_TOKEN")
            }
        }
    }
}

// Configure signing (required for Maven Central)
signing {
    // Use in-memory key if provided via environment, otherwise use system GPG
    if (signingKey != null && signingKey.contains("BEGIN PGP")) {
        useInMemoryPgpKeys(signingKeyId, signingKey, signingPassword)
    } else {
        // Use system GPG (configured via gradle.properties)
        useGpgCmd()
    }
    // Sign all publications
    sign(publishing.publications)
}

// Only sign when publishing to Maven Central (not for local builds)
tasks.withType<Sign>().configureEach {
    onlyIf {
        gradle.taskGraph.hasTask(":publishAllPublicationsToMavenCentralRepository") ||
            gradle.taskGraph.hasTask(":publish") ||
            project.hasProperty("signing.gnupg.keyName") ||
            signingKey != null
    }
}

// Disable JVM and debug publications - only publish Android release and metadata
tasks.withType<PublishToMavenRepository>().configureEach {
    onlyIf {
        val dominated = publication.name in listOf("jvm", "androidDebug")
        !dominated
    }
}

