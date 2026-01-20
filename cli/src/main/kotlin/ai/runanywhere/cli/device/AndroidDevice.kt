package ai.runanywhere.cli.device

import ai.runanywhere.cli.benchmark.BenchmarkConfig
import java.nio.file.Files
import java.nio.file.Path
import kotlin.io.path.name

/**
 * Communicates with Android devices/emulators for benchmark operations
 */
class AndroidDevice(
    private val serial: String,
) {
    
    private val packageName = "com.runanywhere.runanywhereai"
    private val benchmarkActivity = "$packageName/.benchmark.BenchmarkActivity"
    
    /**
     * Launch the app with benchmark intent
     */
    fun launchBenchmark(config: BenchmarkConfig, modelIds: List<String>) {
        val configJson = config.toJsonArg()
        val modelsArg = modelIds.joinToString(",")
        
        // Launch using adb with intent extras
        ProcessBuilder(
            "adb", "-s", serial,
            "shell", "am", "start",
            "-n", "$packageName/.MainActivity",
            "--es", "benchmark_config", configJson,
            "--es", "benchmark_models", modelsArg,
            "--ez", "start_benchmark", "true"
        )
            .inheritIO()
            .start()
            .waitFor()
    }
    
    /**
     * Pull benchmark results from the device
     */
    fun pullResults(outputDir: Path): List<Path> {
        val pulledFiles = mutableListOf<Path>()
        
        // App's external files directory
        val remotePath = "/sdcard/Android/data/$packageName/files/"
        
        // Create temp directory
        val tempDir = Files.createTempDirectory("android_benchmark_")
        
        // Pull all benchmark files
        val pullProcess = ProcessBuilder(
            "adb", "-s", serial, "pull", remotePath, tempDir.toString()
        )
            .redirectErrorStream(true)
            .start()
        
        pullProcess.waitFor()
        
        // Find and copy benchmark files to output
        if (Files.exists(tempDir)) {
            Files.walk(tempDir)
                .filter { it.name.startsWith("benchmark_") && it.name.endsWith(".json") }
                .forEach { sourceFile ->
                    val destFile = outputDir.resolve("android_${serial}_${sourceFile.name}")
                    Files.copy(sourceFile, destFile)
                    pulledFiles.add(destFile)
                }
            
            // Cleanup temp directory
            tempDir.toFile().deleteRecursively()
        }
        
        // Alternative: try pulling from app's internal storage using run-as
        if (pulledFiles.isEmpty()) {
            try {
                val internalPath = "/data/data/$packageName/files/"
                
                // List files using run-as
                val listProcess = ProcessBuilder(
                    "adb", "-s", serial,
                    "shell", "run-as", packageName, "ls", internalPath
                )
                    .redirectErrorStream(true)
                    .start()
                
                val files = listProcess.inputStream.bufferedReader().readText()
                    .lines()
                    .filter { it.startsWith("benchmark_") && it.endsWith(".json") }
                
                listProcess.waitFor()
                
                files.forEach { filename ->
                    val tempFile = Files.createTempFile("benchmark_", ".json")
                    
                    // Use run-as to cat the file
                    val catProcess = ProcessBuilder(
                        "adb", "-s", serial,
                        "shell", "run-as", packageName, "cat", "$internalPath$filename"
                    )
                        .redirectErrorStream(true)
                        .start()
                    
                    val content = catProcess.inputStream.bufferedReader().readText()
                    catProcess.waitFor()
                    
                    if (content.contains("\"modelId\"")) {
                        val destFile = outputDir.resolve("android_${serial}_$filename")
                        Files.writeString(destFile, content)
                        pulledFiles.add(destFile)
                    }
                    
                    Files.deleteIfExists(tempFile)
                }
            } catch (e: Exception) {
                // run-as may not work on release builds
            }
        }
        
        return pulledFiles
    }
    
    /**
     * Check if RunAnywhereAI app is installed
     */
    fun isAppInstalled(): Boolean {
        return try {
            val result = ProcessBuilder(
                "adb", "-s", serial,
                "shell", "pm", "list", "packages", packageName
            )
                .redirectErrorStream(true)
                .start()
            
            val output = result.inputStream.bufferedReader().readText()
            result.waitFor()
            
            output.contains(packageName)
        } catch (e: Exception) {
            false
        }
    }
    
    /**
     * Clear benchmark results on device
     */
    fun clearResults() {
        // Clear external files
        ProcessBuilder(
            "adb", "-s", serial,
            "shell", "rm", "-rf",
            "/sdcard/Android/data/$packageName/files/benchmark_*.json"
        )
            .start()
            .waitFor()
    }
    
    /**
     * Get device info
     */
    fun getDeviceInfo(): Map<String, String> {
        fun getProperty(prop: String): String {
            return try {
                ProcessBuilder("adb", "-s", serial, "shell", "getprop", prop)
                    .redirectErrorStream(true)
                    .start()
                    .inputStream.bufferedReader().readText().trim()
            } catch (e: Exception) {
                ""
            }
        }
        
        return mapOf(
            "model" to getProperty("ro.product.model"),
            "manufacturer" to getProperty("ro.product.manufacturer"),
            "android_version" to getProperty("ro.build.version.release"),
            "api_level" to getProperty("ro.build.version.sdk"),
            "cpu_abi" to getProperty("ro.product.cpu.abi"),
        )
    }
}
