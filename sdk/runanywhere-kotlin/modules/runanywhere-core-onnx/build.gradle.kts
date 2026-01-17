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
// Configuration
// =============================================================================
// Note: This module does NOT handle native libs - main SDK bundles everything
val testLocal: Boolean =
    rootProject.findProperty("runanywhere.testLocal")?.toString()?.toBoolean()
        ?: project.findProperty("runanywhere.testLocal")?.toString()?.toBoolean()
        ?: false

logger.lifecycle("ONNX Module: testLocal=$testLocal (native libs handled by main SDK)")

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
    // JNI Libraries - Handled by Main SDK
    // ==========================================================================
    // Backend modules do NOT bundle their own native libs.
    // All native libs are bundled by the main SDK (runanywhere-kotlin).
    // This module only contains Kotlin code for the ONNX backend.
    // ==========================================================================
}

// =============================================================================
// JNI Library Download Task - DISABLED for backend modules
// =============================================================================
// Backend modules do NOT download their own native libs.
// The main SDK's downloadJniLibs task downloads ALL native libs (including backend libs)
// to src/androidMain/jniLibs/ which is shared across all modules.
//
// This task is kept as a no-op for backwards compatibility.
// =============================================================================
tasks.register("downloadJniLibs") {
    group = "runanywhere"
    description = "No-op: Main SDK handles all native library downloads"

    doLast {
        logger.lifecycle("ONNX Module: Skipping downloadJniLibs (main SDK handles all native libs)")
    }
}

// Note: JNI libs are handled by the main SDK, not by backend modules

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
