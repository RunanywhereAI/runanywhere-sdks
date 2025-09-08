
// Clean Gradle script for KMP SDK

plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.serialization)
    id("maven-publish")
}

group = "com.runanywhere.sdk"
version = "0.1.0"

kotlin {
    // Use Java 17 toolchain across targets
    jvmToolchain(17)

    // JVM target for IntelliJ plugins and general JVM usage
    jvm {
        testRuns["test"].executionTask.configure {
            useJUnitPlatform()
        }
    }

    // Android target
    androidTarget {
        compilations.all {
            kotlinOptions {
                jvmTarget = "17"
            }
        }
    }

    // Native targets (temporarily disabled to fix compilation issues)
    // linuxX64()
    // macosX64()
    // macosArm64()
    // mingwX64()

    sourceSets {
        // Common source set
        commonMain {
            dependencies {
                implementation(libs.kotlinx.coroutines.core)
                implementation(libs.kotlinx.serialization.json)
                implementation(libs.kotlinx.datetime)

                // Ktor for networking
                implementation(libs.ktor.client.core)
                implementation(libs.ktor.client.content.negotiation)
                implementation(libs.ktor.client.logging)
                implementation(libs.ktor.serialization.kotlinx.json)
            }
        }

        commonTest {
            dependencies {
                implementation(kotlin("test"))
                implementation(libs.kotlinx.coroutines.test)
            }
        }

        // JVM and Android shared dependencies
        val jvmAndroidMain by creating {
            dependsOn(commonMain.get())
            dependencies {
                // Whisper JNI for STT (shared between JVM and Android)
                implementation(libs.whisper.jni)
                // HTTP client
                implementation(libs.okhttp)
                implementation(libs.okhttp.logging)
                // JSON processing
                implementation(libs.gson)
                // File operations
                implementation(libs.commons.io)
                // Ktor engine for JVM/Android
                implementation(libs.ktor.client.okhttp)
            }
        }

        // JVM-specific dependencies
        jvmMain {
            dependsOn(jvmAndroidMain)
            dependencies {
                // JVM-specific dependencies only
            }
        }

        jvmTest {
            dependencies {
                implementation(libs.junit)
                implementation(libs.mockk)
            }
        }

        // Android-specific dependencies
        androidMain {
            dependsOn(jvmAndroidMain)
            dependencies {
                // Android-specific dependencies only
                implementation(libs.androidx.core.ktx)
                implementation(libs.kotlinx.coroutines.android)
                // Android VAD (only for Android target)
                implementation(libs.android.vad.webrtc)
                // Android-specific download manager
                implementation(libs.prdownloader)
                implementation(libs.androidx.work.runtime.ktx)
                // Android Room database
                implementation(libs.androidx.room.runtime)
                implementation(libs.androidx.room.ktx)
                // Android security for encrypted storage
                implementation(libs.androidx.security.crypto)
                // Retrofit for API calls
                implementation(libs.retrofit)
                implementation(libs.retrofit.gson)
            }
        }

        androidUnitTest {
            dependencies {
                implementation(libs.junit)
                implementation(libs.mockk)
            }
        }
    }
}

android {
    namespace = "com.runanywhere.sdk.kotlin"
    compileSdk = 35

    defaultConfig {
        minSdk = 24

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        consumerProguardFiles("consumer-rules.pro")
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
}

// Rely on Kotlin Multiplatform's default publications for all targets
