// Root build script for RunAnywhere Android SDK
//
// SIMPLIFIED BUILD TASKS:
// ----------------------
// The SDK is now a local module that builds automatically with the apps.
// No need to build or publish the SDK separately during development!
//
// AVAILABLE TASKS:
//   1. buildAndroidApp     - Build Android sample app (SDK builds automatically)
//   2. runAndroidApp       - Build and launch Android app on connected device
//   3. buildIntellijPlugin - Build IntelliJ plugin (publishes SDK to Maven Local first)
//   4. runIntellijPlugin   - Build and launch IntelliJ plugin in sandbox
//   5. cleanAll            - Clean all projects
//
// PUBLISHING (for SDK distribution only):
//   publishSdkToMavenLocal - Publish SDK to Maven Local repository
//
// Run these tasks from IntelliJ run configurations or via:
//   ./gradlew <taskName>

plugins {
    // Apply plugins to submodules only - no root plugins needed for composite builds
    id("io.gitlab.arturbosch.detekt") version "1.23.8" apply false
}

// Configure all projects
allprojects {
    group = "com.runanywhere"
    version = "0.1.0"
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

// ============================================================================
// ANDROID APP TASKS
// ============================================================================

tasks.register("buildAndroidApp") {
    group = "android"
    description = "Build Android sample app (SDK builds automatically as local module)"
    doLast {
        exec {
            workingDir = file("examples/android/RunAnywhereAI")
            commandLine("./gradlew", "assembleDebug")
        }
        println(" Android app built successfully")
    }
}

tasks.register("runAndroidApp") {
    group = "android"
    description = "Build and launch Android app on connected device"
    doLast {
        // 1. Build app (SDK builds automatically)
        println(" Building Android app...")
        exec {
            workingDir = file("examples/android/RunAnywhereAI")
            commandLine("./gradlew", "assembleDebug")
        }

        // 2. Install on connected device
        println(" Installing app...")
        exec {
            workingDir = file("examples/android/RunAnywhereAI")
            commandLine("./gradlew", "installDebug")
        }

        // 3. Launch the app
        println(" Launching app...")
        exec {
            commandLine(
                "adb",
                "shell",
                "am",
                "start",
                "-n",
                "com.runanywhere.runanywhereai.debug/.MainActivity"
            )
        }

        println(" Android app launched successfully")
    }
}

// ============================================================================
// INTELLIJ PLUGIN TASKS
// ============================================================================

tasks.register("buildIntellijPlugin") {
    group = "intellij"
    description = "Build IntelliJ plugin (publishes SDK to Maven Local first)"
    doLast {
        // 1. Publish SDK to Maven Local (plugin can't use local module)
        println("📦 Publishing SDK to Maven Local...")
        exec {
            workingDir = projectDir
            commandLine("./gradlew", ":sdk:runanywhere-kotlin:publishToMavenLocal")
        }

        // 2. Build plugin
        println("💡 Building IntelliJ plugin...")
        exec {
            workingDir = file("examples/intellij-plugin-demo/plugin")
            commandLine("./gradlew", "buildPlugin")
        }
        println("✅ IntelliJ plugin built successfully")
    }
}

tasks.register("runIntellijPlugin") {
    group = "intellij"
    description = "Build and run IntelliJ plugin in sandbox (publishes SDK first)"
    doLast {
        // 1. Publish SDK to Maven Local (plugin can't use local module)
        println("📦 Publishing SDK to Maven Local...")
        exec {
            workingDir = projectDir
            commandLine("./gradlew", ":sdk:runanywhere-kotlin:publishToMavenLocal")
        }

        // 2. Build and run plugin
        println("💡 Building and running IntelliJ plugin...")
        exec {
            workingDir = file("examples/intellij-plugin-demo/plugin")
            commandLine("./gradlew", "runIde")
        }
        println("✅ IntelliJ plugin launched successfully")
    }
}

// ============================================================================
// SDK PUBLISHING (for distribution only, not needed for development)
// ============================================================================

tasks.register("publishSdkToMavenLocal") {
    group = "publishing"
    description = "Publish SDK to Maven Local (for external projects, not needed for examples)"
    dependsOn(":sdk:runanywhere-kotlin:publishToMavenLocal")
    doLast {
        println("✅ SDK published to Maven Local (~/.m2/repository)")
        println("   Group: com.runanywhere.sdk")
        println("   Artifact: RunAnywhereKotlinSDK")
        println("   Version: 0.1.0")
        println("")
        println("📝 Note: This is automatically done for IntelliJ plugin tasks.")
        println("   Android app uses SDK as local module and doesn't need this.")
    }
}

// ============================================================================
// CLEAN TASK
// ============================================================================

tasks.register("cleanAll") {
    group = "build"
    description = "Clean SDK and all sample apps"
    doLast {
        // Clean SDK
        println(" Cleaning SDK...")
        delete(layout.buildDirectory)
        project(":sdk:runanywhere-kotlin").layout.buildDirectory.asFile.get().deleteRecursively()

        // Clean Android app
        println(" Cleaning Android app...")
        exec {
            workingDir = file("examples/android/RunAnywhereAI")
            commandLine("./gradlew", "clean")
        }

        // Clean IntelliJ plugin
        println(" Cleaning IntelliJ plugin...")
        exec {
            workingDir = file("examples/intellij-plugin-demo/plugin")
            commandLine("./gradlew", "clean")
        }

        println(" All projects cleaned successfully")
    }
}
