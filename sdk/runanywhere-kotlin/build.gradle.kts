import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.detekt)
    alias(libs.plugins.ktlint)
    id("maven-publish")
    signing
}

detekt {
    buildUponDefaultConfig = true
    allRules = false
    config.setFrom(files("detekt.yml"))
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

val isJitPack = System.getenv("JITPACK") == "true"
val usePendingNamespace = System.getenv("USE_RUNANYWHERE_NAMESPACE")?.toBoolean() ?: false
group =
    when {
        isJitPack -> "com.github.RunanywhereAI.runanywhere-sdks"
        usePendingNamespace -> "com.runanywhere"
        else -> "io.github.sanchitmonga22"
    }

val resolvedVersion =
    System.getenv("SDK_VERSION")?.removePrefix("v")
        ?: System.getenv("VERSION")?.removePrefix("v")
        ?: "0.1.5-SNAPSHOT"
version = resolvedVersion

logger.lifecycle("RunAnywhere SDK version: $resolvedVersion (JitPack=$isJitPack)")

val useLocalNatives: Boolean =
    rootProject.findProperty("runanywhere.useLocalNatives")?.toString()?.toBoolean()
        ?: project.findProperty("runanywhere.useLocalNatives")?.toString()?.toBoolean()
        ?: false

val rebuildCommons: Boolean =
    rootProject.findProperty("runanywhere.rebuildCommons")?.toString()?.toBoolean()
        ?: project.findProperty("runanywhere.rebuildCommons")?.toString()?.toBoolean()
        ?: false

val nativeLibVersion: String =
    rootProject.findProperty("runanywhere.nativeLibVersion")?.toString()
        ?: project.findProperty("runanywhere.nativeLibVersion")?.toString()
        ?: resolvedVersion

logger.lifecycle("RunAnywhere SDK: useLocalNatives=$useLocalNatives, nativeLibVersion=$nativeLibVersion")

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

fun androidNdkOmpArchForAbi(abi: String): String =
    when (abi) {
        "arm64-v8a" -> "aarch64"
        "armeabi-v7a" -> "arm"
        "x86_64" -> "x86_64"
        else -> throw GradleException("Unsupported Android ABI for libomp runtime lookup: $abi")
    }

fun latestAndroidClangDir(prebuiltDir: File): File {
    val clangRoot = prebuiltDir.resolve("lib/clang")
    return clangRoot
        .listFiles { file -> file.isDirectory }
        ?.maxByOrNull { it.name }
        ?: throw GradleException("No Clang runtime directory found under $clangRoot")
}

fun syncAndroidNdkRuntimeLibs(
    outputDir: File,
    includeLibcxx: Boolean,
    includeLibomp: Boolean,
) {
    val ndkHome = androidNdkHomeForRuntime()
    val prebuiltDir = ndkHome.resolve("toolchains/llvm/prebuilt/${androidNdkHostTag()}")
    if (!prebuiltDir.isDirectory) {
        throw GradleException("Android NDK prebuilt directory not found: $prebuiltDir")
    }

    val clangDir = if (includeLibomp) latestAndroidClangDir(prebuiltDir) else null
    androidRuntimeAbis.forEach { abi ->
        val abiDir = outputDir.resolve(abi)
        val hasNativeLibs = abiDir.isDirectory && abiDir.listFiles { file -> file.extension == "so" }?.isNotEmpty() == true
        if (!hasNativeLibs) return@forEach

        if (includeLibcxx) {
            val libcxx = prebuiltDir.resolve("sysroot/usr/lib/${androidNdkTripleForAbi(abi)}/libc++_shared.so")
            if (!libcxx.isFile) throw GradleException("libc++_shared.so not found for $abi at $libcxx")
            libcxx.copyTo(abiDir.resolve("libc++_shared.so"), overwrite = true)
        }

        if (includeLibomp && clangDir != null) {
            val libomp = clangDir.resolve("lib/linux/${androidNdkOmpArchForAbi(abi)}/libomp.so")
            if (!libomp.isFile) throw GradleException("libomp.so not found for $abi at $libomp")
            libomp.copyTo(abiDir.resolve("libomp.so"), overwrite = true)
        }
    }
}

android {
    namespace = "com.runanywhere.sdk.kotlin"
    compileSdk = 37

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

    publishing {
        singleVariant("release") {
            withSourcesJar()
        }
    }
}

kotlin {
    jvmToolchain(17)
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
        freeCompilerArgs.add("-Xsuppress-version-warnings")
        freeCompilerArgs.add("-Xno-param-assertions")
    }
}

