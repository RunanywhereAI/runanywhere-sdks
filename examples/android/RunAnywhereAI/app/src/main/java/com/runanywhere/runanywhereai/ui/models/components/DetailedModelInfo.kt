package com.runanywhere.runanywhereai.ui.models.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Analytics
import androidx.compose.material.icons.filled.Architecture
import androidx.compose.material.icons.filled.Battery3Bar
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.Category
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Code
import androidx.compose.material.icons.filled.Cpu
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Hardware
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Memory
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material.icons.filled.Tag
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.data.repository.ModelInfo
import com.runanywhere.runanywhereai.utils.formatBytes

/**
 * Detailed model information component shown when model card is expanded
 */
@Composable
fun DetailedModelInfo(
    model: ModelInfo,
    performanceMetrics: ModelPerformanceMetrics? = null,
    hardwareRequirements: HardwareRequirements? = null,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Model specifications
        DetailSection(
            title = "Model Specifications",
            icon = Icons.Filled.Info
        ) {
            SpecificationGrid(model = model)
        }

        // Performance metrics
        performanceMetrics?.let { metrics ->
            DetailSection(
                title = "Performance Metrics",
                icon = Icons.Filled.Speed
            ) {
                PerformanceMetricsGrid(metrics = metrics)
            }
        }

        // Hardware requirements
        hardwareRequirements?.let { requirements ->
            DetailSection(
                title = "Hardware Requirements",
                icon = Icons.Filled.Hardware
            ) {
                HardwareRequirementsGrid(requirements = requirements)
            }
        }

        // Benchmark results
        performanceMetrics?.benchmarkScore?.let { score ->
            DetailSection(
                title = "Benchmark Results",
                icon = Icons.Filled.Analytics
            ) {
                BenchmarkResults(
                    score = score,
                    metrics = performanceMetrics
                )
            }
        }
    }
}

/**
 * Detail section wrapper with title and icon
 */
@Composable
private fun DetailSection(
    title: String,
    icon: ImageVector,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    Column(modifier = modifier) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
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

        Spacer(modifier = Modifier.height(8.dp))

        content()
    }
}

/**
 * Model specifications grid
 */
@Composable
private fun SpecificationGrid(
    model: ModelInfo,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(modifier = Modifier.fillMaxWidth()) {
            SpecificationItem(
                label = "Model ID",
                value = model.id,
                modifier = Modifier.weight(1f)
            )
            Spacer(modifier = Modifier.width(8.dp))
            SpecificationItem(
                label = "Framework",
                value = model.framework.name.replace("_", " "),
                modifier = Modifier.weight(1f)
            )
        }

        Row(modifier = Modifier.fillMaxWidth()) {
            SpecificationItem(
                label = "File Size",
                value = formatBytes(model.sizeBytes),
                modifier = Modifier.weight(1f)
            )
            Spacer(modifier = Modifier.width(8.dp))
            SpecificationItem(
                label = "Format",
                value = getModelFormat(model),
                modifier = Modifier.weight(1f)
            )
        }

        Row(modifier = Modifier.fillMaxWidth()) {
            SpecificationItem(
                label = "Parameters",
                value = model.parameters?.let { formatParameters(it) } ?: "Unknown",
                modifier = Modifier.weight(1f)
            )
            Spacer(modifier = Modifier.width(8.dp))
            SpecificationItem(
                label = "Quantization",
                value = model.quantization ?: "None",
                modifier = Modifier.weight(1f)
            )
        }

        SpecificationItem(
            label = "Download URL",
            value = if (model.downloadUrl.isNotEmpty()) "Available" else "System managed",
            modifier = Modifier.fillMaxWidth()
        )
    }
}

/**
 * Performance metrics grid
 */
