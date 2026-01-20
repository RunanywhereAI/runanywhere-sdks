package ai.runanywhere.cli.commands

import ai.runanywhere.cli.device.AndroidDevice
import ai.runanywhere.cli.device.DeviceManager
import ai.runanywhere.cli.benchmark.BenchmarkConfig
import ai.runanywhere.cli.benchmark.ResultsAggregator
import com.github.ajalt.clikt.core.CliktCommand
import com.github.ajalt.clikt.core.subcommands
import com.github.ajalt.clikt.parameters.arguments.argument
import com.github.ajalt.clikt.parameters.arguments.multiple
import com.github.ajalt.clikt.parameters.options.default
import com.github.ajalt.clikt.parameters.options.flag
import com.github.ajalt.clikt.parameters.options.option
import com.github.ajalt.clikt.parameters.types.choice
import com.github.ajalt.clikt.parameters.types.file
import com.github.ajalt.mordant.rendering.TextColors.*
import com.github.ajalt.mordant.terminal.Terminal
import java.io.File

class BenchmarkCommand : CliktCommand(
    name = "benchmark",
    help = "Run and manage model benchmarks on Android devices"
) {
    override fun run() {
        val terminal = Terminal()
        terminal.println()
        terminal.println(cyan("📊 RunAnywhere Android Benchmark"))
        terminal.println()
        terminal.println("Commands:")
        terminal.println("  ${white("devices")}  - ${gray("List connected Android devices")}")
        terminal.println("  ${white("run")}      - ${gray("Launch benchmarks on devices")}")
        terminal.println("  ${white("pull")}     - ${gray("Pull results from devices")}")
        terminal.println("  ${white("compare")}  - ${gray("Compare results across files")}")
        terminal.println()
        terminal.println(yellow("Quick Start:"))
        terminal.println("  1. Connect your Android phone via USB")
        terminal.println("  2. Run: ${white("runanywhere benchmark run")}")
        terminal.println()
    }
    
    init {
        subcommands(
            BenchmarkDevicesCommand(),
            BenchmarkRunCommand(),
            BenchmarkPullCommand(),
            BenchmarkCompareCommand(),
        )
    }
}

class BenchmarkDevicesCommand : CliktCommand(
    name = "devices",
    help = "List connected Android devices"
) {
    override fun run() {
        val terminal = Terminal()
        terminal.println()
        terminal.println(cyan("🤖 Android Devices"))
        terminal.println(gray("─".repeat(50)))
        
        val deviceManager = DeviceManager()
        val devices = deviceManager.listAndroidDevices()
        
        if (devices.isEmpty()) {
            terminal.println()
            terminal.println(yellow("No Android devices found"))
            terminal.println()
            terminal.println("To connect a device:")
            terminal.println("  1. Enable USB debugging on your phone")
            terminal.println("  2. Connect via USB")
            terminal.println("  3. Accept the debugging prompt on phone")
        } else {
            terminal.println()
            devices.forEach { device ->
                val icon = if (device.isEmulator) "📱" else "📲"
                terminal.println("  $icon ${cyan(device.model)} (API ${device.apiLevel}) ${gray("[${device.serial}]")}")
            }
        }
        terminal.println()
    }
}

class BenchmarkRunCommand : CliktCommand(
    name = "run",
    help = "Run benchmarks on connected Android devices"
) {
    private val models by option("--models", "-m", help = "Comma-separated list of model IDs")
    private val config by option("--config", "-c", help = "Configuration: quick, default, comprehensive")
        .choice("quick", "default", "comprehensive").default("default")
    
    override fun run() {
        val terminal = Terminal()
        val deviceManager = DeviceManager()
        
        val modelList = models?.split(",")?.map { it.trim() }
        val benchmarkConfig = when (config) {
            "quick" -> BenchmarkConfig.QUICK
            "comprehensive" -> BenchmarkConfig.COMPREHENSIVE
            else -> BenchmarkConfig.DEFAULT
        }
        
        terminal.println()
        terminal.println(cyan("🚀 Starting Android Benchmark"))
        terminal.println(gray("─".repeat(40)))
        terminal.println("  Config: $config")
        terminal.println("  Models: ${modelList?.joinToString(", ") ?: "all downloaded"}")
        terminal.println()
        
        val devices = deviceManager.listAndroidDevices()
        
        if (devices.isEmpty()) {
            terminal.println(red("❌ No Android devices found"))
            return
        }
        
        devices.forEach { device ->
            terminal.println(cyan("▶ Running on ${device.model}..."))
            
            val androidDevice = AndroidDevice(device.serial)
            androidDevice.launchBenchmark(benchmarkConfig, modelList ?: emptyList())
            
            terminal.println(green("  ✓ Benchmark started"))
            terminal.println(gray("    Results will be saved to app storage"))
        }
        
        terminal.println()
        terminal.println(gray("Use 'runanywhere benchmark pull' to retrieve results"))
    }
}

class BenchmarkPullCommand : CliktCommand(
    name = "pull",
    help = "Pull benchmark results from Android devices"
) {
    private val output by option("--output", "-o", help = "Output directory").file().default(File("benchmark_results"))
    
    override fun run() {
        val terminal = Terminal()
        val deviceManager = DeviceManager()
        
        output.mkdirs()
        
        terminal.println()
        terminal.println(cyan("📥 Pulling Benchmark Results"))
        terminal.println(gray("─".repeat(40)))
        
        val devices = deviceManager.listAndroidDevices()
        
        if (devices.isEmpty()) {
            terminal.println(yellow("⚠ No Android devices found"))
            return
        }
        
        var totalFiles = 0
        devices.forEach { device ->
            terminal.println(gray("  From ${device.model}..."))
            
            val androidDevice = AndroidDevice(device.serial)
            val files = androidDevice.pullResults(output.toPath())
            
            totalFiles += files.size
            files.forEach { file ->
                terminal.println(green("    ✓ ${file.fileName}"))
            }
        }
        
        terminal.println()
        if (totalFiles > 0) {
            terminal.println(green("✓ Pulled $totalFiles file(s) to ${output.absolutePath}"))
        } else {
            terminal.println(yellow("⚠ No result files found"))
        }
    }
}

class BenchmarkCompareCommand : CliktCommand(
    name = "compare",
    help = "Compare benchmark results"
) {
    private val files by argument("files").file(mustExist = true).multiple()
    
    override fun run() {
        val terminal = Terminal()
        
        if (files.isEmpty()) {
            terminal.println(yellow("⚠ No files specified"))
            return
        }
        
        terminal.println()
        terminal.println(cyan("📊 Benchmark Comparison"))
        terminal.println(gray("─".repeat(60)))
        
        val aggregator = ResultsAggregator()
        val results = aggregator.loadAndCompare(files)
        
        if (results.isEmpty()) {
            terminal.println(yellow("⚠ No valid results found"))
            return
        }
        
        terminal.println()
        terminal.println(
            white("Model".padEnd(20)) +
            white("Device".padEnd(15)) +
            white("Tok/s".padEnd(10)) +
            white("TTFT".padEnd(10))
        )
        terminal.println(gray("─".repeat(55)))
        
        results.forEach { result ->
            terminal.println(
                cyan(result.modelName.take(19).padEnd(20)) +
                gray(result.deviceModel.take(14).padEnd(15)) +
                "${String.format("%.1f", result.avgTokensPerSecond).padEnd(10)}" +
                "${String.format("%.0fms", result.avgTtftMs).padEnd(10)}"
            )
        }
        terminal.println()
    }
}
