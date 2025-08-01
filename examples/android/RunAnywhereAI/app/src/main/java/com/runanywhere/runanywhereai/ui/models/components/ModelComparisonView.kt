package com.runanywhere.runanywhereai.ui.models.components

import androidx.compose.animation.*
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.foundation.BorderStroke
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ClearAll
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Code
import androidx.compose.material.icons.filled.Compare
import androidx.compose.material.icons.filled.Hardware
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.data.repository.ModelInfo
import com.runanywhere.runanywhereai.llm.LLMFramework
import com.runanywhere.runanywhereai.utils.formatBytes

/**
 * Model comparison view that shows side-by-side comparison of selected models
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ModelComparisonView(
    comparedModels: List<ModelInfo>,
    performanceMetrics: Map<String, ModelPerformanceMetrics>,
    hardwareRequirements: Map<String, HardwareRequirements>,
    onRemoveModel: (ModelInfo) -> Unit,
    onClearAll: () -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier.fillMaxSize(),
        color = MaterialTheme.colorScheme.background
    ) {
        Column {
            // Header
            ComparisonHeader(
                modelCount = comparedModels.size,
                onClearAll = onClearAll,
                onClose = onClose
            )

            if (comparedModels.isEmpty()) {
                // Empty state
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(16.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Filled.Compare,
                            contentDescription = null,
                            modifier = Modifier.size(64.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Text(
                            text = "No models selected for comparison",
                            style = MaterialTheme.typography.headlineSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Text(
                            text = "Select models from the main list to compare them here",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center
                        )
                    }
                }
            } else {
                // Comparison table
                ComparisonTable(
                    models = comparedModels,
                    performanceMetrics = performanceMetrics,
                    hardwareRequirements = hardwareRequirements,
                    onRemoveModel = onRemoveModel,
                    modifier = Modifier.fillMaxSize()
                )
            }
        }
    }
}

/**
 * Comparison header with controls
 */
@Composable
private fun ComparisonHeader(
    modelCount: Int,
    onClearAll: () -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surfaceVariant,
        tonalElevation = 4.dp
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column {
                Text(
                    text = "Model Comparison",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = "$modelCount models selected",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                if (modelCount > 0) {
                    OutlinedButton(
                        onClick = onClearAll,
                        colors = ButtonDefaults.outlinedButtonColors(
                            contentColor = MaterialTheme.colorScheme.error
                        )
                    ) {
                        Icon(
                            imageVector = Icons.Filled.ClearAll,
                            contentDescription = null,
                            modifier = Modifier.size(18.dp)
                        )
                        Spacer(modifier = Modifier.width(4.dp))
                        Text("Clear All")
                    }
                }

                IconButton(onClick = onClose) {
                    Icon(
                        imageVector = Icons.Filled.Close,
                        contentDescription = "Close comparison"
                    )
                }
            }
        }
    }
}

/**
 * Comparison table with scrollable content
 */
@Composable
private fun ComparisonTable(
    models: List<ModelInfo>,
    performanceMetrics: Map<String, ModelPerformanceMetrics>,
    hardwareRequirements: Map<String, HardwareRequirements>,
    onRemoveModel: (ModelInfo) -> Unit,
    modifier: Modifier = Modifier
) {
    val horizontalScrollState = rememberScrollState()
    val verticalScrollState = rememberScrollState()

    Box(modifier = modifier) {
        Column(
            modifier = Modifier
                .verticalScroll(verticalScrollState)
                .horizontalScroll(horizontalScrollState)
                .padding(16.dp)
        ) {
            // Model headers
            ModelHeaderRow(
                models = models,
                onRemoveModel = onRemoveModel
            )

            Spacer(modifier = Modifier.height(16.dp))

            // Comparison categories
            ComparisonCategory(
                title = "Basic Information",
                icon = Icons.Filled.Info
            ) {
                BasicInfoRows(models = models)
            }

            Spacer(modifier = Modifier.height(16.dp))

            ComparisonCategory(
                title = "Performance Metrics",
                icon = Icons.Filled.Speed
            ) {
                PerformanceRows(
                    models = models,
                    performanceMetrics = performanceMetrics
                )
            }

            Spacer(modifier = Modifier.height(16.dp))

            ComparisonCategory(
                title = "Hardware Requirements",
                icon = Icons.Filled.Hardware
            ) {
                HardwareRows(
                    models = models,
                    hardwareRequirements = hardwareRequirements
                )
            }

            Spacer(modifier = Modifier.height(16.dp))

            ComparisonCategory(
                title = "Framework Support",
                icon = Icons.Filled.Code
            ) {
                FrameworkRows(models = models)
            }
        }
    }
}

/**
 * Model header row with model cards
 */
