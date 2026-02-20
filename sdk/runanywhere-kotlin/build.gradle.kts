// Clean Gradle script for KMP SDK

plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.detekt)
    alias(libs.plugins.ktlint)
    id("maven-publish")
    signing
}

// Detekt
detekt {
    buildUponDefaultConfig = true
    allRules = false
    config.setFrom(files("detekt.yml"))
    source.setFrom(
        "src/commonMain/kotlin",
        "src/jvmMain/kotlin",
        "src/jvmAndroidMain/kotlin",
        "src/androidMain/kotlin",
    )
}

// ktlint
ktlint {
    version.set("1.5.0")
    android.set(true)
    verbose.set(true)
    outputToConsole.set(true)
    enableExperimentalRules.set(false)
    filter {
        exclude("**/generated/**")
        include("**/kotlin/**")
    }
}

// Maven Central group ID
// TODO: Change to "com.runanywhere" once DNS verification completes
val isJitPack = System.getenv("JITPACK") == "true"
val usePendingNamespace = System.getenv("USE_RUNANYWHERE_NAMESPACE")?.toBoolean() ?: false
group =
    when {
        isJitPack -> "com.github.RunanywhereAI.runanywhere-sdks"
        usePendingNamespace -> "com.runanywhere" // Use after DNS verification completes
        else -> "io.github.sanchitmonga22" // Currently verified namespace
    }

// Version: SDK_VERSION (CI) → VERSION (JitPack) → fallback
val resolvedVersion =
    System.getenv("SDK_VERSION")?.removePrefix("v")
        ?: System.getenv("VERSION")?.removePrefix("v")
        ?: "0.1.5-SNAPSHOT"
version = resolvedVersion

logger.lifecycle("RunAnywhere SDK version: $resolvedVersion (JitPack=$isJitPack)")

// JNI library mode:
//   testLocal=true  → locally built libs from src/androidMain/jniLibs/ (run ./scripts/build-kotlin.sh --setup)
//   testLocal=false → download pre-built libs from GitHub releases
// rootProject checked first to support composite builds (app's gradle.properties takes precedence)
val testLocal: Boolean =
    rootProject.findProperty("runanywhere.testLocal")?.toString()?.toBoolean()
        ?: project.findProperty("runanywhere.testLocal")?.toString()?.toBoolean()
        ?: false

// rebuildCommons=true → force rebuild of runanywhere-commons C++ code
val rebuildCommons: Boolean =
    rootProject.findProperty("runanywhere.rebuildCommons")?.toString()?.toBoolean()
        ?: project.findProperty("runanywhere.rebuildCommons")?.toString()?.toBoolean()
        ?: false

// Native lib version for GitHub release downloads (when testLocal=false)
val nativeLibVersion: String =
    rootProject.findProperty("runanywhere.nativeLibVersion")?.toString()
        ?: project.findProperty("runanywhere.nativeLibVersion")?.toString()
        ?: resolvedVersion // Default to SDK version

logger.lifecycle("RunAnywhere SDK: testLocal=$testLocal, nativeLibVersion=$nativeLibVersion")

