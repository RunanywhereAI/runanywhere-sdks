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
        appendLine(
            "Category,Scenario,Model,Framework,Trials,Success,LoadMs,WarmupMs,E2EMs,E2EMinMs,E2EMaxMs," +
                "TokensPerSec,TokensPerSecMin,TokensPerSecMax,TtftMs,TtftMinMs,TtftMaxMs," +
                "InTokens,OutTokens,PromptEvalMs,DecodeMs,RTF,AudioLenS,AudioDurS,Chars,MemDeltaBytes,Error",
        )
        run.results.forEach { r ->
            val m = r.metrics
            val v = r.variance
            val cells = listOf(
                r.category.name, r.scenario, r.modelName, r.framework, r.trials.toString(), r.success.toString(),
                num(m.loadTimeMs), num(m.warmupTimeMs), num(m.endToEndLatencyMs),
                v?.endToEndLatencyMs?.min?.let(::num).orEmpty(), v?.endToEndLatencyMs?.max?.let(::num).orEmpty(),
                m.tokensPerSecond?.let(::num).orEmpty(),
                v?.tokensPerSecond?.min?.let(::num).orEmpty(), v?.tokensPerSecond?.max?.let(::num).orEmpty(),
                m.ttftMs?.let(::num).orEmpty(),
                v?.ttftMs?.min?.let(::num).orEmpty(), v?.ttftMs?.max?.let(::num).orEmpty(),
                m.inputTokens?.toString().orEmpty(), m.outputTokens?.toString().orEmpty(),
                m.promptEvalMs?.let(::num).orEmpty(), m.decodeMs?.let(::num).orEmpty(),
                m.realTimeFactor?.let(::num).orEmpty(), m.audioLengthSeconds?.let(::num).orEmpty(),
                m.audioDurationSeconds?.let(::num).orEmpty(), m.charactersProcessed?.toString().orEmpty(),
                m.memoryDeltaBytes.toString(), r.errorMessage.orEmpty(),
            )
            appendLine(cells.joinToString(",") { csvCell(it) })
        }
    }

    // The metric label/value pairs shown for a successful result, by category. When a
    // run had multiple trials, the median is shown with the observed min–max range.
    fun metricRows(result: BenchmarkResult): List<Pair<String, String>> {
        val m = result.metrics
        val v = result.variance
        return buildList {
            if (result.trials > 1) add("Trials" to "${result.trials} (median shown)")
            add("Load" to "${"%.0f".format(m.loadTimeMs)}ms")
            if (m.warmupTimeMs > 0) add("Warmup" to "${"%.0f".format(m.warmupTimeMs)}ms")
            add("End-to-end" to withRange("${"%.0f".format(m.endToEndLatencyMs)}ms", v?.endToEndLatencyMs) { "%.0f".format(it) })
            m.tokensPerSecond?.let { add("Tokens/s" to withRange("%.1f".format(it), v?.tokensPerSecond) { "%.1f".format(it) }) }
            m.ttftMs?.let { add("TTFT" to withRange("${"%.0f".format(it)}ms", v?.ttftMs) { "%.0f".format(it) }) }
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

    // Appends " (min–max)" to a formatted median when a variance range is present.
    private fun withRange(base: String, range: MetricRange?, fmt: (Double) -> String): String =
        if (range == null) base else "$base (${fmt(range.min)}–${fmt(range.max)})"

    fun gb(bytes: Long): String = when {
        bytes >= 1_000_000_000 -> "%.1f GB".format(bytes / 1_000_000_000.0)
        bytes >= 1_000_000 -> "%.0f MB".format(bytes / 1_000_000.0)
        bytes >= 1_000 -> "%.0f KB".format(bytes / 1_000.0)
        else -> "$bytes B"
    }

    private fun num(value: Double): String = String.format(Locale.US, "%.2f", value)

    private fun csvCell(value: String): String =
        if (value.any { it == ',' || it == '"' || it == '\r' || it == '\n' }) {
            "\"${value.replace("\"", "\"\"")}\""
        } else {
            value
        }
}
