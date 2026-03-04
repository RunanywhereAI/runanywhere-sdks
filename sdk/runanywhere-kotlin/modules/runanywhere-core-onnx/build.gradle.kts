/**
 * RunAnywhere Core ONNX Module
 *
 * This module provides the ONNX Runtime backend for STT, TTS, and VAD.
 * It is SELF-CONTAINED with its own native libraries.
 *
 * Architecture (mirrors iOS RABackendONNX.xcframework):
 *   iOS:     ONNXRuntime.swift -> RABackendONNX.xcframework + onnxruntime.xcframework
 *   Android: ONNX.kt -> librunanywhere_onnx.so + libonnxruntime.so + libsherpa-onnx-*.so
 *
 * Native Libraries Included (~25MB total):
 *   - librunanywhere_onnx.so - ONNX backend wrapper
 *   - libonnxruntime.so (~15MB) - ONNX Runtime
 *   - libsherpa-onnx-c-api.so - Sherpa-ONNX C API
 *   - libsherpa-onnx-cxx-api.so - Sherpa-ONNX C++ API
 *   - libsherpa-onnx-jni.so - Sherpa-ONNX JNI (STT/TTS/VAD)
 *
 * This module is OPTIONAL - only include it if your app needs STT/TTS/VAD capabilities.
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

val testLocal: Boolean =
    rootProject.findProperty("runanywhere.testLocal")?.toString()?.toBoolean()
        ?: project.findProperty("runanywhere.testLocal")?.toString()?.toBoolean()
        ?: false

logger.lifecycle("ONNX Module: testLocal=$testLocal")

// Detekt
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

kotlin {
    jvm {
        compilations.all {
            kotlinOptions.jvmTarget = "17"
        }
    }

    androidTarget {
        publishLibraryVariants("release")

        mavenPublication {
            artifactId = "runanywhere-onnx-android"
        }

        compilations.all {
            kotlinOptions.jvmTarget = "17"
        }
    }

    sourceSets {
        val commonMain by getting {
            dependencies {
                // Core SDK — resolve by finding the project whose dir matches the SDK root
                api(
                    rootProject.allprojects.firstOrNull {
                        it.projectDir.canonicalPath == projectDir.resolve("../..").canonicalPath
                    } ?: error("Cannot find core SDK project at ${projectDir.resolve("../..")}"),
                )
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

        val jvmAndroidMain by creating {
            dependsOn(commonMain)
            dependencies {
                implementation("org.apache.commons:commons-compress:1.26.0")
            }
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

android {
    namespace = "com.runanywhere.sdk.core.onnx"
    compileSdk = 36

    defaultConfig {
        minSdk = 24
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        ndk {
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

    // Native libs: librac_backend_onnx.so, librac_backend_onnx_jni.so,
    // libonnxruntime.so, libsherpa-onnx-c-api.so, libsherpa-onnx-cxx-api.so, libsherpa-onnx-jni.so
    // Downloaded from RABackendONNX-android GitHub release assets, or built locally.
}

// Native lib version for downloads
val nativeLibVersion: String =
    rootProject.findProperty("runanywhere.nativeLibVersion")?.toString()
        ?: project.findProperty("runanywhere.nativeLibVersion")?.toString()
        ?: (System.getenv("SDK_VERSION")?.removePrefix("v") ?: "0.1.5-SNAPSHOT")

// Download ONNX backend libs from GitHub releases (testLocal=false)
tasks.register("downloadJniLibs") {
    group = "runanywhere"
    description = "Download ONNX backend JNI libraries from GitHub releases"

    onlyIf { !testLocal }

    val outputDir = file("src/androidMain/jniLibs")
    val tempDir = file("${layout.buildDirectory.get()}/jni-temp")

    val releaseBaseUrl = "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v$nativeLibVersion"
    val targetAbis = listOf("arm64-v8a", "armeabi-v7a", "x86_64")
    val packageType = "RABackendONNX-android"

    val onnxLibs = setOf(
        "librac_backend_onnx.so",
        "librac_backend_onnx_jni.so",
        "libonnxruntime.so",
        "libsherpa-onnx-c-api.so",
        "libsherpa-onnx-cxx-api.so",
        "libsherpa-onnx-jni.so",
    )

    outputs.dir(outputDir)

    doLast {
        val existingLibs = outputDir.walkTopDown().filter { it.extension == "so" }.count()
        if (existingLibs > 0) {
            logger.lifecycle("ONNX: Skipping download, $existingLibs .so files already present")
            return@doLast
        }

        outputDir.deleteRecursively()
        tempDir.deleteRecursively()
        outputDir.mkdirs()
        tempDir.mkdirs()

        logger.lifecycle("ONNX Module: Downloading backend JNI libraries")

        var totalDownloaded = 0

        targetAbis.forEach { abi ->
            val abiOutputDir = file("$outputDir/$abi")
            abiOutputDir.mkdirs()

            val packageName = "$packageType-$abi-v$nativeLibVersion.zip"
            val zipUrl = "$releaseBaseUrl/$packageName"
            val tempZip = file("$tempDir/$packageName")

            logger.lifecycle("  Downloading: $packageName")

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
                    .filter { it.extension == "so" && it.name in onnxLibs }
                    .forEach { soFile ->
                        val targetFile = file("$abiOutputDir/${soFile.name}")
                        soFile.copyTo(targetFile, overwrite = true)
                        logger.lifecycle("    ${soFile.name}")
                        totalDownloaded++
                    }

                tempZip.delete()
            } catch (e: Exception) {
                logger.warn("  Failed to download $packageName: ${e.message}")
            }
        }

        tempDir.deleteRecursively()
        logger.lifecycle("ONNX: $totalDownloaded .so files downloaded")
    }
}

tasks.matching { it.name.contains("merge") && it.name.contains("JniLibFolders") }.configureEach {
    if (!testLocal) dependsOn("downloadJniLibs")
}
tasks.matching { it.name == "preBuild" }.configureEach {
    if (!testLocal) dependsOn("downloadJniLibs")
}

tasks.named<Jar>("jvmJar") {
    from(rootProject.file("THIRD_PARTY_LICENSES.md")) {
        into("META-INF")
    }
}

// Maven Central publishing
// Usage: implementation("com.runanywhere:runanywhere-onnx:1.0.0")

val isJitPack = System.getenv("JITPACK") == "true"
val usePendingNamespace = System.getenv("USE_RUNANYWHERE_NAMESPACE")?.toBoolean() ?: false
group =
    when {
        isJitPack -> "com.github.RunanywhereAI.runanywhere-sdks"
        usePendingNamespace -> "com.runanywhere"
        else -> "io.github.sanchitmonga22"
    }

version = System.getenv("SDK_VERSION")?.removePrefix("v")
    ?: System.getenv("VERSION")?.removePrefix("v")
    ?: "0.1.5-SNAPSHOT"

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
        artifactId =
            when (name) {
                "kotlinMultiplatform" -> "runanywhere-onnx"
                "androidRelease" -> "runanywhere-onnx-android"
                "jvm" -> "runanywhere-onnx-jvm"
                else -> "runanywhere-onnx-$name"
            }

        pom {
            name.set("RunAnywhere ONNX Backend")
            description.set("ONNX Runtime backend for RunAnywhere SDK - on-device STT, TTS, and VAD using Sherpa-ONNX.")
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
        maven {
            name = "MavenCentral"
            url = uri("https://ossrh-staging-api.central.sonatype.com/service/local/staging/deploy/maven2/")
            credentials {
                username = mavenCentralUsername
                password = mavenCentralPassword
            }
        }
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

tasks.withType<Sign>().configureEach {
    onlyIf {
        project.hasProperty("signing.gnupg.keyName") || signingKey != null
    }
}

// Only publish Android release and metadata (skip JVM and debug)
tasks.withType<PublishToMavenRepository>().configureEach {
    onlyIf { publication.name !in listOf("jvm", "androidDebug") }
}
