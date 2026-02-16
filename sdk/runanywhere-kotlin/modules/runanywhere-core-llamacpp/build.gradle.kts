/**
 * RunAnywhere Core LlamaCPP Module
 *
 * This module provides the LlamaCPP backend for LLM text generation.
 * It is SELF-CONTAINED with its own native libraries.
 *
 * Architecture (mirrors iOS RABackendLlamaCPP.xcframework):
 *   iOS:     LlamaCPPRuntime.swift -> RABackendLlamaCPP.xcframework
 *   Android: LlamaCPP.kt -> librunanywhere_llamacpp.so
 *
 * Native Libraries Included:
 *   - librunanywhere_llamacpp.so (~34MB) - LLM inference with llama.cpp
 *
 * This module is OPTIONAL - only include it if your app needs LLM capabilities.
 */

plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.detekt)
    alias(libs.plugins.ktlint)
    `maven-publish`
    signing
}

// =============================================================================
// Configuration
// =============================================================================
// Note: This module does NOT handle native libs - main SDK bundles everything
val testLocal: Boolean =
    rootProject.findProperty("runanywhere.testLocal")?.toString()?.toBoolean()
        ?: project.findProperty("runanywhere.testLocal")?.toString()?.toBoolean()
        ?: false

logger.lifecycle("LlamaCPP Module: testLocal=$testLocal (native libs handled by main SDK)")

// =============================================================================
// Detekt Configuration
// =============================================================================
detekt {
    buildUponDefaultConfig = true
    allRules = false
    config.setFrom(files("../../detekt.yml"))
    source.setFrom(
        "src/commonMain/kotlin",
        "src/jvmMain/kotlin",
        "src/jvmAndroidMain/kotlin",
        "src/androidMain/kotlin",
    )
}

// =============================================================================
// ktlint Configuration
// =============================================================================
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

// =============================================================================
// Kotlin Multiplatform Configuration
// =============================================================================

kotlin {
    jvm {
        compilations.all {
            kotlinOptions.jvmTarget = "17"
        }
    }

    androidTarget {
        // Enable publishing Android AAR to Maven
        publishLibraryVariants("release")

        // Set correct artifact ID for Android publication
        mavenPublication {
            artifactId = "runanywhere-llamacpp-android"
        }

        compilations.all {
            kotlinOptions.jvmTarget = "17"
        }
    }

    sourceSets {
        val commonMain by getting {
            dependencies {
                // Core SDK dependency for interfaces and models
                api(project.parent!!.parent!!)
                implementation(libs.kotlinx.coroutines.core)
                implementation(libs.kotlinx.serialization.json)
            }
        }

        val commonTest by getting {
            dependencies {
                implementation(kotlin("test"))
                implementation(libs.kotlinx.coroutines.test)
            }
        }

        // Shared JVM/Android code
        val jvmAndroidMain by creating {
            dependsOn(commonMain)
        }

        val jvmMain by getting {
            dependsOn(jvmAndroidMain)
        }

        val androidMain by getting {
            dependsOn(jvmAndroidMain)
        }

        val jvmTest by getting
        val androidUnitTest by getting
    }
}

// =============================================================================
// Android Configuration
// =============================================================================

