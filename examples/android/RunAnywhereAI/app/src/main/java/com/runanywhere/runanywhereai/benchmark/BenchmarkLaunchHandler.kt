package com.runanywhere.runanywhereai.benchmark

import android.content.Intent
import android.util.Log
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.json.Json

/**
 * Handles auto-launch benchmark from CLI
 * When launched with benchmark_auto=true intent extra, automatically starts benchmarking
 */
object BenchmarkLaunchHandler {
    
    private const val TAG = "BenchmarkLaunchHandler"
    
    private val _shouldAutoStart = MutableStateFlow(false)
    val shouldAutoStart: StateFlow<Boolean> = _shouldAutoStart.asStateFlow()
    
    private val _autoConfig = MutableStateFlow<BenchmarkConfig?>(null)
    val autoConfig: StateFlow<BenchmarkConfig?> = _autoConfig.asStateFlow()
    
    private val _autoModelIds = MutableStateFlow<List<String>?>(null)
    val autoModelIds: StateFlow<List<String>?> = _autoModelIds.asStateFlow()
    
    private val json = Json { ignoreUnknownKeys = true }
    
    /**
     * Check intent for benchmark launch arguments
     * Call this from MainActivity.onCreate()
     */
    fun checkIntent(intent: Intent?) {
        if (intent == null) return
        
        val autoBenchmark = intent.getBooleanExtra("benchmark_auto", false)
        
        if (autoBenchmark) {
            _shouldAutoStart.value = true
            
            // Parse config
            val configStr = intent.getStringExtra("benchmark_config")
            _autoConfig.value = parseConfig(configStr)
            
            // Parse models
            val modelsStr = intent.getStringExtra("benchmark_models")
            if (modelsStr != null && modelsStr != "all") {
                _autoModelIds.value = modelsStr.split(",").map { it.trim() }
            }
            
            Log.i(TAG, "🚀 Auto-benchmark mode activated")
            Log.i(TAG, "   Config: ${_autoConfig.value?.warmupIterations} warmups, ${_autoConfig.value?.testIterations} iterations")
            Log.i(TAG, "   Models: ${_autoModelIds.value?.joinToString(", ") ?: "all"}")
        }
    }
    
    /**
     * Reset after benchmark completes
     */
    fun reset() {
        _shouldAutoStart.value = false
        _autoConfig.value = null
        _autoModelIds.value = null
    }
    
    private fun parseConfig(configStr: String?): BenchmarkConfig {
        if (configStr == null) return BenchmarkConfig.DEFAULT
        
        // Try JSON parsing
        try {
            if (configStr.contains("warmupIterations")) {
                return json.decodeFromString<BenchmarkConfig>(configStr)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse config JSON: ${e.message}")
        }
        
        // Check for preset names
        return when (configStr.lowercase()) {
            "quick" -> BenchmarkConfig.QUICK
            "comprehensive" -> BenchmarkConfig.COMPREHENSIVE
            else -> BenchmarkConfig.DEFAULT
        }
    }
}
