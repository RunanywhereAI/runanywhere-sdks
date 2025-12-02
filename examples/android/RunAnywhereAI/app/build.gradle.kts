plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.detekt)
    alias(libs.plugins.sentry)
}

android {
    namespace = "com.runanywhere.runanywhereai"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.runanywhere.runanywhereai"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"

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

            // Sentry DSN - disabled in debug builds for open source privacy
            // Set SENTRY_DSN environment variable if you want to enable for local testing
            buildConfigField(
                "String",
                "SENTRY_DSN",
                "\"${System.getenv("SENTRY_DSN") ?: ""}\""
            )
        }

        release {
            isDebuggable = false
            isMinifyEnabled = true
            isShrinkResources = true

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )

            // Build configuration fields
            buildConfigField("boolean", "DEBUG_MODE", "false")
            buildConfigField("String", "BUILD_TYPE", "\"release\"")

            // Sentry DSN - only populated in release builds via CI/CD environment variable
            // This ensures DSN is not exposed in open source repository
            buildConfigField(
                "String",
                "SENTRY_DSN",
                "\"${System.getenv("SENTRY_DSN") ?: ""}\""
            )

            // Optimization flags
            isJniDebuggable = false

            // Using default debug signing for now
        }

        create("benchmark") {
            initWith(getByName("release"))
            matchingFallbacks += listOf("release")
            isDebuggable = false

            // Additional optimizations for benchmarking
            buildConfigField("boolean", "BENCHMARK_MODE", "true")
            // Sentry DSN from release build type
            buildConfigField(
                "String",
                "SENTRY_DSN",
                "\"${System.getenv("SENTRY_DSN") ?: ""}\""
            )
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
            excludes += listOf(
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
                "META-INF/INDEX.LIST"
            )
        }

        jniLibs {
            // Use legacy packaging to extract libraries to filesystem
            // This helps with symbol resolution for transitive dependencies
            useLegacyPackaging = true
            // Handle duplicate native libraries when using multiple backend modules
            // Both llamacpp and onnx modules include shared JNI bridge libs
            pickFirsts += listOf(
                "lib/arm64-v8a/librunanywhere_bridge.so",
                "lib/arm64-v8a/librunanywhere_jni.so",
                "lib/arm64-v8a/libc++_shared.so",
                "lib/armeabi-v7a/librunanywhere_bridge.so",
                "lib/armeabi-v7a/librunanywhere_jni.so",
                "lib/armeabi-v7a/libc++_shared.so"
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
        freeCompilerArgs += listOf(
            "-opt-in=kotlin.RequiresOptIn",
            "-opt-in=kotlinx.coroutines.ExperimentalCoroutinesApi",
            "-opt-in=androidx.compose.material3.ExperimentalMaterial3Api",
            "-opt-in=androidx.compose.foundation.ExperimentalFoundationApi",
            "-Xjvm-default=all"
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
    implementation(project(":sdk:runanywhere-kotlin"))

    // Backend modules - each is SELF-CONTAINED with all native libs
    // Pick the backends you need:
    implementation(project(":sdk:runanywhere-kotlin:modules:runanywhere-core-llamacpp"))  // ~45MB - LLM text generation
    implementation(project(":sdk:runanywhere-kotlin:modules:runanywhere-core-onnx"))      // ~30MB - STT, TTS, VAD

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
    // Permissions
    // ========================================
    implementation(libs.accompanist.permissions)

    // ========================================
    // Database
    // ========================================
    implementation(libs.androidx.room.runtime)
    implementation(libs.androidx.room.ktx)

    // ========================================
    // Play Services
    // ========================================
    implementation(libs.google.play.core)
    implementation(libs.google.play.core.ktx)

    // ========================================
    // Logging
    // ========================================
    implementation(libs.timber)

    // ========================================
    // Crash Reporting - Sentry
    // ========================================
    implementation(libs.sentry.android)

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

// Sentry plugin configuration
// Only uploads symbols/mappings when SENTRY_AUTH_TOKEN is set (in CI/CD)
sentry {
    // Disable auto-init since we initialize manually in RunAnywhereApplication
    autoInstallation.enabled.set(false)

    // Enable source context for better stack traces (only in release builds with auth token)
    includeSourceContext.set(System.getenv("SENTRY_AUTH_TOKEN") != null)

    // Upload proguard mappings for release builds
    autoUploadProguardMapping.set(System.getenv("SENTRY_AUTH_TOKEN") != null)

    // Disable telemetry to Sentry
    telemetry.set(false)

    // Organization and project for uploads (only used when auth token is set)
    org.set(System.getenv("SENTRY_ORG") ?: "")
    projectName.set(System.getenv("SENTRY_PROJECT") ?: "")
}
