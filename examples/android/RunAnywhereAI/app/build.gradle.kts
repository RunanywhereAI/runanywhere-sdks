import java.net.URI
import java.security.MessageDigest
import java.time.Instant
import java.util.Properties
import java.util.UUID
import org.gradle.api.artifacts.dsl.LockMode

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

// STRICT locking is a release/CI reproducibility gate; locally (and during
// Android Studio sync, which resolves synthetic *Copy configs and IDE-only
// source artifacts) it only causes friction, so relax to LENIENT off-CI.
val strictDependencyLocks = providers.environmentVariable("CI").isPresent ||
    providers.gradleProperty("runanywhere.strictLocks").map { it.toBoolean() }.orElse(false).get() ||
    gradle.startParameter.isWriteDependencyLocks

dependencyLocking {
    lockAllConfigurations()
    lockMode.set(if (strictDependencyLocks) LockMode.STRICT else LockMode.LENIENT)
}

// Backend config comes from CI-safe environment variables first, then the
// gitignored local.properties file. Empty defaults keep local/offline builds
// working until publication credentials are provided.
val localProps = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun releaseValue(environmentName: String, localName: String): String =
    providers.environmentVariable(environmentName).orNull?.trim().orEmpty()
        .ifBlank { localProps.getProperty(localName).orEmpty().trim() }

fun String.asBuildConfigString(): String = buildString {
    append('"')
    this@asBuildConfigString.forEach { char ->
        when (char) {
            '\\' -> append("\\\\")
            '"' -> append("\\\"")
            '\n' -> append("\\n")
            '\r' -> append("\\r")
            else -> append(char)
        }
    }
    append('"')
}

val runanywhereBaseUrl = releaseValue("RUNANYWHERE_BASE_URL", "runanywhere.baseUrl")
val runanywhereApiKey = releaseValue("RUNANYWHERE_API_KEY", "runanywhere.apiKey")
val privacyPolicyUrl = releaseValue("RUNANYWHERE_PRIVACY_POLICY_URL", "runanywhere.privacyPolicyUrl")
val webSearchUrl = releaseValue("RUNANYWHERE_WEB_SEARCH_URL", "runanywhere.webSearchUrl")
require(runanywhereBaseUrl.isBlank() == runanywhereApiKey.isBlank()) {
    "RUNANYWHERE_BASE_URL and RUNANYWHERE_API_KEY must either both be set or both be blank"
}

val releaseKeystorePath = System.getenv("KEYSTORE_PATH")
val releaseKeystorePassword = System.getenv("KEYSTORE_PASSWORD")
val releaseKeyAlias = System.getenv("KEY_ALIAS")
val releaseKeyPassword = System.getenv("KEY_PASSWORD")
val expectedUploadCertSha256 = System.getenv("UPLOAD_CERT_SHA256")?.trim().orEmpty()
val e2eApplicationIdSuffix = providers.environmentVariable("RUNANYWHERE_E2E_APPLICATION_ID_SUFFIX")
    .orNull?.trim().orEmpty()
require(
    e2eApplicationIdSuffix.isBlank() ||
        Regex("(?:\\.[A-Za-z][A-Za-z0-9_]*)+").matches(e2eApplicationIdSuffix)
) {
    "RUNANYWHERE_E2E_APPLICATION_ID_SUFFIX must be blank or dot-prefixed identifier segments"
}
val releaseSigningValues = listOf(releaseKeystorePath, releaseKeystorePassword, releaseKeyAlias, releaseKeyPassword)
val hasReleaseSigning = releaseSigningValues.all { !it.isNullOrBlank() }
require(hasReleaseSigning || releaseSigningValues.all { it.isNullOrBlank() }) {
    "KEYSTORE_PATH, KEYSTORE_PASSWORD, KEY_ALIAS, and KEY_PASSWORD must all be set together"
}

