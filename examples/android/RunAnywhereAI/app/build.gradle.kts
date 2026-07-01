import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

// Backend config read from local.properties (gitignored) so the URL + api key
// are never committed in source. Empty defaults keep the build working without
// them (telemetry/auth simply stay disabled until provided).
val localProps = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val runanywhereBaseUrl: String = (localProps.getProperty("runanywhere.baseUrl") ?: "").trim()
val runanywhereApiKey: String = (localProps.getProperty("runanywhere.apiKey") ?: "").trim()

android {
    namespace = "com.runanywhere.runanywhereai"
    compileSdk {
        version = release(37) {
            minorApiLevel = 0
        }
    }

    signingConfigs {
        val keystorePath = System.getenv("KEYSTORE_PATH")
        val keystorePassword = System.getenv("KEYSTORE_PASSWORD")
        val keyAlias = System.getenv("KEY_ALIAS")
        val keyPassword = System.getenv("KEY_PASSWORD")

        if (keystorePath != null && keystorePassword != null && keyAlias != null && keyPassword != null) {
            create("release") {
                storeFile = file(keystorePath)
                storePassword = keystorePassword
                this.keyAlias = keyAlias
                this.keyPassword = keyPassword
            }
        }
    }

    defaultConfig {
        applicationId = "com.runanywhere.runanywhereai"
        minSdk = 24
        targetSdk = 37
        versionCode = 13
        versionName = "0.1.4"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        buildConfigField("String", "RUNANYWHERE_BASE_URL", "\"$runanywhereBaseUrl\"")
        buildConfigField("String", "RUNANYWHERE_API_KEY", "\"$runanywhereApiKey\"")

        // Ship arm64-v8a only: the Qualcomm Hexagon NPU (QHexRT, Hexagon v75/v79/v81)
        // is arm64-only hardware, and target devices (Snapdragon 8 Gen 3+) are all
        // arm64. Constraining to one ABI keeps a single consistent native slice (no
        // stale x86_64/armv7 commons), guarantees the v79+v81 QAIRT skels travel with
        // it, and roughly halves the APK size.
        ndk {
            abiFilters += "arm64-v8a"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            // Prefer an env-provided release keystore (CI / store builds); fall back to
            // the debug keystore so a release-type APK is still installable locally.
            // Replace with a real upload keystore before publishing to a store.
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    packaging {
        jniLibs {
            // SDK + backend AARs each bundle the NDK C++ runtime; keep one copy per ABI.
            pickFirsts += "**/libc++_shared.so"
            useLegacyPackaging = true
        }
    }
}

dependencies {
    implementation(files("../libs/runanywhere-sdk.aar"))
    implementation(files("../libs/runanywhere-llamacpp.aar"))
    implementation(files("../libs/runanywhere-onnx.aar"))
    implementation(files("../libs/runanywhere-qhexrt.aar"))
    implementation(libs.okhttp)
    implementation(libs.pdfbox.android)

    // CameraX — NPU VLM live camera view
    implementation(libs.androidx.camera.core)
    implementation(libs.androidx.camera.camera2)
    implementation(libs.androidx.camera.lifecycle)
    implementation(libs.androidx.camera.view)

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.security.crypto)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.kotlinx.serialization.json)
    // files(...) AARs carry no POM; declare coroutines 1.11.0 directly so it outranks
    // the older transitive core from androidx (SDK is compiled against 1.11.0).
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.proto.wire.runtime)
    testImplementation(libs.junit)

    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(libs.androidx.junit)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
    debugImplementation(libs.androidx.compose.ui.tooling)
}