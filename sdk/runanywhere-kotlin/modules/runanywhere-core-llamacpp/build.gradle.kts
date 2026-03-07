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
    id("com.runanywhere.native-downloader")
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

logger.lifecycle("LlamaCPP Module: testLocal=$testLocal")

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
            artifactId = "runanywhere-llamacpp-android"
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
    namespace = "com.runanywhere.sdk.core.llamacpp"
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

    // Native libs: librac_backend_llamacpp.so, librac_backend_llamacpp_jni.so
    // Downloaded from RABackendLLAMACPP-android GitHub release assets, or built locally.
}

// Securely download native libraries from GitHub releases, with checksum verification and safe extraction
val nativeLibVersion: String =
    rootProject.findProperty("runanywhere.nativeLibVersion")?.toString()
        ?: project.findProperty("runanywhere.nativeLibVersion")?.toString()
        ?: (System.getenv("SDK_VERSION")?.removePrefix("v") ?: "0.1.5-SNAPSHOT")

val releaseBaseUrl = "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v$nativeLibVersion"
val targetAbis = listOf("arm64-v8a", "armeabi-v7a", "x86_64")
val packageType = "RABackendLLAMACPP-android"
val llamacppLibs = listOf("librac_backend_llamacpp.so", "librac_backend_llamacpp_jni.so")

// Create a secure download task for EACH architecture
val downloadTasks = targetAbis.map { abi ->
    val sanitizedAbiName = abi.replace("-", "_")
    
    tasks.register<com.runanywhere.buildlogic.DownloadAndVerifyNativeLibTask>("downloadJniLibs_$sanitizedAbiName") {
        val packageName = "$packageType-$abi-v$nativeLibVersion.zip"
        
        downloadUrl.set("$releaseBaseUrl/$packageName")
        expectedSha256Url.set("$releaseBaseUrl/$packageName.sha256")
        outputDir.set(file("src/androidMain/jniLibs/$abi"))
        allowedSoFiles.set(llamacppLibs)

        onlyIf { !testLocal }
    }
}

// Aggregate task to download all ABIs
tasks.register("downloadJniLibs") {
    group = "runanywhere"
    description = "Securely download and verify LlamaCPP backend JNI libraries from GitHub releases"

    onlyIf { !testLocal }
    dependsOn(downloadTasks)
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
// Usage: implementation("com.runanywhere:runanywhere-llamacpp:1.0.0")

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
                "kotlinMultiplatform" -> "runanywhere-llamacpp"
                "androidRelease" -> "runanywhere-llamacpp-android"
                "jvm" -> "runanywhere-llamacpp-jvm"
                else -> "runanywhere-llamacpp-$name"
            }

        pom {
            name.set("RunAnywhere LlamaCPP Backend")
            description.set("LlamaCPP backend for RunAnywhere SDK - on-device LLM text generation using llama.cpp.")
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