kotlin {
    // Use Java 17 toolchain across targets
    jvmToolchain(17)

    // JVM target for IntelliJ plugins and general JVM usage
    jvm {
        compilations.all {
            compilerOptions.configure {
                freeCompilerArgs.add("-Xsuppress-version-warnings")
            }
        }
        testRuns["test"].executionTask.configure {
            useJUnitPlatform()
        }
    }

    // Android target
    androidTarget {
        // Enable publishing Android AAR to Maven
        publishLibraryVariants("release")

        // Set correct artifact ID for Android publication
        mavenPublication {
            artifactId = "runanywhere-sdk-android"
        }

        compilations.all {
            compilerOptions.configure {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                freeCompilerArgs.add("-Xsuppress-version-warnings")
                freeCompilerArgs.add("-Xno-param-assertions")
            }
        }
    }

    // Native targets (temporarily disabled)
    // linuxX64()
    // macosX64()
    // macosArm64()
    // mingwX64()

    sourceSets {
        // Common source set
        commonMain {
            dependencies {
                implementation(libs.kotlinx.coroutines.core)
                implementation(libs.kotlinx.serialization.json)
                implementation(libs.kotlinx.datetime)

                // Ktor for networking
                implementation(libs.ktor.client.core)
                implementation(libs.ktor.client.content.negotiation)
                implementation(libs.ktor.client.logging)
                implementation(libs.ktor.serialization.kotlinx.json)

                // Okio for file system operations (replaces Files library from iOS)
                implementation(libs.okio)
            }
        }

        commonTest {
            dependencies {
                implementation(kotlin("test"))
                implementation(libs.kotlinx.coroutines.test)
                // Okio FakeFileSystem for testing
                implementation(libs.okio.fakefilesystem)
            }
        }

        // JVM + Android shared
        val jvmAndroidMain by creating {
            dependsOn(commonMain.get())
            dependencies {
                implementation(libs.whisper.jni)
                implementation(libs.okhttp)
                implementation(libs.okhttp.logging)
                implementation(libs.gson)
                implementation(libs.commons.io)
                implementation(libs.commons.compress)
                implementation(libs.ktor.client.okhttp)
                // Error tracking - Sentry (matches iOS SDK SentryDestination)
                implementation(libs.sentry)
                // org.json - available on Android via SDK, needed explicitly for JVM
                implementation("org.json:json:20240303")
            }
        }

        jvmMain {
            dependsOn(jvmAndroidMain)
        }

        jvmTest {
            dependencies {
                implementation(libs.junit)
                implementation(libs.mockk)
            }
        }

        androidMain {
            dependsOn(jvmAndroidMain)
            dependencies {
                // Native libs (.so files) are included directly in jniLibs/
                // Built from runanywhere-commons/scripts/build-android.sh

                implementation(libs.androidx.core.ktx)
                implementation(libs.kotlinx.coroutines.android)
                implementation(libs.android.vad.webrtc)
                implementation(libs.prdownloader)
                implementation(libs.androidx.work.runtime.ktx)
                implementation(libs.androidx.security.crypto)
                implementation(libs.retrofit)
                implementation(libs.retrofit.gson)
            }
        }

        androidUnitTest {
            dependencies {
                implementation(libs.junit)
                implementation(libs.mockk)
            }
        }
    }
}

