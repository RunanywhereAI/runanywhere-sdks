plugins {
    kotlin("jvm")
}

group = "com.runanywhere.sdk"
version = "1.0.0"

dependencies {
    implementation(kotlin("stdlib"))

    // Kotlin coroutines
    implementation(libs.kotlinx.coroutines.core)

    // Testing
    testImplementation(libs.junit)
    testImplementation(kotlin("test"))
}

kotlin {
    jvmToolchain(17)
}

tasks.test {
    useJUnitPlatform()
}

// Task to compile native code (placeholder - needs CMake setup)
tasks.register("compileNative") {
    doLast {
        println("Native compilation would happen here with CMake")
        println("This requires whisper.cpp and webrtc-vad sources")
    }
}

// Copy native libraries to resources
tasks.register<Copy>("copyNativeLibraries") {
    from("src/main/resources/native")
    into("build/resources/main/native")
}

tasks.jar {
    dependsOn("copyNativeLibraries")
}
