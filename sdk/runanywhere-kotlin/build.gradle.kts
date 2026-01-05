// Clean Gradle script for KMP SDK

plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.detekt)
    alias(libs.plugins.ktlint)
    id("maven-publish")
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

group = "com.runanywhere.sdk"
version = "0.1.3"

// =============================================================================
// Local vs Remote JNI Library Configuration
// =============================================================================
// testLocal = true  → Use locally built JNI libs from src/androidMain/jniLibs/
//                     Run: ./scripts/build-local.sh to build and copy libs
//
// testLocal = false → Download pre-built JNI libs from GitHub releases (default)
//                     Downloads from: https://github.com/RunanywhereAI/runanywhere-binaries/releases
//
// Mirrors Swift SDK's Package.swift testLocal pattern
// =============================================================================
// IMPORTANT: Check rootProject first to support composite builds (e.g., when SDK is included from example app)
// This ensures the app's gradle.properties takes precedence over the SDK's default
val testLocal: Boolean = rootProject.findProperty("runanywhere.testLocal")?.toString()?.toBoolean()
    ?: project.findProperty("runanywhere.testLocal")?.toString()?.toBoolean()
    ?: false

// Version constants for remote downloads (mirrors Swift's Package.swift)
// These should match the releases at:
// - https://github.com/RunanywhereAI/runanywhere-binaries/releases (Android JNI libs for backends)
// - https://github.com/RunanywhereAI/runanywhere-sdks/releases (Android JNI libs for commons)
// IMPORTANT: Check rootProject first to support composite builds
val coreVersion: String = rootProject.findProperty("runanywhere.coreVersion")?.toString()
    ?: project.findProperty("runanywhere.coreVersion")?.toString()
    ?: "0.2.6"
val commonsVersion: String = rootProject.findProperty("runanywhere.commonsVersion")?.toString()
    ?: project.findProperty("runanywhere.commonsVersion")?.toString()
    ?: "0.1.2"

// Log the build mode
logger.lifecycle("RunAnywhere SDK: testLocal=$testLocal, coreVersion=$coreVersion")

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
    sourceSets {
        getByName("main") {
            // IMPORTANT: Use only ONE jniLibs directory to avoid duplicates
            // Clear any default directories and set only the one we want
            jniLibs.setSrcDirs(
                listOf(if (testLocal) "src/androidMain/jniLibs" else "build/jniLibs")
            )
        }
    }

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
// Runs scripts/build-local.sh to build native libraries from source when testLocal=true.
// This mirrors the Swift SDK's testLocal pattern.
// =============================================================================
tasks.register<Exec>("buildLocalJniLibs") {
    group = "runanywhere"
    description = "Build JNI libraries locally from runanywhere-commons (when testLocal=true)"

    val jniLibsDir = file("src/androidMain/jniLibs")
    val buildScript = file("scripts/build-local.sh")

    // Only enable this task when testLocal=true
    onlyIf { testLocal }

    // Check if libs already exist
    onlyIf {
        val hasLibs = jniLibsDir.exists() &&
            jniLibsDir.walkTopDown().any { it.extension == "so" }
        if (hasLibs) {
            logger.lifecycle("Local JNI libs already exist at: $jniLibsDir")
            logger.lifecycle("To rebuild, delete jniLibs/ or run: ./scripts/build-local.sh --clean")
        }
        !hasLibs
    }

    workingDir = projectDir
    commandLine("bash", buildScript.absolutePath)

    // Set environment
    environment("ANDROID_NDK_HOME",
        System.getenv("ANDROID_NDK_HOME") ?: "${System.getProperty("user.home")}/Library/Android/sdk/ndk/27.0.12077973"
    )

    doFirst {
        logger.lifecycle("")
        logger.lifecycle("═══════════════════════════════════════════════════════════════")
        logger.lifecycle(" Building JNI libraries locally (testLocal=true)")
        logger.lifecycle("═══════════════════════════════════════════════════════════════")
        logger.lifecycle("")
        logger.lifecycle("This may take several minutes on first build...")
        logger.lifecycle("Output will be in: $jniLibsDir")
        logger.lifecycle("")
    }

    doLast {
        // Verify the build succeeded
        val soFiles = jniLibsDir.walkTopDown().filter { it.extension == "so" }.toList()
        if (soFiles.isEmpty()) {
            throw GradleException("Local JNI build failed: No .so files found in $jniLibsDir")
        }
        logger.lifecycle("")
        logger.lifecycle("✓ Local JNI build complete: ${soFiles.size} .so files")
        soFiles.groupBy { it.parentFile.name }.forEach { (abi, files) ->
            logger.lifecycle("  $abi: ${files.map { it.name }.joinToString(", ")}")
        }
    }
}

