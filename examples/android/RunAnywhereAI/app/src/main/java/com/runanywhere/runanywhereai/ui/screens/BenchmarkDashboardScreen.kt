package com.runanywhere.runanywhereai.ui.screens

import android.text.format.Formatter
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.models.BenchmarkCategory
import com.runanywhere.runanywhereai.models.BenchmarkRun
import com.runanywhere.runanywhereai.models.BenchmarkRunStatus
import com.runanywhere.runanywhereai.models.BenchmarkUiState
import com.runanywhere.runanywhereai.services.SyntheticInputGenerator
import com.runanywhere.runanywhereai.ui.components.RAButton
import com.runanywhere.runanywhereai.ui.components.RAButtonStyle
import com.runanywhere.runanywhereai.ui.components.RACard
import com.runanywhere.runanywhereai.ui.components.RAIconButton
import com.runanywhere.runanywhereai.ui.components.RAProgressBar
import com.runanywhere.runanywhereai.ui.icons.RAIcons
import com.runanywhere.runanywhereai.ui.theme.AppMotion
import com.runanywhere.runanywhereai.viewmodels.BenchmarkViewModel
import com.runanywhere.sdk.models.DeviceInfo
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

private val dateFormat: DateTimeFormatter =
    DateTimeFormatter.ofPattern("MMM d, h:mm a").withZone(ZoneId.systemDefault())

@Composable
fun BenchmarkDashboardScreen(
    onBack: () -> Unit = {},
    onNavigateToDetail: (String) -> Unit = {},
    benchmarkViewModel: BenchmarkViewModel = viewModel(),
) {
    val uiState by benchmarkViewModel.uiState.collectAsStateWithLifecycle()

    when (val state = uiState) {
        is BenchmarkUiState.Loading -> {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text("Loading...", style = MaterialTheme.typography.bodyLarge)
            }
        }

        is BenchmarkUiState.Error -> {
            Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        "Something went wrong",
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.error,
                    )
                    Spacer(Modifier.height(8.dp))
                    Text(
                        state.message,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        is BenchmarkUiState.Ready -> {
            BenchmarkDashboardContent(
                state = state,
                viewModel = benchmarkViewModel,
                onNavigateToDetail = onNavigateToDetail,
            )

            // Dialogs
            BenchmarkDialogs(state = state, viewModel = benchmarkViewModel)
        }
    }
}

// =============================================================================
// Dialogs
// =============================================================================

@Composable
private fun BenchmarkDialogs(
    state: BenchmarkUiState.Ready,
    viewModel: BenchmarkViewModel,
) {
    // Progress Dialog
    if (state.isRunning) {
        BenchmarkProgressDialog(
            progress = state.progress,
            currentScenario = state.currentScenario,
            currentModel = state.currentModel,
            completedCount = state.completedCount,
            totalCount = state.totalCount,
            onCancel = { viewModel.cancel() },
        )
    }

    // Clear Confirmation
    if (state.showClearConfirmation) {
        AlertDialog(
            onDismissRequest = { viewModel.dismissClearConfirmation() },
            title = { Text("Clear All Results?") },
            text = { Text("This will permanently delete all benchmark history.") },
            confirmButton = {
                TextButton(
                    onClick = { viewModel.clearAllResults() },
                    colors = ButtonDefaults.textButtonColors(
                        contentColor = MaterialTheme.colorScheme.error,
                    ),
                ) { Text("Clear") }
            },
            dismissButton = {
                TextButton(onClick = { viewModel.dismissClearConfirmation() }) { Text("Cancel") }
            },
        )
    }

    // Error Dialog
    state.errorMessage?.let { error ->
        AlertDialog(
            onDismissRequest = { viewModel.dismissError() },
            title = { Text("Benchmark Error") },
            text = { Text(error) },
            confirmButton = {
                TextButton(onClick = { viewModel.dismissError() }) { Text("OK") }
            },
        )
    }
}

// =============================================================================
// Dashboard Content
// =============================================================================

