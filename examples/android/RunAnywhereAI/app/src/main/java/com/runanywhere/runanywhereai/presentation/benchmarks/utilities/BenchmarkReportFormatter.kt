package com.runanywhere.runanywhereai.presentation.benchmarks.utilities

import android.content.Context
import android.text.format.Formatter
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkCategory
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkRun
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

// -- Export Format --

enum class BenchmarkExportFormat(val displayName: String) {
    MARKDOWN("Markdown"),
    JSON("JSON"),
}

/**
 * Formats benchmark runs as Markdown, JSON, or CSV for export.
 * Matches iOS BenchmarkReportFormatter exactly.
 */
object BenchmarkReportFormatter {

    private val json = Json {
        prettyPrint = true
        encodeDefaults = true
    }

    private val dateFormat: DateTimeFormatter =
        DateTimeFormatter.ofPattern("MMM d, yyyy h:mm a").withZone(ZoneId.systemDefault())

    // -- Clipboard String --

    fun formattedString(
        run: BenchmarkRun,
        format: BenchmarkExportFormat,
        context: Context,
    ): String = when (format) {
        BenchmarkExportFormat.MARKDOWN -> formatMarkdown(run, context)
        BenchmarkExportFormat.JSON -> formatJSON(run)
    }

    // -- Markdown --

    fun formatMarkdown(run: BenchmarkRun, context: Context): String {
        val lines = mutableListOf<String>()
        lines.add("# Benchmark Report")
        lines.add("")
        lines.add("**Device:** ${run.deviceInfo.modelName}")
        lines.add("**Chip:** ${run.deviceInfo.chipName}")
        lines.add("**RAM:** ${Formatter.formatFileSize(context, run.deviceInfo.totalMemoryBytes)}")
        lines.add("**OS:** ${run.deviceInfo.osVersion}")
        lines.add("**Date:** ${dateFormat.format(Instant.ofEpochMilli(run.startedAt))}")
        run.durationSeconds?.let {
            lines.add("**Duration:** ${"%.1f".format(it)}s")
        }
        lines.add("**Status:** ${run.status.value}")
        lines.add("")

        val successCount = run.results.count { it.metrics.didSucceed }
        val failCount = run.results.size - successCount
        lines.add("**Results:** ${run.results.size} total, $successCount passed, $failCount failed")
        lines.add("")

        val grouped = run.results.groupBy { it.category }
        for (category in BenchmarkCategory.entries) {
            val results = grouped[category] ?: continue
            if (results.isEmpty()) continue
            lines.add("## ${category.displayName}")
            lines.add("")
            for (result in results) {
                val m = result.metrics
                lines.add("### ${result.scenario.name} — ${result.modelInfo.name}")
                lines.add("- Framework: ${result.modelInfo.framework}")
                if (!m.didSucceed) {
                    lines.add("- **Error:** ${m.errorMessage ?: "Unknown"}")
                } else {
                    lines.add("- Load: ${"%.0f".format(m.loadTimeMs)}ms")
                    if (m.warmupTimeMs > 0) {
                        lines.add("- Warmup: ${"%.0f".format(m.warmupTimeMs)}ms")
                    }
                    lines.add("- End-to-end: ${"%.0f".format(m.endToEndLatencyMs)}ms")
                    m.tokensPerSecond?.let { lines.add("- Tokens/s: ${"%.1f".format(it)}") }
                    m.ttftMs?.let { lines.add("- TTFT: ${"%.0f".format(it)}ms") }
                    m.inputTokens?.let { lines.add("- Input tokens: $it") }
                    m.outputTokens?.let { lines.add("- Output tokens: $it") }
                    m.realTimeFactor?.let { lines.add("- RTF: ${"%.2f".format(it)}x") }
                    m.audioLengthSeconds?.let { lines.add("- Audio length: ${"%.1f".format(it)}s") }
                    m.audioDurationSeconds?.let { lines.add("- Audio duration: ${"%.1f".format(it)}s") }
                    m.charactersProcessed?.let { lines.add("- Characters: $it") }
                    m.promptTokens?.let { lines.add("- Prompt tokens: $it") }
                    m.completionTokens?.let { lines.add("- Completion tokens: $it") }
                    if (m.memoryDeltaBytes != 0L) {
                        lines.add("- Memory delta: ${Formatter.formatFileSize(context, m.memoryDeltaBytes)}")
                    }
                }
                lines.add("")
            }
        }
        return lines.joinToString("\n")
    }

    // -- JSON --

    fun formatJSON(run: BenchmarkRun): String = try {
        json.encodeToString(run)
    } catch (_: Exception) {
        "{\"error\": \"Failed to encode benchmark run\"}"
    }

    // -- File Export: JSON --

    fun writeJSON(run: BenchmarkRun, context: Context): File {
        val content = formatJSON(run)
        val file = File(context.cacheDir, "benchmark_${run.id.take(8)}.json")
        file.writeText(content)
        return file
    }

    // -- File Export: CSV --

    fun writeCSV(run: BenchmarkRun, context: Context): File {
        val header = "Category,Scenario,Model,Framework,LoadMs,WarmupMs,E2EMs,TPS,TTFT,RTF,AudioLen,AudioDur,Chars,PromptTok,CompTok,MemDeltaBytes,Success,Error"
        val rows = run.results.map { r ->
            val m = r.metrics
            val row = listOf(
                r.category.displayName,
                r.scenario.name,
                r.modelInfo.name,
                r.modelInfo.framework,
                "%.0f".format(m.loadTimeMs),
                "%.0f".format(m.warmupTimeMs),
                "%.0f".format(m.endToEndLatencyMs),
                m.tokensPerSecond?.let { "%.1f".format(it) } ?: "",
                m.ttftMs?.let { "%.0f".format(it) } ?: "",
                m.realTimeFactor?.let { "%.2f".format(it) } ?: "",
                m.audioLengthSeconds?.let { "%.1f".format(it) } ?: "",
                m.audioDurationSeconds?.let { "%.1f".format(it) } ?: "",
                m.charactersProcessed?.toString() ?: "",
                m.promptTokens?.toString() ?: "",
                m.completionTokens?.toString() ?: "",
                m.memoryDeltaBytes.toString(),
                if (m.didSucceed) "true" else "false",
                m.errorMessage ?: "",
            ).map { field ->
                if (field.contains(",") || field.contains("\"") || field.contains("\n")) {
                    "\"${field.replace("\"", "\"\"")}\""
                } else {
                    field
                }
            }
            row.joinToString(",")
        }
        val csv = (listOf(header) + rows).joinToString("\n")
        val file = File(context.cacheDir, "benchmark_${run.id.take(8)}.csv")
        file.writeText(csv)
        return file
    }
}
