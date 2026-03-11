package com.runanywhere.runanywhereai.services

import android.content.Context
import com.runanywhere.runanywhereai.models.BenchmarkRun
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File

/**
 * JSON file persistence for benchmark runs in internal storage.
 */
class BenchmarkStore(private val context: Context) {

    private val json = Json {
        prettyPrint = true
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    private val file: File
        get() = File(context.filesDir, FILE_NAME)

    fun loadRuns(): List<BenchmarkRun> {
        if (!file.exists()) return emptyList()
        return try {
            val text = file.readText()
            json.decodeFromString<List<BenchmarkRun>>(text)
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun save(run: BenchmarkRun) {
        val runs = loadRuns().toMutableList()
        runs.add(run)
        val trimmed = if (runs.size > MAX_RUNS) runs.takeLast(MAX_RUNS) else runs
        try {
            file.writeText(json.encodeToString(trimmed))
        } catch (_: Exception) {
            // Best-effort persistence
        }
    }

    fun clearAll() {
        file.delete()
    }

    companion object {
        private const val FILE_NAME = "benchmarks.json"
        private const val MAX_RUNS = 50
    }
}
