package ai.runanywhere.cli.commands

import ai.runanywhere.cli.device.AndroidDevice
import ai.runanywhere.cli.device.DeviceManager
import ai.runanywhere.cli.device.IOSDevice
import ai.runanywhere.cli.benchmark.BenchmarkConfig
import ai.runanywhere.cli.benchmark.HistoryStore
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
import com.github.ajalt.clikt.parameters.types.int
import com.github.ajalt.mordant.rendering.TextColors.*
import com.github.ajalt.mordant.terminal.Terminal
import java.io.File

/**
 * Benchmark command - orchestrate mobile benchmarks
 * 
 * Usage:
 *   runanywhere benchmark devices
 *   runanywhere benchmark run --ios --models=smollm2-360m
 *   runanywhere benchmark run --android --models=smollm2-360m
 *   runanywhere benchmark pull --ios --output=results/
 *   runanywhere benchmark compare results/*.json
 *   runanywhere benchmark history --model=smollm2-360m
 *   runanywhere benchmark report --format=markdown
 */
class BenchmarkCommand : CliktCommand(
    name = "benchmark",
    help = "Run and manage model benchmarks on mobile devices"
) {
    override fun run() {
        // Show help when no subcommand
    }
    
    init {
        subcommands(
            BenchmarkDevicesCommand(),
            BenchmarkRunCommand(),
            BenchmarkPullCommand(),
            BenchmarkCompareCommand(),
            BenchmarkHistoryCommand(),
            BenchmarkReportCommand(),
        )
    }
}

/**
 * List connected devices
 */
class BenchmarkDevicesCommand : CliktCommand(
    name = "devices",
    help = "List connected iOS and Android devices"
) {
    override fun run() {
        val terminal = Terminal()
        terminal.println()
        terminal.println(cyan("Connected Devices"))
        terminal.println(gray("─".repeat(60)))
        
        val deviceManager = DeviceManager()
        
        // iOS devices
        terminal.println()
        terminal.println(white("iOS:"))
        val iosDevices = deviceManager.listIOSDevices()
        if (iosDevices.isEmpty()) {
            terminal.println(gray("  No iOS devices/simulators connected"))
        } else {
            iosDevices.forEach { device ->
                val typeIcon = if (device.isSimulator) "📱" else "📲"
                terminal.println(
                    "  $typeIcon ${cyan(device.name)} " +
                    "(${device.osVersion}) " +
                    gray("[${device.udid.take(12)}...]")
                )
            }
        }
        
        // Android devices
        terminal.println()
        terminal.println(white("Android:"))
        val androidDevices = deviceManager.listAndroidDevices()
        if (androidDevices.isEmpty()) {
            terminal.println(gray("  No Android devices/emulators connected"))
        } else {
            androidDevices.forEach { device ->
                val typeIcon = if (device.isEmulator) "📱" else "📲"
                terminal.println(
                    "  $typeIcon ${cyan(device.model)} " +
                    "(API ${device.apiLevel}) " +
                    gray("[${device.serial}]")
                )
            }
        }
        
        terminal.println()
    }
}

/**
 * Run benchmarks on devices
 */
