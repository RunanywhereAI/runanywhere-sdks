plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.serialization)
    id("maven-publish")
}

group = "com.runanywhere.sdk"
version = "1.0.0-SNAPSHOT"

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
                implementation("org.jetbrains.kotlinx:kotlinx-datetime:0.6.1")
            }
        }

        commonTest {
            dependencies {
                implementation(kotlin("test"))
                implementation(libs.kotlinx.coroutines.test)
            }
        }

        // JVM-specific dependencies
        jvmMain {
            dependencies {
                // Whisper JNI for STT
                implementation(libs.whisper.jni)
                // HTTP client for JVM
                implementation(libs.okhttp)
                implementation(libs.okhttp.logging)
                // JSON processing
                implementation(libs.gson)
                // File operations
                implementation(libs.commons.io)
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
                // Whisper JNI for Android
                implementation(libs.whisper.jni)
                // HTTP client
                implementation(libs.okhttp)
                implementation(libs.okhttp.logging)
                // JSON processing
                implementation(libs.gson)
                // File operations
                implementation(libs.commons.io)
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
    compileSdk = 35

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
