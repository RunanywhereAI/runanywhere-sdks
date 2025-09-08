
// Build script for RunAnywhere IntelliJ plugin

plugins {
    id("org.jetbrains.intellij") version "1.17.4"
    kotlin("jvm") version "2.0.21"
}

group = "com.runanywhere"
version = "1.0.0"

intellij {
    version.set("2024.1")
    type.set("IC")
    plugins.set(listOf("java"))
}

repositories {
    mavenLocal()
    mavenCentral()
}

dependencies {
    // RunAnywhere KMP SDK
    implementation("com.runanywhere.sdk:runanywhere-kotlin-jvm:0.1.0")
}

tasks {
    patchPluginXml {
        sinceBuild.set("233")
        untilBuild.set("271.*")
        changeNotes.set(
            """
            <h2>1.0.0</h2>
            <ul>
                <li>Initial release</li>
                <li>Voice command support</li>
                <li>Voice dictation mode</li>
                <li>Whisper-based transcription</li>
            </ul>
        """.trimIndent()
        )
    }

    buildPlugin {
        archiveFileName.set("runanywhere-voice-${project.version}.zip")
    }

    publishPlugin {
        token.set(System.getenv("JETBRAINS_TOKEN"))
    }
}

kotlin {
    jvmToolchain(17)
    compilerOptions {
        freeCompilerArgs.add("-Xskip-metadata-version-check")
        freeCompilerArgs.add("-Xsuppress-version-warnings")
    }
}