@Composable
private fun PerformanceMetricsGrid(
    metrics: ModelPerformanceMetrics,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(modifier = Modifier.fillMaxWidth()) {
            MetricItem(
                icon = Icons.Filled.Speed,
                label = "Tokens/Second",
                value = "${metrics.tokensPerSecond.toInt()}",
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.weight(1f)
            )
            Spacer(modifier = Modifier.width(8.dp))
            MetricItem(
                icon = Icons.Filled.Timer,
                label = "Latency",
                value = "${metrics.latencyMs}ms",
                color = MaterialTheme.colorScheme.secondary,
                modifier = Modifier.weight(1f)
            )
        }

        Row(modifier = Modifier.fillMaxWidth()) {
            MetricItem(
                icon = Icons.Filled.Memory,
                label = "Memory Usage",
                value = "${metrics.memoryUsageMB}MB",
                color = MaterialTheme.colorScheme.tertiary,
                modifier = Modifier.weight(1f)
            )
            Spacer(modifier = Modifier.width(8.dp))
            metrics.powerConsumptionMw?.let { power ->
                MetricItem(
                    icon = Icons.Filled.Battery3Bar,
                    label = "Power",
                    value = "${power.toInt()}mW",
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.weight(1f)
                )
            } ?: Spacer(modifier = Modifier.weight(1f))
        }

        Row(modifier = Modifier.fillMaxWidth()) {
            metrics.accuracy?.let { accuracy ->
                MetricItem(
                    icon = Icons.Filled.CheckCircle,
                    label = "Accuracy",
                    value = "${(accuracy * 100).toInt()}%",
                    color = Color(0xFF4CAF50),
                    modifier = Modifier.weight(1f)
                )
            } ?: Spacer(modifier = Modifier.weight(1f))

            Spacer(modifier = Modifier.width(8.dp))

            metrics.benchmarkScore?.let { score ->
                MetricItem(
                    icon = Icons.Filled.Star,
                    label = "Benchmark",
                    value = score.toString(),
                    color = Color(0xFFFF9800),
                    modifier = Modifier.weight(1f)
                )
            } ?: Spacer(modifier = Modifier.weight(1f))
        }
    }
}

/**
 * Hardware requirements grid
 */
@Composable
private fun HardwareRequirementsGrid(
    requirements: HardwareRequirements,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(modifier = Modifier.fillMaxWidth()) {
            RequirementItem(
                label = "Min RAM",
                value = formatBytes(requirements.minRamBytes),
                modifier = Modifier.weight(1f)
            )
            Spacer(modifier = Modifier.width(8.dp))
            RequirementItem(
                label = "Min Storage",
                value = formatBytes(requirements.minStorageBytes),
                modifier = Modifier.weight(1f)
            )
        }

        Row(modifier = Modifier.fillMaxWidth()) {
            RequirementItem(
                label = "Min Android",
                value = "API ${requirements.minAndroidVersion}",
                modifier = Modifier.weight(1f)
            )
            Spacer(modifier = Modifier.width(8.dp))
            RequirementItem(
                label = "Thermal Optimized",
                value = if (requirements.thermalOptimized) "Yes" else "No",
                modifier = Modifier.weight(1f)
            )
        }

        // Hardware support details
        HardwareSupportDetails(requirements = requirements)
    }
}

/**
 * Hardware support details
 */
@Composable
private fun HardwareSupportDetails(
    requirements: HardwareRequirements,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        HardwareSupportRow(
            icon = Icons.Filled.Cpu,
            label = "CPU Support",
            isSupported = requirements.cpuSupported,
            details = requirements.cpuDetails
        )

        HardwareSupportRow(
            icon = Icons.Filled.GraphicEq,
            label = "GPU Support",
            isSupported = requirements.gpuSupported,
            details = requirements.gpuDetails
        )

        HardwareSupportRow(
            icon = Icons.Filled.Memory,
            label = "NPU Support",
            isSupported = requirements.npuSupported,
            details = requirements.npuDetails
        )
    }
}

/**
 * Hardware support row
 */