android {
    namespace = "com.runanywhere.runanywhereai"
    // Debug remains the normal developer target. Device acceptance can compile
    // instrumentation against the exact minified/signed release variant with
    // `-Prunanywhere.testBuildType=release`.
    testBuildType = providers.gradleProperty("runanywhere.testBuildType").orElse("debug").get()
    compileSdk {
        version = release(37) {
            minorApiLevel = 0
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(checkNotNull(releaseKeystorePath))
                storePassword = releaseKeystorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    defaultConfig {
        applicationId = "com.runanywhere.runanywhereai"
        minSdk = 24
        targetSdk = 37
        versionCode = 25
        versionName = "0.1.14"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        buildConfigField("String", "RUNANYWHERE_BASE_URL", runanywhereBaseUrl.asBuildConfigString())
        buildConfigField("String", "RUNANYWHERE_API_KEY", runanywhereApiKey.asBuildConfigString())
        buildConfigField("String", "PRIVACY_POLICY_URL", privacyPolicyUrl.asBuildConfigString())
        buildConfigField("String", "WEB_SEARCH_URL", webSearchUrl.asBuildConfigString())

        // Release/device builds ship arm64-v8a: the Qualcomm Hexagon NPU (QHexRT, Hexagon v75+)
        // is arm64-only hardware, and target devices (Snapdragon 8 Gen 3+) are all
        // arm64. Constraining to one ABI keeps a single consistent native slice (no
        // stale armv7 commons), guarantees the QAIRT skels travel with
        // it, and roughly halves the APK size.
        ndk {
            abiFilters += "arm64-v8a"
        }
    }

    buildTypes {
        debug {
            if (e2eApplicationIdSuffix.isNotEmpty()) {
                applicationIdSuffix = e2eApplicationIdSuffix
            }
            // Keep emulator development available for the shared example app.
            // QHexRT remains unavailable on x86_64; the SDK falls back to CPU backends.
            ndk {
                abiFilters += "x86_64"
            }
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            ndk.debugSymbolLevel = "SYMBOL_TABLE"
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            testProguardFiles("test-proguard-rules.pro")
            // CI/store builds use the env-provided upload key. The debug-key fallback
            // exists only so a minified release APK can be installed on a test device;
            // bundleRelease is gated by verifyPlayRelease below.
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    packaging {
        jniLibs {
            // SDK + backend AARs each bundle the NDK C++ runtime; keep one copy per ABI.
            pickFirsts += "**/libc++_shared.so"
            pickFirsts += "**/libomp.so"
            pickFirsts += "**/librac_commons.so"
            // Extract native libs to a real nativeLibraryDir. The QNN HTP FastRPC
            // loader resolves the per-arch DSP skel (libQnnHtpV81Skel.so) as a
            // filesystem file via ADSP_LIBRARY_PATH; with the default
            // extractNativeLibs=false the skels stay inside base.apk and the cDSP
            // cannot open them (contextCreateFromBinary -> 0x36b1). Extracting them
            // gives the qhexrt engine's dladdr fallback a real skel directory.
            useLegacyPackaging = true
        }
    }
}

dependencies {
    implementation(files("../libs/runanywhere-sdk.aar"))
    implementation(files("../libs/runanywhere-llamacpp.aar"))
    implementation(files("../libs/runanywhere-onnx.aar"))
    implementation(files("../libs/runanywhere-qhexrt.aar"))
    implementation(libs.okhttp)
    implementation(libs.pdfbox.android)

    // CameraX — Vision screen Live mode
    implementation(libs.androidx.camera.core)
    implementation(libs.androidx.camera.camera2)
    implementation(libs.androidx.camera.lifecycle)
    implementation(libs.androidx.camera.view)

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.kotlinx.serialization.json)
    // files(...) AARs carry no POM; declare coroutines 1.11.0 directly so it outranks
    // the older transitive core from androidx (SDK is compiled against 1.11.0).
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.proto.wire.runtime)
    testImplementation(libs.junit)

    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(libs.androidx.junit)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
    debugImplementation(libs.androidx.compose.ui.tooling)
}

val verifyPlayRelease = tasks.register("verifyPlayRelease") {
    group = "verification"
    description = "Fails unless the Play bundle has real signing and backend configuration."
    doLast {
        check(hasReleaseSigning) {
            "Play release requires KEYSTORE_PATH, KEYSTORE_PASSWORD, KEY_ALIAS, and KEY_PASSWORD"
        }
        check(runanywhereBaseUrl.isNotBlank() && runanywhereApiKey.isNotBlank()) {
            "Play release requires RUNANYWHERE_BASE_URL and RUNANYWHERE_API_KEY"
        }
        fun requireHttps(name: String, value: String) {
            val uri = runCatching { URI(value) }.getOrNull()
            check(uri?.scheme.equals("https", ignoreCase = true) && !uri?.host.isNullOrBlank() && uri?.userInfo == null) {
                "$name must be a valid HTTPS URL without embedded credentials"
            }
        }
        requireHttps("RUNANYWHERE_BASE_URL", runanywhereBaseUrl)
        requireHttps("RUNANYWHERE_PRIVACY_POLICY_URL", privacyPolicyUrl)
        if (webSearchUrl.isNotBlank()) {
            requireHttps("RUNANYWHERE_WEB_SEARCH_URL", webSearchUrl)
        }

        val keystore = file(checkNotNull(releaseKeystorePath))
        check(keystore.isFile) { "KEYSTORE_PATH does not point to a readable upload keystore" }
        check(expectedUploadCertSha256.isNotBlank()) {
            "Play release requires UPLOAD_CERT_SHA256 for upload-certificate verification"
        }
        val keytool = ProcessBuilder(
            "keytool", "-list", "-v",
            "-keystore", keystore.absolutePath,
            "-alias", checkNotNull(releaseKeyAlias),
            "-storepass:env", "KEYSTORE_PASSWORD",
        ).redirectErrorStream(true).start()
        val keytoolOutput = keytool.inputStream.bufferedReader().use { it.readText() }
        check(keytool.waitFor() == 0) { "Could not inspect the configured upload keystore" }
        val actualFingerprint = Regex("SHA256:\\s*([0-9A-Fa-f:]+)")
            .find(keytoolOutput)?.groupValues?.get(1)?.replace(":", "")?.uppercase()
        val expectedFingerprint = expectedUploadCertSha256.replace(":", "").uppercase()
        check(actualFingerprint == expectedFingerprint) {
            "Upload certificate SHA-256 does not match UPLOAD_CERT_SHA256"
        }
    }
}

val localSdkVersion = providers.environmentVariable("SDK_VERSION").orNull
    ?.removePrefix("v")
    ?.takeIf { it.isNotBlank() }
    ?: "0.1.12-SNAPSHOT"
val localSdkAars = fileTree("../libs") { include("*.aar") }

val generateReleaseSbom = tasks.register("generateReleaseSbom") {
    group = "verification"
    description = "Writes a CycloneDX JSON inventory for the release runtime classpath and local SDK AARs."
    val output = layout.buildDirectory.file("reports/release-sbom.cdx.json")
    inputs.files(localSdkAars)
        .withPropertyName("localSdkAars")
        .withPathSensitivity(PathSensitivity.RELATIVE)
    inputs.property("applicationVersion", android.defaultConfig.versionName.orEmpty())
    inputs.property("localSdkVersion", localSdkVersion)
    outputs.file(output)
    doLast {
        data class Component(
            val group: String,
            val name: String,
            val version: String,
            val file: File,
        )

        val runtime = configurations.getByName("releaseRuntimeClasspath")
        val components = runtime.resolvedConfiguration.resolvedArtifacts.map { artifact ->
            Component(
                group = artifact.moduleVersion.id.group,
                name = artifact.name,
                version = artifact.moduleVersion.id.version,
                file = artifact.file,
            )
        }.toMutableList()
        localSdkAars.files.forEach { aar ->
            if (components.none { it.file.canonicalFile == aar.canonicalFile }) {
                components += Component("com.runanywhere.local", aar.nameWithoutExtension, localSdkVersion, aar)
            }
        }

        fun String.json(): String = buildString {
            append('"')
            this@json.forEach { c ->
                when (c) {
                    '\\' -> append("\\\\")
                    '"' -> append("\\\"")
                    '\n' -> append("\\n")
                    '\r' -> append("\\r")
                    '\t' -> append("\\t")
                    else -> append(c)
                }
            }
            append('"')
        }
        fun File.sha256(): String {
            val digest = MessageDigest.getInstance("SHA-256")
            inputStream().use { input ->
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    digest.update(buffer, 0, count)
                }
            }
            return digest.digest().joinToString("") { "%02x".format(it) }
        }

        val componentJson = components
            .distinctBy { it.file.canonicalFile }
            .sortedWith(compareBy<Component>({ it.group }, { it.name }, { it.version }, { it.file.name }))
            .joinToString(",\n") { component ->
                """    {
      "type": "library",
      "group": ${component.group.json()},
      "name": ${component.name.json()},
      "version": ${component.version.json()},
      "hashes": [{"alg": "SHA-256", "content": ${component.file.sha256().json()}}],
      "properties": [{"name": "artifact.file", "value": ${component.file.name.json()}}]
    }"""
            }
        val json = """{
  "bomFormat": "CycloneDX",
  "specVersion": "1.5",
  "serialNumber": "urn:uuid:${UUID.randomUUID()}",
  "version": 1,
  "metadata": {
    "timestamp": ${Instant.now().toString().json()},
    "component": {
      "type": "application",
      "group": "com.runanywhere",
      "name": "RunAnywhere",
      "version": ${android.defaultConfig.versionName.orEmpty().json()}
    }
  },
  "components": [
$componentJson
  ]
}
"""
        output.get().asFile.apply {
            parentFile.mkdirs()
            writeText(json)
        }
    }
}

// Android variant configurations are materialized after this script has been
// evaluated, so attach the runtime-classpath input at that point while keeping
// task execution and dependency resolution lazy.
afterEvaluate {
    generateReleaseSbom.configure {
        inputs.files(configurations.getByName("releaseRuntimeClasspath"))
            .withPropertyName("releaseRuntimeClasspath")
            .withPathSensitivity(PathSensitivity.RELATIVE)
    }
}

tasks.configureEach {
    if (name == "signReleaseBundle" || name == "bundleRelease") {
        dependsOn(verifyPlayRelease)
    }
    if (name == "bundleRelease") {
        dependsOn(generateReleaseSbom)
    }
}