class BenchmarkRunCommand : CliktCommand(
    name = "run",
    help = "Run benchmarks on connected devices"
) {
    private val ios by option("--ios", help = "Run on iOS device").flag()
    private val android by option("--android", help = "Run on Android device").flag()
    private val allDevices by option("--all-devices", help = "Run on all connected devices").flag()
    
    private val models by option(
        "--models", "-m",
        help = "Comma-separated list of model IDs to benchmark"
    )
    
    private val config by option(
        "--config", "-c",
        help = "Benchmark configuration (quick, default, comprehensive)"
    ).choice("quick", "default", "comprehensive").default("default")
    
    private val deviceId by option(
        "--device", "-d",
        help = "Specific device ID to use"
    )
    
    override fun run() {
        val terminal = Terminal()
        val deviceManager = DeviceManager()
        
        val modelList = models?.split(",")?.map { it.trim() } ?: listOf("smollm2-360m")
        val benchmarkConfig = when (config) {
            "quick" -> BenchmarkConfig.QUICK
            "comprehensive" -> BenchmarkConfig.COMPREHENSIVE
            else -> BenchmarkConfig.DEFAULT
        }
        
        terminal.println()
        terminal.println(cyan("Starting Benchmark"))
        terminal.println(gray("─".repeat(40)))
        terminal.println("  Config: ${config}")
        terminal.println("  Models: ${modelList.joinToString(", ")}")
        terminal.println()
        
        // Determine which devices to run on
        val runIOS = ios || allDevices
        val runAndroid = android || allDevices
        
        if (!runIOS && !runAndroid) {
            terminal.println(yellow("⚠ No platform specified. Use --ios, --android, or --all-devices"))
            return
        }
        
        // Run on iOS
        if (runIOS) {
            val iosDevices = if (deviceId != null) {
                deviceManager.listIOSDevices().filter { it.udid == deviceId }
            } else {
                deviceManager.listIOSDevices().take(1)
            }
            
            if (iosDevices.isEmpty()) {
                terminal.println(yellow("⚠ No iOS devices found"))
            } else {
                iosDevices.forEach { device ->
                    terminal.println(cyan("Running on iOS: ${device.name}"))
                    
                    val iosDevice = IOSDevice(device.udid, device.isSimulator)
                    iosDevice.launchBenchmark(benchmarkConfig, modelList)
                    
                    terminal.println(green("✓ Benchmark started on ${device.name}"))
                    terminal.println(gray("  Results will be saved to app Documents folder"))
                }
            }
        }
        
        // Run on Android
        if (runAndroid) {
            val androidDevices = if (deviceId != null) {
                deviceManager.listAndroidDevices().filter { it.serial == deviceId }
            } else {
                deviceManager.listAndroidDevices().take(1)
            }
            
            if (androidDevices.isEmpty()) {
                terminal.println(yellow("⚠ No Android devices found"))
            } else {
                androidDevices.forEach { device ->
                    terminal.println(cyan("Running on Android: ${device.model}"))
                    
                    val androidDevice = AndroidDevice(device.serial)
                    androidDevice.launchBenchmark(benchmarkConfig, modelList)
                    
                    terminal.println(green("✓ Benchmark started on ${device.model}"))
                    terminal.println(gray("  Results will be saved to app external files"))
                }
            }
        }
        
        terminal.println()
        terminal.println(gray("Use 'runanywhere benchmark pull' to retrieve results after completion"))
    }
}

/**
 * Pull benchmark results from devices
 */
