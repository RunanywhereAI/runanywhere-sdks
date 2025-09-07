plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.serialization)
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

    // Future iOS support
    // iosArm64()
    // iosX64()
    // iosSimulatorArm64()

    sourceSets {
        val commonMain by getting {
            dependencies {
                implementation(libs.kotlinx.coroutines.core)
                implementation(libs.kotlinx.serialization.json)
                implementation(libs.kotlinx.datetime)
                api(libs.koin.core)
            }
        }

        val commonTest by getting {
            dependencies {
                implementation(libs.kotlin.test)
                implementation(libs.kotlinx.coroutines.test)
            }
        }

        val jvmAndroidMain by creating {
            dependsOn(commonMain)
            dependencies {
                implementation(libs.okhttp)
                implementation(libs.gson)
            }
        }

        val jvmMain by getting {
            dependsOn(jvmAndroidMain)
        }

        val androidMain by getting {
            dependsOn(jvmAndroidMain)
            dependencies {
                implementation(libs.androidx.core.ktx)
                implementation(libs.androidx.security.crypto)
                implementation(libs.androidx.room.runtime)
                implementation(libs.androidx.room.ktx)
            }
        }

        val jvmTest by getting
        val androidUnitTest by getting
    }
}

android {
    namespace = "com.runanywhere.sdk.core"
    compileSdk = 36

    defaultConfig {
        minSdk = 24
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

// Publishing configuration
publishing {
    publications {
        create<MavenPublication>("maven") {
            groupId = "com.runanywhere.sdk"
            artifactId = "runanywhere-core"
            version = "0.1.0"
        }
    }
}
