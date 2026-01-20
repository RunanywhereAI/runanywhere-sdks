package ai.runanywhere.cli.commands

import ai.runanywhere.cli.benchmark.BenchmarkConfig
import ai.runanywhere.cli.benchmark.ResultsAggregator
import ai.runanywhere.cli.device.AndroidDevice
import ai.runanywhere.cli.device.DeviceManager
import ai.runanywhere.cli.device.IOSDevice
import com.github.ajalt.clikt.core.CliktCommand
import com.github.ajalt.clikt.parameters.options.default
import com.github.ajalt.clikt.parameters.options.flag
import com.github.ajalt.clikt.parameters.options.option
import com.github.ajalt.clikt.parameters.types.choice
import com.github.ajalt.clikt.parameters.types.int
import com.github.ajalt.mordant.animation.progressAnimation
import com.github.ajalt.mordant.rendering.TextColors.*
import com.github.ajalt.mordant.rendering.TextStyles.*
import com.github.ajalt.mordant.table.table
import com.github.ajalt.mordant.terminal.Terminal
import java.io.File
import java.nio.file.Files
import kotlin.io.path.name

/**
 * Fully automated benchmark command
 * 
 * Usage:
 *   runanywhere benchmark auto                    # Auto-detect device and run
 *   runanywhere benchmark auto --models=smollm2   # Specific models
 *   runanywhere benchmark auto --config=quick     # Quick benchmark
 */
