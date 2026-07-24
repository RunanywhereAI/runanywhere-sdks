import com.runanywhere.gradle.NativeLibraryDownload
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.library)
    // Keep the module on the SDK's Kotlin 2.4.0 toolchain.
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.detekt)
    alias(libs.plugins.ktlint)
    `maven-publish`
    signing
}

val useLocalNatives: Boolean =
    rootProject.findProperty("runanywhere.useLocalNatives")?.toString()?.toBoolean()
        ?: project.findProperty("runanywhere.useLocalNatives")?.toString()?.toBoolean()
        ?: false

logger.lifecycle("ONNX Module: useLocalNatives=$useLocalNatives")

val androidRuntimeAbis = listOf("arm64-v8a", "armeabi-v7a", "x86_64")

fun androidNdkHomeForRuntime(): File {
    val explicitNdk = System.getenv("ANDROID_NDK_HOME") ?: System.getenv("NDK_HOME")
    if (!explicitNdk.isNullOrBlank()) return file(explicitNdk)

    val androidSdk =
        System.getenv("ANDROID_HOME")
            ?: System.getenv("ANDROID_SDK_ROOT")
            ?: "${System.getProperty("user.home")}/Library/Android/sdk"
    val ndkVersion =
        rootProject.findProperty("racNdkVersion")?.toString()
            ?: project.findProperty("racNdkVersion")?.toString()
            ?: "27.3.13750724"
    return file("$androidSdk/ndk/$ndkVersion")
}

fun androidNdkHostTag(): String =
    when {
        System.getProperty("os.name").lowercase().contains("mac") -> "darwin-x86_64"
        System.getProperty("os.name").lowercase().contains("linux") -> "linux-x86_64"
        else -> throw GradleException("Unsupported host for Android NDK runtime lookup: ${System.getProperty("os.name")}")
    }

fun androidNdkTripleForAbi(abi: String): String =
    when (abi) {
        "arm64-v8a" -> "aarch64-linux-android"
        "armeabi-v7a" -> "arm-linux-androideabi"
        "x86_64" -> "x86_64-linux-android"
        else -> throw GradleException("Unsupported Android ABI for libc++ runtime lookup: $abi")
    }

fun syncAndroidNdkRuntimeLibs(outputDir: File) {
    val prebuiltDir = androidNdkHomeForRuntime().resolve("toolchains/llvm/prebuilt/${androidNdkHostTag()}")
    if (!prebuiltDir.isDirectory) {
        throw GradleException("Android NDK prebuilt directory not found: $prebuiltDir")
    }

    androidRuntimeAbis.forEach { abi ->
        val abiDir = outputDir.resolve(abi)
        val hasNativeLibs = abiDir.isDirectory && abiDir.listFiles { file -> file.extension == "so" }?.isNotEmpty() == true
        if (!hasNativeLibs) return@forEach

        val libcxx = prebuiltDir.resolve("sysroot/usr/lib/${androidNdkTripleForAbi(abi)}/libc++_shared.so")
        if (!libcxx.isFile) throw GradleException("libc++_shared.so not found for $abi at $libcxx")
        libcxx.copyTo(abiDir.resolve("libc++_shared.so"), overwrite = true)
    }
}

detekt {
    buildUponDefaultConfig = true
    allRules = false
    config.setFrom(files("../../detekt.yml"))
    source.setFrom("src/main/kotlin")
}

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

val generateRunAnywhereLicenseResource by tasks.registering(Copy::class) {
    from(rootProject.file("../../LICENSE"))
    into(layout.buildDirectory.dir("generated/runanywhere-license/META-INF"))
    rename { "LICENSE.runanywhere-onnx.txt" }
}

android {
    namespace = "com.runanywhere.sdk.core.onnx"
    compileSdk = 37

    defaultConfig {
        minSdk = 24
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }

    sourceSets {
        getByName("main").resources.srcDir(
            layout.buildDirectory
                .dir("generated/runanywhere-license")
                .get()
                .asFile,
        )
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
        jniLibs {
            excludes += "**/libonnxruntime_qnn.so"
            keepDebugSymbols += "**/*.so"
        }
    }

    publishing {
        singleVariant("release") {
            withSourcesJar()
        }
    }
}

tasks.matching { it.name == "preBuild" }.configureEach {
    dependsOn(generateRunAnywhereLicenseResource)
}

kotlin {
    jvmToolchain(17)
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    api(findProject(":runanywhere-kotlin") ?: project(":"))
    implementation(libs.kotlinx.coroutines.core)

    testImplementation(kotlin("test"))
    testImplementation(libs.kotlinx.coroutines.test)
}

val nativeLibVersion: String =
    rootProject.findProperty("runanywhere.nativeLibVersion")?.toString()
        ?: project.findProperty("runanywhere.nativeLibVersion")?.toString()
        ?: rootProject.version.toString()