class BenchmarkPullCommand : CliktCommand(
    name = "pull",
    help = "Pull benchmark results from devices"
) {
    private val ios by option("--ios", help = "Pull from iOS device").flag()
    private val android by option("--android", help = "Pull from Android device").flag()
    private val all by option("--all", help = "Pull from all devices").flag()
    
    private val output by option(
        "--output", "-o",
        help = "Output directory for results"
    ).file().default(File("benchmark_results"))
    
    override fun run() {
        val terminal = Terminal()
        val deviceManager = DeviceManager()
        
        // Create output directory
        output.mkdirs()
        
        terminal.println()
        terminal.println(cyan("Pulling Benchmark Results"))
        terminal.println(gray("─".repeat(40)))
        terminal.println("  Output: ${output.absolutePath}")
        terminal.println()
        
        val pullIOS = ios || all
        val pullAndroid = android || all
        
        if (!pullIOS && !pullAndroid) {
            terminal.println(yellow("⚠ No platform specified. Use --ios, --android, or --all"))
            return
        }
        
        var totalFiles = 0
        
        // Pull from iOS
        if (pullIOS) {
            val iosDevices = deviceManager.listIOSDevices()
            iosDevices.forEach { device ->
                terminal.println(gray("Pulling from iOS: ${device.name}"))
                
                val iosDevice = IOSDevice(device.udid, device.isSimulator)
                val files = iosDevice.pullResults(output.toPath())
                
                totalFiles += files.size
                files.forEach { file ->
                    terminal.println(green("  ✓ ${file.fileName}"))
                }
            }
        }
        
        // Pull from Android
        if (pullAndroid) {
            val androidDevices = deviceManager.listAndroidDevices()
            androidDevices.forEach { device ->
                terminal.println(gray("Pulling from Android: ${device.model}"))
                
                val androidDevice = AndroidDevice(device.serial)
                val files = androidDevice.pullResults(output.toPath())
                
                totalFiles += files.size
                files.forEach { file ->
                    terminal.println(green("  ✓ ${file.fileName}"))
                }
            }
        }
        
        terminal.println()
        if (totalFiles > 0) {
            terminal.println(green("✓ Pulled $totalFiles result file(s) to ${output.absolutePath}"))
        } else {
            terminal.println(yellow("⚠ No result files found"))
        }
    }
}

/**
 * Compare benchmark results
 */
class BenchmarkCompareCommand : CliktCommand(
    name = "compare",
    help = "Compare benchmark results across files/devices"
) {
    private val files by argument(
        "files",
        help = "Result files to compare"
    ).file(mustExist = true).multiple()
    
    override fun run() {
        val terminal = Terminal()
        
        if (files.isEmpty()) {
            terminal.println(yellow("⚠ No files specified"))
            return
        }
        
        terminal.println()
        terminal.println(cyan("Benchmark Comparison"))
        terminal.println(gray("─".repeat(70)))
        
        val aggregator = ResultsAggregator()
        val results = aggregator.loadAndCompare(files)
        
        if (results.isEmpty()) {
            terminal.println(yellow("⚠ No valid results found in specified files"))
            return
        }
        
        // Print comparison table header
        terminal.println()
        terminal.println(
            white("Model".padEnd(20)) +
            white("Device".padEnd(20)) +
            white("Tok/s".padEnd(12)) +
            white("TTFT".padEnd(12)) +
            white("Memory".padEnd(12))
        )
        terminal.println(gray("─".repeat(70)))
        
        // Print results
        results.forEach { result ->
            terminal.println(
                cyan(result.modelName.take(19).padEnd(20)) +
                gray(result.deviceModel.take(19).padEnd(20)) +
                "${String.format("%.1f", result.avgTokensPerSecond).padEnd(12)}" +
                "${String.format("%.0fms", result.avgTtftMs).padEnd(12)}" +
                "${String.format("%.0fMB", result.peakMemoryMB).padEnd(12)}"
            )
        }
        
        terminal.println()
    }
}

/**
 * View historical benchmark data
 */
