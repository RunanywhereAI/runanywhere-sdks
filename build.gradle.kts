// Root build script for RunAnywhere monorepo
//
// Available tasks:
//   ./gradlew setup              - Check environment and create local.properties
//
//   Native (C++):
//   ./gradlew buildCpp           - Build C++ and copy .so to jniLibs
//   ./gradlew buildFullSdk       - Full pipeline: C++ + copy + Kotlin SDK
//   ./gradlew copyNativeLibs     - Copy .so from dist/ to jniLibs/ (no rebuild)
//
//   Kotlin SDK:
//   ./gradlew buildSdk           - Build SDK (debug AAR + JVM JAR)
//   ./gradlew buildSdkRelease    - Build SDK (release AAR)
//   ./gradlew publishSdkToMavenLocal - Publish SDK to ~/.m2
//
//   Android App:
//   ./gradlew buildAndroidApp    - Build Android example app
//   ./gradlew runAndroidApp      - Build, install, and launch Android app
//
//   IntelliJ Plugin:
//   ./gradlew buildIntellijPlugin - Build IntelliJ plugin
//   ./gradlew runIntellijPlugin  - Run IntelliJ plugin in sandbox
//
//   Utility:
//   ./gradlew buildAll           - Build everything
//   ./gradlew cleanAll           - Clean everything

plugins {
    alias(libs.plugins.kotlin.multiplatform) apply false
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.kotlin.serialization) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.detekt) apply false
    alias(libs.plugins.ktlint) apply false
}

allprojects {
    group = "com.runanywhere"
    version = "0.1.0"
}

subprojects {
    tasks.withType<Test> {
        useJUnitPlatform()
        testLogging {
            events("passed", "skipped", "failed")
        }
    }
}

// Shared helpers

fun resolveAndroidHome(): String =
    System.getenv("ANDROID_HOME")
        ?: System.getenv("ANDROID_SDK_ROOT")
        ?: "${System.getProperty("user.home")}/Android/Sdk"

fun resolveNdkHome(androidHome: String): String =
    System.getenv("ANDROID_NDK_HOME")
        ?: "$androidHome/ndk/27.0.12077973"

fun ensureLocalProperties(dir: java.io.File, includeNdk: Boolean = false) {
    val localProps = dir.resolve("local.properties")
    if (!localProps.exists() && dir.exists()) {
        val androidHome = resolveAndroidHome()
        val content = buildString {
            appendLine("sdk.dir=$androidHome")
            if (includeNdk) appendLine("ndk.dir=${resolveNdkHome(androidHome)}")
        }
        localProps.writeText(content)
        println("  Created: ${localProps.relativeTo(rootDir)}")
    }
}

// Setup — single command to check environment, create local.properties, and setup native deps

tasks.register("setup") {
    group = "setup"
    description = "Check environment, create local.properties, and setup native dependencies if testLocal=true"

    doLast {
        println("RunAnywhere Development Setup")
        println()

        // Check environment
        val androidHome = resolveAndroidHome()
        val ndkHome = resolveNdkHome(androidHome)

        val sdkExists = file(androidHome).exists()
        val ndkExists = file(ndkHome).exists()

        println("Environment:")
        println("  Android SDK: ${if (sdkExists) "[OK] $androidHome" else "[WARN] Not found at $androidHome"}")
        println("  Android NDK: ${if (ndkExists) "[OK] $ndkHome" else "[WARN] Not found at $ndkHome"}")
        println()

        // Create local.properties where needed
        println("local.properties:")
        ensureLocalProperties(projectDir, includeNdk = true)
        ensureLocalProperties(file("sdk/runanywhere-kotlin"), includeNdk = true)
        ensureLocalProperties(file("examples/android/RunAnywhereAI"))

        val locations = mapOf(
            "Root" to projectDir,
            "SDK" to file("sdk/runanywhere-kotlin"),
            "Android App" to file("examples/android/RunAnywhereAI"),
        )
        locations.forEach { (name, dir) ->
            val props = dir.resolve("local.properties")
            println("  $name: ${if (props.exists()) "[OK]" else "[MISSING]"} ${props.relativeTo(rootDir)}")
        }
        println()

        // Check build mode and run native setup if needed
        val testLocal = projectDir.resolve("gradle.properties").let { f ->
            f.exists() && f.readText().contains("runanywhere.testLocal=true")
        }
        println("Build mode: testLocal=$testLocal")

        if (testLocal) {
            println()
            println("testLocal=true: Running native dependency setup...")
            val buildScript = file("sdk/runanywhere-kotlin/scripts/build-kotlin.sh")
            if (buildScript.exists()) {
                exec {
                    workingDir = file("sdk/runanywhere-kotlin")
                    environment("ANDROID_NDK_HOME", ndkHome)
                    commandLine("bash", buildScript.absolutePath, "--setup", "--skip-build")
                }
                println("Native setup complete")
            } else {
                println("[WARN] build-kotlin.sh not found at ${buildScript.relativeTo(rootDir)}")
            }
        } else {
            println("testLocal=false: Native libs will be downloaded from GitHub releases during build")
        }
    }
}

// =============================================================================
// Native (C++) tasks — wraps build-sdk.sh for IDE integration
// =============================================================================

tasks.register("buildCpp") {
    group = "native"
    description = "Build C++ (runanywhere-commons) and copy .so to jniLibs"

    doLast {
        val ndkHome = resolveNdkHome(resolveAndroidHome())
        exec {
            workingDir = file("sdk/runanywhere-kotlin")
            environment("ANDROID_NDK_HOME", ndkHome)
            commandLine("bash", "scripts/build-sdk.sh", "--cpp-only")
        }
    }
}