dependencies {
    api(libs.wire.runtime)
    api(libs.okhttp)

    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.datetime)
    implementation(libs.ktor.client.core)
    implementation(libs.ktor.client.content.negotiation)
    implementation(libs.ktor.client.logging)
    implementation(libs.ktor.serialization.kotlinx.json)
    implementation(libs.okio)
    implementation(libs.whisper.jni)
    implementation(libs.gson)
    implementation(libs.commons.io)
    implementation(libs.sentry)
    implementation(libs.json)
    implementation(libs.androidx.core.ktx)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.android.vad.webrtc)
    implementation(libs.prdownloader)
    implementation(libs.androidx.work.runtime.ktx)
    implementation(libs.androidx.security.crypto)
    implementation(libs.retrofit)
    implementation(libs.retrofit.gson)

    testImplementation(kotlin("test-junit"))
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.okio.fakefilesystem)
    testImplementation(libs.junit)
    testImplementation(libs.mockk)
    testRuntimeOnly(libs.junit.vintage.engine)
}

val buildCoreAndroidScript = projectDir.resolve("../../scripts/build/build-core-android.sh").canonicalFile

tasks.register<Exec>("buildLocalJniLibs") {
    group = "runanywhere"
    description = "Build JNI libraries locally from the repo-root Android native build (when useLocalNatives=true)"

    val jniLibsDir = file("src/main/jniLibs")
    val llamaCppJniLibsDir = file("modules/runanywhere-core-llamacpp/src/main/jniLibs")
    val onnxJniLibsDir = file("modules/runanywhere-core-onnx/src/main/jniLibs")

    onlyIf { useLocalNatives }

    workingDir = projectDir

    environment(
        "ANDROID_NDK_HOME",
        System.getenv("ANDROID_NDK_HOME") ?: "${System.getProperty("user.home")}/Library/Android/sdk/ndk/${project.findProperty("racNdkVersion") ?: "27.3.13750724"}",
    )

    doFirst {
        if (!buildCoreAndroidScript.exists()) {
            throw GradleException("Missing Android build script: ${buildCoreAndroidScript.absolutePath}")
        }

        val hasMainLibs =
            jniLibsDir.resolve("arm64-v8a/librac_commons.so").exists() &&
                jniLibsDir.resolve("arm64-v8a/librunanywhere_jni.so").exists() &&
                jniLibsDir.resolve("arm64-v8a/libc++_shared.so").exists() &&
                jniLibsDir.resolve("arm64-v8a/libomp.so").exists()
        val hasLlamaCppLibs = llamaCppJniLibsDir.resolve("arm64-v8a/librac_backend_llamacpp_jni.so").exists()
        val hasOnnxLibs = onnxJniLibsDir.resolve("arm64-v8a/librac_backend_onnx_jni.so").exists()

        val allLibsExist = hasMainLibs && hasLlamaCppLibs && hasOnnxLibs

        if (allLibsExist && !rebuildCommons) {
            commandLine("echo", "JNI libs up to date")
        } else {
            commandLine("bash", buildCoreAndroidScript.absolutePath)
        }
    }

    doLast {
        fun countLibs(dir: java.io.File): Int =
            if (dir.exists()) dir.walkTopDown().filter { it.extension == "so" }.count() else 0

        val mainCount = countLibs(jniLibsDir)
        val llamaCppCount = countLibs(llamaCppJniLibsDir)
        val onnxCount = countLibs(onnxJniLibsDir)

        if (mainCount == 0 && useLocalNatives) {
            throw GradleException(
                """
                Local JNI build failed: No .so files found in $jniLibsDir

                Run first-time setup:
                  ./scripts/build/build-core-android.sh

                Or download from releases:
                  ./gradlew -Prunanywhere.useLocalNatives=false assembleDebug
                """.trimIndent(),
            )
        }

        logger.lifecycle("JNI libs: main=$mainCount llamacpp=$llamaCppCount onnx=$onnxCount")
    }
}

tasks.register("setup") {
    group = "runanywhere"
    description = "Create local.properties and verify Android SDK / NDK paths"

    doLast {
        val androidHome =
            System.getenv("ANDROID_HOME")
                ?: System.getenv("ANDROID_SDK_ROOT")
                ?: "${System.getProperty("user.home")}/Android/Sdk"
        val ndkVersion = project.findProperty("racNdkVersion")?.toString() ?: "27.3.13750724"
        val ndkHome = System.getenv("ANDROID_NDK_HOME") ?: "$androidHome/ndk/$ndkVersion"
        val localProps = projectDir.resolve("local.properties")
        if (!localProps.exists()) {
            localProps.writeText("sdk.dir=$androidHome\nndk.dir=$ndkHome\n")
            logger.lifecycle("Created ${localProps.relativeTo(projectDir)}")
        }
        logger.lifecycle("Android SDK: $androidHome (${if (file(androidHome).exists()) "OK" else "MISSING"})")
        logger.lifecycle("Android NDK: $ndkHome (${if (file(ndkHome).exists()) "OK" else "MISSING"})")
    }
}

tasks.register("buildSdk") {
    group = "runanywhere"
    description = "Build SDK debug AAR"
    dependsOn("assembleDebug")
}