android {
    namespace = "com.runanywhere.sdk.kotlin"
    compileSdk = 35

    defaultConfig {
        minSdk = 24
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        consumerProguardFiles("consumer-rules.pro")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // This SDK bundles commons JNI libs (librac_commons, librunanywhere_jni, libc++_shared, libomp).
    // Backend-specific libs are in their own modules (runanywhere-core-llamacpp, runanywhere-core-onnx).
}

// Build JNI libs locally (testLocal=true). Skips if libs exist unless rebuildCommons=true.
tasks.register<Exec>("buildLocalJniLibs") {
    group = "runanywhere"
    description = "Build JNI libraries locally from runanywhere-commons (when testLocal=true)"

    val jniLibsDir = file("src/androidMain/jniLibs")
    val llamaCppJniLibsDir = file("modules/runanywhere-core-llamacpp/src/androidMain/jniLibs")
    val onnxJniLibsDir = file("modules/runanywhere-core-onnx/src/androidMain/jniLibs")
    val buildMarker = file(".commons-build-marker")
    val buildKotlinScript = file("scripts/build-kotlin.sh")
    val buildLocalScript = file("scripts/build-local.sh")

    // Only enable this task when testLocal=true
    onlyIf { testLocal }

    workingDir = projectDir

    // Set environment
    environment(
        "ANDROID_NDK_HOME",
        System.getenv("ANDROID_NDK_HOME") ?: "${System.getProperty("user.home")}/Library/Android/sdk/ndk/27.0.12077973",
    )

    doFirst {
        logger.lifecycle("")
        logger.lifecycle("═══════════════════════════════════════════════════════════════")
        logger.lifecycle(" RunAnywhere JNI Libraries (testLocal=true)")
        logger.lifecycle("═══════════════════════════════════════════════════════════════")
        logger.lifecycle("")

        // Check if we have existing libs
        val hasMainLibs = jniLibsDir.resolve("arm64-v8a/libc++_shared.so").exists()
        val hasLlamaCppLibs = llamaCppJniLibsDir.resolve("arm64-v8a/librac_backend_llamacpp_jni.so").exists()
        val hasOnnxLibs = onnxJniLibsDir.resolve("arm64-v8a/librac_backend_onnx_jni.so").exists()
        val allLibsExist = hasMainLibs && hasLlamaCppLibs && hasOnnxLibs

        if (allLibsExist && !rebuildCommons) {
            logger.lifecycle("✅ JNI libraries already exist - skipping build")
            logger.lifecycle("   (use -Prunanywhere.rebuildCommons=true to force rebuild)")
            logger.lifecycle("")
            // Skip the exec by setting a dummy command
            commandLine("echo", "JNI libs up to date")
        } else if (!allLibsExist) {
            // First time setup - use build-kotlin.sh --setup
            logger.lifecycle("🆕 First-time setup: Running build-kotlin.sh --setup")
            logger.lifecycle("   This will download dependencies and build everything...")
            logger.lifecycle("")
            commandLine("bash", buildKotlinScript.absolutePath, "--setup", "--skip-build")
        } else if (rebuildCommons) {
            // Force rebuild - use build-kotlin.sh with --rebuild-commons
            logger.lifecycle("🔄 Rebuild requested: Running build-kotlin.sh --rebuild-commons")
            logger.lifecycle("")
            commandLine("bash", buildKotlinScript.absolutePath, "--local", "--rebuild-commons", "--skip-build")
        }
    }

    doLast {
        // Verify the build succeeded for all modules
        fun countLibs(dir: java.io.File, moduleName: String): Int {
            if (!dir.exists()) return 0
            val soFiles = dir.walkTopDown().filter { it.extension == "so" }.toList()
            if (soFiles.isNotEmpty()) {
                logger.lifecycle("")
                logger.lifecycle("✓ $moduleName: ${soFiles.size} .so files")
                soFiles.groupBy { it.parentFile.name }.forEach { (abi, files) ->
                    logger.lifecycle("  $abi: ${files.map { it.name }.joinToString(", ")}")
                }
            }
            return soFiles.size
        }

        val mainCount = countLibs(jniLibsDir, "Main SDK (Commons)")
        val llamaCppCount = countLibs(llamaCppJniLibsDir, "LlamaCPP Module")
        val onnxCount = countLibs(onnxJniLibsDir, "ONNX Module")

        if (mainCount == 0 && testLocal) {
            throw GradleException(
                """
                Local JNI build failed: No .so files found in $jniLibsDir

                Run first-time setup:
                  ./scripts/build-kotlin.sh --setup

                Or download from releases:
                  ./gradlew -Prunanywhere.testLocal=false assembleDebug
                """.trimIndent(),
            )
        }

        if (mainCount > 0) {
            logger.lifecycle("")
            logger.lifecycle("═══════════════════════════════════════════════════════════════")
            logger.lifecycle(" Total: ${mainCount + llamaCppCount + onnxCount} native libraries")
            logger.lifecycle("═══════════════════════════════════════════════════════════════")
        }
    }
}

// First-time setup: download dependencies, build commons, copy JNI libs
tasks.register<Exec>("setupLocalDevelopment") {
    group = "runanywhere"
    description = "First-time setup: download dependencies, build commons, copy JNI libs"

    workingDir = projectDir
    commandLine("bash", "scripts/build-kotlin.sh", "--setup", "--skip-build")

    environment(
        "ANDROID_NDK_HOME",
        System.getenv("ANDROID_NDK_HOME") ?: "${System.getProperty("user.home")}/Library/Android/sdk/ndk/27.0.12077973",
    )

    doFirst {
        logger.lifecycle("")
        logger.lifecycle("═══════════════════════════════════════════════════════════════")
        logger.lifecycle(" RunAnywhere SDK - First-Time Local Development Setup")
        logger.lifecycle("═══════════════════════════════════════════════════════════════")
        logger.lifecycle("")
        logger.lifecycle("This will:")
        logger.lifecycle("  1. Download dependencies (Sherpa-ONNX, etc.)")
        logger.lifecycle("  2. Build runanywhere-commons for Android")
        logger.lifecycle("  3. Copy JNI libraries to module directories")
        logger.lifecycle("  4. Set testLocal=true in gradle.properties")
        logger.lifecycle("")
        logger.lifecycle("This may take 10-15 minutes on first run...")
        logger.lifecycle("")
    }

    doLast {
        logger.lifecycle("")
        logger.lifecycle("✅ Setup complete! You can now build with:")
        logger.lifecycle("   ./gradlew assembleDebug")
        logger.lifecycle("")
    }
}

// Rebuild C++ code after changes to runanywhere-commons
tasks.register<Exec>("rebuildCommons") {
    group = "runanywhere"
    description = "Rebuild runanywhere-commons C++ code (use after making C++ changes)"

    workingDir = projectDir
    commandLine("bash", "scripts/build-kotlin.sh", "--local", "--rebuild-commons", "--skip-build")

    environment(
        "ANDROID_NDK_HOME",
        System.getenv("ANDROID_NDK_HOME") ?: "${System.getProperty("user.home")}/Library/Android/sdk/ndk/27.0.12077973",
    )

    doFirst {
        logger.lifecycle("")
        logger.lifecycle("═══════════════════════════════════════════════════════════════")
        logger.lifecycle(" Rebuilding runanywhere-commons C++ code")
        logger.lifecycle("═══════════════════════════════════════════════════════════════")
        logger.lifecycle("")
    }
}

// Download commons JNI libs from GitHub releases (testLocal=false).
// Backend libs are downloaded by their own modules.
tasks.register("downloadJniLibs") {
    group = "runanywhere"
    description = "Download commons JNI libraries from GitHub releases (when testLocal=false)"

    // Only run when NOT using local libs
    onlyIf { !testLocal }

    val outputDir = file("src/androidMain/jniLibs")
    val nativeLibVersionMarker = file("$outputDir/.native_lib_version")
    val tempDir = file("${layout.buildDirectory.get()}/jni-temp")

    val releaseBaseUrl = "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v$nativeLibVersion"

    val targetAbis = listOf("arm64-v8a", "armeabi-v7a", "x86_64")

    // Only download commons package — backend packages are handled by submodules
    val packageType = "RACommons-android"

    // Whitelist: only keep commons-owned .so files (the RACommons zip is a "fat" zip)
    val commonsLibs = setOf(
        "librac_commons.so",
        "librunanywhere_jni.so",
        "libc++_shared.so",
        "libomp.so",
    )

    outputs.dir(outputDir)

    doLast {
        if (testLocal) {
            logger.lifecycle("Skipping JNI download: testLocal=true (using local libs)")
            return@doLast
        }

        // Check if libs already exist (CI pre-populates build/jniLibs/).
        // Guard against stale libs from a different native version.
        val existingLibs = outputDir.walkTopDown().filter { it.extension == "so" }.count()
        val existingVersion = nativeLibVersionMarker.takeIf { it.exists() }?.readText()?.trim()
        if (existingLibs > 0 && existingVersion == nativeLibVersion) {
            logger.lifecycle(
                "Skipping JNI download: $existingLibs .so files already in $outputDir " +
                    "(native version v$nativeLibVersion)",
            )
            return@doLast
        }
        if (existingLibs > 0 && existingVersion != nativeLibVersion) {
            logger.lifecycle(
                "Refreshing JNI libs: found $existingLibs existing .so files " +
                    "with version '${existingVersion ?: "unknown"}', expected '$nativeLibVersion'",
            )
        }

        // Clean output directories for a fresh download
        outputDir.deleteRecursively()
        tempDir.deleteRecursively()
        outputDir.mkdirs()
        tempDir.mkdirs()

        logger.lifecycle("")
        logger.lifecycle("═══════════════════════════════════════════════════════════════")
        logger.lifecycle(" Downloading commons JNI libraries (testLocal=false)")
        logger.lifecycle("═══════════════════════════════════════════════════════════════")
        logger.lifecycle("")
        logger.lifecycle("Native lib version: v$nativeLibVersion")
        logger.lifecycle("Target ABIs: ${targetAbis.joinToString(", ")}")
        logger.lifecycle("")

        var totalDownloaded = 0

        targetAbis.forEach { abi ->
            val abiOutputDir = file("$outputDir/$abi")
            abiOutputDir.mkdirs()

            val packageName = "$packageType-$abi-v$nativeLibVersion.zip"
            val zipUrl = "$releaseBaseUrl/$packageName"
            val tempZip = file("$tempDir/$packageName")

            logger.lifecycle("▶ Downloading: $packageName")

            try {
                ant.withGroovyBuilder {
                    "get"("src" to zipUrl, "dest" to tempZip, "verbose" to false)
                }

                val extractDir = file("$tempDir/extracted-${packageName.replace(".zip", "")}")
                extractDir.mkdirs()
                ant.withGroovyBuilder {
                    "unzip"("src" to tempZip, "dest" to extractDir)
                }

                // Only copy commons-owned .so files (whitelist filter)
                extractDir
                    .walkTopDown()
                    .filter { it.extension == "so" && it.name in commonsLibs }
                    .forEach { soFile ->
                        val targetFile = file("$abiOutputDir/${soFile.name}")
                        soFile.copyTo(targetFile, overwrite = true)
                        logger.lifecycle("  ✓ ${soFile.name}")
                        totalDownloaded++
                    }

                tempZip.delete()
            } catch (e: Exception) {
                logger.warn("  ⚠ Failed to download $packageName: ${e.message}")
            }

            logger.lifecycle("")
        }

        tempDir.deleteRecursively()

        val totalLibs = outputDir.walkTopDown().filter { it.extension == "so" }.count()
        val abiDirs = outputDir.listFiles()?.filter { it.isDirectory }?.map { it.name } ?: emptyList()

        logger.lifecycle("═══════════════════════════════════════════════════════════════")
        logger.lifecycle("✓ Commons JNI libraries ready: $totalLibs .so files")
        logger.lifecycle("  ABIs: ${abiDirs.joinToString(", ")}")
        logger.lifecycle("  Output: $outputDir")
        logger.lifecycle("═══════════════════════════════════════════════════════════════")

        // Record native lib version to avoid reusing stale JNI binaries.
        nativeLibVersionMarker.parentFile.mkdirs()
        nativeLibVersionMarker.writeText(nativeLibVersion)

        // List libraries per ABI
        abiDirs.forEach { abi ->
            val libs = file("$outputDir/$abi").listFiles()?.filter { it.extension == "so" }?.map { it.name } ?: emptyList()
            logger.lifecycle("$abi (${libs.size} libs):")
            libs.sorted().forEach { lib ->
                val size = file("$outputDir/$abi/$lib").length() / 1024
                logger.lifecycle("  - $lib (${size}KB)")
            }
        }
    }
}

// Ensure JNI libs are available before Android build
tasks.matching { it.name.contains("merge") && it.name.contains("JniLibFolders") }.configureEach {
    if (testLocal) {
        dependsOn("buildLocalJniLibs")
    } else {
        dependsOn("downloadJniLibs")
    }
}

// Also ensure preBuild triggers JNI lib preparation
tasks.matching { it.name == "preBuild" }.configureEach {
    if (testLocal) {
        dependsOn("buildLocalJniLibs")
    } else {
        dependsOn("downloadJniLibs")
    }
}

// Bundle third-party licenses in JVM JAR
tasks.named<Jar>("jvmJar") {
    from(rootProject.file("THIRD_PARTY_LICENSES.md")) {
        into("META-INF")
    }
}

// Maven Central publishing
// Usage: implementation("com.runanywhere:runanywhere-sdk:1.0.0")
val mavenCentralUsername: String? =
    System.getenv("MAVEN_CENTRAL_USERNAME")
        ?: project.findProperty("mavenCentral.username") as String?
val mavenCentralPassword: String? =
    System.getenv("MAVEN_CENTRAL_PASSWORD")
        ?: project.findProperty("mavenCentral.password") as String?

// GPG signing
val signingKeyId: String? =
    System.getenv("GPG_KEY_ID")
        ?: project.findProperty("signing.keyId") as String?
val signingPassword: String? =
    System.getenv("GPG_SIGNING_PASSWORD")
        ?: project.findProperty("signing.password") as String?
val signingKey: String? =
    System.getenv("GPG_SIGNING_KEY")
        ?: project.findProperty("signing.key") as String?

publishing {
    publications.withType<MavenPublication> {
        // Artifact naming for Maven Central
        // Main artifact: com.runanywhere:runanywhere-sdk:1.0.0
        artifactId =
            when (name) {
                "kotlinMultiplatform" -> "runanywhere-sdk"
                "androidRelease" -> "runanywhere-sdk-android"
                "jvm" -> "runanywhere-sdk-jvm"
                else -> "runanywhere-sdk-$name"
            }

        // POM metadata (required by Maven Central)
        pom {
            name.set("RunAnywhere SDK")
            description.set("Privacy-first, on-device AI SDK for Kotlin/JVM and Android. Includes core infrastructure and common native libraries.")
            url.set("https://runanywhere.ai")
            inceptionYear.set("2024")

            licenses {
                license {
                    name.set("The Apache License, Version 2.0")
                    url.set("https://www.apache.org/licenses/LICENSE-2.0.txt")
                    distribution.set("repo")
                }
            }

            developers {
                developer {
                    id.set("runanywhere")
                    name.set("RunAnywhere Team")
                    email.set("founders@runanywhere.ai")
                    organization.set("RunAnywhere AI")
                    organizationUrl.set("https://runanywhere.ai")
                }
            }

            scm {
                connection.set("scm:git:git://github.com/RunanywhereAI/runanywhere-sdks.git")
                developerConnection.set("scm:git:ssh://github.com/RunanywhereAI/runanywhere-sdks.git")
                url.set("https://github.com/RunanywhereAI/runanywhere-sdks")
            }

            issueManagement {
                system.set("GitHub Issues")
                url.set("https://github.com/RunanywhereAI/runanywhere-sdks/issues")
            }
        }
    }

    repositories {
        // Maven Central (Sonatype Central Portal - new API)
        maven {
            name = "MavenCentral"
            url = uri("https://ossrh-staging-api.central.sonatype.com/service/local/staging/deploy/maven2/")
            credentials {
                username = mavenCentralUsername
                password = mavenCentralPassword
            }
        }

        // Sonatype Snapshots (Central Portal)
        maven {
            name = "SonatypeSnapshots"
            url = uri("https://central.sonatype.com/repository/maven-snapshots/")
            credentials {
                username = mavenCentralUsername
                password = mavenCentralPassword
            }
        }

        // GitHub Packages (backup/alternative)
        maven {
            name = "GitHubPackages"
            url = uri("https://maven.pkg.github.com/RunanywhereAI/runanywhere-sdks")
            credentials {
                username = project.findProperty("gpr.user") as String? ?: System.getenv("GITHUB_ACTOR")
                password = project.findProperty("gpr.token") as String? ?: System.getenv("GITHUB_TOKEN")
            }
        }
    }
}

signing {
    if (signingKey != null && signingKey.contains("BEGIN PGP")) {
        useInMemoryPgpKeys(signingKeyId, signingKey, signingPassword)
    } else {
        useGpgCmd()
    }
    sign(publishing.publications)
}

// Only sign when publishing (not for local builds)
tasks.withType<Sign>().configureEach {
    onlyIf {
        gradle.taskGraph.hasTask(":publishAllPublicationsToMavenCentralRepository") ||
            gradle.taskGraph.hasTask(":publish") ||
            project.hasProperty("signing.gnupg.keyName") ||
            signingKey != null
    }
}

// Only publish Android release and metadata (skip JVM and debug)
tasks.withType<PublishToMavenRepository>().configureEach {
    onlyIf {
        val dominated = publication.name in listOf("jvm", "androidDebug")
        !dominated
    }
}
