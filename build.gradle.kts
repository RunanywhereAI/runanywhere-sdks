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
        ?: "$androidHome/ndk/${project.findProperty("racNdkVersion") ?: "27.0.12077973"}"

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
            f.exists() && f.readText().contains("runanywhere.useLocalNatives=true")
        }
        println("Build mode: testLocal=$testLocal")

        if (testLocal) {
            println()
            println("testLocal=true: Running native dependency setup...")
            // sdk/runanywhere-kotlin/scripts/build-{kotlin,sdk}.sh were
            // removed by GAP 07 Phase 6; the canonical entry point is the
            // repo-root scripts/build-core-android.sh, which builds via CMake
            // presets and stages JNI libs into every consuming SDK
            // (runanywhere-kotlin, runanywhere-react-native, runanywhere-flutter).
            val buildScript = file("scripts/build-core-android.sh")
            if (!buildScript.exists()) {
                throw GradleException(
                    "runanywhere.useLocalNatives=true requires scripts/build-core-android.sh, " +
                        "but it is missing at ${buildScript.relativeTo(rootDir)}. " +
                        "Restore the script or switch to runanywhere.useLocalNatives=false.",
                )
            }
            exec {
                workingDir = projectDir
                environment("ANDROID_NDK_HOME", ndkHome)
                commandLine("bash", buildScript.absolutePath)
            }
            println("Native setup complete")
        } else {
            println("testLocal=false: Native libs will be downloaded from GitHub releases during build")
        }
    }
}

// =============================================================================
// Native (C++) tasks — wraps scripts/build-core-android.sh for IDE integration.
// build-core-android.sh runs the android-{arm64,armv7,x86_64} CMake presets
// and stages the resulting .so files into every consuming SDK's jniLibs tree
// (Kotlin, React Native, Flutter). It replaces the per-SDK build-sdk.sh /
// build-kotlin.sh shell scripts removed in GAP 07 Phase 6.
// =============================================================================

tasks.register("buildCpp") {
    group = "native"
    description = "Build C++ (runanywhere-commons) and stage .so into Kotlin/RN/Flutter jniLibs"

    doLast {
        val ndkHome = resolveNdkHome(resolveAndroidHome())
        exec {
            workingDir = projectDir
            environment("ANDROID_NDK_HOME", ndkHome)
            commandLine("bash", "scripts/build-core-android.sh")
        }
    }
}

tasks.register("buildFullSdk") {
    group = "native"
    description = "Full pipeline: build C++ + stage .so + build Kotlin SDK"
    dependsOn("buildCpp", ":runanywhere-kotlin:assembleDebug", ":runanywhere-kotlin:jvmJar")

    doLast {
        println("Full SDK build complete (C++ + Kotlin AAR + JVM JAR)")
    }
}

tasks.register("copyNativeLibs") {
    group = "native"
    description = "Re-stage .so into jniLibs/ (incremental: rebuilds via CMake only if sources changed)"

    doLast {
        val ndkHome = resolveNdkHome(resolveAndroidHome())
        // build-core-android.sh is incremental: CMake's --build is a no-op
        // when nothing changed, so the marginal cost over a pure copy is
        // small. There is no separate copy-only script after GAP 07 Phase 6.
        exec {
            workingDir = projectDir
            environment("ANDROID_NDK_HOME", ndkHome)
            commandLine("bash", "scripts/build-core-android.sh")
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

// Convenience tasks

tasks.register("buildAll") {
    group = "build"
    description = "Build SDK and all example apps"
    dependsOn("setup")

    doLast {
        exec {
            workingDir = projectDir
            commandLine("./gradlew", ":runanywhere-kotlin:assembleDebug")
        }

        exec {
            workingDir = file("examples/android/RunAnywhereAI")
            commandLine("./gradlew", "assembleDebug")
        }

        exec {
            workingDir = projectDir
            commandLine("./gradlew", ":runanywhere-kotlin:publishToMavenLocal")
        }

        println()
        println("Build complete:")
        println("  SDK AAR:          sdk/runanywhere-kotlin/build/outputs/aar/")
        println("  Maven Local:      ~/.m2/repository/com/runanywhere/runanywhere-sdk/")
        println("  Android APK:      examples/android/RunAnywhereAI/app/build/outputs/apk/")
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
        println("All projects cleaned")
    }
}
