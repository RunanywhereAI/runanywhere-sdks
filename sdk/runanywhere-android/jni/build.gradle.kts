plugins {
    kotlin("jvm")
}

dependencies {
    // Kotlin coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")

    // Testing
    testImplementation(kotlin("test"))
}

kotlin {
    jvmToolchain(17)
}

// Copy native libraries to resources
tasks.register<Copy>("copyNativeLibraries") {
    from("src/main/resources/native")
    into("build/resources/main/native")
}

tasks.jar {
    dependsOn("copyNativeLibraries")
}