tasks.register("downloadJniLibs") {
    group = "runanywhere"
    description = "Download ONNX backend JNI libraries from GitHub releases"

    onlyIf { !useLocalNatives }

    val outputDir = file("src/main/jniLibs")
    val tempDir = file("${layout.buildDirectory.get()}/jni-temp")

    val releaseBaseUrl = "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v$nativeLibVersion"
    val targetAbis = listOf("arm64-v8a", "armeabi-v7a", "x86_64")
    val packageType = "RABackendONNX-android"

    val onnxLibs =
        setOf(
            "libc++_shared.so",
            "libonnxruntime.so",
            "librac_backend_onnx.so",
            "librac_backend_onnx_jni.so",
            "librac_backend_sherpa.so",
            "librunanywhere_onnx.so",
            "librunanywhere_sherpa.so",
            "libsherpa-onnx-c-api.so",
            "libsherpa-onnx-jni.so",
        )

    outputs.dir(outputDir)

    doLast {
        fun validateAbiInventory(abi: String) {
            val abiDir = file("$outputDir/$abi")
            val actual =
                abiDir
                    .listFiles { file -> file.extension == "so" }
                    ?.map { it.name }
                    ?.toSet()
                    .orEmpty()
            if (actual != onnxLibs) {
                throw GradleException(
                    "ONNX native inventory mismatch for $abi: " +
                        "missing=${(onnxLibs - actual).sorted()}, unexpected=${(actual - onnxLibs).sorted()}",
                )
            }
        }

        val existingLibs = outputDir.walkTopDown().any { it.extension == "so" }
        if (existingLibs) {
            targetAbis.forEach(::validateAbiInventory)
            return@doLast
        }

        outputDir.deleteRecursively()
        tempDir.deleteRecursively()
        outputDir.mkdirs()
        tempDir.mkdirs()

        var totalDownloaded = 0

        targetAbis.forEach { abi ->
            val abiOutputDir = file("$outputDir/$abi")
            abiOutputDir.mkdirs()

            val packageName = "$packageType-$abi-v$nativeLibVersion.zip"
            val zipUrl = "$releaseBaseUrl/$packageName"
            val tempZip = file("$tempDir/$packageName")

            try {
                NativeLibraryDownload.downloadZipWithChecksum(zipUrl, tempZip)

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
                        totalDownloaded++
                    }

                validateAbiInventory(abi)
                tempZip.delete()
            } catch (e: Exception) {
                outputDir.deleteRecursively()
                tempDir.deleteRecursively()
                throw GradleException("Failed to download and verify $packageName: ${e.message}", e)
            }
        }

        tempDir.deleteRecursively()
        val expectedTotal = targetAbis.size * onnxLibs.size
        if (totalDownloaded != expectedTotal) {
            throw GradleException("ONNX downloaded $totalDownloaded libraries; expected $expectedTotal")
        }
        logger.lifecycle("ONNX: $totalDownloaded .so files downloaded")
    }
}

tasks.register("syncAndroidRuntimeLibs") {
    group = "runanywhere"
    description = "Stage 16 KB-aligned Android NDK libc++ into ONNX JNI libs"

    if (!useLocalNatives) dependsOn("downloadJniLibs")

    val outputDir = file("src/main/jniLibs")
    outputs.dirs(androidRuntimeAbis.map { file("$outputDir/$it") })

    doLast {
        if (!useLocalNatives) return@doLast
        syncAndroidNdkRuntimeLibs(outputDir)
    }
}

tasks.matching { it.name.contains("merge") && it.name.contains("JniLibFolders") }.configureEach {
    dependsOn("syncAndroidRuntimeLibs")
}
tasks.matching { it.name == "preBuild" }.configureEach {
    dependsOn("syncAndroidRuntimeLibs")
}

val isJitPack = System.getenv("JITPACK") == "true"
val usePendingNamespace = System.getenv("USE_RUNANYWHERE_NAMESPACE")?.toBoolean() ?: false
group =
    when {
        isJitPack -> "com.github.RunanywhereAI.runanywhere-sdks"
        usePendingNamespace -> "com.runanywhere"
        else -> "io.github.sanchitmonga22"
    }

version = rootProject.version

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
val skipSigning: Boolean =
    rootProject.findProperty("runanywhere.skipSigning")?.toString()?.toBoolean()
        ?: false

afterEvaluate {
    publishing {
        publications {
            register<MavenPublication>("release") {
                from(components["release"])
                groupId = project.group.toString()
                artifactId = "runanywhere-onnx"
                version = project.version.toString()

                pom {
                    name.set("RunAnywhere ONNX Backend")
                    description.set("ONNX Runtime backend for RunAnywhere SDK - on-device STT, TTS, and VAD using Sherpa-ONNX.")
                    url.set("https://runanywhere.ai")
                    inceptionYear.set("2024")

                    licenses {
                        license {
                            name.set("RunAnywhere License")
                            url.set("https://github.com/RunanywhereAI/runanywhere-sdks/blob/main/LICENSE")
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
}

tasks.withType<Sign>().configureEach {
    onlyIf {
        !skipSigning &&
            (project.hasProperty("signing.gnupg.keyName") || signingKey != null)
    }
}
