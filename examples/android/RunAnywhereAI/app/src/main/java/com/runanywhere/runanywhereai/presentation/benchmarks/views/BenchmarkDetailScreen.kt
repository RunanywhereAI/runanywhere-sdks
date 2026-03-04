package com.runanywhere.runanywhereai.presentation.benchmarks.views

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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
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
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkCategory
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkMetrics
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkResult
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkRun
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkRunStatus
import com.runanywhere.runanywhereai.presentation.benchmarks.utilities.BenchmarkExportFormat
import com.runanywhere.runanywhereai.presentation.benchmarks.viewmodel.BenchmarkViewModel
import com.runanywhere.runanywhereai.presentation.components.ConfigureTopBar
import com.runanywhere.runanywhereai.ui.theme.AppColors
import com.runanywhere.runanywhereai.ui.theme.AppSpacing
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

private val dateFormat: DateTimeFormatter =
    DateTimeFormatter.ofPattern("MMM d, yyyy h:mm a").withZone(ZoneId.systemDefault())

/**
 * Shows details of a single benchmark run with export actions.
 * Matches iOS BenchmarkDetailView exactly.
 */
@Composable
fun BenchmarkDetailScreen(
    runId: String,
    onBack: () -> Unit = {},
    benchmarkViewModel: BenchmarkViewModel = viewModel(),
) {
    val uiState by benchmarkViewModel.uiState.collectAsStateWithLifecycle()
    val run = uiState.pastRuns.find { it.id == runId }
    val context = LocalContext.current

    ConfigureTopBar(title = "Benchmark Details", showBack = true, onBack = onBack)

    if (run == null) {
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center,
        ) {
            Text("Run not found", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    } else {
        Box(modifier = Modifier.fillMaxSize()) {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = AppSpacing.large),
                verticalArrangement = Arrangement.spacedBy(AppSpacing.large),
            ) {
                // Run Info
                item { RunInfoSection(run) }

                // Device Info
                item { DeviceSection(run, context) }

                // Copy & Export
                item { CopyExportSection(run, benchmarkViewModel, context) }

                // Results grouped by category
                val grouped = run.results.groupBy { it.category }
                for (category in BenchmarkCategory.entries) {
                    val results = grouped[category] ?: continue
                    if (results.isEmpty()) continue
                    item {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(category.icon, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(modifier = Modifier.width(AppSpacing.small))
                            Text(category.displayName, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                        }
                    }
                    items(results, key = { it.id }) { result ->
                        ResultCard(result)
                    }
                }

                // Empty results
                if (run.results.isEmpty()) {
                    item { EmptyResultsState() }
                }

                item { Spacer(modifier = Modifier.height(AppSpacing.xxLarge)) }
            }

            // Copied toast overlay
            androidx.compose.animation.AnimatedVisibility(
                visible = uiState.copiedToastMessage != null,
                modifier = Modifier.align(Alignment.BottomCenter),
                enter = slideInVertically(initialOffsetY = { it }) + fadeIn(),
                exit = slideOutVertically(targetOffsetY = { it }) + fadeOut(),
            ) {
                uiState.copiedToastMessage?.let { toast ->
                    Text(
                        text = toast,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onPrimary,
                        fontWeight = FontWeight.Medium,
                        modifier = Modifier
                            .padding(bottom = AppSpacing.xxLarge)
                            .shadow(4.dp, RoundedCornerShape(AppSpacing.cornerRadiusLarge))
                            .background(AppColors.statusGreen.copy(alpha = 0.9f), RoundedCornerShape(AppSpacing.cornerRadiusLarge))
                            .padding(horizontal = AppSpacing.xxLarge, vertical = AppSpacing.medium),
                    )
                }
            }
        }
    }
}

// -- Run Info --

@Composable
private fun RunInfoSection(run: BenchmarkRun) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
    ) {
        Column(modifier = Modifier.padding(AppSpacing.large)) {
            Text("Run Info", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            Spacer(modifier = Modifier.height(AppSpacing.small))
            DetailRow("Started", dateFormat.format(Instant.ofEpochMilli(run.startedAt)))
            run.completedAt?.let { DetailRow("Completed", dateFormat.format(Instant.ofEpochMilli(it))) }
            run.durationSeconds?.let { DetailRow("Duration", "${"%.1f".format(it)}s") }
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = AppSpacing.xxSmall),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Status", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                StatusBadge(run.status)
            }
            val successCount = run.results.count { it.metrics.didSucceed }
            val failCount = run.results.size - successCount
            DetailRow("Results", "${run.results.size} ($successCount passed, $failCount failed)")
        }
    }
}

// -- Device Info --

@Composable
private fun DeviceSection(run: BenchmarkRun, context: Context) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
    ) {
        Column(modifier = Modifier.padding(AppSpacing.large)) {
            Text("Device", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            Spacer(modifier = Modifier.height(AppSpacing.small))
            DetailRow("Model", run.deviceInfo.modelName)
            DetailRow("Chip", run.deviceInfo.chipName)
            DetailRow("RAM", Formatter.formatFileSize(context, run.deviceInfo.totalMemoryBytes))
            DetailRow("OS", run.deviceInfo.osVersion)
        }
    }
}

