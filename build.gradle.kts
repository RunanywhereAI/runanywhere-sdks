// Root build script for RunAnywhere Android SDK

plugins {
    // Apply plugins to submodules only - no root plugins needed for composite builds
    id("io.gitlab.arturbosch.detekt") version "1.23.7" apply false
}

// Configure all projects
allprojects {
    group = "com.runanywhere"
    version = "0.1.0"

    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
        mavenLocal()
    }
}

// Configure subprojects (not composite builds)
subprojects {
    tasks.withType<Test> {
        useJUnitPlatform()
        testLogging {
            events("passed", "skipped", "failed")
        }
    }

}

// Define reusable task for publishing SDK
tasks.register("publishSdkToMavenLocal") {
    group = "publishing"
    description = "Publishes the KMP SDK to Maven Local"
    dependsOn(":sdk:runanywhere-kotlin:publishToMavenLocal")
}

// Task to build everything
tasks.register("buildAll") {
    group = "build"
    description = "Builds all modules and composite builds"
    dependsOn(":sdk:runanywhere-kotlin:build")

    // Also trigger builds for composite builds
    finalizedBy("buildCompositeBuilds")
}

tasks.register("buildCompositeBuilds") {
    group = "build"
    description = "Builds composite builds (sample apps)"
    doLast {
        exec {
            workingDir = file("examples/android/RunAnywhereAI")
            commandLine("./gradlew", "assembleDebug")
        }
        exec {
            workingDir = file("examples/intellij-plugin-demo/plugin")
            commandLine("./gradlew", "buildPlugin")
        }
    }
}
