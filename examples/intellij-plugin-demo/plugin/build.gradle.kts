plugins {
    id("org.jetbrains.intellij") version "1.17.4"
    kotlin("jvm") version "2.1.0"  // Match the version from gradle/libs.versions.toml
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
    mavenLocal()  // For SDK dependency
    mavenCentral()
    gradlePluginPortal()
    google()
}

dependencies {
    // RunAnywhere KMP SDK (JVM target) from Maven Local
    // Run './gradlew publishToMavenLocal' from sdk/runanywhere-kotlin/ to publish SDK first
    implementation("io.github.sanchitmonga22:runanywhere-sdk-jvm:0.16.1")
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
