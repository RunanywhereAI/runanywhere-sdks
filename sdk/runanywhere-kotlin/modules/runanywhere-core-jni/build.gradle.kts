/**
 * RunAnywhere Core JNI Module
 *
 * This module provides the shared Kotlin JNI bridge code (RunAnywhereBridge.kt).
 * It does NOT include native libraries - those are bundled in each backend module.
 *
 * Architecture:
 *   Backend Module (e.g., runanywhere-core-llamacpp)
 *     -> This module (Kotlin JNI declarations)
 *     -> Native libs bundled in backend module
 *
 * This module provides:
 *   - RunAnywhereBridge.kt - Kotlin JNI declarations
 *   - NativeBridgeException.kt - Exception types
 *   - NativeResultCode.kt - Result codes
 *
 * Native libraries (librunanywhere_jni.so, etc.) are bundled with each backend module:
 *   - runanywhere-core-llamacpp: LLM backend + JNI bridge
 *   - runanywhere-core-onnx: ONNX backend + JNI bridge
 *
 * This allows apps to include only the backends they need.
 */

plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.library)
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
    }

    // Note: This module does NOT include native libraries.
    // Native libs are bundled in each backend module (llamacpp, onnx).
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
