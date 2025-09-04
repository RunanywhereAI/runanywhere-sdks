package com.runanywhere.runanywhereai.ui.models.components

import androidx.compose.animation.*
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Android
import androidx.compose.material.icons.filled.FlashOn
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Code
import androidx.compose.material.icons.filled.Compare
import androidx.compose.material.icons.filled.Computer
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DeviceThermostat
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Equalizer
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Hub
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Memory
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.Psychology
import androidx.compose.material.icons.filled.RecordVoiceOver
import androidx.compose.material.icons.filled.RocketLaunch
import androidx.compose.material.icons.filled.SmartToy
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material.icons.filled.Thermostat
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.runanywhere.runanywhereai.data.repository.ModelInfo
import com.runanywhere.runanywhereai.data.repository.DownloadProgress
import com.runanywhere.runanywhereai.llm.LLMFramework
import com.runanywhere.runanywhereai.utils.formatBytes

/**
 * Enhanced model card with detailed information, compatibility badges, and performance metrics
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EnhancedModelCard(
    model: ModelInfo,
    isSelected: Boolean = false,
    downloadProgress: DownloadProgress? = null,
    performanceMetrics: ModelPerformanceMetrics? = null,
    hardwareRequirements: HardwareRequirements? = null,
    onSelect: () -> Unit = {},
    onDownload: () -> Unit = {},
    onDelete: () -> Unit = {},
    onCompare: () -> Unit = {},
    modifier: Modifier = Modifier
) {
    var isExpanded by remember { mutableStateOf(false) }

    Card(
        modifier = modifier
            .fillMaxWidth()
            .clickable { onSelect() }
            .then(
                if (isSelected) {
                    Modifier.border(
                        2.dp,
                        MaterialTheme.colorScheme.primary,
                        RoundedCornerShape(12.dp)
                    )
                } else Modifier
            ),
        elevation = CardDefaults.cardElevation(
            defaultElevation = if (isSelected) 8.dp else 4.dp
        ),
        shape = RoundedCornerShape(12.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp)
        ) {
            // Header with model name and framework badge
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = model.name,
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )

                    Text(
                        text = model.description,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                }

                // Framework compatibility badge
                FrameworkBadge(
                    framework = model.framework,
                    modifier = Modifier.padding(start = 8.dp)
                )
            }

            Spacer(modifier = Modifier.height(12.dp))

            // Model statistics row
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                StatisticChip(
                    icon = Icons.Filled.Storage,
                    label = "Size",
                    value = formatBytes(model.sizeBytes),
                    color = MaterialTheme.colorScheme.primary
                )

                performanceMetrics?.let { metrics ->
                    StatisticChip(
                        icon = Icons.Filled.Speed,
                        label = "Speed",
                        value = "${metrics.tokensPerSecond.toInt()} t/s",
                        color = MaterialTheme.colorScheme.secondary
                    )
                }

                hardwareRequirements?.let { requirements ->
                    StatisticChip(
                        icon = Icons.Filled.Memory,
                        label = "RAM",
                        value = formatBytes(requirements.minRamBytes),
                        color = MaterialTheme.colorScheme.tertiary
                    )
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            // Hardware compatibility indicators
            hardwareRequirements?.let { requirements ->
                HardwareCompatibilityRow(
                    requirements = requirements,
                    modifier = Modifier.fillMaxWidth()
                )

                Spacer(modifier = Modifier.height(12.dp))
            }

            // Download progress or action buttons
            if (downloadProgress != null) {
                DownloadProgressSection(
                    progress = downloadProgress,
                    onCancel = { /* Handle cancel */ }
                )
            } else {
                ActionButtonsRow(
                    model = model,
                    onDownload = onDownload,
                    onDelete = onDelete,
                    onCompare = onCompare,
                    onToggleExpanded = { isExpanded = !isExpanded }
                )
            }

            // Expandable details section
            AnimatedVisibility(
                visible = isExpanded,
                enter = expandVertically() + fadeIn(),
                exit = shrinkVertically() + fadeOut()
            ) {
                Column {
                    Spacer(modifier = Modifier.height(12.dp))
                    Divider()
                    Spacer(modifier = Modifier.height(12.dp))

                    DetailedModelInfo(
                        model = model,
                        performanceMetrics = performanceMetrics,
                        hardwareRequirements = hardwareRequirements
                    )
                }
            }
        }
    }
}