class BenchmarkHistoryCommand : CliktCommand(
    name = "history",
    help = "View historical benchmark performance"
) {
    private val model by option(
        "--model", "-m",
        help = "Filter by model ID"
    )
    
    private val platform by option(
        "--platform", "-p",
        help = "Filter by platform (ios, android)"
    ).choice("ios", "android")
    
    private val last by option(
        "--last",
        help = "Time period (e.g., 7days, 30days)"
    ).default("30days")
    
    override fun run() {
        val terminal = Terminal()
        
        terminal.println()
        terminal.println(cyan("Benchmark History"))
        terminal.println(gray("─".repeat(60)))
        
        val historyStore = HistoryStore()
        val entries = historyStore.query(
            modelId = model,
            platform = platform,
            lastDays = parseDays(last)
        )
        
        if (entries.isEmpty()) {
            terminal.println(yellow("⚠ No historical data found"))
            terminal.println(gray("  Run some benchmarks first with 'runanywhere benchmark run'"))
            return
        }
        
        // Group by model
        entries.groupBy { it.modelId }.forEach { (modelId, modelEntries) ->
            terminal.println()
            terminal.println(white(modelId))
            
            modelEntries.sortedByDescending { it.timestamp }.take(10).forEach { entry ->
                val trend = if (entry.tokensPerSecondDelta > 0) {
                    green("↑ +${String.format("%.1f", entry.tokensPerSecondDelta)}%")
                } else if (entry.tokensPerSecondDelta < 0) {
                    red("↓ ${String.format("%.1f", entry.tokensPerSecondDelta)}%")
                } else {
                    gray("→ 0%")
                }
                
                terminal.println(
                    "  ${gray(entry.dateString)} " +
                    "${entry.platform.padEnd(8)} " +
                    "${String.format("%.1f", entry.tokensPerSecond).padEnd(8)} tok/s " +
                    trend + " " +
                    gray(entry.gitCommit?.take(7) ?: "")
                )
            }
        }
        
        terminal.println()
    }
    
    private fun parseDays(period: String): Int {
        return when {
            period.endsWith("days") -> period.removeSuffix("days").toIntOrNull() ?: 30
            period.endsWith("d") -> period.removeSuffix("d").toIntOrNull() ?: 30
            else -> period.toIntOrNull() ?: 30
        }
    }
}

/**
 * Generate benchmark report
 */
