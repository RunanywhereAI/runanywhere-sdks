package com.runanywhere.runanywhereai.presentation.benchmarks.views

import android.text.format.Formatter
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkCategory
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkRun
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkRunStatus
import com.runanywhere.runanywhereai.presentation.benchmarks.utilities.SyntheticInputGenerator
import com.runanywhere.runanywhereai.presentation.benchmarks.viewmodel.BenchmarkViewModel
import com.runanywhere.runanywhereai.presentation.components.ConfigureTopBar
import com.runanywhere.runanywhereai.ui.theme.AppColors
import com.runanywhere.runanywhereai.ui.theme.AppSpacing
import com.runanywhere.sdk.models.DeviceInfo
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * Main benchmarking screen: device info, category filters, run controls, and history.
 * Matches iOS BenchmarkDashboardView exactly.
 */
@Composable
fun BenchmarkDashboardScreen(
    onNavigateToDetail: (String) -> Unit,
    onBack: () -> Unit = {},
    benchmarkViewModel: BenchmarkViewModel = viewModel(),
) {
    val uiState by benchmarkViewModel.uiState.collectAsStateWithLifecycle()

    ConfigureTopBar(
        title = "Benchmarks",
        showBack = true,
        onBack = onBack,
        actions = {
            if (uiState.pastRuns.isNotEmpty()) {
                IconButton(onClick = { benchmarkViewModel.showClearConfirmation() }) {
                    Icon(
                        Icons.Filled.Delete,
                        contentDescription = "Clear All",
                        tint = AppColors.statusRed,
                    )
                }
            }
        },
    )

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = AppSpacing.large),
        verticalArrangement = Arrangement.spacedBy(AppSpacing.large),
    ) {
        // Device Info
        item { DeviceInfoSection() }

        // Benchmark Suite Info
        item { BenchmarkSuiteInfoSection() }

        // Category Selection
        item { CategorySelectionSection(uiState.selectedCategories, benchmarkViewModel) }

        // Scenario descriptions
        item {
            Column(verticalArrangement = Arrangement.spacedBy(AppSpacing.small)) {
                BenchmarkCategory.entries
                    .filter { it in uiState.selectedCategories }
                    .forEach { category ->
                        CategoryScenarioRow(category)
                    }
            }
        }

        // Run Controls
        item {
            RunControlsSection(
                selectedCategories = uiState.selectedCategories,
                isRunning = uiState.isRunning,
                onRunAll = {
                    benchmarkViewModel.selectAllCategories()
                    benchmarkViewModel.runBenchmarks()
                },
                onRunSelected = { benchmarkViewModel.runBenchmarks() },
            )
        }

        // Skipped categories warning
        uiState.skippedCategoriesMessage?.let { msg ->
            item { SkippedWarning(msg) }
        }

        // Past Runs or Empty State
        if (uiState.pastRuns.isNotEmpty()) {
            item {
                Text(
                    "History",
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = AppSpacing.small),
                )
            }
            items(uiState.pastRuns, key = { it.id }) { run ->
                RunRow(run = run, onClick = { onNavigateToDetail(run.id) })
            }
        } else {
            item { EmptyState() }
        }

        item { Spacer(modifier = Modifier.height(AppSpacing.xxLarge)) }
    }
    
    // Progress Dialog
    if (uiState.isRunning) {
        BenchmarkProgressDialog(
            progress = uiState.progress,
            currentScenario = uiState.currentScenario,
            currentModel = uiState.currentModel,
            completedCount = uiState.completedCount,
            totalCount = uiState.totalCount,
            onCancel = { benchmarkViewModel.cancel() },
        )
    }
    
    // Clear Confirmation Dialog
    if (uiState.showClearConfirmation) {
        AlertDialog(
            onDismissRequest = { benchmarkViewModel.dismissClearConfirmation() },
            title = { Text("Clear All Results?") },
            text = { Text("This will permanently delete all benchmark history.") },
            confirmButton = {
                TextButton(
                    onClick = { benchmarkViewModel.clearAllResults() },
                    colors = ButtonDefaults.textButtonColors(contentColor = AppColors.statusRed),
                ) { Text("Clear") }
            },
            dismissButton = {
                TextButton(onClick = { benchmarkViewModel.dismissClearConfirmation() }) { Text("Cancel") }
            },
        )
    }
    
    // Error Dialog
    uiState.errorMessage?.let { error ->
        AlertDialog(
            onDismissRequest = { benchmarkViewModel.dismissError() },
            title = { Text("Benchmark Error") },
            text = { Text(error) },
            confirmButton = {
                TextButton(onClick = { benchmarkViewModel.dismissError() }) { Text("OK") }
            },
            )
        }
}