@Composable
private fun BenchmarkDashboardContent(
    state: BenchmarkUiState.Ready,
    viewModel: BenchmarkViewModel,
    onNavigateToDetail: (String) -> Unit,
) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item(key = "spacer_top") { Spacer(Modifier.height(4.dp)) }

        // Header description
        item(key = "header", contentType = "header") { HeaderSection() }

        // Device Info
        item(key = "device_info", contentType = "device_info") { DeviceInfoSection() }

        // Category Selection
        item(key = "categories", contentType = "categories") {
            CategorySelectionSection(
                selectedCategories = state.selectedCategories,
                onToggle = { viewModel.toggleCategory(it) },
            )
        }

        // Scenario descriptions for selected categories
        item(key = "scenarios", contentType = "scenarios") {
            AnimatedContent(
                targetState = state.selectedCategories,
                transitionSpec = {
                    (fadeIn(AppMotion.tweenMedium()) + expandVertically(AppMotion.tweenMedium()))
                        .togetherWith(fadeOut(AppMotion.tweenShort()) + shrinkVertically(AppMotion.tweenShort()))
                },
                label = "ScenarioDescriptions",
            ) { categories ->
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    BenchmarkCategory.entries
                        .filter { it in categories }
                        .forEach { category ->
                            CategoryScenarioRow(category)
                        }
                }
            }
        }

        // Run Controls
        item(key = "run_controls", contentType = "run_controls") {
            RunControlsSection(
                selectedCategories = state.selectedCategories,
                isRunning = state.isRunning,
                onRunAll = {
                    viewModel.selectAllCategories()
                    viewModel.runBenchmarks()
                },
                onRunSelected = { viewModel.runBenchmarks() },
            )
        }

        // Skipped categories warning
        item(key = "skipped_warning", contentType = "skipped_warning") {
            AnimatedVisibility(
                visible = state.skippedCategoriesMessage != null,
                enter = expandVertically(AppMotion.tweenMedium()) + fadeIn(AppMotion.tweenMedium()),
                exit = shrinkVertically(AppMotion.tweenShort()) + fadeOut(AppMotion.tweenShort()),
            ) {
                state.skippedCategoriesMessage?.let { msg ->
                    SkippedWarning(msg)
                }
            }
        }

        // History section
        if (state.pastRuns.isNotEmpty()) {
            item(key = "history_header", contentType = "section_header") {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    SectionHeader("History")
                    RAIconButton(
                        icon = RAIcons.Trash,
                        contentDescription = "Clear All",
                        tint = MaterialTheme.colorScheme.error,
                        onClick = { viewModel.showClearConfirmation() },
                    )
                }
            }

            items(
                items = state.pastRuns,
                key = { it.id },
                contentType = { "benchmark_run" },
            ) { run ->
                RunRow(run = run, onClick = { onNavigateToDetail(run.id) })
            }
        } else {
            item(key = "empty_state", contentType = "empty_state") { EmptyState() }
        }

        item(key = "spacer_bottom") { Spacer(Modifier.height(32.dp)) }
    }
}

// =============================================================================
// Header
// =============================================================================

