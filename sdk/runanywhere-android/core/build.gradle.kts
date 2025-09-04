plugins {
    kotlin("jvm")
}

group = "com.runanywhere.sdk"
version = "1.0.0"

dependencies {
    implementation(project(":sdk:runanywhere-android:jni"))

    // Kotlin
    implementation(libs.kotlin.stdlib)
    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.kotlinx.coroutines.android)

    // Logging
    implementation(libs.slf4j.api)
    implementation(libs.logback.classic)

    // HTTP client for model downloading
    implementation(libs.okhttp)

    // JSON parsing
    implementation(libs.gson)

    // Whisper implementation - using whisper-jni from Maven Central
    implementation("io.github.givimad:whisper-jni:1.7.1")

    // VAD implementation - using WebRTC VAD from android-vad library
    implementation("com.github.gkonovalov.android-vad:webrtc:2.0.10")

    // Testing
    testImplementation(kotlin("test"))
    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.mockito.kotlin)
}

kotlin {
    jvmToolchain(17)
}

tasks.test {
    useJUnitPlatform()
}
