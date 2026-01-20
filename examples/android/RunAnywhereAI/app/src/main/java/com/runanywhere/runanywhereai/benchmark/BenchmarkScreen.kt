package com.runanywhere.runanywhereai.benchmark

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Divider
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.ui.theme.AppSpacing

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BenchmarkScreen(
    viewModel: BenchmarkViewModel = viewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()
    val benchmarkState by viewModel.benchmarkService.state.collectAsState()
    val progress by viewModel.benchmarkService.progress.collectAsState()
    val results by viewModel.benchmarkService.results.collectAsState()
    val error by viewModel.benchmarkService.error.collectAsState()
    
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Benchmark") }
            )
        }
    ) { paddingValues ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
                .padding(horizontal = AppSpacing.medium),
            verticalArrangement = Arrangement.spacedBy(AppSpacing.medium)
        ) {
            // Configuration Section
            item {
                ConfigurationSection(
                    selectedConfig = uiState.selectedConfig,
                    onConfigSelected = { viewModel.setSelectedConfig(it) },
                    enabled = !benchmarkState.isRunning
                )
            }
            
            // Model Selection Section
            item {
                ModelSelectionSection(
                    availableModels = uiState.availableModels,
                    selectedModelIds = uiState.selectedModelIds,
                    onToggleModel = { viewModel.toggleModelSelection(it) },
                    onSelectAll = { viewModel.selectAllModels() },
                    onDeselectAll = { viewModel.deselectAllModels() },
                    enabled = !benchmarkState.isRunning
                )
            }
            
            // Control Buttons
            item {
                ControlButtons(
                    isRunning = benchmarkState.isRunning,
                    canStart = uiState.canStartBenchmark && !benchmarkState.isRunning,
                    hasResults = results.isNotEmpty(),
                    onStart = { viewModel.startBenchmark() },
                    onCancel = { viewModel.cancelBenchmark() },
                    onClear = { viewModel.clearResults() }
                )
            }
            
            // Progress Section
            if (benchmarkState.isRunning && progress != null) {
                item {
                    ProgressSection(
                        state = benchmarkState,
                        progress = progress!!,
                        viewModel = viewModel
                    )
                }
            }
            
            // Error Section
            error?.let { err ->
                item {
                    ErrorSection(error = err)
                }
            }
            
            // Results Section
            if (results.isNotEmpty()) {
                item {
                    Text(
                        text = "Results",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold
                    )
                }
                
                items(results) { result ->
                    BenchmarkResultCard(result = result, viewModel = viewModel)
                }
            }
            
            item { Spacer(modifier = Modifier.height(AppSpacing.large)) }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ConfigurationSection(
    selectedConfig: ConfigOption,
    onConfigSelected: (ConfigOption) -> Unit,
    enabled: Boolean,
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Column(
            modifier = Modifier.padding(AppSpacing.medium)
        ) {
            Text(
                text = "Configuration",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold
            )
            
            Spacer(modifier = Modifier.height(AppSpacing.small))
            
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(AppSpacing.small)
            ) {
                ConfigOption.entries.forEach { option ->
                    FilterChip(
                        selected = selectedConfig == option,
                        onClick = { onConfigSelected(option) },
                        enabled = enabled,
                        label = { Text(option.displayName) },
                        modifier = Modifier.weight(1f)
                    )
                }
            }
            
            Spacer(modifier = Modifier.height(AppSpacing.small))
            
            Text(
                text = selectedConfig.description,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun ModelSelectionSection(
    availableModels: List<com.runanywhere.sdk.public.extensions.Models.ModelInfo>,
    selectedModelIds: Set<String>,
    onToggleModel: (String) -> Unit,
    onSelectAll: () -> Unit,
    onDeselectAll: () -> Unit,
    enabled: Boolean,
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Column(
            modifier = Modifier.padding(AppSpacing.medium)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Models",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold
                )
                
                TextButton(
                    onClick = {
                        if (selectedModelIds.isEmpty()) onSelectAll() else onDeselectAll()
                    },
                    enabled = enabled
                ) {
                    Text(if (selectedModelIds.isEmpty()) "Select All" else "Deselect All")
                }
            }
            
            if (availableModels.isEmpty()) {
                Text(
                    text = "No downloaded LLM models found. Download a model first.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(vertical = AppSpacing.medium)
                )
            } else {
                availableModels.forEach { model ->
                    ModelSelectionRow(
                        modelName = model.name,
                        framework = model.framework.name,
                        isSelected = selectedModelIds.contains(model.id),
                        onToggle = { onToggleModel(model.id) },
                        enabled = enabled
                    )
                }
            }
        }
    }
}

