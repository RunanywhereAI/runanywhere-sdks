package com.runanywhere.runanywhereai.benchmark

import android.content.Context
import android.os.Build
import android.os.Debug
import android.util.Log
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.LLM.LLMGenerationOptions
import com.runanywhere.sdk.public.extensions.availableModels
import com.runanywhere.sdk.public.extensions.generate
import com.runanywhere.sdk.public.extensions.loadLLMModel
import com.runanywhere.sdk.public.extensions.unloadLLMModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

/**
 * Service for running model benchmarks and collecting metrics
 */
class BenchmarkService(
    private val context: Context,
) {
    // MARK: - State
    
    private val _state = MutableStateFlow<BenchmarkState>(BenchmarkState.Idle)
    val state: StateFlow<BenchmarkState> = _state.asStateFlow()
    
    private val _progress = MutableStateFlow<BenchmarkProgress?>(null)
    val progress: StateFlow<BenchmarkProgress?> = _progress.asStateFlow()
    
    private val _results = MutableStateFlow<List<BenchmarkResult>>(emptyList())
    val results: StateFlow<List<BenchmarkResult>> = _results.asStateFlow()
    
    private val _error = MutableStateFlow<Throwable?>(null)
    val error: StateFlow<Throwable?> = _error.asStateFlow()
    
    // MARK: - Private State
    
    private var startTimeMs: Long = 0
    private var peakMemoryBytes: Long = 0
    
    private val json = Json {
        prettyPrint = true
        encodeDefaults = true
    }
    
    // MARK: - Public Methods
    
    /**
     * Run LLM benchmarks on the specified models
     */
    suspend fun runLLMBenchmark(
        modelIds: List<String>,
        config: BenchmarkConfig = BenchmarkConfig.DEFAULT,
    ): List<BenchmarkResult> = withContext(Dispatchers.Default) {
        if (_state.value.isRunning) {
            throw BenchmarkException.AlreadyRunning
        }
        
        _state.value = BenchmarkState.Preparing
        startTimeMs = System.currentTimeMillis()
        _results.value = emptyList()
        _error.value = null
        
        val allResults = mutableListOf<BenchmarkResult>()
        
        try {
            modelIds.forEachIndexed { modelIndex, modelId ->
                val result = benchmarkSingleModel(
                    modelId = modelId,
                    modelIndex = modelIndex,
                    totalModels = modelIds.size,
                    config = config
                )
                allResults.add(result)
                _results.value = allResults.toList()
            }
            
            _state.value = BenchmarkState.Completed
            
            // Export results to file
            exportResults(allResults)
            
            Log.i(TAG, "Benchmark completed: ${allResults.size} models tested")
            allResults
            
        } catch (e: Exception) {
            _state.value = BenchmarkState.Failed(e.message ?: "Unknown error")
            _error.value = e
            throw e
        }
    }
    
    /**
     * Cancel the current benchmark
     */
    fun cancel() {
        _state.value = BenchmarkState.Idle
        Log.i(TAG, "Benchmark cancelled")
    }
    
    /**
     * Clear results
     */
    fun clearResults() {
        _results.value = emptyList()
        _state.value = BenchmarkState.Idle
        _error.value = null
    }
    
    // MARK: - Private Methods
    
    private suspend fun benchmarkSingleModel(
        modelId: String,
        modelIndex: Int,
        totalModels: Int,
        config: BenchmarkConfig,
    ): BenchmarkResult {
        Log.i(TAG, "Starting benchmark for model: $modelId")
        
        // Get model info
        val modelInfo = RunAnywhere.availableModels().firstOrNull { it.id == modelId }
            ?: throw BenchmarkException.ModelNotFound(modelId)
        
        // Load model and measure load time
        val loadStart = System.nanoTime()
        RunAnywhere.loadLLMModel(modelId)
        val loadTimeMs = (System.nanoTime() - loadStart) / 1_000_000.0
        
        Log.i(TAG, "Model loaded in ${loadTimeMs}ms")
        
        // Reset peak memory tracking
        peakMemoryBytes = 0
        
        // Warmup phase
        for (i in 0 until config.warmupIterations) {
            _state.value = BenchmarkState.WarmingUp(
                model = modelInfo.name,
                iteration = i + 1,
                total = config.warmupIterations
            )
            updateProgress(modelIndex, totalModels)
            
            runSingleInference(
                prompt = config.prompts.first(),
                maxTokens = config.maxTokensList.first()
            )
        }
        
        // Benchmark runs
        val runResults = mutableListOf<SingleRunResult>()
        val totalRuns = config.prompts.size * config.maxTokensList.size * config.testIterations
        var currentRun = 0
        
        for (prompt in config.prompts) {
            for (maxTokens in config.maxTokensList) {
                repeat(config.testIterations) {
                    currentRun++
                    _state.value = BenchmarkState.Running(
                        model = modelInfo.name,
                        prompt = prompt.id,
                        iteration = currentRun,
                        total = totalRuns
                    )
                    updateProgress(modelIndex, totalModels)
                    
                    val result = runSingleInference(prompt, maxTokens)
                    runResults.add(result)
                    
                    // Track peak memory
                    val currentMemory = getMemoryUsage()
                    if (currentMemory > peakMemoryBytes) {
                        peakMemoryBytes = currentMemory
                    }
                }
            }
        }
        
        // Unload model
        RunAnywhere.unloadLLMModel()
        
        // Aggregate results
        val aggregatedResult = aggregateResults(
            runResults = runResults,
            modelInfo = modelInfo,
            loadTimeMs = loadTimeMs,
            config = config
        )
        
        Log.i(TAG, "Benchmark completed for $modelId: ${aggregatedResult.avgTokensPerSecond} tok/s")
        
        return aggregatedResult
    }
    
    private suspend fun runSingleInference(
        prompt: BenchmarkPrompt,
        maxTokens: Int,
    ): SingleRunResult {
        val options = LLMGenerationOptions(
            maxTokens = maxTokens,
            temperature = 0.7f
        )
        
        val result = RunAnywhere.generate(prompt.text, options)
        
        return SingleRunResult(
            promptId = prompt.id,
            maxTokens = maxTokens,
            tokensPerSecond = result.tokensPerSecond,
            latencyMs = result.latencyMs,
            ttftMs = result.timeToFirstTokenMs,
            outputTokens = result.tokensUsed,
            inputTokens = result.inputTokens,
            timestamp = System.currentTimeMillis()
        )
    }
    
    private fun aggregateResults(
        runResults: List<SingleRunResult>,
        modelInfo: com.runanywhere.sdk.public.extensions.Models.ModelInfo,
        loadTimeMs: Double,
        config: BenchmarkConfig,
    ): BenchmarkResult {
        val tokensPerSecondValues = runResults.map { it.tokensPerSecond }
        val latencyValues = runResults.map { it.latencyMs }
        val ttftValues = runResults.mapNotNull { it.ttftMs }
        
        // Group by prompt for per-prompt stats
        val promptGroups = runResults.groupBy { it.promptId }
        val promptResults = promptGroups.map { (promptId, results) ->
            val prompt = config.prompts.firstOrNull { it.id == promptId }
            PromptAggregatedResult(
                promptId = promptId,
                promptCategory = prompt?.category?.name ?: "unknown",
                avgTokensPerSecond = results.map { it.tokensPerSecond }.average(),
                avgLatencyMs = results.map { it.latencyMs }.average(),
                avgTtftMs = results.mapNotNull { it.ttftMs }.averageOrZero(),
                runCount = results.size
            )
        }
        
        return BenchmarkResult(
            id = UUID.randomUUID().toString(),
            modelId = modelInfo.id,
            modelName = modelInfo.name,
            framework = modelInfo.framework.name,
            deviceId = getDeviceId(),
            deviceModel = getDeviceModel(),
            osVersion = getOSVersion(),
            sdkVersion = RunAnywhere.version,
            gitCommit = getGitCommit(),
            timestamp = System.currentTimeMillis(),
            modelLoadTimeMs = loadTimeMs,
            avgTokensPerSecond = tokensPerSecondValues.average(),
            p50TokensPerSecond = tokensPerSecondValues.percentile(50),
            p95TokensPerSecond = tokensPerSecondValues.percentile(95),
            minTokensPerSecond = tokensPerSecondValues.minOrNull() ?: 0.0,
            maxTokensPerSecond = tokensPerSecondValues.maxOrNull() ?: 0.0,
            avgTtftMs = ttftValues.averageOrZero(),
            p50TtftMs = ttftValues.percentile(50),
            p95TtftMs = ttftValues.percentile(95),
            avgLatencyMs = latencyValues.average(),
            p50LatencyMs = latencyValues.percentile(50),
            p95LatencyMs = latencyValues.percentile(95),
            peakMemoryBytes = peakMemoryBytes,
            totalRuns = runResults.size,
            promptResults = promptResults,
            config = config
        )
    }
    
    private fun updateProgress(modelIndex: Int, totalModels: Int) {
        val elapsed = System.currentTimeMillis() - startTimeMs
        val overallProgress: Float = when (val currentState = _state.value) {
            is BenchmarkState.WarmingUp -> {
                val warmupProgress = currentState.iteration.toFloat() / currentState.total
                (modelIndex + warmupProgress * 0.2f) / totalModels
            }
            is BenchmarkState.Running -> {
                val runProgress = currentState.iteration.toFloat() / currentState.total
                (modelIndex + 0.2f + runProgress * 0.8f) / totalModels
            }
            else -> modelIndex.toFloat() / totalModels
        }
        
        val estimatedRemaining: Long? = if (overallProgress > 0.1f) {
            ((elapsed / overallProgress) * (1 - overallProgress)).toLong()
        } else {
            null
        }
        
        _progress.value = BenchmarkProgress(
            state = _state.value,
            overallProgress = overallProgress,
            currentModelIndex = modelIndex,
            totalModels = totalModels,
            elapsedTimeMs = elapsed,
            estimatedRemainingTimeMs = estimatedRemaining
        )
    }
    
    private fun exportResults(results: List<BenchmarkResult>) {
        try {
            val export = BenchmarkExport(results = results)
            val jsonString = json.encodeToString(export)
            
            val dateFormat = SimpleDateFormat("yyyy-MM-dd'T'HH-mm-ss", Locale.US)
            val timestamp = dateFormat.format(Date())
            val filename = "benchmark_$timestamp.json"
            
            val file = File(context.getExternalFilesDir(null), filename)
            file.writeText(jsonString)
            
            Log.i(TAG, "Benchmark results exported to: ${file.absolutePath}")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to export results", e)
        }
    }
    
    // MARK: - Device Info Helpers
    
    private fun getDeviceId(): String {
        return android.provider.Settings.Secure.getString(
            context.contentResolver,
            android.provider.Settings.Secure.ANDROID_ID
        ) ?: "unknown"
    }
    
    private fun getDeviceModel(): String {
        return "${Build.MANUFACTURER} ${Build.MODEL}"
    }
    
    private fun getOSVersion(): String {
        return "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})"
    }
    
    private fun getGitCommit(): String? {
        return try {
            context.packageManager.getApplicationInfo(
                context.packageName,
                android.content.pm.PackageManager.GET_META_DATA
            ).metaData?.getString("GIT_COMMIT")
        } catch (e: Exception) {
            null
        }
    }
    
    private fun getMemoryUsage(): Long {
        return Debug.getNativeHeapAllocatedSize()
    }
    
    companion object {
        private const val TAG = "BenchmarkService"
    }
}

// MARK: - Exceptions

sealed class BenchmarkException(message: String) : Exception(message) {
    data object AlreadyRunning : BenchmarkException("A benchmark is already running")
    data class ModelNotFound(val modelId: String) : BenchmarkException("Model not found: $modelId")
    data class InferenceError(val details: String) : BenchmarkException("Inference error: $details")
}

// MARK: - List Extensions for Statistics

private fun List<Double>.averageOrZero(): Double {
    return if (isEmpty()) 0.0 else average()
}

private fun List<Double>.percentile(p: Int): Double {
    if (isEmpty()) return 0.0
    val sorted = sorted()
    val index = ((size - 1) * p / 100.0).toInt()
    return sorted[minOf(index, size - 1)]
}