android {
    namespace = "com.runanywhere.sdk.core.llamacpp"
    compileSdk = 36

    defaultConfig {
        minSdk = 24

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        ndk {
            // Support ARM64 devices and x86_64 emulators
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
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

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }

    // ==========================================================================
    // JNI Libraries - Self-Contained
    // ==========================================================================
    // This module bundles its own native libs:
    //   - librac_backend_llamacpp.so - LlamaCPP C++ backend (with VLM mtmd)
    //   - librac_backend_llamacpp_jni.so - LlamaCPP JNI bridge
    //
    // Downloaded from RABackendLLAMACPP-android GitHub release assets.
    // In local mode, build-kotlin.sh copies them to src/androidMain/jniLibs/.
    // ==========================================================================
}

// =============================================================================
// Native Library Version for Downloads (mirrors root SDK pattern)
// =============================================================================
val nativeLibVersion: String =
    rootProject.findProperty("runanywhere.nativeLibVersion")?.toString()
        ?: project.findProperty("runanywhere.nativeLibVersion")?.toString()
        ?: (System.getenv("SDK_VERSION")?.removePrefix("v") ?: "0.1.5-SNAPSHOT")

// =============================================================================
// JNI Library Download Task (for testLocal=false mode)
// =============================================================================
// Downloads LlamaCPP backend native libs from GitHub releases.
// Only libs owned by this module:
//   - librac_backend_llamacpp.so
//   - librac_backend_llamacpp_jni.so
// =============================================================================
tasks.register("downloadJniLibs") {
    group = "runanywhere"
    description = "Download LlamaCPP backend JNI libraries from GitHub releases"

    onlyIf { !testLocal }

    val outputDir = file("src/androidMain/jniLibs")
    val tempDir = file("${layout.buildDirectory.get()}/jni-temp")

    val releaseBaseUrl = "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v$nativeLibVersion"
    val targetAbis = listOf("arm64-v8a", "armeabi-v7a", "x86_64")
    val packageType = "RABackendLLAMACPP-android"

    // Whitelist: only keep LlamaCPP-owned .so files
    val llamacppLibs = setOf(
        "librac_backend_llamacpp.so",
        "librac_backend_llamacpp_jni.so",
    )

    outputs.dir(outputDir)

    doLast {
        val existingLibs = outputDir.walkTopDown().filter { it.extension == "so" }.count()
        if (existingLibs > 0) {
            logger.lifecycle("LlamaCPP: Skipping download, $existingLibs .so files already present")
            return@doLast
        }

        outputDir.deleteRecursively()
        tempDir.deleteRecursively()
        outputDir.mkdirs()
        tempDir.mkdirs()

        logger.lifecycle("")
        logger.lifecycle("═══════════════════════════════════════════════════════════════")
        logger.lifecycle(" LlamaCPP Module: Downloading backend JNI libraries")
        logger.lifecycle("═══════════════════════════════════════════════════════════════")

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

                extractDir
                    .walkTopDown()
                    .filter { it.extension == "so" && it.name in llamacppLibs }
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
        }

        tempDir.deleteRecursively()
        logger.lifecycle("✓ LlamaCPP: $totalDownloaded .so files downloaded")
    }
}

// Ensure JNI libs are available before Android build
tasks.matching { it.name.contains("merge") && it.name.contains("JniLibFolders") }.configureEach {
    if (!testLocal) dependsOn("downloadJniLibs")
}
tasks.matching { it.name == "preBuild" }.configureEach {
    if (!testLocal) dependsOn("downloadJniLibs")
}

// =============================================================================
// Include third-party licenses in JVM JAR
// =============================================================================

tasks.named<Jar>("jvmJar") {
    from(rootProject.file("THIRD_PARTY_LICENSES.md")) {
        into("META-INF")
    }
}

// =============================================================================
// Maven Central Publishing Configuration
// =============================================================================
// Consumer usage (after publishing):
//   implementation("com.runanywhere:runanywhere-llamacpp:1.0.0")
// =============================================================================

// Maven Central group ID - using verified namespace
val isJitPack = System.getenv("JITPACK") == "true"
val usePendingNamespace = System.getenv("USE_RUNANYWHERE_NAMESPACE")?.toBoolean() ?: false
group =
    when {
        isJitPack -> "com.github.RunanywhereAI.runanywhere-sdks"
        usePendingNamespace -> "com.runanywhere"
        else -> "io.github.sanchitmonga22" // Currently verified namespace
    }

// Version: SDK_VERSION (our CI), VERSION (JitPack), or fallback
version = System.getenv("SDK_VERSION")?.removePrefix("v")
    ?: System.getenv("VERSION")?.removePrefix("v")
    ?: "0.1.5-SNAPSHOT"

// Get publishing credentials
val mavenCentralUsername: String? =
    System.getenv("MAVEN_CENTRAL_USERNAME")
        ?: project.findProperty("mavenCentral.username") as String?
val mavenCentralPassword: String? =
    System.getenv("MAVEN_CENTRAL_PASSWORD")
        ?: project.findProperty("mavenCentral.password") as String?
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
        // Maven Central artifact naming
        artifactId =
            when (name) {
                "kotlinMultiplatform" -> "runanywhere-llamacpp"
                "androidRelease" -> "runanywhere-llamacpp-android"
                "jvm" -> "runanywhere-llamacpp-jvm"
                else -> "runanywhere-llamacpp-$name"
            }

        pom {
            name.set("RunAnywhere LlamaCPP Backend")
            description.set("LlamaCPP backend for RunAnywhere SDK - enables on-device LLM text generation using llama.cpp. Includes LlamaCPP-specific native libraries.")
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

        // GitHub Packages (backup)
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

// Configure signing
signing {
    if (signingKey != null && signingKey.contains("BEGIN PGP")) {
        useInMemoryPgpKeys(signingKeyId, signingKey, signingPassword)
    } else {
        useGpgCmd()
    }
    sign(publishing.publications)
}

// Only sign when needed
tasks.withType<Sign>().configureEach {
    onlyIf {
        project.hasProperty("signing.gnupg.keyName") || signingKey != null
    }
}

// Disable JVM and debug publications - only publish Android release and metadata
tasks.withType<PublishToMavenRepository>().configureEach {
    onlyIf { publication.name !in listOf("jvm", "androidDebug") }
}