// -- Copy & Export --

@Composable
private fun CopyExportSection(
    run: BenchmarkRun,
    viewModel: BenchmarkViewModel,
    context: Context,
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
    ) {
        Column(modifier = Modifier.padding(AppSpacing.large)) {
            Text("Copy & Export", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            Spacer(modifier = Modifier.height(AppSpacing.small))

            BenchmarkExportFormat.entries.forEach { format ->
                OutlinedButton(
                    onClick = { viewModel.copyToClipboard(run, format) },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(Icons.Filled.ContentCopy, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(modifier = Modifier.width(AppSpacing.small))
                    Text("Copy as ${format.displayName}")
                }
                Spacer(modifier = Modifier.height(AppSpacing.xSmall))
            }

            OutlinedButton(
                onClick = {
                    val intent = viewModel.shareFile(run, csv = false)
                    context.startActivity(android.content.Intent.createChooser(intent, "Export JSON"))
                },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.Filled.Share, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(AppSpacing.small))
                Text("Export JSON File")
            }

            Spacer(modifier = Modifier.height(AppSpacing.xSmall))

            OutlinedButton(
                onClick = {
                    val intent = viewModel.shareFile(run, csv = true)
                    context.startActivity(android.content.Intent.createChooser(intent, "Export CSV"))
                },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.Filled.Share, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(AppSpacing.small))
                Text("Export CSV File")
            }
        }
    }
}

// -- Result Card --

@Composable
private fun ResultCard(result: BenchmarkResult) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
    ) {
        Column(modifier = Modifier.padding(AppSpacing.large)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    result.scenario.name,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    modifier = Modifier.weight(1f),
                )
                Icon(
                    imageVector = if (result.metrics.didSucceed) Icons.Filled.CheckCircle else Icons.Filled.Error,
                    contentDescription = null,
                    tint = if (result.metrics.didSucceed) AppColors.statusGreen else AppColors.statusRed,
                    modifier = Modifier.size(20.dp),
                )
            }

            Spacer(modifier = Modifier.height(AppSpacing.xSmall))

            Text(
                "${result.modelInfo.name} · ${result.modelInfo.framework}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            result.metrics.errorMessage?.let { error ->
                Spacer(modifier = Modifier.height(AppSpacing.small))
                Text(error, style = MaterialTheme.typography.bodySmall, color = AppColors.statusRed)
            } ?: run {
                Spacer(modifier = Modifier.height(AppSpacing.small))
                MetricsGrid(metrics = result.metrics, category = result.category)
            }
        }
    }
}

// -- Metrics Grid --

@Composable
private fun MetricsGrid(metrics: BenchmarkMetrics, category: BenchmarkCategory) {
    val context = LocalContext.current
    val items = buildMetricItems(metrics, category, context)
    val rows = items.chunked(2)
    Column(verticalArrangement = Arrangement.spacedBy(AppSpacing.xSmall)) {
        rows.forEach { row ->
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(AppSpacing.large)) {
                row.forEach { (label, value) ->
                    Row(
                        modifier = Modifier.weight(1f),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(value, style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace), fontWeight = FontWeight.Medium)
                    }
                }
                if (row.size == 1) {
                    Spacer(modifier = Modifier.weight(1f))
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
        items.add("Mem Δ" to Formatter.formatFileSize(context, metrics.memoryDeltaBytes))
    }
    return items
}

// -- Helper Views --

@Composable
private fun DetailRow(label: String, value: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = AppSpacing.xxSmall),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun StatusBadge(status: BenchmarkRunStatus) {
    val color = when (status) {
        BenchmarkRunStatus.COMPLETED -> AppColors.statusGreen
        BenchmarkRunStatus.RUNNING -> AppColors.primaryBlue
        BenchmarkRunStatus.CANCELLED -> AppColors.statusOrange
        BenchmarkRunStatus.FAILED -> AppColors.statusRed
    }
    Text(
        text = status.value.replaceFirstChar { it.uppercase() },
        style = MaterialTheme.typography.labelSmall,
        color = color,
        modifier = Modifier
            .background(color.copy(alpha = 0.2f), RoundedCornerShape(AppSpacing.cornerRadiusSmall))
            .padding(horizontal = AppSpacing.smallMedium, vertical = AppSpacing.xxSmall),
    )
}

@Composable
private fun EmptyResultsState() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = AppSpacing.xxLarge),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            Icons.Filled.Warning,
            contentDescription = null,
            modifier = Modifier.size(48.dp),
            tint = AppColors.statusOrange.copy(alpha = 0.6f),
        )
        Spacer(modifier = Modifier.height(AppSpacing.large))
        Text(
            "No results in this run",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(modifier = Modifier.height(AppSpacing.small))
        Text(
            "This may happen if no downloaded models were available for the selected categories.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(horizontal = AppSpacing.xxLarge),
        )
    }
}