@Composable
private fun ModelHeaderRow(
    models: List<ModelInfo>,
    onRemoveModel: (ModelInfo) -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Row labels column
        Box(
            modifier = Modifier.width(150.dp),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = "Models",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold
            )
        }

        // Model cards
        models.forEach { model ->
            ModelComparisonCard(
                model = model,
                onRemove = { onRemoveModel(model) },
                modifier = Modifier.width(200.dp)
            )
        }
    }
}

/**
 * Individual model comparison card
 */
@Composable
private fun ModelComparisonCard(
    model: ModelInfo,
    onRemove: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier,
        elevation = CardDefaults.cardElevation(defaultElevation = 4.dp)
    ) {
        Column(
            modifier = Modifier.padding(12.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = model.name,
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Bold,
                        maxLines = 2
                    )

                    Spacer(modifier = Modifier.height(4.dp))

                    FrameworkBadge(
                        framework = model.framework,
                        modifier = Modifier.fillMaxWidth()
                    )
                }

                IconButton(
                    onClick = onRemove,
                    modifier = Modifier.size(24.dp)
                ) {
                    Icon(
                        imageVector = Icons.Filled.Close,
                        contentDescription = "Remove from comparison",
                        modifier = Modifier.size(16.dp)
                    )
                }
            }

            Spacer(modifier = Modifier.height(8.dp))

            Text(
                text = formatBytes(model.sizeBytes),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.primary,
                fontWeight = FontWeight.Medium
            )
        }
    }
}

/**
 * Comparison category section
 */
@Composable
private fun ComparisonCategory(
    title: String,
    icon: ImageVector,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    Column(modifier = modifier) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.padding(bottom = 12.dp)
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(20.dp)
            )
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.primary
            )
        }

        content()
    }
}

/**
 * Basic information comparison rows
 */
@Composable
private fun BasicInfoRows(
    models: List<ModelInfo>,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        ComparisonRow("Model ID") { model ->
            Text(
                text = model.id,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium
            )
        }

        ComparisonRow("Description") { model ->
            Text(
                text = model.description,
                style = MaterialTheme.typography.bodySmall,
                maxLines = 3
            )
        }

        ComparisonRow("File Size") { model ->
            Text(
                text = formatBytes(model.sizeBytes),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
                color = getComparisonColor(
                    models.map { it.sizeBytes },
                    model.sizeBytes,
                    true // smaller is better for size
                )
            )
        }

        ComparisonRow("Parameters") { model ->
            Text(
                text = model.parameters?.let { formatParameters(it) } ?: "Unknown",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium
            )
        }

        ComparisonRow("Quantization") { model ->
            Text(
                text = model.quantization ?: "None",
                style = MaterialTheme.typography.bodyMedium
            )
        }

        ComparisonRow("Downloaded") { model ->
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Icon(
                    imageVector = if (model.isDownloaded) {
                        Icons.Filled.CheckCircle
                    } else {
                        Icons.Filled.Cancel
                    },
                    contentDescription = null,
                    tint = if (model.isDownloaded) {
                        Color(0xFF4CAF50)
                    } else {
                        MaterialTheme.colorScheme.error
                    },
                    modifier = Modifier.size(16.dp)
                )
                Text(
                    text = if (model.isDownloaded) "Yes" else "No",
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (model.isDownloaded) {
                        Color(0xFF4CAF50)
                    } else {
                        MaterialTheme.colorScheme.error
                    }
                )
            }
        }
    }
}

/**
 * Performance metrics comparison rows
 */
