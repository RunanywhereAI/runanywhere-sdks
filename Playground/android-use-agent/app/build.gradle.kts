plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.runanywhere.agent"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.runanywhere.agent"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"

        ndk {
            abiFilters += "arm64-v8a"
        }

        // Read API key from gradle.properties, falling back to local.properties
        val gptKeyFromGradle = (project.findProperty("GPT52_API_KEY") as String? ?: "").trim()
        val gptKeyRaw = if (gptKeyFromGradle.isNotEmpty()) {
            gptKeyFromGradle
        } else {
            val localFile = rootProject.file("local.properties")
            if (localFile.exists()) {
                localFile.readLines()
                    .firstOrNull { it.startsWith("GPT52_API_KEY=") }
                    ?.substringAfter("=")?.trim() ?: ""
            } else ""
        }
        val gptKey = gptKeyRaw.replace("\"", "\\\"")
        buildConfigField("String", "GPT52_API_KEY", "\"$gptKey\"")
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

    buildFeatures {
        compose = true
        buildConfig = true
    }


    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
        jniLibs {
            pickFirsts += "**/*.so"
        }
    }
}

dependencies {
    // RunAnywhere SDK (on-device LLM + STT) - local AARs
    implementation(files("../libs/RunAnywhereKotlinSDK-release.aar"))
    implementation(files("../libs/runanywhere-core-llamacpp-release.aar"))
    implementation(files("../libs/runanywhere-core-onnx-release.aar"))

    // Android Core
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")
    implementation("androidx.activity:activity-compose:1.8.2")

    // Jetpack Compose
    implementation(platform("androidx.compose:compose-bom:2024.06.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.7.0")

    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")

    // Archive extraction (required by RunAnywhere SDK for model downloads)
    implementation("org.apache.commons:commons-compress:1.26.0")

    // Networking
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    // Debug
    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