tasks.register("buildFullSdk") {
    group = "native"
    description = "Full pipeline: build C++ + copy .so + build Kotlin SDK"

    doLast {
        val ndkHome = resolveNdkHome(resolveAndroidHome())
        exec {
            workingDir = file("sdk/runanywhere-kotlin")
            environment("ANDROID_NDK_HOME", ndkHome)
            commandLine("bash", "scripts/build-sdk.sh")
        }
    }
}

tasks.register("copyNativeLibs") {
    group = "native"
    description = "Copy .so from dist/ to jniLibs/ (no C++ rebuild)"

    doLast {
        val ndkHome = resolveNdkHome(resolveAndroidHome())
        exec {
            workingDir = file("sdk/runanywhere-kotlin")
            environment("ANDROID_NDK_HOME", ndkHome)
            commandLine("bash", "scripts/build-kotlin.sh", "--local", "--skip-build")
        }
    }
}

// =============================================================================
// SDK tasks
// =============================================================================

tasks.register("buildSdk") {
    group = "sdk"
    description = "Build SDK debug (AAR + JVM JAR)"
    dependsOn(":runanywhere-kotlin:assembleDebug", ":runanywhere-kotlin:jvmJar")

    doLast {
        println("SDK debug build complete")
        println("  AAR: sdk/runanywhere-kotlin/build/outputs/aar/")
        println("  JAR: sdk/runanywhere-kotlin/build/libs/")
    }
}

tasks.register("buildSdkRelease") {
    group = "sdk"
    description = "Build SDK release AAR"
    dependsOn(":runanywhere-kotlin:assembleRelease")

    doLast {
        println("SDK release build complete")
    }
}

tasks.register("publishSdkToMavenLocal") {
    group = "sdk"
    description = "Publish SDK to Maven Local (~/.m2/repository)"
    dependsOn(":runanywhere-kotlin:publishToMavenLocal")

    doLast {
        println("SDK published to Maven Local")
        println("  Group: ${project.group}")
        println("  Version: ${project.version}")
    }
}

// Android example app tasks

tasks.register("buildAndroidApp") {
    group = "android"
    description = "Build Android example app"

    doFirst {
        ensureLocalProperties(file("examples/android/RunAnywhereAI"))
    }

    doLast {
        exec {
            workingDir = file("examples/android/RunAnywhereAI")
            commandLine("./gradlew", "assembleDebug")
        }
        println("Android app built: examples/android/RunAnywhereAI/app/build/outputs/apk/")
    }
}

tasks.register("runAndroidApp") {
    group = "android"
    description = "Build, install, and launch Android app on device"
    dependsOn("buildAndroidApp")

    doLast {
        exec {
            workingDir = file("examples/android/RunAnywhereAI")
            commandLine("./gradlew", "installDebug")
        }
        exec {
            commandLine(
                "adb", "shell", "am", "start", "-n",
                "com.runanywhere.runanywhereai.debug/com.runanywhere.runanywhereai.MainActivity",
            )
        }
        println("Android app launched")
    }
}

// IntelliJ plugin tasks (SDK consumed via Maven Local)

tasks.register("buildIntellijPlugin") {
    group = "intellij"
    description = "Publish SDK + build IntelliJ plugin"

    doLast {
        exec {
            workingDir = projectDir
            commandLine("./gradlew", ":runanywhere-kotlin:publishToMavenLocal")
        }
        exec {
            workingDir = file("examples/intellij-plugin-demo/plugin")
            commandLine("./gradlew", "buildPlugin")
        }
        println("IntelliJ plugin built: examples/intellij-plugin-demo/plugin/build/distributions/")
    }
}

tasks.register("runIntellijPlugin") {
    group = "intellij"
    description = "Publish SDK + run IntelliJ plugin in sandbox"

    doLast {
        exec {
            workingDir = projectDir
            commandLine("./gradlew", ":runanywhere-kotlin:publishToMavenLocal")
        }
        exec {
            workingDir = file("examples/intellij-plugin-demo/plugin")
            commandLine("./gradlew", "runIde")
        }
    }
}

// Convenience tasks

tasks.register("buildAll") {
    group = "build"
    description = "Build SDK and all example apps"
    dependsOn("setup")

    doLast {
        // Build SDK
        exec {
            workingDir = projectDir
            commandLine("./gradlew", ":runanywhere-kotlin:assembleDebug")
        }

        // Build Android app
        exec {
            workingDir = file("examples/android/RunAnywhereAI")
            commandLine("./gradlew", "assembleDebug")
        }

        // Publish SDK to Maven Local + build IntelliJ plugin
        exec {
            workingDir = projectDir
            commandLine("./gradlew", ":runanywhere-kotlin:publishToMavenLocal")
        }
        exec {
            workingDir = file("examples/intellij-plugin-demo/plugin")
            commandLine("./gradlew", "buildPlugin")
        }

        println()
        println("Build complete:")
        println("  SDK AAR:          sdk/runanywhere-kotlin/build/outputs/aar/")
        println("  Maven Local:      ~/.m2/repository/com/runanywhere/runanywhere-sdk/")
        println("  Android APK:      examples/android/RunAnywhereAI/app/build/outputs/apk/")
        println("  IntelliJ Plugin:  examples/intellij-plugin-demo/plugin/build/distributions/")
    }
}

tasks.register("cleanAll") {
    group = "build"
    description = "Clean all projects"

    doLast {
        delete(layout.buildDirectory)
        file("sdk/runanywhere-kotlin/build").deleteRecursively()

        exec {
            workingDir = file("examples/android/RunAnywhereAI")
            commandLine("./gradlew", "clean")
        }
        exec {
            workingDir = file("examples/intellij-plugin-demo/plugin")
            commandLine("./gradlew", "clean")
        }
        println("All projects cleaned")
    }
}
