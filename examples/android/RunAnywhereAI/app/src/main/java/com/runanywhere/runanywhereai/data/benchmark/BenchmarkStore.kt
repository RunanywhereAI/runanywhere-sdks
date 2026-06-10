package com.runanywhere.runanywhereai.data.benchmark

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import java.io.File

// Persists benchmark runs to filesDir/benchmarks.json, newest first, capped at MAX_RUNS.
object BenchmarkStore {
    private const val FILE = "benchmarks.json"
    private const val MAX_RUNS = 50

    private val json = Json { ignoreUnknownKeys = true }
    private val serializer = ListSerializer(BenchmarkRun.serializer())
    private var file: File? = null

    var runs: List<BenchmarkRun> by mutableStateOf(emptyList())
        private set

    fun initialize(context: Context) {
        if (file != null) return
        file = File(context.filesDir, FILE)
        runs = runCatching {
            file?.takeIf { it.exists() }?.readText()?.let { json.decodeFromString(serializer, it) }
        }.getOrNull().orEmpty()
    }

    fun save(run: BenchmarkRun) {
        runs = (listOf(run) + runs).take(MAX_RUNS)
        persist()
    }

    fun delete(id: String) {
        runs = runs.filterNot { it.id == id }
        persist()
    }

    fun find(id: String): BenchmarkRun? = runs.firstOrNull { it.id == id }

    private fun persist() {
        runCatching { file?.writeText(json.encodeToString(serializer, runs)) }
    }
}