/**
 * Framework compatibility badge
 */
@Composable
private fun FrameworkBadge(
    framework: LLMFramework,
    modifier: Modifier = Modifier
) {
    val (color, icon, text) = when (framework) {
        LLMFramework.GEMINI_NANO -> Triple(
            Color(0xFF4285F4), // Google Blue
            Icons.Filled.Android,
            "Gemini"
        )
        LLMFramework.TFLITE -> Triple(
            Color(0xFFFF6F00), // TensorFlow Orange
            Icons.Filled.Psychology,
            "TFLite"
        )
        LLMFramework.LLAMA_CPP -> Triple(
            Color(0xFF8BC34A), // Green
            Icons.Filled.Code,
            "llama.cpp"
        )
        LLMFramework.ONNX_RUNTIME -> Triple(
            Color(0xFF9C27B0), // Purple
            Icons.Filled.Hub,
            "ONNX"
        )
        LLMFramework.EXECUTORCH -> Triple(
            Color(0xFFE91E63), // Pink
            Icons.Filled.FlashOn,
            "ExecuTorch"
        )
        LLMFramework.MLC_LLM -> Triple(
            Color(0xFF00BCD4), // Cyan
            Icons.Filled.RocketLaunch,
            "MLC-LLM"
        )
        LLMFramework.MEDIAPIPE -> Triple(
            Color(0xFF607D8B), // Blue Grey
            Icons.Filled.Videocam,
            "MediaPipe"
        )
        LLMFramework.PICOLLM -> Triple(
            Color(0xFF795548), // Brown
            Icons.Filled.RecordVoiceOver,
            "picoLLM"
        )
        LLMFramework.AI_CORE -> Triple(
            Color(0xFF3F51B5), // Indigo
            Icons.Filled.SmartToy,
            "AI Core"
        )
    }

    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(20.dp),
        color = color.copy(alpha = 0.1f),
        border = BorderStroke(1.dp, color.copy(alpha = 0.3f))
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = color,
                modifier = Modifier.size(16.dp)
            )
            Text(
                text = text,
                style = MaterialTheme.typography.labelSmall,
                color = color,
                fontWeight = FontWeight.Medium
            )
        }
    }
}

/**
 * Statistic chip component
 */
@Composable
private fun StatisticChip(
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
        Row(
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = color,
                modifier = Modifier.size(14.dp)
            )
            Column {
                Text(
                    text = label,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontSize = 10.sp
                )
                Text(
                    text = value,
                    style = MaterialTheme.typography.labelMedium,
                    color = color,
                    fontWeight = FontWeight.Medium
                )
            }
        }
    }
}

/**
 * Hardware compatibility row
 */
@Composable
private fun HardwareCompatibilityRow(
    requirements: HardwareRequirements,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        HardwareIndicator(
            icon = Icons.Filled.Computer,
            label = "CPU",
            isSupported = requirements.cpuSupported,
            details = requirements.cpuDetails
        )

        HardwareIndicator(
            icon = Icons.Filled.Equalizer,
            label = "GPU",
            isSupported = requirements.gpuSupported,
            details = requirements.gpuDetails
        )

        HardwareIndicator(
            icon = Icons.Filled.Memory,
            label = "NPU",
            isSupported = requirements.npuSupported,
            details = requirements.npuDetails
        )

        HardwareIndicator(
            icon = Icons.Filled.Thermostat,
            label = "Thermal",
            isSupported = requirements.thermalOptimized,
            details = "Thermal optimized"
        )
    }
}

/**
 * Hardware compatibility indicator
 */