@Composable
private fun HardwareSupportRow(
    icon: ImageVector,
    label: String,
    isSupported: Boolean,
    details: String,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = if (isSupported) {
                MaterialTheme.colorScheme.primary
            } else {
                MaterialTheme.colorScheme.onSurfaceVariant
            },
            modifier = Modifier.size(20.dp)
        )

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = label,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium
            )
            Text(
                text = details,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        Icon(
            imageVector = if (isSupported) Icons.Filled.CheckCircle else Icons.Filled.Cancel,
            contentDescription = if (isSupported) "Supported" else "Not supported",
            tint = if (isSupported) {
                Color(0xFF4CAF50)
            } else {
                MaterialTheme.colorScheme.error
            },
            modifier = Modifier.size(18.dp)
        )
    }
}

/**
 * Benchmark results section
 */
@Composable
private fun BenchmarkResults(
    score: Int,
    metrics: ModelPerformanceMetrics,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        // Overall score
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Overall Score",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )

            Surface(
                shape = RoundedCornerShape(16.dp),
                color = getBenchmarkScoreColor(score).copy(alpha = 0.1f),
                border = BorderStroke(1.dp, getBenchmarkScoreColor(score).copy(alpha = 0.3f))
            ) {
                Text(
                    text = score.toString(),
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = getBenchmarkScoreColor(score)
                )
            }
        }

        // Performance categories
        BenchmarkCategory(
            label = "Speed",
            score = ((metrics.tokensPerSecond / 50f) * 100).toInt().coerceAtMost(100),
            color = MaterialTheme.colorScheme.primary
        )

        BenchmarkCategory(
            label = "Efficiency",
            score = ((1000f / metrics.latencyMs) * 100).toInt().coerceAtMost(100),
            color = MaterialTheme.colorScheme.secondary
        )

        metrics.accuracy?.let { accuracy ->
            BenchmarkCategory(
                label = "Accuracy",
                score = (accuracy * 100).toInt(),
                color = Color(0xFF4CAF50)
            )
        }
    }
}

/**
 * Benchmark category with progress bar
 */
@Composable
private fun BenchmarkCategory(
    label: String,
    score: Int,
    color: Color,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = label,
                style = MaterialTheme.typography.bodyMedium
            )
            Text(
                text = "$score%",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
                color = color
            )
        }

        Spacer(modifier = Modifier.height(4.dp))

        LinearProgressIndicator(
            progress = score / 100f,
            modifier = Modifier.fillMaxWidth(),
            color = color,
            trackColor = color.copy(alpha = 0.2f)
        )
    }
}

/**
 * Specification item
 */
@Composable
private fun SpecificationItem(
    label: String,
    value: String,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium
        )
    }
}

/**
 * Metric item with icon
 */
@Composable
private fun MetricItem(
    icon: ImageVector,
    label: String,
    value: String,
    color: Color,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(8.dp),
        color = color.copy(alpha = 0.1f)
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = color,
                modifier = Modifier.size(20.dp)
            )
            Text(
                text = label,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = value,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
                color = color
            )
        }
    }
}

/**
 * Requirement item
 */
@Composable
private fun RequirementItem(
    label: String,
    value: String,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(8.dp),
        color = MaterialTheme.colorScheme.surfaceVariant
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = label,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = value,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium
            )
        }
    }
}

// Helper functions
private fun getModelFormat(model: ModelInfo): String {
    return when (model.framework) {
        LLMFramework.LLAMA_CPP -> "GGUF"
        LLMFramework.TFLITE -> "TFLite"
        LLMFramework.ONNX_RUNTIME -> "ONNX"
        LLMFramework.EXECUTORCH -> "PTE"
        LLMFramework.GEMINI_NANO -> "System"
        else -> "Binary"
    }
}

private fun formatParameters(params: Long): String {
    return when {
        params >= 1_000_000_000 -> "${params / 1_000_000_000}B"
        params >= 1_000_000 -> "${params / 1_000_000}M"
        params >= 1_000 -> "${params / 1_000}K"
        else -> params.toString()
    }
}

private fun getBenchmarkScoreColor(score: Int): Color {
    return when {
        score >= 80 -> Color(0xFF4CAF50) // Green
        score >= 60 -> Color(0xFFFF9800) // Orange
        score >= 40 -> Color(0xFFFFC107) // Amber
        else -> Color(0xFFF44336) // Red
    }
}
