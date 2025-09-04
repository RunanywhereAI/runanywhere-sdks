plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)  // Re-enable for Kotlin 2.0
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.detekt)
    // id("kotlin-kapt")
    // TODO: #001 - Add Hilt plugin when configured in project level build.gradle
    // id("dagger.hilt.android.plugin")
}

android {
    namespace = "com.runanywhere.runanywhereai"
    compileSdk = 35  // Update to 35

    defaultConfig {
        applicationId = "com.runanywhere.runanywhereai"
        minSdk = 24
        targetSdk = 35  // Update to 35
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
            abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86", "x86_64")
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
            useLegacyPackaging = false
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
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = "11"

        // Kotlin compiler optimizations
        freeCompilerArgs += listOf(
            "-opt-in=kotlin.RequiresOptIn",
            "-opt-in=kotlinx.coroutines.ExperimentalCoroutinesApi",
            "-opt-in=androidx.compose.material3.ExperimentalMaterial3Api",
            "-opt-in=androidx.compose.foundation.ExperimentalFoundationApi",
            "-Xjvm-default=all",
            "-Xskip-metadata-version-check"  // Skip version check to avoid conflicts
        )
    }

    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.15"
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
    // SDK module
    implementation(project(":sdk-core"))

    // AndroidX Core
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.activity.compose)

    // Material Design
    implementation(libs.material)

    // Compose
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation(libs.androidx.material.icons.extended)

    // Navigation
    implementation(libs.androidx.navigation.compose)

    // Coroutines
    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.kotlinx.coroutines.android)

    // Serialization
    implementation(libs.kotlinx.serialization.json)

    // Dependency Injection
    // implementation(libs.hilt.android)
    // kapt(libs.hilt.android.compiler)
    // implementation(libs.hilt.navigation.compose)

    // Networking
    implementation(libs.okhttp)
    implementation(libs.okhttp.logging)
    implementation(libs.retrofit)
    implementation(libs.retrofit.gson)
    implementation(libs.gson)

    // File Management
    implementation(libs.commons.io)

    // Background Work
    implementation(libs.androidx.work.runtime.ktx)

    // Speech Recognition & VAD (for SDK)
    implementation(libs.whisper.jni)
    implementation(libs.android.vad.webrtc)
    implementation(libs.prdownloader)

    // Security
    implementation(libs.androidx.security.crypto)

    // Permissions
    implementation(libs.accompanist.permissions)

    // Room Database (if needed for model caching)
    implementation(libs.androidx.room.runtime)
    implementation(libs.androidx.room.ktx)
    // kapt(libs.androidx.room.compiler)

    // Play Core (for in-app updates)
    implementation(libs.google.play.core)
    implementation(libs.google.play.core.ktx)

    // Logging
    implementation(libs.timber)

    // Testing
    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.mockk)

    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.ui.test.junit4)
    debugImplementation(libs.androidx.ui.tooling)
    debugImplementation(libs.androidx.ui.test.manifest)

    // Enforce Kotlin version alignment across all dependencies to avoid conflicts
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