@Composable
private fun HeaderSection() {
    RACard {
        Row(verticalAlignment = Alignment.Top) {
            Icon(
                RAIcons.Gauge,
                contentDescription = null,
                modifier = Modifier.size(20.dp),
                tint = MaterialTheme.colorScheme.primary,
            )
            Spacer(Modifier.width(12.dp))
            Text(
                "Run deterministic benchmarks against downloaded models. " +
                    "Synthetic inputs (silent audio, sine waves, solid-color images) ensure reproducible results.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// =============================================================================
// Device Info
// =============================================================================

@Composable
private fun DeviceInfoSection() {
    val context = LocalContext.current
    val deviceInfo = try {
        DeviceInfo.current
    } catch (_: Exception) {
        null
    }

    if (deviceInfo != null) {
        RACard {
            Text(
                "Device",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(Modifier.height(8.dp))
            InfoRow("Model", deviceInfo.modelName)
            InfoRow("Architecture", deviceInfo.architecture)
            InfoRow("RAM", Formatter.formatFileSize(context, deviceInfo.totalMemory))
            InfoRow(
                "Available",
                Formatter.formatFileSize(context, SyntheticInputGenerator.availableMemoryBytes()),
            )
        }
    }
}

@Composable
private fun InfoRow(label: String, value: String) {
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

// =============================================================================
// Category Selection
// =============================================================================

@Composable
private fun CategorySelectionSection(
    selectedCategories: Set<BenchmarkCategory>,
    onToggle: (BenchmarkCategory) -> Unit,
) {
    Column {
        SectionHeader("Categories")
        Spacer(Modifier.height(8.dp))
        Row(
            modifier = Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            BenchmarkCategory.entries.forEach { category ->
                val isSelected = category in selectedCategories
                FilterChip(
                    selected = isSelected,
                    onClick = { onToggle(category) },
                    label = { Text(category.displayName) },
                    leadingIcon = {
                        Icon(
                            categoryIcon(category),
                            contentDescription = null,
                            modifier = Modifier.size(18.dp),
                        )
                    },
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.15f),
                        selectedLabelColor = MaterialTheme.colorScheme.primary,
                        selectedLeadingIconColor = MaterialTheme.colorScheme.primary,
                    ),
                )
            }
        }
    }
}

// =============================================================================
// Scenario Descriptions
// =============================================================================

@Composable
private fun CategoryScenarioRow(category: BenchmarkCategory) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(
            categoryIcon(category),
            contentDescription = null,
            modifier = Modifier.size(14.dp),
            tint = MaterialTheme.colorScheme.onSurface,
        )
        Spacer(Modifier.width(6.dp))
        Text(
            category.displayName,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold,
        )
        Spacer(Modifier.width(8.dp))
        Text(
            text = scenarioDescription(category),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

private fun scenarioDescription(category: BenchmarkCategory): String = when (category) {
    BenchmarkCategory.LLM -> "50/256/512 tok - tok/s, TTFT, load"
    BenchmarkCategory.STT -> "Silent 2s, Sine 3s - RTF, latency"
    BenchmarkCategory.TTS -> "Short/Medium text - duration, chars"
    BenchmarkCategory.VLM -> "Solid/Gradient 224px - tok/s"
}

// =============================================================================
// Run Controls
// =============================================================================

@Composable
private fun RunControlsSection(
    selectedCategories: Set<BenchmarkCategory>,
    isRunning: Boolean,
    onRunAll: () -> Unit,
    onRunSelected: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        RAButton(
            text = "Run All Benchmarks",
            onClick = onRunAll,
            icon = RAIcons.Play,
            enabled = !isRunning,
            modifier = Modifier.fillMaxWidth(),
        )

        AnimatedVisibility(
            visible = selectedCategories.size < BenchmarkCategory.entries.size && selectedCategories.isNotEmpty(),
            enter = expandVertically(AppMotion.tweenMedium()) + fadeIn(AppMotion.tweenMedium()),
            exit = shrinkVertically(AppMotion.tweenShort()) + fadeOut(AppMotion.tweenShort()),
        ) {
            RAButton(
                text = "Run Selected (${selectedCategories.size})",
                onClick = onRunSelected,
                icon = RAIcons.Play,
                style = RAButtonStyle.Tonal,
                enabled = !isRunning,
                modifier = Modifier.fillMaxWidth(),
            )
        }

        AnimatedVisibility(
            visible = selectedCategories.isEmpty(),
            enter = fadeIn(AppMotion.tweenMedium()),
            exit = fadeOut(AppMotion.tweenShort()),
        ) {
            Text(
                "Select at least one category to run benchmarks.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error.copy(alpha = 0.8f),
            )
        }
    }
}

// =============================================================================
// Skipped Warning
// =============================================================================

@Composable
private fun SkippedWarning(message: String) {
    RACard(
        containerColor = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.3f),
        contentPadding = 12.dp,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                RAIcons.AlertCircle,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.error,
                modifier = Modifier.size(18.dp),
            )
            Spacer(Modifier.width(10.dp))
            Text(
                message,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
            )
        }
    }
}

// =============================================================================
// Run Row
// =============================================================================

@Composable
private fun RunRow(run: BenchmarkRun, onClick: () -> Unit) {
    RACard(
        modifier = Modifier.clickable(onClick = onClick),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        dateFormat.format(Instant.ofEpochMilli(run.startedAt)),
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Medium,
                    )
                    RunStatusBadge(run.status)
                }
                Spacer(Modifier.height(4.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    run.durationSeconds?.let { dur ->
                        Text(
                            "${"%.1f".format(dur)}s",
                            style = MaterialTheme.typography.bodySmall.copy(
                                fontFamily = FontFamily.Monospace,
                            ),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    if (run.results.isEmpty()) {
                        Text(
                            "No results",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error.copy(alpha = 0.7f),
                        )
                    } else {
                        Text(
                            "${run.results.size} results",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        val failCount = run.results.count { !it.metrics.didSucceed }
                        if (failCount > 0) {
                            Text(
                                "$failCount failed",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.error.copy(alpha = 0.7f),
                            )
                        }
                    }
                }
            }
            Spacer(Modifier.width(8.dp))
            Icon(
                RAIcons.ChevronRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                modifier = Modifier.size(20.dp),
            )
        }
    }
}

// =============================================================================
// Status Badge
// =============================================================================

@Composable
private fun RunStatusBadge(status: BenchmarkRunStatus) {
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

// =============================================================================
// Empty State
// =============================================================================

@Composable
private fun EmptyState() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 40.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            RAIcons.Gauge,
            contentDescription = null,
            modifier = Modifier.size(48.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
        )
        Spacer(Modifier.height(16.dp))
        Text(
            "No benchmark results yet",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(8.dp))
        Text(
            "Download models first, then run benchmarks to measure on-device AI performance.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(horizontal = 40.dp),
        )
    }
}

