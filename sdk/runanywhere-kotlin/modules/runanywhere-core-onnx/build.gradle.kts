/**
 * RunAnywhere Core ONNX Module
 *
 * This module provides JNI bindings to the RunAnywhere Core C++ library with ONNX Runtime backend.
 * It mirrors the architecture of runanywhere-swift's CRunAnywhereONNX module.
 *
 * Architecture:
 *   Kotlin Service Layer (ONNXCoreService) -> JNI Bindings (RunAnywhereBridge)
 *     -> Native Library (librunanywhere_jni.so) -> C API (runanywhere_bridge.h)
 *       -> C++ Backend (runanywhere_onnx)
 */

plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.serialization)
    `maven-publish`
}

kotlin {
    jvm {
        compilations.all {
            kotlinOptions.jvmTarget = "17"
        }
    }

    androidTarget {
        compilations.all {
            kotlinOptions.jvmTarget = "17"
        }
    }

    sourceSets {
        val commonMain by getting {
            dependencies {
                // Core SDK dependency for interfaces and models
                api(project.parent!!.parent!!)
                implementation(libs.kotlinx.coroutines.core)
                implementation(libs.kotlinx.serialization.json)
            }
        }

        val commonTest by getting {
            dependencies {
                implementation(kotlin("test"))
                implementation(libs.kotlinx.coroutines.test)
            }
        }

        // Shared JVM/Android code
        val jvmAndroidMain by creating {
            dependsOn(commonMain)
        }

        val jvmMain by getting {
            dependsOn(jvmAndroidMain)
        }

        val androidMain by getting {
            dependsOn(jvmAndroidMain)
        }

        val jvmTest by getting
        val androidUnitTest by getting
    }
}

android {
    namespace = "com.runanywhere.sdk.core.onnx"
    compileSdk = 36

    defaultConfig {
        minSdk = 24

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        ndk {
            // Target ARM 64-bit only (modern Android devices)
            abiFilters += listOf("arm64-v8a")
        }

        externalNativeBuild {
            cmake {
                // CMake arguments for building the JNI layer
                arguments += "-DCMAKE_BUILD_TYPE=Release"

                // Path to runanywhere-core for headers and pre-built libs
                val runAnywhereCoreDir = rootProject.projectDir.resolve("../../../runanywhere-core")
                arguments += "-DRUNANYWHERE_CORE_DIR=${runAnywhereCoreDir.absolutePath}"
            }
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

    externalNativeBuild {
        cmake {
            // Point to the JNI CMakeLists.txt in runanywhere-core
            val jniCMakePath = rootProject.projectDir.resolve("../../../runanywhere-core/src/bridge/jni/CMakeLists.txt")
            path = jniCMakePath
            version = "3.22.1"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
        // Include pre-built .so files from runanywhere-core dist
        jniLibs {
            useLegacyPackaging = true
        }
    }

    // Copy pre-built libraries from runanywhere-core/dist/android into jniLibs
    sourceSets {
        getByName("main") {
            val runAnywhereCoreDir = rootProject.projectDir.resolve("../../../runanywhere-core")
            val distDir = runAnywhereCoreDir.resolve("dist/android/onnx")

            if (distDir.exists()) {
                jniLibs.srcDirs(distDir)
            }
        }
    }
}

// Include third-party licenses in JVM JAR
tasks.named<Jar>("jvmJar") {
    from(rootProject.file("THIRD_PARTY_LICENSES.md")) {
        into("META-INF")
    }
}

// Configure publishing
publishing {
    publications.withType<MavenPublication> {
        pom {
            name.set("RunAnywhere Core ONNX Module")
            description.set("Native ONNX Runtime backend for RunAnywhere SDK via JNI")
            url.set("https://github.com/RunanywhereAI/runanywhere-sdks")

            licenses {
                license {
                    name.set("The Apache License, Version 2.0")
                    url.set("http://www.apache.org/licenses/LICENSE-2.0.txt")
                }
            }

            developers {
                developer {
                    id.set("runanywhere")
                    name.set("RunAnywhere Team")
                    email.set("founders@runanywhere.ai")
                }
            }

            scm {
                connection.set("scm:git:git://github.com/RunanywhereAI/runanywhere-sdks.git")
                developerConnection.set("scm:git:ssh://github.com/RunanywhereAI/runanywhere-sdks.git")
                url.set("https://github.com/RunanywhereAI/runanywhere-sdks")
            }
        }
    }
}
