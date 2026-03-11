package com.runanywhere.runanywhereai.ui.screens

import android.content.Context
import android.text.format.Formatter
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.models.BenchmarkCategory
import com.runanywhere.runanywhereai.models.BenchmarkExportFormat
import com.runanywhere.runanywhereai.models.BenchmarkMetrics
import com.runanywhere.runanywhereai.models.BenchmarkResult
import com.runanywhere.runanywhereai.models.BenchmarkRun
import com.runanywhere.runanywhereai.models.BenchmarkRunStatus
import com.runanywhere.runanywhereai.models.BenchmarkUiState
import com.runanywhere.runanywhereai.ui.components.RAButton
import com.runanywhere.runanywhereai.ui.components.RAButtonStyle
import com.runanywhere.runanywhereai.ui.components.RACard
import com.runanywhere.runanywhereai.ui.icons.RAIcons
import com.runanywhere.runanywhereai.viewmodels.BenchmarkViewModel
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

private val dateFormat: DateTimeFormatter =
    DateTimeFormatter.ofPattern("MMM d, yyyy h:mm a").withZone(ZoneId.systemDefault())

@Composable
fun BenchmarkDetailScreen(
    runId: String,
    onBack: () -> Unit = {},
    benchmarkViewModel: BenchmarkViewModel = viewModel(),
) {
    val uiState by benchmarkViewModel.uiState.collectAsStateWithLifecycle()
    val state = uiState as? BenchmarkUiState.Ready
    val run = state?.pastRuns?.find { it.id == runId }
    val context = LocalContext.current

    if (run == null) {
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                "Run not found",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        return
    }

    Box(modifier = Modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item(key = "spacer_top") { Spacer(Modifier.height(4.dp)) }

            // Run Info
            item(key = "run_info", contentType = "run_info") {
                RunInfoSection(run)
            }

            // Device Info
            item(key = "device_info", contentType = "device_info") {
                DeviceSection(run, context)
            }

            // Copy & Export
            item(key = "export", contentType = "export") {
                CopyExportSection(run, benchmarkViewModel, context)
            }

            // Results grouped by category
            val grouped = run.results.groupBy { it.category }
            for (category in BenchmarkCategory.entries) {
                val results = grouped[category] ?: continue
                if (results.isEmpty()) continue

                item(key = "category_header_${category.value}", contentType = "category_header") {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            categoryIcon(category),
                            contentDescription = null,
                            modifier = Modifier.size(18.dp),
                            tint = MaterialTheme.colorScheme.primary,
                        )
                        Spacer(Modifier.width(8.dp))
                        Text(
                            category.displayName,
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                }

                items(
                    items = results,
                    key = { it.id },
                    contentType = { "result_card" },
                ) { result ->
                    ResultCard(result)
                }
            }

            // Empty results
            if (run.results.isEmpty()) {
                item(key = "empty_results", contentType = "empty") {
                    EmptyResultsState()
                }
            }

            item(key = "spacer_bottom") { Spacer(Modifier.height(32.dp)) }
        }

        // Copied toast overlay
        AnimatedVisibility(
            visible = state?.copiedToastMessage != null,
            modifier = Modifier.align(Alignment.BottomCenter),
            enter = slideInVertically(initialOffsetY = { it }) + fadeIn(),
            exit = slideOutVertically(targetOffsetY = { it }) + fadeOut(),
        ) {
            state?.copiedToastMessage?.let { toast ->
                Text(
                    text = toast,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onPrimary,
                    fontWeight = FontWeight.Medium,
                    modifier = Modifier
                        .padding(bottom = 32.dp)
                        .shadow(4.dp, RoundedCornerShape(16.dp))
                        .background(
                            MaterialTheme.colorScheme.tertiary.copy(alpha = 0.9f),
                            RoundedCornerShape(16.dp),
                        )
                        .padding(horizontal = 24.dp, vertical = 12.dp),
                )
            }
        }
    }
}

