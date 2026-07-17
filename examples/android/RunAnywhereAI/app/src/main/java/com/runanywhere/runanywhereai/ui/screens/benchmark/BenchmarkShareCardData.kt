package com.runanywhere.runanywhereai.ui.screens.benchmark

import com.runanywhere.runanywhereai.data.benchmark.BenchmarkCategory
import com.runanywhere.runanywhereai.data.benchmark.BenchmarkResult
import com.runanywhere.runanywhereai.data.benchmark.BenchmarkRun
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// One labelled metric shown on the share card (e.g. "tok/s" -> "42.1").
data class ShareCardMetric(val value: String, val label: String)

// One model's row on the share card: its name/framework plus its headline metrics.
data class ShareCardRow(
    val model: String,
    val framework: String,
    val metrics: List<ShareCardMetric>,
)

// The deterministic, presentation-ready projection of ONE modality of a benchmark run
// used to draw the branded share card. A run can span several modalities (LLM/STT/TTS/
// VLM) and many models, which can't stay clean in a single image — so each card is
// scoped to a single modality and the share sheet lets the user pick which to share.
// Only the important metrics are surfaced; memory deltas and raw token counts are
// intentionally omitted to keep the card clean and shareable.
data class ShareCardData(
    val modalityLabel: String,
    val deviceLine: String,
    val hero: ShareCardMetric?,
    val heroCaption: String,
    // A compact secondary stat for the hero model (e.g. TTFT), so the top model's
    // detail lives with the headline instead of being repeated in a row below.
    val heroSecondary: ShareCardMetric?,
    // Only the models BEYOND the hero — the top model is never repeated as a row.
    val rows: List<ShareCardRow>,
    val dateLine: String,
    // Prepopulated, post-ready caption that already includes the run's headline
    // numbers, the @runanywhereai tag and the download CTA.
    val shareMessage: String,
) {
    companion object {
        // Keep the card clean — only the top few models make the social image.
        private const val MAX_ROWS = 3

        /** Returns categories with successful results in canonical display order. */
        fun availableModalities(run: BenchmarkRun): List<BenchmarkCategory> =
            BenchmarkCategory.entries.filter { category ->
                run.results.any { it.success && it.category == category }
            }

        /**
         * Builds presentation-ready data for one category returned by [availableModalities].
         */
        fun from(run: BenchmarkRun, category: BenchmarkCategory): ShareCardData {
            val successes = run.results
                .filter { it.success && it.category == category }
                // One row per model, using its best-throughput (or first) scenario.
                .groupBy { it.modelName }
                .values
                .map { perModel -> perModel.maxByOrNull { it.sortKey() } ?: perModel.first() }
                .sortedByDescending { it.sortKey() }

            val top = successes.firstOrNull()
            val hero = top?.let { heroMetric(category, it) }
            val heroCaption = top?.let { "${it.modelName} · ${it.framework}" }.orEmpty()

            // Device + chipset are the important "flex" facts; keep it to one clean line.
            val deviceLine = listOf(run.device.device, run.device.chipset)
                .filter { it.isNotBlank() }
                .joinToString(" · ")

            // The hero's compact secondary stat (2nd metric of the top model's row).
            val heroSecondary = top?.toRow()?.metrics?.getOrNull(1)
            // Rows are the OTHER models only — the top model already headlines the card.
            val additional = successes.drop(1).take(MAX_ROWS).map { it.toRow() }

            val dateFormat = SimpleDateFormat("MMM d, yyyy", Locale.US)
            return ShareCardData(
                modalityLabel = category.cardLabel,
                deviceLine = deviceLine,
                hero = hero,
                heroCaption = heroCaption,
                heroSecondary = heroSecondary,
                rows = additional,
                dateLine = dateFormat.format(Date(run.startedAt)),
                shareMessage = buildShareMessage(top?.modelName, hero, deviceLine),
            )
        }

        // A clean, post-ready caption seeded with the run's headline numbers.
        private fun buildShareMessage(model: String?, hero: ShareCardMetric?, device: String): String {
            val headline = if (model != null && hero != null) {
                "$model hit ${hero.value} ${hero.label} running 100% on-device on my $device"
            } else {
                "Running AI models 100% on-device on my $device"
            }
            return "$headline with @runanywhereai ⚡\n" +
                "No cloud. No API keys. Full privacy.\n\n" +
                "Download the RunAnywhere app → runanywhere.ai"
        }

        // Ordering key: throughput-like metric where higher is better. STT uses the
        // realtime speedup (1/RTF) so faster transcription sorts first.
        private fun BenchmarkResult.sortKey(): Double = when (category) {
            BenchmarkCategory.LLM, BenchmarkCategory.VLM -> metrics.tokensPerSecond ?: -1.0
            BenchmarkCategory.STT -> metrics.realTimeFactor?.let { if (it > 0) 1.0 / it else -1.0 } ?: -1.0
            BenchmarkCategory.TTS -> charsPerSecond() ?: -1.0
        }

        // The single headline metric for a modality's fastest model.
        private fun heroMetric(category: BenchmarkCategory, result: BenchmarkResult): ShareCardMetric? {
            val m = result.metrics
            return when (category) {
                BenchmarkCategory.LLM, BenchmarkCategory.VLM ->
                    m.tokensPerSecond?.let { ShareCardMetric("%.0f".format(Locale.US, it), "tokens / sec") }
                BenchmarkCategory.STT ->
                    m.realTimeFactor?.takeIf { it > 0 }
                        ?.let { ShareCardMetric("%.1f×".format(Locale.US, 1.0 / it), "faster than realtime") }
                BenchmarkCategory.TTS ->
                    result.charsPerSecond()?.let { ShareCardMetric("%.0f".format(Locale.US, it), "chars / sec") }
            }
        }

        private fun BenchmarkResult.charsPerSecond(): Double? {
            val chars = metrics.charactersProcessed ?: return null
            val seconds = metrics.endToEndLatencyMs / 1000.0
            return if (seconds > 0) chars / seconds else null
        }

        private fun BenchmarkResult.toRow(): ShareCardRow {
            val m = metrics
            val cells = when (category) {
                BenchmarkCategory.LLM, BenchmarkCategory.VLM -> listOfNotNull(
                    m.tokensPerSecond?.let { ShareCardMetric("%.1f".format(Locale.US, it), "tok/s") },
                    m.ttftMs?.let { ShareCardMetric("${"%.0f".format(Locale.US, it)}ms", "TTFT") },
                )
                BenchmarkCategory.STT -> listOfNotNull(
                    m.realTimeFactor?.let { ShareCardMetric("${"%.2f".format(Locale.US, it)}x", "RTF") },
                    ShareCardMetric("${"%.0f".format(Locale.US, m.loadTimeMs)}ms", "load"),
                )
                BenchmarkCategory.TTS -> listOfNotNull(
                    charsPerSecond()?.let { ShareCardMetric("%.0f".format(Locale.US, it), "chars/s") },
                    ShareCardMetric("${"%.0f".format(Locale.US, m.loadTimeMs)}ms", "load"),
                )
            }
            return ShareCardRow(model = modelName, framework = framework, metrics = cells)
        }

        // Short, social-friendly modality label shown on the card.
        private val BenchmarkCategory.cardLabel: String
            get() = when (this) {
                BenchmarkCategory.LLM -> "LANGUAGE MODELS"
                BenchmarkCategory.STT -> "SPEECH → TEXT"
                BenchmarkCategory.TTS -> "TEXT → SPEECH"
                BenchmarkCategory.VLM -> "VISION"
            }
    }
}
