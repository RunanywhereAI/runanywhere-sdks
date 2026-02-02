plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.detekt)
    alias(libs.plugins.ktlint)
}

android {
    namespace = "com.runanywhere.runanywhereai"
    compileSdk = 36

    signingConfigs {
        val keystorePath = System.getenv("KEYSTORE_PATH")
        val keystorePassword = System.getenv("KEYSTORE_PASSWORD")
        val keyAlias = System.getenv("KEY_ALIAS")
        val keyPassword = System.getenv("KEY_PASSWORD")

        if (keystorePath != null && keystorePassword != null && keyAlias != null && keyPassword != null) {
            create("release") {
                storeFile = file(keystorePath)
                storePassword = keystorePassword
                this.keyAlias = keyAlias
                this.keyPassword = keyPassword
            }
        }
    }

    defaultConfig {
        applicationId = "com.runanywhere.runanywhereai"
        minSdk = 24
        targetSdk = 36
        versionCode = 13
        versionName = "0.1.4"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        // Native build disabled for now to focus on Kotlin implementation
        // externalNativeBuild {
        //     cmake {
        //         cppFlags += listOf("-std=c++17", "-O3")
        //         arguments += listOf(
        //             "-DANDROID_STL=c++_shared",
        //             "-DBUILD_SHARED_LIBS=ON"
        //         )
        //     }
        // }

        ndk {
            // Only arm64-v8a for now (RunAnywhere Core ONNX is built for arm64-v8a)
            abiFilters += listOf("arm64-v8a")
        }
    }

    buildTypes {
        debug {
            isDebuggable = true
            isMinifyEnabled = false
            isShrinkResources = false
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"

            // Disable optimizations for faster builds
            buildConfigField("boolean", "DEBUG_MODE", "true")
            buildConfigField("String", "BUILD_TYPE", "\"debug\"")
        }

        release {
            // MUST be false for Play Store publishing
            isDebuggable = false
            isMinifyEnabled = true
            isShrinkResources = true

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )

            // Build configuration fields
            buildConfigField("boolean", "DEBUG_MODE", "false")
            buildConfigField("String", "BUILD_TYPE", "\"release\"")

            // MUST be false for Play Store publishing
            isJniDebuggable = false

            // Use release signing config if available
            val releaseSigningConfig = signingConfigs.findByName("release")
            if (releaseSigningConfig != null) {
                signingConfig = releaseSigningConfig
            }
        }

        create("benchmark") {
            initWith(getByName("release"))
            matchingFallbacks += listOf("release")
            isDebuggable = false

            // Additional optimizations for benchmarking
            buildConfigField("boolean", "BENCHMARK_MODE", "true")
            applicationIdSuffix = ".benchmark"
            versionNameSuffix = "-benchmark"
        }
    }

    // Signing configurations
    // Using default debug keystore for now

    // APK splits disabled for now to focus on basic functionality
    // splits {
    //     abi {
    //         isEnable = true
    //         reset()
    //         include("armeabi-v7a", "arm64-v8a")  // Focus on ARM architectures for mobile
    //         isUniversalApk = true  // Also generate a universal APK
    //     }
    //
    //     density {
    //         isEnable = true
    //         reset()
    //         include("ldpi", "mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi")
    //     }
    // }

    // Packaging options
    packaging {
        resources {
            excludes +=
                listOf(
                    "/META-INF/{AL2.0,LGPL2.1}",
                    "/META-INF/DEPENDENCIES",
                    "/META-INF/LICENSE",
                    "/META-INF/LICENSE.txt",
                    "/META-INF/NOTICE",
                    "/META-INF/NOTICE.txt",
                    "/META-INF/licenses/**",
                    "/META-INF/AL2.0",
                    "/META-INF/LGPL2.1",
                    "**/kotlin/**",
                    "kotlin/**",
                    "META-INF/kotlin/**",
                    "META-INF/*.kotlin_module",
                    "META-INF/INDEX.LIST",
                )
        }

        jniLibs {
            // Use legacy packaging to extract libraries to filesystem
            // This helps with symbol resolution for transitive dependencies
            // CRITICAL: useLegacyPackaging = true is REQUIRED for 16KB page size support
            // when using AGP < 8.5.1. With AGP 8.5.1+, this ensures proper extraction
            // and 16KB alignment during packaging.
            useLegacyPackaging = true

            // Handle duplicate native libraries from multiple backend modules
            // (ONNX and LlamaCPP both include some common libraries)
            pickFirsts += listOf(
                "lib/arm64-v8a/libomp.so",
                "lib/arm64-v8a/libc++_shared.so",
                "lib/arm64-v8a/librac_commons.so",
                "lib/armeabi-v7a/libomp.so",
                "lib/armeabi-v7a/libc++_shared.so",
                "lib/armeabi-v7a/librac_commons.so",
            )
        }
    }

    // Bundle configuration for Play Store
    bundle {
        language {
            enableSplit = true
        }
        density {
            enableSplit = true
        }
        abi {
            enableSplit = true
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"

        // Kotlin compiler optimizations
        freeCompilerArgs +=
            listOf(
                "-opt-in=kotlin.RequiresOptIn",
                "-opt-in=kotlinx.coroutines.ExperimentalCoroutinesApi",
                "-opt-in=androidx.compose.material3.ExperimentalMaterial3Api",
                "-opt-in=androidx.compose.foundation.ExperimentalFoundationApi",
                "-Xjvm-default=all",
            )
    }

    buildFeatures {
        compose = true
        buildConfig = true

        // Disable unused features for smaller APK
        aidl = false
        renderScript = false
        resValues = false
        shaders = false
        viewBinding = false
        dataBinding = false
    }
    lint {
        abortOnError = true
        checkDependencies = true
        warningsAsErrors = true
        baseline = file("lint-baseline.xml")
        lintConfig = file("lint.xml")
    }
    // Native build disabled for now to focus on Kotlin implementation
    // externalNativeBuild {
    //     cmake {
    //         path = file("src/main/cpp/CMakeLists.txt")
    //         version = "3.22.1"
    //     }
    // }
}