// =============================================================================
// Run Info
// =============================================================================

@Composable
private fun RunInfoSection(run: BenchmarkRun) {
    RACard {
        Text(
            "Run Info",
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
        )
        Spacer(Modifier.height(8.dp))
        DetailRow("Started", dateFormat.format(Instant.ofEpochMilli(run.startedAt)))
        run.completedAt?.let {
            DetailRow("Completed", dateFormat.format(Instant.ofEpochMilli(it)))
        }
        run.durationSeconds?.let {
            DetailRow("Duration", "${"%.1f".format(it)}s")
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 2.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                "Status",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            StatusBadge(run.status)
        }
        val successCount = run.results.count { it.metrics.didSucceed }
        val failCount = run.results.size - successCount
        DetailRow("Results", "${run.results.size} ($successCount passed, $failCount failed)")
    }
}

// =============================================================================
// Device Info
// =============================================================================

@Composable
private fun DeviceSection(run: BenchmarkRun, context: Context) {
    RACard {
        Text(
            "Device",
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
        )
        Spacer(Modifier.height(8.dp))
        DetailRow("Model", run.deviceInfo.modelName)
        DetailRow("Chip", run.deviceInfo.chipName)
        DetailRow("RAM", Formatter.formatFileSize(context, run.deviceInfo.totalMemoryBytes))
        DetailRow("OS", run.deviceInfo.osVersion)
    }
}

// =============================================================================
// Copy & Export
// =============================================================================

@Composable
private fun CopyExportSection(
    run: BenchmarkRun,
    viewModel: BenchmarkViewModel,
    context: Context,
) {
    RACard {
        Text(
            "Copy & Export",
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
        )
        Spacer(Modifier.height(12.dp))

        BenchmarkExportFormat.entries.forEach { format ->
            RAButton(
                text = "Copy as ${format.displayName}",
                onClick = { viewModel.copyToClipboard(run, format) },
                icon = RAIcons.Copy,
                style = RAButtonStyle.Outlined,
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(8.dp))
        }

        HorizontalDivider(
            Modifier.padding(vertical = 4.dp),
            color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.3f),
        )

        Spacer(Modifier.height(4.dp))

        RAButton(
            text = "Export JSON File",
            onClick = {
                val intent = viewModel.shareFile(run, csv = false)
                context.startActivity(
                    android.content.Intent.createChooser(intent, "Export JSON"),
                )
            },
            icon = RAIcons.Download,
            style = RAButtonStyle.Outlined,
            modifier = Modifier.fillMaxWidth(),
        )

        Spacer(Modifier.height(8.dp))

        RAButton(
            text = "Export CSV File",
            onClick = {
                val intent = viewModel.shareFile(run, csv = true)
                context.startActivity(
                    android.content.Intent.createChooser(intent, "Export CSV"),
                )
            },
            icon = RAIcons.Download,
            style = RAButtonStyle.Outlined,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

// =============================================================================
// Result Card
// =============================================================================

@Composable
private fun ResultCard(result: BenchmarkResult) {
    RACard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                result.scenario.name,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
                modifier = Modifier.weight(1f),
            )
            Icon(
                imageVector = if (result.metrics.didSucceed) RAIcons.CircleCheck else RAIcons.AlertCircle,
                contentDescription = null,
                tint = if (result.metrics.didSucceed) {
                    MaterialTheme.colorScheme.tertiary
                } else {
                    MaterialTheme.colorScheme.error
                },
                modifier = Modifier.size(20.dp),
            )
        }

        Spacer(Modifier.height(4.dp))

        Text(
            "${result.modelInfo.name} \u00b7 ${result.modelInfo.framework}",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        result.metrics.errorMessage?.let { error ->
            Spacer(Modifier.height(8.dp))
            Text(
                error,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
            )
        } ?: run {
            Spacer(Modifier.height(8.dp))
            MetricsGrid(metrics = result.metrics, category = result.category)
        }
    }
}

