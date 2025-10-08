plugins {
    id("org.jetbrains.intellij") version "1.17.4"
    kotlin("jvm") version "2.1.21"
    java
}

group = "com.runanywhere"
version = "1.0.0"

intellij {
    version.set("2024.2")   // IC-2024.2 uses JDK 17
    type.set("IC")
    plugins.set(listOf("java"))
}

repositories {
    mavenLocal()
    mavenCentral()
    gradlePluginPortal()
    google()
}

dependencies {
    // RunAnywhere KMP SDK (adjust version/coords if your repo uses a different name)
    implementation("com.runanywhere.sdk:RunAnywhereKotlinSDK-jvm:0.1.0")
}

tasks {
    patchPluginXml {
        sinceBuild.set("242")
        untilBuild.set("251.*")
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

    // Skip generating searchable options (faster CI and avoids headless issues)
    buildSearchableOptions {
        enabled = false
    }

    publishPlugin {
        token.set(System.getenv("JETBRAINS_TOKEN"))
    }
}

// Use JDK 17 for compilation (matches IntelliJ 2024.2 runtime)
kotlin {
    jvmToolchain(17)
}

// If you prefer Java toolchain style instead of the kotlin{} helper, you can use:
// java {
//     toolchain {
//         languageVersion.set(JavaLanguageVersion.of(17))
//     }
// }
