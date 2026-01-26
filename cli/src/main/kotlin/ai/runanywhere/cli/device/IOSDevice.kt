package ai.runanywhere.cli.device

import ai.runanywhere.cli.benchmark.BenchmarkConfig
import java.io.BufferedReader
import java.nio.file.Files
import java.nio.file.Path
import kotlin.io.path.name

/**
 * Communicates with iOS devices/simulators for benchmark operations
 */
class IOSDevice(
    private val udid: String,
    private val isSimulator: Boolean,
) {
    
    private val appBundleId = "ai.runanywhere.RunAnywhereAI"
    private var benchmarkStartTime: Long = 0
    
    /**
     * Launch app and auto-start benchmark (for CLI automation)
     */
    fun launchBenchmarkAuto(config: BenchmarkConfig, modelIds: List<String>?) {
        benchmarkStartTime = System.currentTimeMillis()
        
        // Clear previous results first
        clearPreviousResults()
        
        val configArg = config.toJsonArg()
        val modelsArg = modelIds?.joinToString(",") ?: "all"
        
        if (isSimulator) {
            // Terminate if running
            runCommand("xcrun", "simctl", "terminate", udid, appBundleId)
            Thread.sleep(500)
            
            // Launch with benchmark arguments
            ProcessBuilder(
                "xcrun", "simctl", "launch", udid,
                appBundleId,
                "-benchmark_auto", "true",
                "-benchmark_config", configArg,
                "-benchmark_models", modelsArg
            )
                .inheritIO()
                .start()
                .waitFor()
        } else {
            // For physical devices, use URL scheme
            // The app should handle: runanywhere://benchmark?auto=true&config=...
            val urlScheme = "runanywhere://benchmark?auto=true&config=$configArg&models=$modelsArg"
            ProcessBuilder(
                "xcrun", "devicectl", "device", "process", "launch",
                "--device", udid, appBundleId,
                "--argument", "-benchmark_auto", "--argument", "true"
            )
                .inheritIO()
                .start()
                .waitFor()
        }
    }
    
    /**
     * Check if benchmark has completed by looking for new result files
     */
    fun isBenchmarkComplete(): Boolean {
        if (isSimulator) {
            val containerProcess = ProcessBuilder(
                "xcrun", "simctl", "get_app_container", udid, appBundleId, "data"
            )
                .redirectErrorStream(true)
                .start()
            
            val containerPath = containerProcess.inputStream.bufferedReader().readText().trim()
            containerProcess.waitFor()
            
            if (containerPath.isNotBlank() && !containerPath.contains("error")) {
                val documentsPath = Path.of(containerPath, "Documents")
                
                if (Files.exists(documentsPath)) {
                    // Check for result files created after benchmark started
                    val newResults = Files.list(documentsPath)
                        .filter { it.name.startsWith("benchmark_") && it.name.endsWith(".json") }
                        .filter { Files.getLastModifiedTime(it).toMillis() > benchmarkStartTime }
                        .count()
                    
                    return newResults > 0
                }
            }
        }
        return false
    }
    
    /**
     * Clear previous benchmark results
     */
    private fun clearPreviousResults() {
        if (isSimulator) {
            val containerProcess = ProcessBuilder(
                "xcrun", "simctl", "get_app_container", udid, appBundleId, "data"
            )
                .redirectErrorStream(true)
                .start()
            
            val containerPath = containerProcess.inputStream.bufferedReader().readText().trim()
            containerProcess.waitFor()
            
            if (containerPath.isNotBlank() && !containerPath.contains("error")) {
                val documentsPath = Path.of(containerPath, "Documents")
                if (Files.exists(documentsPath)) {
                    Files.list(documentsPath)
                        .filter { it.name.startsWith("benchmark_") && it.name.endsWith(".json") }
                        .forEach { Files.deleteIfExists(it) }
                }
            }
        }
    }
    
    private fun runCommand(vararg args: String): String {
        val process = ProcessBuilder(*args)
            .redirectErrorStream(true)
            .start()
        val output = process.inputStream.bufferedReader().use(BufferedReader::readText)
        process.waitFor()
        return output
    }
    
    /**
     * Launch the app with benchmark intent (manual mode)
     */
    fun launchBenchmark(config: BenchmarkConfig, modelIds: List<String>) {
        // Build launch arguments
        val configJson = config.toJsonArg()
        val modelsArg = modelIds.joinToString(",")
        
        if (isSimulator) {
            // Use simctl for simulators
            ProcessBuilder(
                "xcrun", "simctl", "launch", udid,
                appBundleId,
                "--benchmark",
                "--config", configJson,
                "--models", modelsArg
            )
                .inheritIO()
                .start()
                .waitFor()
        } else {
            // Use ios-deploy or idevicedebug for physical devices
            try {
                // Try using idevicedebug (from libimobiledevice)
                ProcessBuilder(
                    "idevicedebug", "-u", udid, "run", appBundleId,
                    "--args", "--benchmark", "--config", configJson, "--models", modelsArg
                )
                    .inheritIO()
                    .start()
                    .waitFor()
            } catch (e: Exception) {
                // Fallback: just launch the app without arguments
                ProcessBuilder(
                    "idevicedebug", "-u", udid, "run", appBundleId
                )
                    .inheritIO()
                    .start()
                    .waitFor()
            }
        }
    }
    
    /**
     * Pull benchmark results from the device
     */
    fun pullResults(outputDir: Path): List<Path> {
        val pulledFiles = mutableListOf<Path>()
        
        if (isSimulator) {
            // Get app container for simulator
            val containerProcess = ProcessBuilder(
                "xcrun", "simctl", "get_app_container", udid, appBundleId, "data"
            )
                .redirectErrorStream(true)
                .start()
            
            val containerPath = containerProcess.inputStream.bufferedReader().readText().trim()
            containerProcess.waitFor()
            
            if (containerPath.isNotBlank() && !containerPath.contains("error")) {
                val documentsPath = Path.of(containerPath, "Documents")
                
                if (Files.exists(documentsPath)) {
                    Files.list(documentsPath)
                        .filter { it.name.startsWith("benchmark_") && it.name.endsWith(".json") }
                        .forEach { sourceFile ->
                            val destFile = outputDir.resolve("ios_sim_${sourceFile.name}")
                            Files.copy(sourceFile, destFile)
                            pulledFiles.add(destFile)
                        }
                }
            }
        } else {
            // For physical devices, use idevice tools
            try {
                // Create temp directory for files
                val tempDir = Files.createTempDirectory("ios_benchmark_")
                
                // Use ifuse or idevicebackup to access app documents
                // This is complex and may require the app to share files
                // Alternative: Use AFC (Apple File Conduit)
                
                ProcessBuilder(
                    "ideviceinstaller", "-u", udid, 
                    "--list-apps", "--key", "CFBundleIdentifier"
                )
                    .start()
                    .waitFor()
                
                // Note: For physical devices, the app should expose results
                // via a shared container or use AirDrop/share extension
                
                println("  Note: For physical iOS devices, export results from the app")
                println("  App → Benchmark → Export Results")
                
            } catch (e: Exception) {
                println("  Could not access physical device files: ${e.message}")
            }
        }
        
        return pulledFiles
    }
    
    /**
     * Check if RunAnywhereAI app is installed
     */
    fun isAppInstalled(): Boolean {
        return try {
            if (isSimulator) {
                val result = ProcessBuilder(
                    "xcrun", "simctl", "get_app_container", udid, appBundleId
                )
                    .redirectErrorStream(true)
                    .start()
                    .waitFor()
                result == 0
            } else {
                val result = ProcessBuilder(
                    "ideviceinstaller", "-u", udid, "-l"
                )
                    .redirectErrorStream(true)
                    .start()
                
                val output = result.inputStream.bufferedReader().readText()
                result.waitFor()
                output.contains(appBundleId)
            }
        } catch (e: Exception) {
            false
        }
    }
}
