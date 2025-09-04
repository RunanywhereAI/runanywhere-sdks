plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.runanywhere.sdk.core"
    compileSdk = 35

    defaultConfig {
        minSdk = 21
        targetSdk = 35

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        consumerProguardFiles("consumer-rules.pro")

        // Add native library support
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86", "x86_64")
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

    kotlinOptions {
        jvmTarget = "17"
        freeCompilerArgs += listOf("-Xskip-metadata-version-check")
    }
}

dependencies {
    implementation(project(":jni"))

    // Kotlin - Force specific version to avoid conflicts
    implementation(platform("org.jetbrains.kotlin:kotlin-bom:2.0.21"))
    implementation(libs.kotlin.stdlib)
    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.kotlinx.coroutines.android)

    // Android Core
    implementation(libs.androidx.core.ktx)

    // JSON processing
    implementation(libs.gson)

    // Network and download management
    implementation(libs.okhttp)
    implementation(libs.okhttp.logging)

    // Retrofit for API calls
    implementation(libs.retrofit)
    implementation(libs.retrofit.gson)

    // PRDownloader - Dedicated download library with pause/resume support
    implementation(libs.prdownloader)

    // WorkManager for background downloads
    implementation(libs.androidx.work.runtime.ktx)

    // File management
    implementation(libs.commons.io)

    // Whisper implementation - using whisper-jni from Maven Central
    implementation("io.github.givimad:whisper-jni:1.6.1")

    // VAD implementation - WebRTC VAD for speech detection
    implementation("com.github.gkonovalov:android-vad:2.0.10")

    // Testing
    testImplementation(kotlin("test"))
    testImplementation(libs.junit)
    testImplementation(libs.mockk)

    // Force Kotlin version alignment across all dependencies
    constraints {
        implementation("org.jetbrains.kotlin:kotlin-stdlib") {
            version {
                strictly("2.0.21")
            }
        }
        implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk7") {
            version {
                strictly("2.0.21")
            }
        }
        implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk8") {
            version {
                strictly("2.0.21")
            }
        }
        implementation("org.jetbrains.kotlin:kotlin-reflect") {
            version {
                strictly("2.0.21")
            }
        }
    }
}