@Composable
private fun HardwareIndicator(
    icon: ImageVector,
    label: String,
    isSupported: Boolean,
    details: String,
    modifier: Modifier = Modifier
) {
    val color = if (isSupported) {
        MaterialTheme.colorScheme.primary
    } else {
        MaterialTheme.colorScheme.onSurfaceVariant
    }

    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(6.dp),
        color = color.copy(alpha = 0.1f),
        border = BorderStroke(
            1.dp,
            color.copy(alpha = if (isSupported) 0.3f else 0.1f)
        )
    ) {
        Column(
            modifier = Modifier.padding(6.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = color,
                modifier = Modifier.size(16.dp)
            )
            Text(
                text = label,
                style = MaterialTheme.typography.labelSmall,
                color = color,
                fontSize = 9.sp
            )
        }
    }
}

/**
 * Download progress section
 */
@Composable
private fun DownloadProgressSection(
    progress: DownloadProgress,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Downloading...",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium
            )

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = "${(progress.progress * 100).toInt()}%",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary
                )

                IconButton(
                    onClick = onCancel,
                    modifier = Modifier.size(24.dp)
                ) {
                    Icon(
                        imageVector = Icons.Filled.Cancel,
                        contentDescription = "Cancel download",
                        modifier = Modifier.size(16.dp)
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(8.dp))

        LinearProgressIndicator(
            progress = progress.progress,
            modifier = Modifier.fillMaxWidth(),
            color = MaterialTheme.colorScheme.primary,
            trackColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.2f)
        )

        Spacer(modifier = Modifier.height(4.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = formatBytes(progress.downloadedBytes),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            Text(
                text = "${progress.speedBytesPerSecond?.let { formatBytes(it) } ?: "0 B"}/s",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

/**
 * Action buttons row
 */
@Composable
private fun ActionButtonsRow(
    model: ModelInfo,
    onDownload: () -> Unit,
    onDelete: () -> Unit,
    onCompare: () -> Unit,
    onToggleExpanded: () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        // Download/Delete button
        if (model.isDownloaded) {
            OutlinedButton(
                onClick = onDelete,
                colors = ButtonDefaults.outlinedButtonColors(
                    contentColor = MaterialTheme.colorScheme.error
                ),
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.error.copy(alpha = 0.5f)),
                modifier = Modifier.weight(1f)
            ) {
                Icon(
                    imageVector = Icons.Filled.Delete,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp)
                )
                Spacer(modifier = Modifier.width(4.dp))
                Text("Delete")
            }
        } else {
            Button(
                onClick = onDownload,
                modifier = Modifier.weight(1f)
            ) {
                Icon(
                    imageVector = Icons.Filled.Download,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp)
                )
                Spacer(modifier = Modifier.width(4.dp))
                Text("Download")
            }
        }

        // Compare button
        OutlinedButton(
            onClick = onCompare,
            modifier = Modifier.width(120.dp)
        ) {
            Icon(
                imageVector = Icons.Filled.Compare,
                contentDescription = null,
                modifier = Modifier.size(16.dp)
            )
            Spacer(modifier = Modifier.width(4.dp))
            Text("Compare")
        }

        // Expand details button
        IconButton(onClick = onToggleExpanded) {
            Icon(
                imageVector = Icons.Filled.ExpandMore,
                contentDescription = "Show details"
            )
        }
    }
}

/**
 * Model performance metrics data
 */
data class ModelPerformanceMetrics(
    val tokensPerSecond: Float,
    val latencyMs: Long,
    val memoryUsageMB: Int,
    val powerConsumptionMw: Float?,
    val accuracy: Float?,
    val benchmarkScore: Int?
)

/**
 * Hardware requirements data
 */
data class HardwareRequirements(
    val minRamBytes: Long,
    val minStorageBytes: Long,
    val cpuSupported: Boolean,
    val cpuDetails: String,
    val gpuSupported: Boolean,
    val gpuDetails: String,
    val npuSupported: Boolean,
    val npuDetails: String,
    val thermalOptimized: Boolean,
    val minAndroidVersion: Int
)
