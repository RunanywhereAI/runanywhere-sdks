plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.serialization)
    id("maven-publish")
}

group = "com.runanywhere.sdk"
version = "0.1.0"

kotlin {
    // JVM target for IntelliJ plugins
    jvm {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    // Android target
    androidTarget {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    sourceSets {
        commonMain {
            dependencies {
                api(project(":"))  // Core SDK dependency - use api to expose STTService
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

        // JVM and Android shared dependencies
        val jvmAndroidMain by creating {
            dependsOn(commonMain.get())
            dependencies {
                // Whisper JNI for actual transcription
                implementation(libs.whisper.jni)
                // HTTP client for model downloads
                implementation(libs.okhttp)
                implementation(libs.okhttp.logging)
            }
        }

        jvmMain {
            dependsOn(jvmAndroidMain)
        }

        androidMain {
            dependsOn(jvmAndroidMain)
            dependencies {
                implementation(libs.androidx.core.ktx)
            }
        }
    }
}

android {
    namespace = "com.runanywhere.whisperkit"
    compileSdk = 36

    defaultConfig {
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")
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
            groupId = "com.runanywhere.sdk"
            artifactId = "runanywhere-whisperkit"
            version = project.version.toString()
        }
    }
}
