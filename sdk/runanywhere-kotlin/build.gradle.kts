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
        compilations.all {
            compilerOptions.configure {
                freeCompilerArgs.add("-Xsuppress-version-warnings")
            }
        }
        testRuns["test"].executionTask.configure {
            useJUnitPlatform()
        }
    }

    // Android target
    androidTarget {
        compilations.all {
            compilerOptions.configure {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                freeCompilerArgs.add("-Xsuppress-version-warnings")
                freeCompilerArgs.add("-Xno-param-assertions")
            }
        }
    }

    // Native targets (temporarily disabled)
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

                // Okio for file system operations (replaces Files library from iOS)
                implementation("com.squareup.okio:okio:3.9.0")
            }
        }

        commonTest {
            dependencies {
                implementation(kotlin("test"))
                implementation(libs.kotlinx.coroutines.test)
                // Okio FakeFileSystem for testing
                implementation("com.squareup.okio:okio-fakefilesystem:3.9.0")
            }
        }

        // JVM + Android shared
        val jvmAndroidMain by creating {
            dependsOn(commonMain.get())
            dependencies {
                implementation(libs.whisper.jni)
                implementation(libs.okhttp)
                implementation(libs.okhttp.logging)
                implementation(libs.gson)
                implementation(libs.commons.io)
                implementation(libs.ktor.client.okhttp)
            }
        }

        jvmMain {
            dependsOn(jvmAndroidMain)
        }

        jvmTest {
            dependencies {
                implementation(libs.junit)
                implementation(libs.mockk)
            }
        }

        androidMain {
            dependsOn(jvmAndroidMain)
            dependencies {
                implementation(libs.androidx.core.ktx)
                implementation(libs.kotlinx.coroutines.android)
                implementation(libs.android.vad.webrtc)
                implementation(libs.prdownloader)
                implementation(libs.androidx.work.runtime.ktx)
                implementation(libs.androidx.room.runtime)
                implementation(libs.androidx.room.ktx)
                implementation(libs.androidx.security.crypto)
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
