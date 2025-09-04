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
    implementation(libs.timber)

    // Dependency injection
    implementation(libs.hilt.android)
    kapt(libs.hilt.android.compiler)

    // JSON processing
    implementation(libs.gson)

    // Network and download management - Battle tested solutions
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.okhttp3:logging-interceptor:4.12.0")

    // Retrofit for API calls (widely used, battle-tested)
    implementation("com.squareup.retrofit2:retrofit:2.9.0")
    implementation("com.squareup.retrofit2:converter-gson:2.9.0")

    // PRDownloader - Dedicated download library with pause/resume support
    implementation("com.mindorks.android:prdownloader:0.6.0")

    // WorkManager for background downloads
    implementation("androidx.work:work-runtime-ktx:2.9.0")

    // File management
    implementation("commons-io:commons-io:2.11.0")

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
