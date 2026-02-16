/**
 * RunAnywhere Core SDCPP Module
 *
 * This module provides the stable-diffusion.cpp backend for image generation.
 * It is SELF-CONTAINED with its own native libraries.
 *
 * Native Libraries Included:
 *   - librac_backend_sdcpp_jni.so (~58MB) - Diffusion inference with sd.cpp
 */

plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.serialization)
}

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
                api(project.parent!!.parent!!)
                implementation(libs.kotlinx.coroutines.core)
                implementation(libs.kotlinx.serialization.json)
            }
        }

        val jvmAndroidMain by creating {
            dependsOn(commonMain)
        }

        val jvmMain by getting {
            dependsOn(jvmAndroidMain)
        }

        val androidMain by getting {
            dependsOn(jvmAndroidMain)
        }
    }
}

android {
    namespace = "com.runanywhere.sdk.core.sdcpp"
    compileSdk = 36

    defaultConfig {
        minSdk = 24
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    packaging {
        jniLibs {
            pickFirsts += setOf("**/*.so")
        }
    }
}