class BenchmarkReportCommand : CliktCommand(
    name = "report",
    help = "Generate benchmark report"
) {
    private val format by option(
        "--format", "-f",
        help = "Output format"
    ).choice("markdown", "json", "html").default("markdown")
    
    private val input by option(
        "--input", "-i",
        help = "Input directory with result files"
    ).file().default(File("benchmark_results"))
    
    private val output by option(
        "--output", "-o",
        help = "Output file path"
    )
    
    override fun run() {
        val terminal = Terminal()
        
        terminal.println()
        terminal.println(cyan("Generating Benchmark Report"))
        terminal.println(gray("─".repeat(40)))
        
        if (!input.exists() || !input.isDirectory) {
            terminal.println(yellow("⚠ Input directory not found: ${input.absolutePath}"))
            return
        }
        
        val resultFiles = input.listFiles { file ->
            file.extension == "json" && file.name.startsWith("benchmark_")
        }?.toList() ?: emptyList()
        
        if (resultFiles.isEmpty()) {
            terminal.println(yellow("⚠ No benchmark result files found in ${input.absolutePath}"))
            return
        }
        
        terminal.println("  Found ${resultFiles.size} result file(s)")
        
        val aggregator = ResultsAggregator()
        val results = aggregator.loadAndCompare(resultFiles)
        
        val reportContent = when (format) {
            "markdown" -> generateMarkdownReport(results)
            "json" -> generateJsonReport(results)
            "html" -> generateHtmlReport(results)
            else -> generateMarkdownReport(results)
        }
        
        val outputFile = output?.let { File(it) } ?: File(
            when (format) {
                "markdown" -> "BENCHMARK_REPORT.md"
                "json" -> "benchmark_report.json"
                "html" -> "benchmark_report.html"
                else -> "BENCHMARK_REPORT.md"
            }
        )
        
        outputFile.writeText(reportContent)
        
        terminal.println(green("✓ Report saved to ${outputFile.absolutePath}"))
    }
    
    private fun generateMarkdownReport(results: List<ResultsAggregator.AggregatedResult>): String {
        return buildString {
            appendLine("# RunAnywhere Benchmark Report")
            appendLine()
            appendLine("Generated: ${java.time.Instant.now()}")
            appendLine()
            appendLine("## Summary")
            appendLine()
            appendLine("| Model | Device | Tokens/sec | TTFT | Latency | Memory |")
            appendLine("|-------|--------|------------|------|---------|--------|")
            
            results.forEach { result ->
                appendLine(
                    "| ${result.modelName} " +
                    "| ${result.deviceModel} " +
                    "| ${String.format("%.1f", result.avgTokensPerSecond)} " +
                    "| ${String.format("%.0fms", result.avgTtftMs)} " +
                    "| ${String.format("%.0fms", result.avgLatencyMs)} " +
                    "| ${String.format("%.0fMB", result.peakMemoryMB)} |"
                )
            }
            
            appendLine()
            appendLine("## Details")
            appendLine()
            
            results.groupBy { it.modelName }.forEach { (modelName, modelResults) ->
                appendLine("### $modelName")
                appendLine()
                modelResults.forEach { result ->
                    appendLine("**${result.deviceModel}** (${result.platform})")
                    appendLine("- Tokens/sec: ${String.format("%.1f", result.avgTokensPerSecond)} (p50: ${String.format("%.1f", result.p50TokensPerSecond)}, p95: ${String.format("%.1f", result.p95TokensPerSecond)})")
                    appendLine("- Time to First Token: ${String.format("%.0fms", result.avgTtftMs)}")
                    appendLine("- Total Latency: ${String.format("%.0fms", result.avgLatencyMs)}")
                    appendLine("- Peak Memory: ${String.format("%.0fMB", result.peakMemoryMB)}")
                    appendLine("- Model Load Time: ${String.format("%.0fms", result.modelLoadTimeMs)}")
                    appendLine()
                }
            }
        }
    }
    
    private fun generateJsonReport(results: List<ResultsAggregator.AggregatedResult>): String {
        // Simple JSON output
        return buildString {
            appendLine("{")
            appendLine("  \"generated\": \"${java.time.Instant.now()}\",")
            appendLine("  \"results\": [")
            results.forEachIndexed { index, result ->
                appendLine("    {")
                appendLine("      \"model\": \"${result.modelName}\",")
                appendLine("      \"device\": \"${result.deviceModel}\",")
                appendLine("      \"platform\": \"${result.platform}\",")
                appendLine("      \"avgTokensPerSecond\": ${result.avgTokensPerSecond},")
                appendLine("      \"avgTtftMs\": ${result.avgTtftMs},")
                appendLine("      \"avgLatencyMs\": ${result.avgLatencyMs},")
                appendLine("      \"peakMemoryMB\": ${result.peakMemoryMB}")
                appendLine("    }${if (index < results.size - 1) "," else ""}")
            }
            appendLine("  ]")
            appendLine("}")
        }
    }
    
    private fun generateHtmlReport(results: List<ResultsAggregator.AggregatedResult>): String {
        return buildString {
            appendLine("<!DOCTYPE html>")
            appendLine("<html><head><title>Benchmark Report</title>")
            appendLine("<style>")
            appendLine("body { font-family: system-ui; max-width: 1000px; margin: 0 auto; padding: 20px; }")
            appendLine("table { border-collapse: collapse; width: 100%; }")
            appendLine("th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }")
            appendLine("th { background: #f4f4f4; }")
            appendLine("</style></head><body>")
            appendLine("<h1>RunAnywhere Benchmark Report</h1>")
            appendLine("<p>Generated: ${java.time.Instant.now()}</p>")
            appendLine("<table>")
            appendLine("<tr><th>Model</th><th>Device</th><th>Tokens/sec</th><th>TTFT</th><th>Memory</th></tr>")
            
            results.forEach { result ->
                appendLine("<tr>")
                appendLine("<td>${result.modelName}</td>")
                appendLine("<td>${result.deviceModel}</td>")
                appendLine("<td>${String.format("%.1f", result.avgTokensPerSecond)}</td>")
                appendLine("<td>${String.format("%.0fms", result.avgTtftMs)}</td>")
                appendLine("<td>${String.format("%.0fMB", result.peakMemoryMB)}</td>")
                appendLine("</tr>")
            }
            
            appendLine("</table></body></html>")
        }
    }
}