// =============================================================================
// Metrics Grid
// =============================================================================

@Composable
private fun MetricsGrid(metrics: BenchmarkMetrics, category: BenchmarkCategory) {
    val context = LocalContext.current
    val items = buildMetricItems(metrics, category, context)
    val rows = items.chunked(2)
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        rows.forEach { row ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                row.forEach { (label, value) ->
                    Row(
                        modifier = Modifier.weight(1f),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(
                            label,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            value,
                            style = MaterialTheme.typography.bodySmall.copy(
                                fontFamily = FontFamily.Monospace,
                            ),
                            fontWeight = FontWeight.Medium,
                        )
                    }
                }
                if (row.size == 1) {
                    Spacer(Modifier.weight(1f))
                }
            }
        }
    }
}

private fun buildMetricItems(
    metrics: BenchmarkMetrics,
    category: BenchmarkCategory,
    context: Context,
): List<Pair<String, String>> {
    val items = mutableListOf<Pair<String, String>>()
    items.add("Load" to "${"%.0f".format(metrics.loadTimeMs)}ms")
    items.add("E2E" to "${"%.0f".format(metrics.endToEndLatencyMs)}ms")

    when (category) {
        BenchmarkCategory.LLM -> {
            metrics.tokensPerSecond?.let { items.add("tok/s" to "%.1f".format(it)) }
            metrics.ttftMs?.let { items.add("TTFT" to "${"%.0f".format(it)}ms") }
            metrics.outputTokens?.let { items.add("Tokens" to "$it") }
        }
        BenchmarkCategory.STT -> {
            metrics.realTimeFactor?.let { items.add("RTF" to "${"%.2f".format(it)}x") }
            metrics.audioLengthSeconds?.let { items.add("Audio" to "${"%.1f".format(it)}s") }
        }
        BenchmarkCategory.TTS -> {
            metrics.audioDurationSeconds?.let { items.add("Audio" to "${"%.1f".format(it)}s") }
            metrics.charactersProcessed?.let { items.add("Chars" to "$it") }
        }
        BenchmarkCategory.VLM -> {
            metrics.tokensPerSecond?.let { items.add("tok/s" to "%.1f".format(it)) }
            metrics.completionTokens?.let { items.add("Tokens" to "$it") }
        }
    }

    if (metrics.memoryDeltaBytes != 0L) {
        items.add("Mem \u0394" to Formatter.formatFileSize(context, metrics.memoryDeltaBytes))
    }
    return items
}

// =============================================================================
// Helper Views
// =============================================================================

@Composable
private fun DetailRow(label: String, value: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            label,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            value,
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.Medium,
        )
    }
}

@Composable
private fun StatusBadge(status: BenchmarkRunStatus) {
    val color = when (status) {
        BenchmarkRunStatus.COMPLETED -> MaterialTheme.colorScheme.tertiary
        BenchmarkRunStatus.RUNNING -> MaterialTheme.colorScheme.primary
        BenchmarkRunStatus.CANCELLED -> MaterialTheme.colorScheme.error.copy(alpha = 0.7f)
        BenchmarkRunStatus.FAILED -> MaterialTheme.colorScheme.error
    }
    Text(
        text = status.value.replaceFirstChar { it.uppercase() },
        style = MaterialTheme.typography.labelSmall,
        color = color,
        modifier = Modifier
            .background(color.copy(alpha = 0.15f), RoundedCornerShape(6.dp))
            .padding(horizontal = 10.dp, vertical = 2.dp),
    )
}

@Composable
private fun EmptyResultsState() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 40.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            RAIcons.AlertCircle,
            contentDescription = null,
            modifier = Modifier.size(48.dp),
            tint = MaterialTheme.colorScheme.error.copy(alpha = 0.5f),
        )
        Spacer(Modifier.height(16.dp))
        Text(
            "No results in this run",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(8.dp))
        Text(
            "This may happen if no downloaded models were available for the selected categories.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(horizontal = 40.dp),
        )
    }
}
