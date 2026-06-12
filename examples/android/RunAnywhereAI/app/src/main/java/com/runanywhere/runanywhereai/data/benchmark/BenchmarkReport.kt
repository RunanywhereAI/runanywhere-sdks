package com.runanywhere.runanywhereai.data.benchmark

import kotlinx.serialization.json.Json
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// Formats a run as Markdown / JSON / CSV for copy + share.
object BenchmarkReport {

    private val json = Json { prettyPrint = true }
    private val dateFormat = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US)

    fun toJson(run: BenchmarkRun): String = json.encodeToString(BenchmarkRun.serializer(), run)

    fun toMarkdown(run: BenchmarkRun): String = buildString {
        appendLine("# Benchmark Report")
        appendLine()
        appendLine("- **Device:** ${run.device.manufacturer} ${run.device.device}")
        appendLine("- **Android:** SDK ${run.device.androidSdk}")
        appendLine("- **RAM:** ${gb(run.device.totalRamBytes)}")
        appendLine("- **Date:** ${dateFormat.format(Date(run.startedAt))}")
        appendLine("- **Duration:** ${"%.1f".format(run.durationMs / 1000.0)}s")
        appendLine("- **Status:** ${run.status.name.lowercase()}")
        appendLine("- **Results:** ${run.results.size} total, ${run.passed} passed, ${run.failed} failed")
        BenchmarkCategory.entries.forEach { category ->
            val items = run.results.filter { it.category == category }
            if (items.isEmpty()) return@forEach
            appendLine()
            appendLine("## ${category.label}")
            items.forEach { r ->
                appendLine()
                appendLine("### ${r.scenario} — ${r.modelName} (${r.framework})")
                if (!r.success) {
                    appendLine("- Failed: ${r.errorMessage ?: "unknown error"}")
                    return@forEach
                }
                metricRows(r).forEach { (label, value) -> appendLine("- $label: $value") }
            }
        }
    }

    fun toCsv(run: BenchmarkRun): String = buildString {
        appendLine("Category,Scenario,Model,Framework,Success,LoadMs,WarmupMs,E2EMs,TokensPerSec,TtftMs,InTokens,OutTokens,PromptEvalMs,DecodeMs,RTF,AudioLenS,AudioDurS,Chars,MemDeltaBytes,Error")
        run.results.forEach { r ->
            val m = r.metrics
            val cells = listOf(
                r.category.name, r.scenario, r.modelName, r.framework, r.success.toString(),
                num(m.loadTimeMs), num(m.warmupTimeMs), num(m.endToEndLatencyMs),
                m.tokensPerSecond?.let(::num).orEmpty(), m.ttftMs?.let(::num).orEmpty(),
                m.inputTokens?.toString().orEmpty(), m.outputTokens?.toString().orEmpty(),
                m.promptEvalMs?.let(::num).orEmpty(), m.decodeMs?.let(::num).orEmpty(),
                m.realTimeFactor?.let(::num).orEmpty(), m.audioLengthSeconds?.let(::num).orEmpty(),
                m.audioDurationSeconds?.let(::num).orEmpty(), m.charactersProcessed?.toString().orEmpty(),
                m.memoryDeltaBytes.toString(), (r.errorMessage ?: "").replace(',', ';'),
            )
            appendLine(cells.joinToString(","))
        }
    }

    // The metric label/value pairs shown for a successful result, by category.
    fun metricRows(result: BenchmarkResult): List<Pair<String, String>> {
        val m = result.metrics
        return buildList {
            add("Load" to "${"%.0f".format(m.loadTimeMs)}ms")
            if (m.warmupTimeMs > 0) add("Warmup" to "${"%.0f".format(m.warmupTimeMs)}ms")
            add("End-to-end" to "${"%.0f".format(m.endToEndLatencyMs)}ms")
            m.tokensPerSecond?.let { add("Tokens/s" to "%.1f".format(it)) }
            m.ttftMs?.let { add("TTFT" to "${"%.0f".format(it)}ms") }
            m.promptEvalMs?.let { add("Prompt eval" to "${"%.0f".format(it)}ms") }
            m.decodeMs?.let { add("Decode" to "${"%.0f".format(it)}ms") }
            m.outputTokens?.let { add("Out tokens" to it.toString()) }
            m.realTimeFactor?.let { add("RTF" to "%.2f".format(it)) }
            m.audioLengthSeconds?.let { add("Audio in" to "${"%.1f".format(it)}s") }
            m.audioDurationSeconds?.let { add("Audio out" to "${"%.1f".format(it)}s") }
            m.charactersProcessed?.let { add("Chars" to it.toString()) }
            if (m.memoryDeltaBytes > 0) add("Mem Δ" to gb(m.memoryDeltaBytes))
        }
    }

    fun gb(bytes: Long): String = when {
        bytes >= 1_000_000_000 -> "%.1f GB".format(bytes / 1_000_000_000.0)
        bytes >= 1_000_000 -> "%.0f MB".format(bytes / 1_000_000.0)
        bytes >= 1_000 -> "%.0f KB".format(bytes / 1_000.0)
        else -> "$bytes B"
    }

    private fun num(value: Double): String = "%.2f".format(value)
}