class BenchmarkAutoCommand : CliktCommand(
    name = "auto",
    help = """
        🚀 Fully automated benchmark - just plug in your phone!
        
        This command will:
        1. Detect your connected device (iOS or Android)
        2. Launch the RunAnywhereAI app
        3. Automatically start the benchmark
        4. Wait for completion and pull results
        5. Display a beautiful report
        
        Examples:
          runanywhere benchmark auto
          runanywhere benchmark auto --config=quick
          runanywhere benchmark auto --models=smollm2-360m,qwen-0.5b
    """.trimIndent()
) {
    private val config by option(
        "--config", "-c",
        help = "Benchmark configuration: quick (fast), default (balanced), comprehensive (thorough)"
    ).choice("quick", "default", "comprehensive").default("default")
    
    private val models by option(
        "--models", "-m",
        help = "Comma-separated list of model IDs (default: all downloaded models)"
    )
    
    private val timeout by option(
        "--timeout", "-t",
        help = "Maximum time to wait for benchmark completion (seconds)"
    ).int().default(600) // 10 minutes default
    
    private val outputDir by option(
        "--output", "-o",
        help = "Directory to save results"
    ).default("benchmark_results")
    
    private val keepOpen by option(
        "--keep-open",
        help = "Keep the app open after benchmark completes"
    ).flag()
    
    private val terminal = Terminal()
    
    override fun run() {
        printBanner()
        
        // Step 1: Detect devices
        terminal.println()
        terminal.println(cyan("📱 Step 1: Detecting devices..."))
        
        val deviceManager = DeviceManager()
        val iosDevices = deviceManager.listIOSDevices()
        val androidDevices = deviceManager.listAndroidDevices()
        
        if (iosDevices.isEmpty() && androidDevices.isEmpty()) {
            terminal.println()
            terminal.println(red("❌ No devices found!"))
            terminal.println()
            terminal.println(yellow("Please connect a device:"))
            terminal.println("  • ${white("iOS")}: Connect iPhone/iPad via USB, or boot a Simulator")
            terminal.println("  • ${white("Android")}: Connect device via USB with USB debugging enabled")
            terminal.println()
            terminal.println(gray("Run 'runanywhere benchmark devices' to check connection status"))
            return
        }
        
        // Show detected devices
        terminal.println(green("✓ Found ${iosDevices.size + androidDevices.size} device(s):"))
        iosDevices.forEach { device ->
            terminal.println("  📱 ${cyan(device.name)} (iOS ${device.osVersion})")
        }
        androidDevices.forEach { device ->
            terminal.println("  🤖 ${cyan(device.model)} (Android API ${device.apiLevel})")
        }
        
        // Step 2: Run benchmarks
        val benchmarkConfig = when (config) {
            "quick" -> BenchmarkConfig.QUICK
            "comprehensive" -> BenchmarkConfig.COMPREHENSIVE
            else -> BenchmarkConfig.DEFAULT
        }
        
        val modelList = models?.split(",")?.map { it.trim() }
        
        terminal.println()
        terminal.println(cyan("⚙️  Step 2: Starting benchmarks..."))
        terminal.println("   Config: ${white(config)}")
        terminal.println("   Models: ${white(modelList?.joinToString(", ") ?: "all downloaded")}")
        terminal.println()
        
        val allResults = mutableListOf<ResultsAggregator.AggregatedResult>()
        
        // Run on iOS devices
        iosDevices.forEach { device ->
            terminal.println(cyan("▶ Running on ${device.name}..."))
            
            val iosDevice = IOSDevice(device.udid, device.isSimulator)
            
            // Launch app with benchmark arguments
            iosDevice.launchBenchmarkAuto(benchmarkConfig, modelList)
            
            // Wait for completion
            val success = waitForCompletion(
                deviceName = device.name,
                checkCompletion = { iosDevice.isBenchmarkComplete() },
                timeoutSeconds = timeout
            )
            
            if (success) {
                // Pull results
                val outputPath = File(outputDir).toPath()
                Files.createDirectories(outputPath)
                
                val files = iosDevice.pullResults(outputPath)
                terminal.println(green("   ✓ Pulled ${files.size} result file(s)"))
                
                // Load and add to results
                val aggregator = ResultsAggregator()
                files.forEach { file ->
                    allResults.addAll(aggregator.loadAndCompare(listOf(file.toFile())))
                }
            }
        }
        
        // Run on Android devices
        androidDevices.forEach { device ->
            terminal.println(cyan("▶ Running on ${device.model}..."))
            
            val androidDevice = AndroidDevice(device.serial)
            
            // Launch app with benchmark arguments
            androidDevice.launchBenchmarkAuto(benchmarkConfig, modelList)
            
            // Wait for completion
            val success = waitForCompletion(
                deviceName = device.model,
                checkCompletion = { androidDevice.isBenchmarkComplete() },
                timeoutSeconds = timeout
            )
            
            if (success) {
                // Pull results
                val outputPath = File(outputDir).toPath()
                Files.createDirectories(outputPath)
                
                val files = androidDevice.pullResults(outputPath)
                terminal.println(green("   ✓ Pulled ${files.size} result file(s)"))
                
                // Load and add to results
                val aggregator = ResultsAggregator()
                files.forEach { file ->
                    allResults.addAll(aggregator.loadAndCompare(listOf(file.toFile())))
                }
            }
        }
        
        // Step 3: Show results
        terminal.println()
        terminal.println(cyan("📊 Step 3: Results"))
        terminal.println()
        
        if (allResults.isEmpty()) {
            terminal.println(yellow("⚠ No benchmark results collected"))
            terminal.println(gray("  Make sure you have models downloaded in the app"))
            return
        }
        
        printResultsTable(allResults)
        
        // Save summary
        terminal.println()
        terminal.println(green("✓ Results saved to: ${File(outputDir).absolutePath}"))
    }
    
    private fun printBanner() {
        terminal.println()
        terminal.println(cyan("╔═══════════════════════════════════════════════════════════╗"))
        terminal.println(cyan("║") + bold(white("        RunAnywhere Automated Benchmark                    ")) + cyan("║"))
        terminal.println(cyan("║") + gray("        Just plug in your phone and run!                   ") + cyan("║"))
        terminal.println(cyan("╚═══════════════════════════════════════════════════════════╝"))
    }
    
    private fun waitForCompletion(
        deviceName: String,
        checkCompletion: () -> Boolean,
        timeoutSeconds: Int
    ): Boolean {
        val startTime = System.currentTimeMillis()
        val timeoutMs = timeoutSeconds * 1000L
        
        var dots = 0
        while (System.currentTimeMillis() - startTime < timeoutMs) {
            if (checkCompletion()) {
                terminal.println()
                return true
            }
            
            // Show progress
            dots = (dots + 1) % 4
            val elapsed = (System.currentTimeMillis() - startTime) / 1000
            print("\r   ⏳ Waiting for benchmark to complete${".".repeat(dots)}${" ".repeat(3 - dots)} (${elapsed}s)")
            
            Thread.sleep(2000) // Check every 2 seconds
        }
        
        terminal.println()
        terminal.println(yellow("   ⚠ Timeout waiting for $deviceName"))
        return false
    }
    
    private fun printResultsTable(results: List<ResultsAggregator.AggregatedResult>) {
        terminal.println(table {
            header {
                row {
                    cell(white("Model"))
                    cell(white("Device"))
                    cell(white("Tokens/s"))
                    cell(white("TTFT"))
                    cell(white("Memory"))
                }
            }
            body {
                results.forEach { result ->
                    row {
                        cell(cyan(result.modelName))
                        cell(gray(result.deviceModel.take(15)))
                        cell(
                            if (result.avgTokensPerSecond > 30) green("${String.format("%.1f", result.avgTokensPerSecond)}")
                            else yellow("${String.format("%.1f", result.avgTokensPerSecond)}")
                        )
                        cell("${String.format("%.0f", result.avgTtftMs)}ms")
                        cell("${String.format("%.0f", result.peakMemoryMB)}MB")
                    }
                }
            }
        })
        
        // Performance comparison bar chart
        terminal.println()
        terminal.println(white("Performance Comparison (tokens/sec):"))
        terminal.println()
        
        val maxTps = results.maxOfOrNull { it.avgTokensPerSecond } ?: 1.0
        results.forEach { result ->
            val barLength = ((result.avgTokensPerSecond / maxTps) * 40).toInt()
            val bar = "█".repeat(barLength)
            val label = "${result.modelName} (${result.platform})"
            terminal.println("  ${label.padEnd(30)} ${green(bar)} ${String.format("%.1f", result.avgTokensPerSecond)}")
        }
    }
}