// =============================================================================
// JNI Library Download Task (for testLocal=false mode)
// =============================================================================
// Downloads ALL JNI libraries from GitHub releases:
//   - Commons: https://github.com/RunanywhereAI/runanywhere-sdks/releases/tag/commons-v{version}
//     - librac_commons.so - RAC Commons infrastructure
//     - librac_commons_jni.so - RAC Commons JNI bridge
//   - Core backends: https://github.com/RunanywhereAI/runanywhere-binaries/releases/tag/core-v{version}
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

    val outputDir = file("build/jniLibs")
    val tempDir = file("${layout.buildDirectory.get()}/jni-temp")

    // GitHub release URLs
    val binariesBaseUrl = "https://github.com/RunanywhereAI/runanywhere-binaries/releases/download/core-v$coreVersion"
    val commonsBaseUrl = "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/commons-v$commonsVersion"

    // Packages to download - ORDER MATTERS: Commons first, then backends
    val packages = listOf(
        // Commons (RAC infrastructure - must be downloaded first)
        "$commonsBaseUrl/RACommons-android-v$commonsVersion.zip",
        // LlamaCPP backend (LLM inference)
        "$binariesBaseUrl/RABackendLlamaCPP-android-v$coreVersion.zip",
        // ONNX backend (STT/TTS/VAD)
        "$binariesBaseUrl/RABackendONNX-android-v$coreVersion.zip"
    )

    outputs.dir(outputDir)

    doLast {
        if (testLocal) {
            logger.lifecycle("Skipping JNI download: testLocal=true (using local libs)")
            return@doLast
        }

        // Clean output directories
        outputDir.deleteRecursively()
        tempDir.deleteRecursively()
        outputDir.mkdirs()
        tempDir.mkdirs()

        logger.lifecycle("")
        logger.lifecycle("═══════════════════════════════════════════════════════════════")
        logger.lifecycle(" Downloading JNI libraries (testLocal=false)")
        logger.lifecycle("═══════════════════════════════════════════════════════════════")
        logger.lifecycle("")
        logger.lifecycle("Core version: $coreVersion")
        logger.lifecycle("Commons version: $commonsVersion")
        logger.lifecycle("")

        var totalDownloaded = 0

        packages.forEach { zipUrl ->
            val packageName = zipUrl.substringAfterLast("/")
            val tempZip = file("$tempDir/$packageName")

            logger.lifecycle("▶ Downloading: $packageName")
            logger.lifecycle("  URL: $zipUrl")

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

                // Copy all .so files from ABI directories
                extractDir.walkTopDown()
                    .filter { it.isDirectory && it.name in listOf("arm64-v8a", "armeabi-v7a", "x86_64", "x86") }
                    .forEach { abiDir ->
                        val targetAbiDir = file("$outputDir/${abiDir.name}")
                        targetAbiDir.mkdirs()

                        abiDir.listFiles()?.filter { it.extension == "so" }?.forEach { soFile ->
                            val targetFile = file("$targetAbiDir/${soFile.name}")
                            if (!targetFile.exists()) {
                                soFile.copyTo(targetFile, overwrite = true)
                                logger.lifecycle("    ✓ ${abiDir.name}/${soFile.name}")
                                totalDownloaded++
                            }
                        }
                    }

                // Clean up temp zip
                tempZip.delete()

                logger.lifecycle("  ✓ $packageName extracted")
                logger.lifecycle("")

            } catch (e: Exception) {
                logger.warn("  ⚠ Failed to download $packageName: ${e.message}")
                logger.warn("    URL: $zipUrl")
                logger.lifecycle("")
            }
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
        logger.lifecycle("")

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

// Configure publishing to include license acknowledgments
publishing {
    publications.withType<MavenPublication> {
        pom {
            name.set("RunAnywhere Kotlin SDK")
            description.set("Privacy-first, on-device AI SDK for Kotlin/JVM and Android")
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

    // GitHub Packages repository configuration
    repositories {
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