tasks.register("buildSdkRelease") {
    group = "runanywhere"
    description = "Build SDK release AAR"
    dependsOn("assembleRelease")
}

tasks.register("publishSdkToMavenLocal") {
    group = "runanywhere"
    description = "Publish SDK to Maven Local (~/.m2/repository)"
    dependsOn("publishToMavenLocal")
}

tasks.register<Exec>("setupLocalDevelopment") {
    group = "runanywhere"
    description = "First-time setup: download dependencies, build commons, copy JNI libs"

    workingDir = projectDir
    commandLine("bash", buildCoreAndroidScript.absolutePath)

    environment(
        "ANDROID_NDK_HOME",
        System.getenv("ANDROID_NDK_HOME") ?: "${System.getProperty("user.home")}/Library/Android/sdk/ndk/${project.findProperty("racNdkVersion") ?: "27.3.13750724"}",
    )
}

tasks.register<Exec>("rebuildCommons") {
    group = "runanywhere"
    description = "Rebuild runanywhere-commons C++ code (use after making C++ changes)"

    workingDir = projectDir
    commandLine("bash", buildCoreAndroidScript.absolutePath)

    environment(
        "ANDROID_NDK_HOME",
        System.getenv("ANDROID_NDK_HOME") ?: "${System.getProperty("user.home")}/Library/Android/sdk/ndk/${project.findProperty("racNdkVersion") ?: "27.3.13750724"}",
    )
}

tasks.register("downloadJniLibs") {
    group = "runanywhere"
    description = "Download commons JNI libraries from GitHub releases (when useLocalNatives=false)"

    onlyIf { !useLocalNatives }

    val outputDir = file("src/main/jniLibs")
    val nativeLibVersionMarker = file("$outputDir/.native_lib_version")
    val tempDir = file("${layout.buildDirectory.get()}/jni-temp")

    val releaseBaseUrl = "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v$nativeLibVersion"
    val targetAbis = listOf("arm64-v8a", "armeabi-v7a", "x86_64")
    val packageType = "RACommons-android"

    val commonsLibs =
        setOf(
            "librac_commons.so",
            "librunanywhere_jni.so",
            "libc++_shared.so",
            "libomp.so",
        )

    outputs.dir(outputDir)

    doLast {
        if (useLocalNatives) return@doLast

        val existingLibs = outputDir.walkTopDown().filter { it.extension == "so" }.count()
        val existingVersion = nativeLibVersionMarker.takeIf { it.exists() }?.readText()?.trim()
        if (existingLibs > 0 && existingVersion == nativeLibVersion) {
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
                    .filter { it.extension == "so" && it.name in commonsLibs }
                    .forEach { soFile ->
                        val targetFile = file("$abiOutputDir/${soFile.name}")
                        soFile.copyTo(targetFile, overwrite = true)
                        totalDownloaded++
                    }

                tempZip.delete()
            } catch (e: Exception) {
                logger.warn("Failed to download $packageName: ${e.message}")
            }
        }

        tempDir.deleteRecursively()
        nativeLibVersionMarker.parentFile.mkdirs()
        nativeLibVersionMarker.writeText(nativeLibVersion)
        logger.lifecycle("Commons JNI libs: $totalDownloaded .so files downloaded")
    }
}

tasks.register("syncAndroidRuntimeLibs") {
    group = "runanywhere"
    description = "Stage 16 KB-aligned Android NDK runtime libraries into commons JNI libs"

    if (useLocalNatives) {
        dependsOn("buildLocalJniLibs")
    } else {
        dependsOn("downloadJniLibs")
    }

    val outputDir = file("src/main/jniLibs")
    outputs.dirs(androidRuntimeAbis.map { file("$outputDir/$it") })

    doLast {
        if (!useLocalNatives) return@doLast
        syncAndroidNdkRuntimeLibs(outputDir, includeLibcxx = true, includeLibomp = true)
    }
}

tasks.matching { it.name.contains("merge") && it.name.contains("JniLibFolders") }.configureEach {
    dependsOn("syncAndroidRuntimeLibs")
}

tasks.matching { it.name == "preBuild" }.configureEach {
    dependsOn("syncAndroidRuntimeLibs")
}

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

afterEvaluate {
    publishing {
        publications {
            register<MavenPublication>("release") {
                from(components["release"])
                groupId = project.group.toString()
                artifactId = "runanywhere-sdk"
                version = project.version.toString()

                pom {
                    name.set("RunAnywhere SDK")
                    description.set("Privacy-first, on-device AI SDK for Android. Includes core infrastructure and common native libraries.")
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
                name = "SonatypeSnapshots"
                url = uri("https://central.sonatype.com/repository/maven-snapshots/")
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
        gradle.taskGraph.hasTask(":publishAllPublicationsToMavenCentralRepository") ||
            gradle.taskGraph.hasTask(":publish") ||
            project.hasProperty("signing.gnupg.keyName") ||
            signingKey != null
    }
}
