// Clean Gradle script for KMP SDK

plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.detekt)
    alias(libs.plugins.ktlint)
    id("maven-publish")
}

// =============================================================================
// Detekt Configuration
// =============================================================================
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

group = "com.runanywhere.sdk"
version = "0.1.4"

// =============================================================================
// Local vs Remote JNI Library Configuration
// =============================================================================
// testLocal = true  → Use locally built JNI libs from src/androidMain/jniLibs/
//                     Run: ./scripts/build-local.sh to build and copy libs
//
// testLocal = false → Download pre-built JNI libs from GitHub releases (default)
//                     Downloads from: https://github.com/RunanywhereAI/runanywhere-binaries/releases
//
// Mirrors Swift SDK's Package.swift testLocal pattern
// =============================================================================
// IMPORTANT: Check rootProject first to support composite builds (e.g., when SDK is included from example app)
// This ensures the app's gradle.properties takes precedence over the SDK's default
val testLocal: Boolean =
    rootProject.findProperty("runanywhere.testLocal")?.toString()?.toBoolean()
        ?: project.findProperty("runanywhere.testLocal")?.toString()?.toBoolean()
        ?: false

// Version constants for remote downloads (mirrors Swift's Package.swift)
// These should match the releases at:
// - https://github.com/RunanywhereAI/runanywhere-binaries/releases (Android JNI libs for backends)
// - https://github.com/RunanywhereAI/runanywhere-sdks/releases (Android JNI libs for commons)
// IMPORTANT: Check rootProject first to support composite builds
// Version defaults must match GitHub releases:
// - Commons: https://github.com/RunanywhereAI/runanywhere-sdks/releases/tag/commons-v{commonsVersion}
// - Backends: https://github.com/RunanywhereAI/runanywhere-binaries/releases/tag/core-v{coreVersion}
val coreVersion: String =
    rootProject.findProperty("runanywhere.coreVersion")?.toString()
        ?: project.findProperty("runanywhere.coreVersion")?.toString()
        ?: "0.1.4"
val commonsVersion: String =
    rootProject.findProperty("runanywhere.commonsVersion")?.toString()
        ?: project.findProperty("runanywhere.commonsVersion")?.toString()
        ?: "0.1.4"

// Log the build mode
logger.lifecycle("RunAnywhere SDK: testLocal=$testLocal, coreVersion=$coreVersion")

// =============================================================================
// Project Path Resolution
// =============================================================================
// When included as a subproject in composite builds (e.g., from example app or Android Studio),
// the module path changes. This function constructs the full absolute path for sibling modules
// based on the current project's location in the hierarchy.
//
// Examples:
// - When SDK is root project: path = ":" → module path = ":modules:$moduleName"
// - When SDK is at ":sdk:runanywhere-kotlin": path → ":sdk:runanywhere-kotlin:modules:$moduleName"
fun resolveModulePath(moduleName: String): String {
    val basePath = project.path
    val computedPath =
        if (basePath == ":") {
            ":modules:$moduleName"
        } else {
            "$basePath:modules:$moduleName"
        }

    // Try to find the project using rootProject to handle Android Studio sync ordering
    val foundProject = rootProject.findProject(computedPath)
    if (foundProject != null) {
        return computedPath
    }

    // Fallback: Try just :modules:$moduleName (when SDK is at non-root but modules are siblings)
    val simplePath = ":modules:$moduleName"
    if (rootProject.findProject(simplePath) != null) {
        return simplePath
    }

    // Return computed path (will fail with clear error if not found)
    return computedPath
}

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
}

// Include third-party licenses in JVM JAR
tasks.named<Jar>("jvmJar") {
    from(rootProject.file("THIRD_PARTY_LICENSES.md")) {
        into("META-INF")
    }
}

// Configure publishing to include license acknowledgments
publishing {
    publications.withType<MavenPublication> {
        pom {
            name.set("RunAnywhere Kotlin SDK")
            description.set("Privacy-first, on-device AI SDK for Kotlin/JVM and Android")
            url.set("https://github.com/RunanywhereAI/runanywhere-sdks")

            licenses {
                license {
                    name.set("The Apache License, Version 2.0")
                    url.set("http://www.apache.org/licenses/LICENSE-2.0.txt")
                }
            }

            developers {
                developer {
                    id.set("runanywhere")
                    name.set("RunAnywhere Team")
                    email.set("founders@runanywhere.ai")
                }
            }

            scm {
                connection.set("scm:git:git://github.com/RunanywhereAI/runanywhere-sdks.git")
                developerConnection.set("scm:git:ssh://github.com/RunanywhereAI/runanywhere-sdks.git")
                url.set("https://github.com/RunanywhereAI/runanywhere-sdks")
            }
        }
    }

    // GitHub Packages repository configuration
    repositories {
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
