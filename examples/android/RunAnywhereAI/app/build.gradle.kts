import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.detekt)
    alias(libs.plugins.ktlint)
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
        freeCompilerArgs.addAll(
            "-opt-in=kotlin.RequiresOptIn",
            "-opt-in=kotlinx.coroutines.ExperimentalCoroutinesApi",
            "-opt-in=androidx.compose.material3.ExperimentalMaterial3Api",
            "-opt-in=androidx.compose.foundation.ExperimentalFoundationApi",
            "-Xjvm-default=all",
        )
    }
}

android {
    namespace = "com.runanywhere.runanywhereai"
    compileSdk = 36

    ndkVersion = (project.findProperty("racNdkVersion") as? String) ?: "27.0.12077973"

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

        // Note: ndk.abiFilters removed — splits.abi handles ABI filtering
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

    splits {
        abi {
            isEnable = true
            reset()
            include("arm64-v8a", "x86_64")
            isUniversalApk = false
        }
    }

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
            // Keep extracted native libraries for the example's transitive
            // backend loading path. The 16 KB launch dialog is handled by
            // packaging only 16 KB ELF-aligned .so files; legacy packaging is
            // not a substitute for ELF alignment.
            useLegacyPackaging = true

            // Handle duplicate native libraries from multiple SDK modules.
            // The main SDK, ONNX module, and LlamaCPP module may share common
            // libraries (libc++_shared, libomp, librac_commons). Use a wildcard
            // to safely pick the first copy for any ABI.
            pickFirsts += listOf("lib/**/*.so")
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

    buildFeatures {
        compose = true
        buildConfig = true
        aidl = false
        resValues = false
        shaders = false
        viewBinding = false
        dataBinding = false
    }
    lint {
        abortOnError = true
        checkDependencies = false
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
    implementation(files("../libs/runanywhere-sdk.aar"))
    implementation(files("../libs/runanywhere-llamacpp.aar"))
    implementation(files("../libs/runanywhere-onnx.aar"))

    implementation(libs.wire.runtime)
    implementation(libs.ktor.client.core)
    implementation(libs.ktor.client.content.negotiation)
    implementation(libs.ktor.client.logging)
    implementation(libs.ktor.serialization.kotlinx.json)
    implementation(libs.okio)
    implementation(libs.sentry)
    implementation(libs.json)

    // AndroidX Core & Lifecycle
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

    // Serialization & DateTime
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.datetime)

    // Networking
    implementation(libs.okhttp)
    implementation(libs.okhttp.logging)
    implementation(libs.retrofit)
    implementation(libs.retrofit.gson)
    implementation(libs.gson)

    // ========================================
    // PDF Text Extraction (RAG document ingestion)
    // ========================================
    implementation(libs.pdfbox.android)

    // Background Work
    implementation(libs.androidx.work.runtime.ktx)

    // Security
    implementation(libs.androidx.security.crypto)

    // DataStore
    implementation(libs.androidx.datastore.preferences)

    // Permissions
    implementation(libs.accompanist.permissions)

    // CameraX
    implementation(libs.androidx.camera.core)
    implementation(libs.androidx.camera.camera2)
    implementation(libs.androidx.camera.lifecycle)
    implementation(libs.androidx.camera.view)

    // Database
    implementation(libs.androidx.room.runtime)
    implementation(libs.androidx.room.ktx)

    // Play Services
    implementation(libs.google.play.app.update)
    implementation(libs.google.play.app.update.ktx)

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
}

detekt {
    config.setFrom("${project.rootDir}/detekt.yml")
}
