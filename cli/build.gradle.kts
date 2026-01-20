plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
    application
    id("com.github.johnrengelman.shadow") version "8.1.1"
}

group = "ai.runanywhere"
version = "0.1.0"

repositories {
    mavenCentral()
    mavenLocal()
}

dependencies {
    // CLI framework
    implementation("com.github.ajalt.clikt:clikt:4.4.0")
    
    // Terminal UI - progress bars, colors, tables
    implementation("com.github.ajalt.mordant:mordant:2.7.2")
    
    // Serialization for config/reports
    implementation(libs.kotlinx.serialization.json)
    
    // YAML config support
    implementation("com.charleskorn.kaml:kaml:0.61.0")
    
    // Coroutines for async operations
    implementation(libs.kotlinx.coroutines.core)
    
    // DateTime
    implementation(libs.kotlinx.datetime)
    
    // SQLite for history tracking
    implementation("org.xerial:sqlite-jdbc:3.46.1.3")
    
    // Testing
    testImplementation(kotlin("test"))
    testImplementation(libs.mockk)
}

application {
    mainClass.set("ai.runanywhere.cli.MainKt")
}

tasks.shadowJar {
    archiveBaseName.set("runanywhere-cli")
    archiveClassifier.set("")
    archiveVersion.set(version.toString())
    manifest {
        attributes["Main-Class"] = "ai.runanywhere.cli.MainKt"
    }
}

// Create a convenient run script
tasks.register("installCli") {
    group = "distribution"
    description = "Install CLI to local bin directory"
    dependsOn("shadowJar")
    
    doLast {
        val jarFile = file("build/libs/runanywhere-cli-${version}.jar")
        val binDir = file("${System.getProperty("user.home")}/.local/bin")
        
        if (!binDir.exists()) {
            binDir.mkdirs()
        }
        
        // Create wrapper script
        val script = binDir.resolve("runanywhere")
        script.writeText("""
            #!/bin/bash
            java -jar "${jarFile.absolutePath}" "${'$'}@"
        """.trimIndent())
        script.setExecutable(true)
        
        println("✅ CLI installed to ${script.absolutePath}")
        println("   Add ${binDir.absolutePath} to your PATH if not already")
    }
}

kotlin {
    jvmToolchain(17)
}