@Composable
private fun ModelSelectionRow(
    modelName: String,
    framework: String,
    isSelected: Boolean,
    onToggle: () -> Unit,
    enabled: Boolean,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = enabled) { onToggle() }
            .padding(vertical = AppSpacing.small),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = if (isSelected) Icons.Default.Check else Icons.Default.Clear,
            contentDescription = null,
            tint = if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline,
            modifier = Modifier.size(20.dp)
        )
        
        Spacer(modifier = Modifier.width(AppSpacing.small))
        
        Column {
            Text(
                text = modelName,
                style = MaterialTheme.typography.bodyMedium
            )
            Text(
                text = framework,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun ControlButtons(
    isRunning: Boolean,
    canStart: Boolean,
    hasResults: Boolean,
    onStart: () -> Unit,
    onCancel: () -> Unit,
    onClear: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(AppSpacing.small)
    ) {
        if (isRunning) {
            Button(
                onClick = onCancel,
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.error
                ),
                modifier = Modifier.weight(1f)
            ) {
                Icon(Icons.Default.Clear, contentDescription = null)
                Spacer(modifier = Modifier.width(AppSpacing.small))
                Text("Cancel")
            }
        } else {
            Button(
                onClick = onStart,
                enabled = canStart,
                modifier = Modifier.weight(1f)
            ) {
                Icon(Icons.Default.PlayArrow, contentDescription = null)
                Spacer(modifier = Modifier.width(AppSpacing.small))
                Text("Run Benchmark")
            }
            
            if (hasResults) {
                OutlinedButton(onClick = onClear) {
                    Text("Clear")
                }
            }
        }
    }
}

@Composable
private fun ProgressSection(
    state: BenchmarkState,
    progress: BenchmarkProgress,
    viewModel: BenchmarkViewModel,
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Column(
            modifier = Modifier.padding(AppSpacing.medium)
        ) {
            LinearProgressIndicator(
                progress = { progress.overallProgress },
                modifier = Modifier.fillMaxWidth()
            )
            
            Spacer(modifier = Modifier.height(AppSpacing.small))
            
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = stateDescription(state),
                    style = MaterialTheme.typography.bodySmall
                )
                Text(
                    text = viewModel.formatProgress(progress.overallProgress),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = "Elapsed: ${viewModel.formatDuration(progress.elapsedTimeMs)}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                progress.estimatedRemainingTimeMs?.let { remaining ->
                    Text(
                        text = "Remaining: ~${viewModel.formatDuration(remaining)}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}

@Composable
private fun ErrorSection(error: Throwable) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.errorContainer
        )
    ) {
        Row(
            modifier = Modifier.padding(AppSpacing.medium),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = Icons.Default.Warning,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.error
            )
            Spacer(modifier = Modifier.width(AppSpacing.small))
            Text(
                text = error.message ?: "Unknown error",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onErrorContainer
            )
        }
    }
}

@Composable
private fun BenchmarkResultCard(
    result: BenchmarkResult,
    viewModel: BenchmarkViewModel,
) {
    var isExpanded by remember { mutableStateOf(false) }
    
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface
        )
    ) {
        Column(
            modifier = Modifier.padding(AppSpacing.medium)
        ) {
            // Header
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { isExpanded = !isExpanded },
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(
                        text = result.modelName,
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Medium
                    )
                    Text(
                        text = result.framework,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(horizontalAlignment = Alignment.End) {
                        Text(
                            text = viewModel.formatTokensPerSecond(result.avgTokensPerSecond),
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.primary
                        )
                        Text(
                            text = "avg",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    
                    Spacer(modifier = Modifier.width(AppSpacing.small))
                    
                    Icon(
                        imageVector = if (isExpanded) Icons.Default.KeyboardArrowUp else Icons.Default.KeyboardArrowDown,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            
            // Expanded details
            AnimatedVisibility(
                visible = isExpanded,
                enter = expandVertically(),
                exit = shrinkVertically()
            ) {
                Column {
                    Spacer(modifier = Modifier.height(AppSpacing.small))
                    Divider()
                    Spacer(modifier = Modifier.height(AppSpacing.small))
                    
                    // Metrics grid
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceEvenly
                    ) {
                        MetricItem("TTFT (avg)", viewModel.formatLatency(result.avgTtftMs))
                        MetricItem("Latency (avg)", viewModel.formatLatency(result.avgLatencyMs))
                    }
                    
                    Spacer(modifier = Modifier.height(AppSpacing.small))
                    
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceEvenly
                    ) {
                        MetricItem("P95 tok/s", viewModel.formatTokensPerSecond(result.p95TokensPerSecond))
                        MetricItem("Load Time", viewModel.formatLatency(result.modelLoadTimeMs))
                    }
                    
                    Spacer(modifier = Modifier.height(AppSpacing.small))
                    
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceEvenly
                    ) {
                        MetricItem("Peak Memory", viewModel.formatMemory(result.peakMemoryBytes))
                        MetricItem("Total Runs", "${result.totalRuns}")
                    }
                }
            }
        }
    }
}

@Composable
private fun MetricItem(label: String, value: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.Medium
        )
    }
}

private fun stateDescription(state: BenchmarkState): String {
    return when (state) {
        is BenchmarkState.Idle -> "Ready"
        is BenchmarkState.Preparing -> "Preparing..."
        is BenchmarkState.WarmingUp -> "Warming up ${state.model} (${state.iteration}/${state.total})"
        is BenchmarkState.Running -> "Testing ${state.model} - ${state.prompt} (${state.iteration}/${state.total})"
        is BenchmarkState.Completed -> "Completed"
        is BenchmarkState.Failed -> "Failed: ${state.error}"
    }
}
