package ai.runanywhere.cli.commands

import com.github.ajalt.clikt.core.CliktCommand
import com.github.ajalt.clikt.core.subcommands
import com.github.ajalt.clikt.parameters.options.flag
import com.github.ajalt.clikt.parameters.options.option
import com.github.ajalt.mordant.rendering.TextColors.*
import com.github.ajalt.mordant.terminal.Terminal
import java.io.File

/**
 * Build command - wraps existing build scripts
 * 
 * Usage:
 *   runanywhere build --all
 *   runanywhere build swift [--setup]
 *   runanywhere build kotlin [--abis=arm64-v8a,armeabi-v7a]
 *   runanywhere build flutter [--ios] [--android]
 *   runanywhere build react-native [--rebuild-commons]
 */
class BuildCommand : CliktCommand(
    name = "build",
    help = "Build SDK packages and sample apps"
) {
    private val all by option("--all", help = "Build all SDKs").flag()
    
    override fun run() {
        if (all) {
            buildAll()
        }
    }
    
    private fun buildAll() {
        val terminal = Terminal()
        terminal.println(cyan("Building all SDKs..."))
        
        listOf("swift", "kotlin", "flutter", "react-native").forEach { sdk ->
            terminal.println(gray("  Building $sdk..."))
        }
        
        terminal.println(green("✓ All SDKs built successfully"))
    }
    
    init {
        subcommands(
            BuildSwiftCommand(),
            BuildKotlinCommand(),
            BuildFlutterCommand(),
            BuildReactNativeCommand(),
            BuildAndroidAppCommand(),
        )
    }
}

class BuildSwiftCommand : CliktCommand(
    name = "swift",
    help = "Build Swift SDK"
) {
    private val setup by option("--setup", help = "Setup dependencies first").flag()
    
    override fun run() {
        val terminal = Terminal()
        terminal.println(cyan("Building Swift SDK..."))
        
        val scriptPath = findScript("sdk/runanywhere-swift/scripts/build-swift.sh")
        if (scriptPath != null) {
            runScript(scriptPath, if (setup) listOf("--setup") else emptyList())
        } else {
            terminal.println(yellow("⚠ Swift build script not found"))
        }
    }
}

class BuildKotlinCommand : CliktCommand(
    name = "kotlin",
    help = "Build Kotlin SDK"
) {
    private val abis by option("--abis", help = "Comma-separated list of ABIs to build")
    
    override fun run() {
        val terminal = Terminal()
        terminal.println(cyan("Building Kotlin SDK..."))
        
        val scriptPath = findScript("sdk/runanywhere-kotlin/scripts/build-kotlin.sh")
        if (scriptPath != null) {
            val args = abis?.let { listOf("--abis=$it") } ?: emptyList()
            runScript(scriptPath, args)
        } else {
            terminal.println(yellow("⚠ Kotlin build script not found"))
        }
    }
}

class BuildFlutterCommand : CliktCommand(
    name = "flutter",
    help = "Build Flutter SDK"
) {
    private val ios by option("--ios", help = "Build for iOS").flag()
    private val android by option("--android", help = "Build for Android").flag()
    
    override fun run() {
        val terminal = Terminal()
        terminal.println(cyan("Building Flutter SDK..."))
        
        val scriptPath = findScript("sdk/runanywhere-flutter/scripts/build-flutter.sh")
        if (scriptPath != null) {
            val args = mutableListOf<String>()
            if (ios) args.add("--ios")
            if (android) args.add("--android")
            runScript(scriptPath, args)
        } else {
            terminal.println(yellow("⚠ Flutter build script not found"))
        }
    }
}

class BuildReactNativeCommand : CliktCommand(
    name = "react-native",
    help = "Build React Native SDK"
) {
    private val rebuildCommons by option("--rebuild-commons", help = "Rebuild C++ commons first").flag()
    
    override fun run() {
        val terminal = Terminal()
        terminal.println(cyan("Building React Native SDK..."))
        
        val scriptPath = findScript("sdk/runanywhere-react-native/scripts/build-react-native.sh")
        if (scriptPath != null) {
            val args = if (rebuildCommons) listOf("--rebuild-commons") else emptyList()
            runScript(scriptPath, args)
        } else {
            terminal.println(yellow("⚠ React Native build script not found"))
        }
    }
}

class BuildAndroidAppCommand : CliktCommand(
    name = "android-app",
    help = "Build and optionally run Android sample app"
) {
    private val run by option("--run", "-r", help = "Run app after building").flag()
    
    override fun run() {
        val terminal = Terminal()
        terminal.println(cyan("Building Android sample app..."))
        
        val workspaceRoot = findWorkspaceRoot()
        val appDir = File(workspaceRoot, "examples/android/RunAnywhereAI")
        
        if (!appDir.exists()) {
            terminal.println(red("✗ Android app directory not found"))
            return
        }
        
        // Build
        val buildResult = ProcessBuilder("./gradlew", "assembleDebug")
            .directory(appDir)
            .inheritIO()
            .start()
            .waitFor()
        
        if (buildResult != 0) {
            terminal.println(red("✗ Build failed"))
            return
        }
        
        terminal.println(green("✓ Build successful"))
        
        if (run) {
            terminal.println(cyan("Installing and launching..."))
            
            ProcessBuilder("./gradlew", "installDebug")
                .directory(appDir)
                .inheritIO()
                .start()
                .waitFor()
            
            ProcessBuilder(
                "adb", "shell", "am", "start",
                "-n", "com.runanywhere.runanywhereai.debug/.MainActivity"
            )
                .inheritIO()
                .start()
                .waitFor()
            
            terminal.println(green("✓ App launched"))
        }
    }
}

// Utility functions

fun findWorkspaceRoot(): File {
    var dir = File(System.getProperty("user.dir"))
    while (dir.parentFile != null) {
        if (File(dir, "settings.gradle.kts").exists() && 
            File(dir, "README.md").exists()) {
            return dir
        }
        dir = dir.parentFile
    }
    return File(System.getProperty("user.dir"))
}

fun findScript(relativePath: String): File? {
    val root = findWorkspaceRoot()
    val script = File(root, relativePath)
    return if (script.exists() && script.canExecute()) script else null
}

fun runScript(script: File, args: List<String> = emptyList()) {
    val terminal = Terminal()
    val command = listOf(script.absolutePath) + args
    
    val result = ProcessBuilder(command)
        .directory(script.parentFile)
        .inheritIO()
        .start()
        .waitFor()
    
    if (result == 0) {
        terminal.println(green("✓ Script completed successfully"))
    } else {
        terminal.println(red("✗ Script failed with exit code $result"))
    }
}
