plugins {
    id("org.jetbrains.intellij") version "1.17.4"
    kotlin("jvm") version "2.1.21"
    java
}

group = "com.runanywhere"
version = "1.0.0"

intellij {
    version.set("2024.1")   // Use 2024.1 to avoid compatibility warnings with plugin 1.x
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
    implementation("com.runanywhere.sdk:RunAnywhereKotlinSDK-jvm:0.1.0") {
        // Exclude Kotlin stdlib to avoid conflicts with IntelliJ Platform's version
        exclude(group = "org.jetbrains.kotlin", module = "kotlin-stdlib")
        exclude(group = "org.jetbrains.kotlin", module = "kotlin-stdlib-common")
        exclude(group = "org.jetbrains.kotlin", module = "kotlin-stdlib-jdk8")
    }
}

tasks {
    patchPluginXml {
        sinceBuild.set("241")
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
