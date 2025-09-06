@file:OptIn(ExperimentalKotlinGradlePluginApi::class)

import org.jetbrains.kotlin.gradle.ExperimentalKotlinGradlePluginApi

plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.serialization)
    id("maven-publish")
}

group = "com.runanywhere.sdk"
version = "0.1.0"

kotlin {
    // JVM target for IntelliJ plugins and general JVM usage
    jvm {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
        testRuns["test"].executionTask.configure {
            useJUnitPlatform()
        }
    }

    // Android target
    androidTarget {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    // Native targets (optional, for future expansion)
    linuxX64()
    macosX64()
    macosArm64()
    mingwX64()

    sourceSets {
        // Common source set
        commonMain {
            dependencies {
                implementation(libs.kotlinx.coroutines.core)
                implementation(libs.kotlinx.serialization.json)
                implementation(libs.kotlinx.datetime)
            }
        }

        commonTest {
            dependencies {
                implementation(kotlin("test"))
                implementation(libs.kotlinx.coroutines.test)
            }
        }

        // Create shared source set for JVM and Android
        val jvmAndroidMain by creating {
            dependsOn(commonMain.get())
            dependencies {
                // Shared dependencies between JVM and Android
                implementation(libs.okhttp)
                implementation(libs.okhttp.logging)
                implementation(libs.gson)
                implementation(libs.commons.io)
                implementation(libs.whisper.jni)
            }
        }

        // JVM-specific dependencies
        jvmMain {
            dependsOn(jvmAndroidMain)
            dependencies {
                // Remove dependencies that are now in jvmAndroidMain
                // Add only JVM-specific dependencies here if any
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
                // Remove dependencies that are now in jvmAndroidMain
            }
        }

        androidUnitTest {
            dependencies {
                implementation(libs.junit)
                implementation(libs.mockk)
            }
        }

        // Native targets (basic setup)
        val nativeMain by creating {
            dependsOn(commonMain.get())
        }

        val linuxX64Main by getting { dependsOn(nativeMain) }
        val macosX64Main by getting { dependsOn(nativeMain) }
        val macosArm64Main by getting { dependsOn(nativeMain) }
        val mingwX64Main by getting { dependsOn(nativeMain) }
    }
}

android {
    namespace = "com.runanywhere.sdk.kotlin"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

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

publishing {
    publications {
        create<MavenPublication>("maven") {
            from(components["kotlin"])
            groupId = project.group.toString()
            artifactId = "runanywhere-kotlin"
            version = project.version.toString()
        }
    }
}
