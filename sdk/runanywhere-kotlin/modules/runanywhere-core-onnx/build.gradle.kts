/**
 * RunAnywhere Core ONNX Module
 *
 * This module provides the ONNX Runtime backend adapter for RunAnywhere Core.
 * It is PURE KOTLIN - no native libraries are bundled here.
 *
 * Architecture (mirrors iOS ONNXRuntime):
 *   iOS:     ONNXRuntime.swift -> CRunAnywhereCore -> RunAnywhereCoreBinary.xcframework
 *   Android: ONNXAdapter.kt -> RunAnywhereBridge.kt -> runanywhere-core-native AAR
 *
 * This module provides:
 *   - ONNXAdapter - High-level adapter for STT/TTS/VAD capabilities
 *   - ONNXServiceProvider - Service provider implementation
 *   - ONNXCoreService - Core service bridging to native code
 *
 * Native libraries are provided transitively via:
 *   runanywhere-core-onnx -> main SDK -> runanywhere-core-native
 */

plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.serialization)
    `maven-publish`
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
            // NOTE: No additional dependencies needed here!
            // The main SDK (parent) includes RunAnywhereBridge and native libs transitively
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
    }

    // NOTE: No jniLibs configuration needed - native libs come from runanywhere-core-native
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
            name.set("RunAnywhere Core ONNX Module")
            description.set("ONNX Runtime backend adapter for RunAnywhere SDK (pure Kotlin)")
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
