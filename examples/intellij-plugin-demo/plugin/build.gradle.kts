plugins {
    id("org.jetbrains.intellij")
    kotlin("jvm")
}

group = "com.runanywhere"
version = "1.0.0"

intellij {
    version.set("2023.3")
    type.set("IC") // IntelliJ IDEA Community Edition
    plugins.set(listOf("java"))
}

dependencies {
    implementation(project(":core"))
    implementation(project(":jni"))
    implementation(libs.kotlinx.coroutines.core)
}

tasks {
    patchPluginXml {
        sinceBuild.set("233")
        untilBuild.set("241.*")
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
        archiveFileName.set("runanywhere-voice-${version.get()}.zip")
    }

    publishPlugin {
        token.set(System.getenv("JETBRAINS_TOKEN"))
    }
}

kotlin {
    jvmToolchain(17)
}
