package ai.runanywhere.cli

import ai.runanywhere.cli.commands.*
import com.github.ajalt.clikt.core.CliktCommand
import com.github.ajalt.clikt.core.main
import com.github.ajalt.clikt.core.subcommands
import com.github.ajalt.mordant.rendering.TextColors.*
import com.github.ajalt.mordant.terminal.Terminal

/**
 * RunAnywhere CLI - Unified tool for building, linting, and benchmarking
 * 
 * Usage:
 *   runanywhere build [--all|swift|kotlin|flutter|react-native]
 *   runanywhere lint [--all|ios|android]
 *   runanywhere benchmark [devices|run|pull|compare|history|report]
 */
class RunAnywhereCli : CliktCommand(
    name = "runanywhere",
    help = """
        RunAnywhere CLI - Build, lint, and benchmark your AI apps
        
        A unified command-line tool for the RunAnywhere SDK ecosystem.
    """.trimIndent()
) {
    private val terminal = Terminal()
    
    override fun run() {
        // Print banner when no subcommand is provided
        terminal.println()
        terminal.println(cyan("╔═══════════════════════════════════════════════════════╗"))
        terminal.println(cyan("║") + white("   RunAnywhere CLI v0.1.0                              ") + cyan("║"))
        terminal.println(cyan("║") + gray("   Build, lint, and benchmark your AI apps              ") + cyan("║"))
        terminal.println(cyan("╚═══════════════════════════════════════════════════════╝"))
        terminal.println()
    }
}

fun main(args: Array<String>) {
    RunAnywhereCli()
        .subcommands(
            BuildCommand(),
            LintCommand(),
            BenchmarkCommand(),
            ModelsCommand(),
        )
        .main(args)
}
