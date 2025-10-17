plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.library)
    `maven-publish`
}

kotlin {
    androidTarget {
        compilations.all {
            kotlinOptions {
                jvmTarget = "17"
            }
        }
    }

    sourceSets {
        val commonMain by getting {
            dependencies {
                // Core SDK dependency (provides interfaces and models)
                api(project.parent!!.parent!!)

                // Coroutines for streaming
                implementation(libs.kotlinx.coroutines.core)

                // JSON serialization for MLC API
                implementation(libs.kotlinx.serialization.json)
            }
        }

        val commonTest by getting {
            dependencies {
                implementation(kotlin("test"))
                implementation(libs.kotlinx.coroutines.test)
            }
        }

        val androidMain by getting {
            dependencies {
                // Android-specific dependencies
                implementation(libs.androidx.core.ktx)

                // MLC4J library - official MLC-LLM Android bindings
                // This is a Git submodule from mlc-ai/mlc-llm (github.com/mlc-ai/mlc-llm)
                // Setup: git submodule update --init --recursive
                //
                // The mlc4j project provides:
                // - TVM runtime bindings (tvm4j_core.jar)
                // - Native libraries (libtvm4j_runtime_packed.so)
                // - OpenAI-compatible API (ai.mlc.mlcllm.MLCEngine)
                //
                // Note: This is an 'api' dependency, meaning consumers of this module
                // will also have access to mlc4j classes if needed
                try {
                    api(project(":mlc4j"))
                } catch (e: Exception) {
                    // mlc4j not available - module will compile but won't be functional at runtime
                    println("⚠ Warning: mlc4j not found. MLC-LLM module will not be functional.")
                    println("  To fix: git submodule update --init --recursive")
                }
            }
        }

        val androidUnitTest by getting {
            dependencies {
                implementation(kotlin("test-junit"))
            }
        }
    }
}

android {
    namespace = "com.runanywhere.sdk.llm.mlc"
    compileSdk = 36

    defaultConfig {
        minSdk = 24  // Match MLC-LLM's minimum (Android 5.1+)

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        ndk {
            // MLC-LLM supports these ABIs
            abiFilters += listOf(
                "arm64-v8a",      // Primary target (modern devices)
                "armeabi-v7a"     // Optional: older 32-bit devices
            )
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

        // Include native libraries in final AAR
        jniLibs {
            useLegacyPackaging = false
        }
    }
}

// Publishing configuration
publishing {
    publications.withType<MavenPublication> {
        groupId = "com.runanywhere.sdk"
        artifactId = "runanywhere-llm-mlc"
        version = "0.1.0"

        pom {
            name.set("RunAnywhere MLC-LLM Module")
            description.set("On-device LLM inference using MLC-LLM framework")
            url.set("https://github.com/runanywhere/sdks")
        }
    }
}