dependencies {
    // ========================================
    // SDK Dependencies
    // ========================================
    // Main SDK - high-level APIs, download, routing (no native libs)
    implementation("com.runanywhere.sdk:runanywhere-kotlin:0.1.4")

    // Backend modules - each is SELF-CONTAINED with all native libs
    // Pick the backends you need:
    implementation("com.runanywhere.sdk:runanywhere-core-llamacpp:0.1.4") // ~45MB - LLM text generation
    implementation("com.runanywhere.sdk:runanywhere-core-onnx:0.1.4") // ~30MB - STT, TTS, VAD

    // ========================================
    // AndroidX Core & Lifecycle
    // ========================================
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.activity.compose)

    // ========================================
    // Material Design
    // ========================================
    implementation(libs.material)

    // ========================================
    // Compose
    // ========================================
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation(libs.androidx.material.icons.extended)

    // ========================================
    // Navigation
    // ========================================
    implementation(libs.androidx.navigation.compose)

    // ========================================
    // Coroutines
    // ========================================
    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.kotlinx.coroutines.android)

    // ========================================
    // Serialization & DateTime
    // ========================================
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.datetime)

    // ========================================
    // Networking
    // ========================================
    implementation(libs.okhttp)
    implementation(libs.okhttp.logging)
    implementation(libs.retrofit)
    implementation(libs.retrofit.gson)
    implementation(libs.gson)

    // ========================================
    // File Management & Storage
    // ========================================
    implementation(libs.commons.io)

    // ========================================
    // Background Work
    // ========================================
    implementation(libs.androidx.work.runtime.ktx)

    // ========================================
    // Speech Recognition & Audio Processing
    // ========================================
    implementation(libs.whisper.jni)
    implementation(libs.android.vad.webrtc)
    implementation(libs.prdownloader)

    // ========================================
    // Security
    // ========================================
    implementation(libs.androidx.security.crypto)

    // ========================================
    // DataStore
    // ========================================
    implementation(libs.androidx.datastore.preferences)

    // ========================================
    // Permissions
    // ========================================
    implementation(libs.accompanist.permissions)

    // ========================================
    // Database
    // ========================================
    implementation(libs.androidx.room.runtime)
    implementation(libs.androidx.room.ktx)

    // ========================================
    // Play Services (Updated for targetSdk 34+)
    // ========================================
    implementation(libs.google.play.app.update)
    implementation(libs.google.play.app.update.ktx)

    // ========================================
    // Logging
    // ========================================
    implementation(libs.timber)

    // ========================================
    // Testing
    // ========================================
    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.mockk)

    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.ui.test.junit4)

    debugImplementation(libs.androidx.ui.tooling)
    debugImplementation(libs.androidx.ui.test.manifest)

    // ========================================
    // Kotlin Version Constraints
    // ========================================
    constraints {
        implementation("org.jetbrains.kotlin:kotlin-stdlib") {
            version {
                strictly(libs.versions.kotlin.get())
            }
        }
        implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk7") {
            version {
                strictly(libs.versions.kotlin.get())
            }
        }
        implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk8") {
            version {
                strictly(libs.versions.kotlin.get())
            }
        }
        implementation("org.jetbrains.kotlin:kotlin-reflect") {
            version {
                strictly(libs.versions.kotlin.get())
            }
        }
    }
}

detekt {
    config.setFrom("${project.rootDir}/detekt.yml")
}
