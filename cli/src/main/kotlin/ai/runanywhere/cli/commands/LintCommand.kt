package ai.runanywhere.cli.commands

import com.github.ajalt.clikt.core.CliktCommand
import com.github.ajalt.clikt.core.subcommands
import com.github.ajalt.clikt.parameters.options.flag
import com.github.ajalt.clikt.parameters.options.option
import com.github.ajalt.mordant.rendering.TextColors.*
import com.github.ajalt.mordant.terminal.Terminal
import java.io.File

/**
 * Lint command - wraps existing lint scripts
 * 
 * Usage:
 *   runanywhere lint --all
 *   runanywhere lint ios
 *   runanywhere lint android
 */
class LintCommand : CliktCommand(
    name = "lint",
    help = "Run code quality checks"
) {
    private val all by option("--all", help = "Lint all platforms").flag()
    private val fix by option("--fix", help = "Auto-fix issues where possible").flag()
    
    override fun run() {
        if (all) {
            lintAll()
        }
    }
    
    private fun lintAll() {
        val terminal = Terminal()
        terminal.println(cyan("Running lint checks on all platforms..."))
        
        val scriptPath = findScript("scripts/lint-all.sh")
        if (scriptPath != null) {
            runScript(scriptPath, emptyList())
        } else {
            // Fallback: run individual linters
            terminal.println(gray("  Linting iOS (SwiftLint)..."))
            lintIOS()
            terminal.println(gray("  Linting Android (ktlint + detekt)..."))
            lintAndroid()
        }
    }
    
    private fun lintIOS() {
        val scriptPath = findScript("scripts/lint-ios.sh")
        if (scriptPath != null) {
            runScript(scriptPath, emptyList())
        }
    }
    
    private fun lintAndroid() {
        val scriptPath = findScript("scripts/lint-android.sh")
        if (scriptPath != null) {
            runScript(scriptPath, emptyList())
        }
    }
    
    init {
        subcommands(
            LintIOSCommand(),
            LintAndroidCommand(),
            LintKotlinSdkCommand(),
        )
    }
}

class LintIOSCommand : CliktCommand(
    name = "ios",
    help = "Lint iOS code with SwiftLint"
) {
    private val fix by option("--fix", help = "Auto-fix issues").flag()
    
    override fun run() {
        val terminal = Terminal()
        terminal.println(cyan("Linting iOS code..."))
        
        val scriptPath = findScript("scripts/lint-ios.sh")
        if (scriptPath != null) {
            val args = if (fix) listOf("--fix") else emptyList()
            runScript(scriptPath, args)
        } else {
            // Direct swiftlint invocation
            val iosDir = File(findWorkspaceRoot(), "examples/ios/RunAnywhereAI")
            if (iosDir.exists()) {
                val command = if (fix) {
                    listOf("swiftlint", "--fix")
                } else {
                    listOf("swiftlint")
                }
                
                ProcessBuilder(command)
                    .directory(iosDir)
                    .inheritIO()
                    .start()
                    .waitFor()
            } else {
                terminal.println(yellow("⚠ iOS app directory not found"))
            }
        }
    }
}

class LintAndroidCommand : CliktCommand(
    name = "android",
    help = "Lint Android code with ktlint and detekt"
) {
    private val fix by option("--fix", help = "Auto-fix issues").flag()
    
    override fun run() {
        val terminal = Terminal()
        terminal.println(cyan("Linting Android code..."))
        
        val scriptPath = findScript("scripts/lint-android.sh")
        if (scriptPath != null) {
            val args = if (fix) listOf("--fix") else emptyList()
            runScript(scriptPath, args)
        } else {
            // Direct gradle invocation
            val androidDir = File(findWorkspaceRoot(), "examples/android/RunAnywhereAI")
            if (androidDir.exists()) {
                val task = if (fix) "ktlintFormat" else "ktlintCheck"
                
                ProcessBuilder("./gradlew", task, "detekt")
                    .directory(androidDir)
                    .inheritIO()
                    .start()
                    .waitFor()
            } else {
                terminal.println(yellow("⚠ Android app directory not found"))
            }
        }
    }
}

class LintKotlinSdkCommand : CliktCommand(
    name = "kotlin-sdk",
    help = "Lint Kotlin SDK code"
) {
    private val fix by option("--fix", help = "Auto-fix issues").flag()
    
    override fun run() {
        val terminal = Terminal()
        terminal.println(cyan("Linting Kotlin SDK..."))
        
        val root = findWorkspaceRoot()
        val task = if (fix) "ktlintFormat" else "ktlintCheck"
        
        ProcessBuilder("./gradlew", ":sdk:runanywhere-kotlin:$task", ":sdk:runanywhere-kotlin:detekt")
            .directory(root)
            .inheritIO()
            .start()
            .waitFor()
    }
}