// -- Device Info Section --

@Composable
private fun DeviceInfoSection() {
    val context = LocalContext.current
    val deviceInfo = try {
        DeviceInfo.current
    } catch (_: Exception) {
        null
    }

    if (deviceInfo != null) {
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        ) {
            Column(modifier = Modifier.padding(AppSpacing.large)) {
                Text("Device", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                Spacer(modifier = Modifier.height(AppSpacing.small))
                InfoRow("Model", deviceInfo.modelName)
                InfoRow("Architecture", deviceInfo.architecture)
                InfoRow("RAM", Formatter.formatFileSize(context, deviceInfo.totalMemory))
                InfoRow("Available", Formatter.formatFileSize(context, SyntheticInputGenerator.availableMemoryBytes()))
            }
        }
    }
}

@Composable
private fun InfoRow(label: String, value: String) {
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

// -- Benchmark Suite Info --

@Composable
private fun BenchmarkSuiteInfoSection() {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
    ) {
        Row(modifier = Modifier.padding(AppSpacing.large)) {
            Icon(
                Icons.Filled.Info,
                contentDescription = null,
                modifier = Modifier.size(20.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.width(AppSpacing.small))
            Text(
                "Each category runs deterministic scenarios against every downloaded model of that type. Synthetic inputs (silent audio, sine waves, solid-color images) ensure reproducible results.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// -- Category Selection --

@Composable
private fun CategorySelectionSection(
    selectedCategories: Set<BenchmarkCategory>,
    viewModel: BenchmarkViewModel,
) {
    Column {
        Text(
            "Categories",
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(modifier = Modifier.height(AppSpacing.small))
        Row(
            modifier = Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(AppSpacing.smallMedium),
        ) {
            BenchmarkCategory.entries.forEach { category ->
                val isSelected = category in selectedCategories
                FilterChip(
                    selected = isSelected,
                    onClick = { viewModel.toggleCategory(category) },
                    label = { Text(category.displayName) },
                    leadingIcon = {
                        Icon(
                            category.icon,
                            contentDescription = null,
                            modifier = Modifier.size(18.dp),
                        )
                    },
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = AppColors.primaryAccent.copy(alpha = 0.2f),
                        selectedLabelColor = AppColors.primaryAccent,
                        selectedLeadingIconColor = AppColors.primaryAccent,
                    ),
                    border = if (isSelected) {
                        BorderStroke(1.dp, AppColors.primaryAccent.copy(alpha = 0.5f))
                    } else {
                        FilterChipDefaults.filterChipBorder(enabled = true, selected = false)
                    },
                )
            }
        }
    }
}

// -- Category Scenario Row --

@Composable
private fun CategoryScenarioRow(category: BenchmarkCategory) {
    Column {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(category.icon, contentDescription = null, modifier = Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onSurface)
            Spacer(modifier = Modifier.width(AppSpacing.xSmall))
            Text(category.displayName, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold)
        }
        Text(
            text = scenarioDescription(category),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(start = 18.dp),
        )
    }
}

private fun scenarioDescription(category: BenchmarkCategory): String = when (category) {
    BenchmarkCategory.LLM -> "Short (50 tok), Medium (256 tok), Long (512 tok) — measures tok/s, TTFT, load time"
    BenchmarkCategory.STT -> "Silent 2s, Sine Tone 3s — measures RTF, processing time"
    BenchmarkCategory.TTS -> "Short text, Medium text — measures audio duration, char throughput"
    BenchmarkCategory.VLM -> "Solid color, Gradient image (224x224) — measures tok/s, completion tokens"
}

// -- Run Controls --

@Composable
private fun RunControlsSection(
    selectedCategories: Set<BenchmarkCategory>,
    isRunning: Boolean,
    onRunAll: () -> Unit,
    onRunSelected: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(AppSpacing.small)) {
        Button(
            onClick = onRunAll,
            modifier = Modifier.fillMaxWidth(),
            enabled = !isRunning,
            colors = ButtonDefaults.buttonColors(containerColor = AppColors.primaryAccent),
        ) {
            Icon(Icons.Filled.PlayArrow, contentDescription = null, modifier = Modifier.size(20.dp))
            Spacer(modifier = Modifier.width(AppSpacing.small))
            Text("Run All Benchmarks")
        }

        if (selectedCategories.size < BenchmarkCategory.entries.size && selectedCategories.isNotEmpty()) {
            Button(
                onClick = onRunSelected,
                modifier = Modifier.fillMaxWidth(),
                enabled = !isRunning,
                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.secondary),
            ) {
                Icon(Icons.Filled.PlayArrow, contentDescription = null, modifier = Modifier.size(20.dp))
                Spacer(modifier = Modifier.width(AppSpacing.small))
                Text("Run Selected (${selectedCategories.size})")
            }
        }

        if (selectedCategories.isEmpty()) {
            Text(
                "Select at least one category to run benchmarks.",
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.statusOrange,
            )
        }
    }
}

// -- Skipped Warning --

@Composable
private fun SkippedWarning(message: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                AppColors.statusOrange.copy(alpha = 0.1f),
                RoundedCornerShape(AppSpacing.cornerRadiusSmall),
            )
            .padding(AppSpacing.medium),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Filled.Warning, contentDescription = null, tint = AppColors.statusOrange, modifier = Modifier.size(18.dp))
        Spacer(modifier = Modifier.width(AppSpacing.small))
        Text(message, style = MaterialTheme.typography.bodySmall, color = AppColors.statusOrange)
    }
}

