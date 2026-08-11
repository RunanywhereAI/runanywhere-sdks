plugins {
    id("com.android.application")
    // Not used for @Serializable — it is here only to pin AGP's built-in
    // Kotlin compiler to 2.4.0 so it can read the SDK's 2.4.0 metadata.
    id("org.jetbrains.kotlin.plugin.serialization")
}

android {
    namespace = "com.runanywhere.minimal"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.runanywhere.minimal"
        minSdk = 24
        targetSdk = 37
        versionCode = 1
        versionName = "1.0"
        // One ABI keeps the APK small; drop the filter to test other devices.
        ndk { abiFilters += "arm64-v8a" }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    packaging {
        jniLibs {
            // The SDK and each backend bundle the NDK C++ runtime; keep one copy.
            pickFirsts += "**/libc++_shared.so"
            pickFirsts += "**/libomp.so"
            pickFirsts += "**/librac_commons.so"
        }
    }
}

dependencies {
    // Substituted onto sdk/runanywhere-kotlin by settings.gradle.kts —
    // these coordinates are never resolved from a repository.
    implementation("com.runanywhere:runanywhere-kotlin")
    implementation("com.runanywhere:runanywhere-core-llamacpp")
}
