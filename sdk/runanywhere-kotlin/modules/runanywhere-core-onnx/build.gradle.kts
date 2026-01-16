/**
 * RunAnywhere Core ONNX Module
 *
 * This module provides the ONNX Runtime backend for STT, TTS, and VAD.
 * It is SELF-CONTAINED with its own native libraries.
 *
 * Architecture (mirrors iOS RABackendONNX.xcframework):
 *   iOS:     ONNXRuntime.swift -> RABackendONNX.xcframework + onnxruntime.xcframework
 *   Android: ONNX.kt -> librunanywhere_onnx.so + libonnxruntime.so + libsherpa-onnx-*.so
 *
 * Native Libraries Included (~25MB total):
 *   - librunanywhere_onnx.so - ONNX backend wrapper
 *   - libonnxruntime.so (~15MB) - ONNX Runtime
 *   - libsherpa-onnx-c-api.so - Sherpa-ONNX C API
 *   - libsherpa-onnx-cxx-api.so - Sherpa-ONNX C++ API
 *   - libsherpa-onnx-jni.so - Sherpa-ONNX JNI (STT/TTS/VAD)
 *
 * This module is OPTIONAL - only include it if your app needs STT/TTS/VAD capabilities.
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
val testLocal: Boolean =
    rootProject.findProperty("runanywhere.testLocal")?.toString()?.toBoolean()
        ?: project.findProperty("runanywhere.testLocal")?.toString()?.toBoolean()
        ?: false
val coreVersion: String =
    rootProject.findProperty("runanywhere.coreVersion")?.toString()
        ?: project.findProperty("runanywhere.coreVersion")?.toString()
        ?: "0.1.4"

logger.lifecycle("ONNX Module: testLocal=$testLocal, coreVersion=$coreVersion")

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
            dependencies {
                // Apache Commons Compress for tar.bz2 extraction on Android
                // (native libarchive is not available on Android)
                implementation("org.apache.commons:commons-compress:1.26.0")
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
    namespace = "com.runanywhere.sdk.core.onnx"
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
    // JNI Libraries Configuration - ONNX Backend
    // ==========================================================================
    // This module bundles ONNX-specific native libraries (~25MB total):
    //   - librunanywhere_onnx.so - ONNX backend wrapper
    //   - libonnxruntime.so (~15MB) - ONNX Runtime
    //   - libsherpa-onnx-c-api.so - Sherpa C API
    //   - libsherpa-onnx-cxx-api.so - Sherpa C++ API
    //   - libsherpa-onnx-jni.so - Sherpa JNI (STT/TTS/VAD)
    //
    // When testLocal=true: Use libs from src/androidMain/jniLibs/
    // When testLocal=false: Use libs from build/jniLibs/ (downloaded)
    // ==========================================================================
    sourceSets {
        getByName("main") {
            // IMPORTANT: Use setSrcDirs to REPLACE (not add to) default jniLibs locations
            jniLibs.setSrcDirs(
                listOf(if (testLocal) "src/androidMain/jniLibs" else "build/jniLibs"),
            )
        }
    }
}

// =============================================================================
// JNI Library Download Task (for testLocal=false mode)
// =============================================================================
tasks.register("downloadJniLibs") {
    group = "runanywhere"
    description = "Download ONNX JNI libraries from GitHub releases"

    val outputDir = file("build/jniLibs")
    val tempDir = file("${layout.buildDirectory.get()}/jni-temp")
    val releaseBaseUrl = "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/core-v$coreVersion"
    val packageName = "RABackendONNX-android-v$coreVersion.zip"

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

        logger.lifecycle("Downloading ONNX JNI libraries...")
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

            // Copy .so files to output (excluding common libs that are in main SDK)
            // In the new RAC architecture, the common libs are from RACommons
            val commonLibs = setOf("libc++_shared.so", "librac_commons.so", "librac_commons_jni.so")

            extractDir
                .walkTopDown()
                .filter { it.isDirectory && it.name in listOf("arm64-v8a", "armeabi-v7a", "x86_64", "x86") }
                .forEach { abiDir ->
                    val targetAbiDir = file("$outputDir/${abiDir.name}")
                    targetAbiDir.mkdirs()

                    abiDir.listFiles()?.filter { it.extension == "so" && it.name !in commonLibs }?.forEach { soFile ->
                        val targetFile = file("$targetAbiDir/${soFile.name}")
                        soFile.copyTo(targetFile, overwrite = true)
                        logger.lifecycle("  Copied: ${abiDir.name}/${soFile.name}")
                    }
                }

            tempDir.deleteRecursively()
            logger.lifecycle("✓ ONNX JNI libraries ready")
        } catch (e: Exception) {
            logger.error("✗ Failed to download ONNX libs: ${e.message}")
        }
    }
}

// Ensure JNI libs are available before Android build
tasks.matching { it.name.contains("merge") && it.name.contains("JniLibFolders") }.configureEach {
    if (testLocal) {
        // When using local libs, depend on the main SDK's buildLocalJniLibs task
        // which runs build-local.sh and populates all module jniLibs directories
        val mainSdkProject = project.parent?.parent
        mainSdkProject?.tasks?.findByName("buildLocalJniLibs")?.let { buildTask ->
            dependsOn(buildTask)
        }
    } else {
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

// Use JitPack-compatible group when building on JitPack
val isJitPack = System.getenv("JITPACK") == "true"
group = if (isJitPack) "com.github.RunanywhereAI.runanywhere-sdks" else "com.runanywhere.sdk"
// Version: SDK_VERSION (our CI), VERSION (JitPack), or fallback
version = System.getenv("SDK_VERSION")?.removePrefix("v")
    ?: System.getenv("VERSION")?.removePrefix("v")
    ?: "0.1.5-SNAPSHOT"

publishing {
    publications.withType<MavenPublication> {
        // Use different artifact IDs to avoid conflicts between KMP publications
        artifactId = when (name) {
            "kotlinMultiplatform" -> "runanywhere-onnx"
            "androidRelease" -> "runanywhere-onnx-android"
            "androidDebug" -> "runanywhere-onnx-android-debug"
            "jvm" -> "runanywhere-onnx-jvm"
            else -> "runanywhere-onnx-$name"
        }

        pom {
            name.set("RunAnywhere ONNX Backend")
            description.set("ONNX Runtime backend for RunAnywhere SDK - STT, TTS, VAD")
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

// Disable JVM and debug publications - only publish Android release and metadata
tasks.withType<PublishToMavenRepository>().configureEach {
    onlyIf {
        val dominated = publication.name in listOf("jvm", "androidDebug")
        !dominated
    }
}
