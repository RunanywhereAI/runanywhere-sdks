package ai.runanywhere.cli.benchmark

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File

/**
 * Aggregates and compares benchmark results from multiple files
 */
class ResultsAggregator {
    
    private val json = Json { 
        ignoreUnknownKeys = true 
        isLenient = true
    }
    
    /**
     * Load results from multiple files and return aggregated data
     */
    fun loadAndCompare(files: List<File>): List<AggregatedResult> {
        val allResults = mutableListOf<AggregatedResult>()
        
        files.forEach { file ->
            try {
                val content = file.readText()
                val results = parseResults(content, file.name)
                allResults.addAll(results)
            } catch (e: Exception) {
                println("Warning: Could not parse ${file.name}: ${e.message}")
            }
        }
        
        return allResults
    }
    
    private fun parseResults(content: String, filename: String): List<AggregatedResult> {
        val results = mutableListOf<AggregatedResult>()
        
        try {
            // Try parsing as BenchmarkExport (array wrapper)
            val export = json.decodeFromString<BenchmarkExportDto>(content)
            export.results.forEach { result ->
                results.add(mapToAggregatedResult(result, filename))
            }
        } catch (e: Exception) {
            try {
                // Try parsing as single BenchmarkResult
                val result = json.decodeFromString<BenchmarkResultDto>(content)
                results.add(mapToAggregatedResult(result, filename))
            } catch (e2: Exception) {
                try {
                    // Try parsing as array of BenchmarkResult
                    val resultList = json.decodeFromString<List<BenchmarkResultDto>>(content)
                    resultList.forEach { result ->
                        results.add(mapToAggregatedResult(result, filename))
                    }
                } catch (e3: Exception) {
                    // Could not parse
                }
            }
        }
        
        return results
    }
    
    private fun mapToAggregatedResult(dto: BenchmarkResultDto, sourceFile: String): AggregatedResult {
        // Determine platform from filename or device info
        val platform = when {
            sourceFile.contains("ios", ignoreCase = true) -> "iOS"
            sourceFile.contains("android", ignoreCase = true) -> "Android"
            dto.osVersion.contains("iOS", ignoreCase = true) -> "iOS"
            dto.osVersion.contains("Android", ignoreCase = true) -> "Android"
            else -> "Unknown"
        }
        
        return AggregatedResult(
            modelId = dto.modelId,
            modelName = dto.modelName,
            framework = dto.framework,
            deviceModel = dto.deviceModel,
            osVersion = dto.osVersion,
            platform = platform,
            avgTokensPerSecond = dto.avgTokensPerSecond,
            p50TokensPerSecond = dto.p50TokensPerSecond,
            p95TokensPerSecond = dto.p95TokensPerSecond,
            minTokensPerSecond = dto.minTokensPerSecond,
            maxTokensPerSecond = dto.maxTokensPerSecond,
            avgTtftMs = dto.avgTtftMs,
            avgLatencyMs = dto.avgLatencyMs,
            peakMemoryMB = dto.peakMemoryBytes / 1024.0 / 1024.0,
            modelLoadTimeMs = dto.modelLoadTimeMs,
            totalRuns = dto.totalRuns,
            timestamp = dto.timestamp,
            gitCommit = dto.gitCommit,
            sourceFile = sourceFile
        )
    }
    
    /**
     * Aggregated result for comparison
     */
    data class AggregatedResult(
        val modelId: String,
        val modelName: String,
        val framework: String,
        val deviceModel: String,
        val osVersion: String,
        val platform: String,
        val avgTokensPerSecond: Double,
        val p50TokensPerSecond: Double,
        val p95TokensPerSecond: Double,
        val minTokensPerSecond: Double,
        val maxTokensPerSecond: Double,
        val avgTtftMs: Double,
        val avgLatencyMs: Double,
        val peakMemoryMB: Double,
        val modelLoadTimeMs: Double,
        val totalRuns: Int,
        val timestamp: Long,
        val gitCommit: String?,
        val sourceFile: String,
    )
}

// DTOs for parsing JSON results

@Serializable
data class BenchmarkExportDto(
    val exportVersion: String = "",
    val exportedAt: Long = 0,
    val results: List<BenchmarkResultDto> = emptyList(),
)

@Serializable
data class BenchmarkResultDto(
    val id: String = "",
    val modelId: String = "",
    val modelName: String = "",
    val framework: String = "",
    val deviceId: String = "",
    val deviceModel: String = "",
    val osVersion: String = "",
    val sdkVersion: String = "",
    val gitCommit: String? = null,
    val timestamp: Long = 0,
    val modelLoadTimeMs: Double = 0.0,
    val avgTokensPerSecond: Double = 0.0,
    val p50TokensPerSecond: Double = 0.0,
    val p95TokensPerSecond: Double = 0.0,
    val minTokensPerSecond: Double = 0.0,
    val maxTokensPerSecond: Double = 0.0,
    val avgTtftMs: Double = 0.0,
    val p50TtftMs: Double = 0.0,
    val p95TtftMs: Double = 0.0,
    val avgLatencyMs: Double = 0.0,
    val p50LatencyMs: Double = 0.0,
    val p95LatencyMs: Double = 0.0,
    val peakMemoryBytes: Long = 0,
    val totalRuns: Int = 0,
)
