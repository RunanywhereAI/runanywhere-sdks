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
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfigs.findByName("release")?.let { signingConfig = it }
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
            useLegacyPackaging = true
        }
    }
}

dependencies {
    // RunAnywhere SDK + native engine backends, consumed from mavenLocal.
    // Publish first: ./run example android publish (publishes all three to ~/.m2).
    // Maven POMs bring each artifact's transitive runtime deps automatically.
    implementation("io.github.sanchitmonga22:runanywhere-sdk:0.1.5-SNAPSHOT")
    implementation("io.github.sanchitmonga22:runanywhere-llamacpp:0.1.5-SNAPSHOT")
    implementation("io.github.sanchitmonga22:runanywhere-onnx:0.1.5-SNAPSHOT")
    implementation(libs.okhttp)
    implementation(libs.pdfbox.android)

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
    implementation(libs.proto.wire.runtime)
    testImplementation(libs.junit)

    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(libs.androidx.junit)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
    debugImplementation(libs.androidx.compose.ui.tooling)
}