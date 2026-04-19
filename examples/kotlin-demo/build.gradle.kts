plugins {
    kotlin("jvm") version "2.1.21"
    application
}

group = "com.runanywhere.demo"
version = "0.1.0"

repositories {
    mavenCentral()
    google()
}

dependencies {
    implementation(project(":adapter"))
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
}

application {
    mainClass.set("com.runanywhere.demo.MainKt")
    applicationDefaultJvmArgs = listOf(
        "-Djava.library.path=" +
        (System.getenv("RA_LIB_DIR") ?: "${rootDir}/../../build/macos-release/core"))
}

kotlin {
    jvmToolchain(17)
}
