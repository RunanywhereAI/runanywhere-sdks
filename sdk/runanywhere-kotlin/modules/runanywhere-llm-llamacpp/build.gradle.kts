plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.library)
    `maven-publish`
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
                // Depend on core SDK for interfaces and models
                // Use rootProject to ensure correct resolution in composite builds
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

android {
    namespace = "com.runanywhere.sdk.llm.llamacpp"
    compileSdk = 36

    defaultConfig {
        minSdk = 24

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        ndk {
            // Target ARM 64-bit only (modern Android devices)
            // armeabi-v7a has NEON intrinsics conflicts with latest llama.cpp
            abiFilters += listOf("arm64-v8a")
        }

        externalNativeBuild {
            cmake {
                // llama.cpp build configuration (following the guide)
                arguments += "-DLLAMA_CURL=OFF"           // Disable CURL support
                arguments += "-DLLAMA_BUILD_COMMON=ON"    // Build common utilities
                arguments += "-DGGML_LLAMAFILE=OFF"       // Disable llamafile
                arguments += "-DCMAKE_BUILD_TYPE=Release" // Release build
                arguments += "-DGGML_NEON=ON"             // Enable ARM NEON SIMD

                // Optimization flags for ARM Cortex-A53
                cppFlags += "-O3"
                cppFlags += "-march=armv8-a"
                cppFlags += "-mtune=cortex-a53"
            }
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

    externalNativeBuild {
        cmake {
            path = file("../../native/llama-jni/CMakeLists.txt")
            version = "3.22.1"
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
}
