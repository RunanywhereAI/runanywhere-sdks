package com.runanywhere.runanywhereai.ui.screens.benchmark

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.data.benchmark.CpuSampler
import com.runanywhere.runanywhereai.data.benchmark.DeviceMonitor
import com.runanywhere.runanywhereai.data.benchmark.DiskSpeed
import com.runanywhere.runanywhereai.data.benchmark.BenchmarkReport
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.RACTextStyles
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.runanywhereai.ui.theme.primaryGreen
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private const val HISTORY = 60

@Composable
fun DeviceMonitorSection() {
    val dimens = LocalDimens.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    val cpuSampler = remember { CpuSampler() }
    val cores = remember { DeviceMonitor.coreCount() }
    val ramHistory = remember { mutableStateListOf<Float>() }
    val cpuHistory = remember { mutableStateListOf<Float>() }

    var mem by remember { mutableStateOf(DeviceMonitor.memory(context)) }
    var storage by remember { mutableStateOf(DeviceMonitor.storage()) }
    var cpu by remember { mutableFloatStateOf(0f) }
    var freqMhz by remember { mutableStateOf<Int?>(null) }
    var diskSpeed by remember { mutableStateOf<DiskSpeed?>(null) }
    var measuring by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        while (true) {
            mem = DeviceMonitor.memory(context)
            storage = DeviceMonitor.storage()
            cpu = cpuSampler.sample()
            freqMhz = DeviceMonitor.currentFreqMhz()
            ramHistory.addCapped(mem.fraction * 100f)
            cpuHistory.addCapped(cpu)
            delay(1000)
        }
    }

    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = androidx.compose.foundation.shape.RoundedCornerShape(dimens.radiusLg),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            modifier = Modifier.padding(dimens.spacingLg),
            verticalArrangement = Arrangement.spacedBy(dimens.spacingMd),
        ) {
            Text("Live monitor", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)

            MetricGraph(
                label = "Memory",
                value = "${BenchmarkReport.gb(mem.usedBytes)} / ${BenchmarkReport.gb(mem.totalBytes)}",
                history = ramHistory,
                color = MaterialTheme.colorScheme.primary,
            )

            val freqText = freqMhz?.let { " · ${it} MHz" }.orEmpty()
            MetricGraph(
                label = "CPU (app)",
                value = "${"%.0f".format(cpu)}% · $cores cores$freqText",
                history = cpuHistory,
                color = MaterialTheme.colorScheme.tertiary,
            )

            StorageBar(used = storage.usedBytes, total = storage.totalBytes, free = storage.freeBytes)

            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd)) {
                Column(modifier = Modifier.weight(1f)) {
                    Text("Disk R/W", style = MaterialTheme.typography.bodyMedium)
                    val speed = diskSpeed
                    Text(
                        text = when {
                            measuring -> "Measuring…"
                            speed != null -> "W ${"%.0f".format(speed.writeMbps)} · R ${"%.0f".format(speed.readMbps)} MB/s"
                            else -> "Not measured"
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                OutlinedButton(
                    enabled = !measuring,
                    onClick = {
                        measuring = true
                        scope.launch {
                            val result = withContext(Dispatchers.IO) {
                                runCatching { DeviceMonitor.measureDiskSpeed(context) }.getOrNull()
                            }
                            diskSpeed = result
                            measuring = false
                        }
                    },
                ) {
                    if (measuring) {
                        CircularProgressIndicator(modifier = Modifier.size(dimens.iconSm), strokeWidth = 2.dp)
                    } else {
                        Icon(RACIcons.Outline.Bolt, contentDescription = null, modifier = Modifier.size(dimens.iconSm))
                        Text("Measure", modifier = Modifier.padding(start = dimens.spacingSm))
                    }
                }
            }
        }
    }
}

@Composable
private fun MetricGraph(label: String, value: String, history: List<Float>, color: Color) {
    val dimens = LocalDimens.current
    Column(verticalArrangement = Arrangement.spacedBy(dimens.spacingXs)) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(label, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(value, style = RACTextStyles.Metric)
        }
        Sparkline(
            values = history,
            maxValue = 100f,
            color = color,
            modifier = Modifier
                .fillMaxWidth()
                .height(40.dp),
        )
    }
}

@Composable
private fun Sparkline(values: List<Float>, maxValue: Float, color: Color, modifier: Modifier) {
    Canvas(modifier = modifier) {
        if (values.size < 2) return@Canvas
        val stepX = size.width / (values.size - 1)
        val line = Path()
        val fill = Path()
        values.forEachIndexed { i, v ->
            val x = i * stepX
            val y = size.height - (v / maxValue).coerceIn(0f, 1f) * size.height
            if (i == 0) {
                line.moveTo(x, y)
                fill.moveTo(x, size.height)
                fill.lineTo(x, y)
            } else {
                line.lineTo(x, y)
                fill.lineTo(x, y)
            }
        }
        fill.lineTo(size.width, size.height)
        fill.close()
        drawPath(fill, color.copy(alpha = 0.15f))
        drawPath(line, color, style = Stroke(width = 2.dp.toPx()))
    }
}

@Composable
private fun StorageBar(used: Long, total: Long, free: Long) {
    val dimens = LocalDimens.current
    Column(verticalArrangement = Arrangement.spacedBy(dimens.spacingXs)) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("Storage", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text("${BenchmarkReport.gb(used)} / ${BenchmarkReport.gb(total)}", style = RACTextStyles.Metric)
        }
        LinearProgressIndicator(
            progress = { if (total > 0) used.toFloat() / total else 0f },
            modifier = Modifier
                .fillMaxWidth()
                .height(6.dp),
            color = primaryGreen,
        )
        Text(
            "${BenchmarkReport.gb(free)} free",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

private fun MutableList<Float>.addCapped(value: Float) {
    add(value)
    while (size > HISTORY) removeAt(0)
}
