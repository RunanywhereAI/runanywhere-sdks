plugins {
    kotlin("jvm")
}

group = "com.runanywhere.sdk"
version = "1.0.0"

dependencies {
    implementation(kotlin("stdlib"))
    implementation(libs.kotlinx.coroutines.core)

    // Logging
    implementation(libs.slf4j.api)
    implementation(libs.logback.classic)

    // HTTP client for model downloading
    implementation(libs.okhttp)

    // JSON parsing
    implementation(libs.gson)

    // JNI module dependency
    implementation(project(":jni"))

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
    useJUnit()
}
