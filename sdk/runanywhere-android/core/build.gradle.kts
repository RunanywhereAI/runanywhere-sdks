plugins {
    id("com.android.library")
    kotlin("android")
}

android {
    namespace = "com.runanywhere.sdk.core"
    compileSdk = 35

    defaultConfig {
        minSdk = 21
        targetSdk = 35

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
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
    }
}

dependencies {
    implementation(project(":sdk-jni"))

    // Kotlin
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
    implementation(libs.whisper.jni)

    // VAD implementation - using WebRTC VAD from android-vad library
    implementation(libs.android.vad.webrtc)

    // Testing
    testImplementation(kotlin("test"))
    testImplementation(libs.junit)
    testImplementation(libs.mockk)
}