@Composable
private fun PerformanceRows(
    models: List<ModelInfo>,
    performanceMetrics: Map<String, ModelPerformanceMetrics>,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        ComparisonRow("Tokens/Second") { model ->
            val metrics = performanceMetrics[model.id]
            if (metrics != null) {
                Text(
                    text = "${metrics.tokensPerSecond.toInt()}",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    color = getComparisonColor(
                        models.mapNotNull { performanceMetrics[it.id]?.tokensPerSecond },
                        metrics.tokensPerSecond,
                        false // higher is better
                    )
                )
            } else {
                Text(
                    text = "N/A",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        ComparisonRow("Latency") { model ->
            val metrics = performanceMetrics[model.id]
            if (metrics != null) {
                Text(
                    text = "${metrics.latencyMs}ms",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    color = getComparisonColor(
                        models.mapNotNull { performanceMetrics[it.id]?.latencyMs?.toFloat() },
                        metrics.latencyMs.toFloat(),
                        true // lower is better
                    )
                )
            } else {
                Text(
                    text = "N/A",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        ComparisonRow("Memory Usage") { model ->
            val metrics = performanceMetrics[model.id]
            if (metrics != null) {
                Text(
                    text = "${metrics.memoryUsageMB}MB",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    color = getComparisonColor(
                        models.mapNotNull { performanceMetrics[it.id]?.memoryUsageMB?.toFloat() },
                        metrics.memoryUsageMB.toFloat(),
                        true // lower is better
                    )
                )
            } else {
                Text(
                    text = "N/A",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        ComparisonRow("Power Consumption") { model ->
            val metrics = performanceMetrics[model.id]
            val power = metrics?.powerConsumptionMw
            if (power != null) {
                Text(
                    text = "${power.toInt()}mW",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    color = getComparisonColor(
                        models.mapNotNull { performanceMetrics[it.id]?.powerConsumptionMw },
                        power,
                        true // lower is better
                    )
                )
            } else {
                Text(
                    text = "N/A",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        ComparisonRow("Benchmark Score") { model ->
            val metrics = performanceMetrics[model.id]
            val score = metrics?.benchmarkScore
            if (score != null) {
                Text(
                    text = score.toString(),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    color = getComparisonColor(
                        models.mapNotNull { performanceMetrics[it.id]?.benchmarkScore?.toFloat() },
                        score.toFloat(),
                        false // higher is better
                    )
                )
            } else {
                Text(
                    text = "N/A",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

/**
 * Hardware requirements comparison rows
 */
@Composable
private fun HardwareRows(
    models: List<ModelInfo>,
    hardwareRequirements: Map<String, HardwareRequirements>,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        ComparisonRow("Min RAM") { model ->
            val requirements = hardwareRequirements[model.id]
            if (requirements != null) {
                Text(
                    text = formatBytes(requirements.minRamBytes),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    color = getComparisonColor(
                        models.mapNotNull { hardwareRequirements[it.id]?.minRamBytes?.toFloat() },
                        requirements.minRamBytes.toFloat(),
                        true // lower is better
                    )
                )
            } else {
                Text(
                    text = "N/A",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        ComparisonRow("CPU Support") { model ->
            val requirements = hardwareRequirements[model.id]
            SupportIndicator(
                isSupported = requirements?.cpuSupported ?: false,
                details = requirements?.cpuDetails ?: "Unknown"
            )
        }

        ComparisonRow("GPU Support") { model ->
            val requirements = hardwareRequirements[model.id]
            SupportIndicator(
                isSupported = requirements?.gpuSupported ?: false,
                details = requirements?.gpuDetails ?: "Unknown"
            )
        }

        ComparisonRow("NPU Support") { model ->
            val requirements = hardwareRequirements[model.id]
            SupportIndicator(
                isSupported = requirements?.npuSupported ?: false,
                details = requirements?.npuDetails ?: "Unknown"
            )
        }

        ComparisonRow("Thermal Optimized") { model ->
            val requirements = hardwareRequirements[model.id]
            SupportIndicator(
                isSupported = requirements?.thermalOptimized ?: false,
                details = if (requirements?.thermalOptimized == true) "Yes" else "No"
            )
        }
    }
}

/**
 * Framework support comparison rows
 */
@Composable
private fun FrameworkRows(
    models: List<ModelInfo>,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        ComparisonRow("Framework") { model ->
            FrameworkBadge(
                framework = model.framework,
                modifier = Modifier.fillMaxWidth()
            )
        }
    }
}

/**
 * Generic comparison row
 */
@Composable
private fun ComparisonRow(
    label: String,
    modifier: Modifier = Modifier,
    content: @Composable (ModelInfo) -> Unit
) {
    // This would need to access the models list, so it should be moved to the calling context
    // For now, it's a placeholder structure
}

/**
 * Support indicator component
 */
@Composable
private fun SupportIndicator(
    isSupported: Boolean,
    details: String,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Icon(
            imageVector = if (isSupported) Icons.Filled.CheckCircle else Icons.Filled.Cancel,
            contentDescription = null,
            tint = if (isSupported) Color(0xFF4CAF50) else MaterialTheme.colorScheme.error,
            modifier = Modifier.size(16.dp)
        )
        Text(
            text = if (isSupported) "Yes" else "No",
            style = MaterialTheme.typography.bodyMedium,
            color = if (isSupported) Color(0xFF4CAF50) else MaterialTheme.colorScheme.error
        )
    }
}

// Helper functions
private fun formatParameters(params: Long): String {
    return when {
        params >= 1_000_000_000 -> "${params / 1_000_000_000}B"
        params >= 1_000_000 -> "${params / 1_000_000}M"
        params >= 1_000 -> "${params / 1_000}K"
        else -> params.toString()
    }
}

private fun getComparisonColor(
    allValues: List<Float>,
    currentValue: Float,
    lowerIsBetter: Boolean
): Color {
    if (allValues.size <= 1) return Color.Unspecified

    val min = allValues.minOrNull() ?: return Color.Unspecified
    val max = allValues.maxOrNull() ?: return Color.Unspecified

    if (min == max) return Color.Unspecified

    val isBest = if (lowerIsBetter) {
        currentValue == min
    } else {
        currentValue == max
    }

    val isWorst = if (lowerIsBetter) {
        currentValue == max
    } else {
        currentValue == min
    }

    return when {
        isBest -> Color(0xFF4CAF50) // Green for best
        isWorst -> Color(0xFFF44336) // Red for worst
        else -> Color(0xFFFF9800) // Orange for middle
    }
}
