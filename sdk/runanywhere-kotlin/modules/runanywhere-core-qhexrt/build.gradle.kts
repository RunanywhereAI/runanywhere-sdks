import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.detekt)
    alias(libs.plugins.ktlint)
}

val useLocalNatives: Boolean =
    rootProject.findProperty("runanywhere.useLocalNatives")?.toString()?.toBoolean()
        ?: project.findProperty("runanywhere.useLocalNatives")?.toString()?.toBoolean()
        ?: false

logger.lifecycle("QHexRT Module: useLocalNatives=$useLocalNatives")

// QHexRT is Qualcomm-only (Snapdragon Hexagon NPU): arm64-v8a exclusively.
val qhexrtAbis = listOf("arm64-v8a")

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
        else -> throw GradleException("Unsupported host for Android NDK runtime lookup")
    }

fun syncAndroidNdkRuntimeLibs(outputDir: File) {
    val prebuilt = androidNdkHomeForRuntime().resolve("toolchains/llvm/prebuilt/${androidNdkHostTag()}")
    if (!prebuilt.isDirectory) throw GradleException("Android NDK prebuilt dir not found: $prebuilt")
    qhexrtAbis.forEach { abi ->
        val abiDir = outputDir.resolve(abi)
        if (!abiDir.isDirectory) return@forEach
        val libcxx = prebuilt.resolve("sysroot/usr/lib/aarch64-linux-android/libc++_shared.so")
        if (!libcxx.isFile) throw GradleException("libc++_shared.so not found at $libcxx")
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

android {
    namespace = "com.runanywhere.sdk.npu.qhexrt"
    compileSdk = 37

    defaultConfig {
        minSdk = 24
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        ndk {
            abiFilters += qhexrtAbis
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
        jniLibs.keepDebugSymbols += "**/*.so"
    }

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

    testImplementation(kotlin("test-junit"))
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.junit)
    testRuntimeOnly(libs.junit.vintage.engine)
}

// Stage the 16 KB-aligned NDK libc++ alongside the bundled QHexRT .so files.
// Only when natives are built locally (runanywhere.useLocalNatives=true, same
// opt-out as llamacpp) — otherwise the staged jniLibs already ship libc++ and
// the build must not require a local NDK.
tasks.register("syncAndroidRuntimeLibs") {
    group = "runanywhere"
    description = "Stage 16 KB-aligned Android NDK libc++ into QHexRT JNI libs"
    val outputDir = file("src/main/jniLibs")
    outputs.dirs(qhexrtAbis.map { file("$outputDir/$it") })
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