// =============================================================================
// Section Header
// =============================================================================

@Composable
private fun SectionHeader(title: String) {
    Text(
        text = title,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

// =============================================================================
// Progress Dialog
// =============================================================================

@Composable
private fun BenchmarkProgressDialog(
    progress: Float,
    currentScenario: String,
    currentModel: String,
    completedCount: Int,
    totalCount: Int,
    onCancel: () -> Unit,
) {
    androidx.compose.ui.window.Dialog(
        onDismissRequest = { /* Non-dismissible */ },
        properties = androidx.compose.ui.window.DialogProperties(
            dismissOnBackPress = false,
            dismissOnClickOutside = false,
        ),
    ) {
        RACard(contentPadding = 24.dp) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    text = "Running Benchmarks",
                    style = MaterialTheme.typography.headlineSmall,
                )

                Spacer(Modifier.height(24.dp))

                RAProgressBar(
                    progress = progress,
                    modifier = Modifier.fillMaxWidth(),
                )

                Spacer(Modifier.height(24.dp))

                Text(
                    text = currentScenario,
                    style = MaterialTheme.typography.bodyMedium,
                    textAlign = TextAlign.Center,
                )

                if (currentModel.isNotEmpty()) {
                    Spacer(Modifier.height(4.dp))
                    Text(
                        text = currentModel,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                    )
                }

                Spacer(Modifier.height(8.dp))

                Text(
                    text = "$completedCount / $totalCount",
                    style = MaterialTheme.typography.bodySmall.copy(
                        fontFamily = FontFamily.Monospace,
                    ),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )

                Spacer(Modifier.height(24.dp))

                RAButton(
                    text = "Cancel",
                    onClick = onCancel,
                    style = RAButtonStyle.Outlined,
                    contentColor = MaterialTheme.colorScheme.error,
                )
            }
        }
    }
}

// =============================================================================
// Helpers
// =============================================================================

internal fun categoryIcon(category: BenchmarkCategory): ImageVector = when (category) {
    BenchmarkCategory.LLM -> RAIcons.Chat
    BenchmarkCategory.STT -> RAIcons.Mic
    BenchmarkCategory.TTS -> RAIcons.Volume2
    BenchmarkCategory.VLM -> RAIcons.Eye
}