// -- Run Row --

private val dateFormat: DateTimeFormatter =
    DateTimeFormatter.ofPattern("MMM d, h:mm a").withZone(ZoneId.systemDefault())

@Composable
private fun RunRow(run: BenchmarkRun, onClick: () -> Unit) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(AppSpacing.large),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        dateFormat.format(Instant.ofEpochMilli(run.startedAt)),
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Medium,
                    )
                    Spacer(modifier = Modifier.weight(1f))
                    RunStatusBadge(run.status)
                }
                Spacer(modifier = Modifier.height(AppSpacing.xSmall))
                Row(horizontalArrangement = Arrangement.spacedBy(AppSpacing.large)) {
                    run.durationSeconds?.let { dur ->
                        Text(
                            "${"%.1f".format(dur)}s",
                            style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    if (run.results.isEmpty()) {
                        Text("No results", style = MaterialTheme.typography.bodySmall, color = AppColors.statusOrange)
                    } else {
                        Text(
                            "${run.results.size} results",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        val failCount = run.results.count { !it.metrics.didSucceed }
                        if (failCount > 0) {
                            Text("$failCount failed", style = MaterialTheme.typography.bodySmall, color = AppColors.statusOrange)
                        }
                    }
                }
            }
            Spacer(modifier = Modifier.width(AppSpacing.small))
            Icon(
                Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// -- Status Badge --

@Composable
private fun RunStatusBadge(status: BenchmarkRunStatus) {
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

// -- Empty State --

@Composable
private fun EmptyState() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = AppSpacing.xxLarge),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            Icons.Filled.Speed,
            contentDescription = null,
            modifier = Modifier.size(48.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
        )
        Spacer(modifier = Modifier.height(AppSpacing.large))
        Text(
            "No benchmark results yet",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(modifier = Modifier.height(AppSpacing.small))
        Text(
            "Download models first, then run benchmarks to measure on-device AI performance.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(horizontal = AppSpacing.xxLarge),
        )
    }
}
