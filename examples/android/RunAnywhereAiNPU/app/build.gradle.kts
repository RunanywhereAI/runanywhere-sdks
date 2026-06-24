plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.runanywhere.sdk.runanywhereainpu"
    compileSdk {
        version = release(37)
    }

    defaultConfig {
        applicationId = "com.runanywhere.sdk.runanywhereainpu"
        minSdk = 27
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        // QHexRT is arm64-only (Snapdragon NPU); CPU-fallback engines also ship arm64.
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    // Core + each engine bundle libc++_shared.so / librac_commons.so; keep one.
    packaging {
        jniLibs {
            pickFirsts += listOf("**/libc++_shared.so", "**/librac_commons.so")
        }
    }

    buildTypes {
        release {
            optimization {
                enable = false
            }
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    buildFeatures {
        compose = true
    }
}

dependencies {
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons.core)
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.kotlinx.coroutines.android)

    // RunAnywhere SDK (mavenLocal) + the private QHexRT NPU engine. NPU-only: no
    // CPU fallback engines are bundled.
    implementation(libs.runanywhere.sdk)
    implementation(libs.runanywhere.qhexrt)

    testImplementation(libs.junit)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(libs.androidx.junit)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
    debugImplementation(libs.androidx.compose.ui.tooling)
}