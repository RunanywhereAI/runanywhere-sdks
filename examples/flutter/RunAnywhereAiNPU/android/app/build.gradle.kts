plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.runanywhere.sdk.runanywhere_ai_npu"
    compileSdk = 36 // RunAnywhere SDK AARs require compile against API 36+.
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.runanywhere.sdk.runanywhere_ai_npu"
        minSdk = 24 // RunAnywhere SDK + QHexRT engine require API 24+.
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // QHexRT is Qualcomm-only (Snapdragon NPU): arm64-v8a.
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    // Core + each engine plugin bundle libc++_shared.so / librac_commons.so; keep one.
    packaging {
        jniLibs {
            pickFirsts += listOf("**/libc++_shared.so", "**/librac_commons.so")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
