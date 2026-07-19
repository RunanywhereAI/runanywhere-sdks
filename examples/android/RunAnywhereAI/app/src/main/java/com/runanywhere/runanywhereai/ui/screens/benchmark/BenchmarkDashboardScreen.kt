package com.runanywhere.runanywhereai.ui.screens.benchmark

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.data.benchmark.BenchDeviceInfo
import com.runanywhere.runanywhereai.data.benchmark.BenchmarkCategory
import com.runanywhere.runanywhereai.data.benchmark.BenchmarkReport
import com.runanywhere.runanywhereai.data.benchmark.BenchmarkRun
import com.runanywhere.runanywhereai.data.benchmark.BenchmarkStatus
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.runanywhereai.ui.theme.primaryGreen
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun BenchmarkDashboardScreen(
    onOpenRun: (String) -> Unit,
    onOpenModels: () -> Unit = {},
    isModelSheetVisible: Boolean = false,
    selectedRunId: String? = null,
    modifier: Modifier = Modifier,
) {
    val dimens = LocalDimens.current
    val vm: BenchmarkViewModel = viewModel()
    val dateFormat = remember { SimpleDateFormat("MMM d, HH:mm", Locale.US) }

    // Re-check when first shown and whenever Models is dismissed, since a model may
    // have been downloaded while this screen remained mounted behind the sheet.
    LaunchedEffect(isModelSheetVisible) {
        if (!isModelSheetVisible) vm.refreshAvailability()
    }

    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .padding(dimens.screenPadding),
        verticalArrangement = Arrangement.spacedBy(dimens.spacingMd),
    ) {
        item { DeviceCard(vm.deviceInfo) }
        item { DeviceMonitorSection() }

        item {
            Text("Categories", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm)) {
                BenchmarkCategory.entries.forEach { category ->
                    FilterChip(
                        selected = category in vm.selected,
                        onClick = { vm.toggle(category) },
                        enabled = !vm.isRunning,
                        label = { Text(category.name) },
                    )
                }
            }
        }

        item {
            Text("Trials per test", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm)) {
                vm.trialOptions.forEach { count ->
                    FilterChip(
                        selected = vm.trials == count,
                        onClick = { vm.selectTrials(count) },
                        enabled = !vm.isRunning,
                        label = { Text(if (count == 1) "1 (fast)" else "$count") },
                    )
                }
            }
        }

        item {
            if (vm.isRunning) {
                RunningCard(
                    current = vm.progress?.current ?: 0,
                    total = vm.progress?.total ?: 0,
                    label = vm.progress?.let { "${it.category.label} · ${it.scenario} · ${it.model}" } ?: "Preparing…",
                    onCancel = vm::cancel,
                )
            } else if (!vm.hasModels) {
                NoModelsCard(onOpenModels = onOpenModels)
            } else {
                Button(
                    onClick = vm::run,
                    enabled = vm.selected.isNotEmpty(),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(RACIcons.Outline.PlayerPlay, contentDescription = null, modifier = Modifier.size(dimens.iconSm))
                    Text("Run benchmark", modifier = Modifier.padding(start = dimens.spacingSm))
                }
            }
        }

        vm.message?.let { message ->
            item {
                Surface(
                    color = MaterialTheme.colorScheme.errorContainer,
                    shape = RoundedCornerShape(dimens.radiusMd),
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable(onClick = vm::clearMessage),
                ) {
                    Text(
                        text = message,
                        color = MaterialTheme.colorScheme.onErrorContainer,
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.padding(dimens.spacingMd),
                    )
                }
            }
        }

        if (vm.history.isNotEmpty()) {
            item {
                Text("History", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            items(vm.history, key = { it.id }) { run ->
                HistoryCard(
                    run = run,
                    date = dateFormat.format(Date(run.startedAt)),
                    selected = run.id == selectedRunId,
                    onOpen = { onOpenRun(run.id) },
                    onDelete = { vm.delete(run.id) },
                )
            }
        } else if (!vm.isRunning) {
            item {
                Text(
                    "No runs yet. Pick categories and run a benchmark across your downloaded models.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun DeviceCard(info: BenchDeviceInfo) {
    val dimens = LocalDimens.current
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = RoundedCornerShape(dimens.radiusLg),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier.padding(dimens.spacingLg),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd),
        ) {
            Icon(
                RACIcons.Outline.Cpu,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(dimens.iconMd),
            )
            Column(modifier = Modifier.weight(1f)) {
                Text("${info.manufacturer} ${info.device}", style = MaterialTheme.typography.bodyLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(
                    "Android SDK ${info.androidSdk} · ${BenchmarkReport.gb(info.totalRamBytes)} RAM",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun NoModelsCard(onOpenModels: () -> Unit) {
    val dimens = LocalDimens.current
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = RoundedCornerShape(dimens.radiusLg),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            modifier = Modifier.padding(dimens.spacingLg),
            verticalArrangement = Arrangement.spacedBy(dimens.spacingSm),
        ) {
            Text("No models downloaded yet", style = MaterialTheme.typography.titleSmall)
            Text(
                "Download an on-device model to run benchmarks.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Button(onClick = onOpenModels, modifier = Modifier.fillMaxWidth()) {
                Icon(RACIcons.Outline.Download, contentDescription = null, modifier = Modifier.size(dimens.iconSm))
                Text("Download models", modifier = Modifier.padding(start = dimens.spacingSm))
            }
        }
    }
}

@Composable
private fun RunningCard(current: Int, total: Int, label: String, onCancel: () -> Unit) {
    val dimens = LocalDimens.current
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = RoundedCornerShape(dimens.radiusLg),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            modifier = Modifier.padding(dimens.spacingLg),
            verticalArrangement = Arrangement.spacedBy(dimens.spacingSm),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm)) {
                CircularProgressIndicator(modifier = Modifier.size(dimens.iconSm), strokeWidth = 2.dp)
                Text(
                    if (total > 0) "Running $current / $total" else "Running…",
                    style = MaterialTheme.typography.bodyLarge,
                    modifier = Modifier.weight(1f),
                )
                OutlinedButton(onClick = onCancel) { Text("Cancel") }
            }
            if (total > 0) {
                LinearProgressIndicator(progress = { current.toFloat() / total }, modifier = Modifier.fillMaxWidth())
            }
            Text(label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
private fun HistoryCard(run: BenchmarkRun, date: String, selected: Boolean, onOpen: () -> Unit, onDelete: () -> Unit) {
    val dimens = LocalDimens.current
    Surface(
        color = if (selected) MaterialTheme.colorScheme.surfaceContainerHighest else MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = RoundedCornerShape(dimens.radiusLg),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier
                .clickable(onClick = onOpen)
                .padding(dimens.spacingLg),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd),
        ) {
            StatusDot(run.status)
            Column(modifier = Modifier.weight(1f)) {
                Text(date, style = MaterialTheme.typography.bodyLarge)
                Text(
                    "${run.results.size} results · ${run.passed} ok · ${run.failed} failed · ${"%.1f".format(run.durationMs / 1000.0)}s",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            IconButton(onClick = onDelete) {
                Icon(RACIcons.Outline.Trash, contentDescription = "Delete", tint = MaterialTheme.colorScheme.error, modifier = Modifier.size(dimens.iconSm))
            }
            Icon(RACIcons.Outline.ChevronRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(dimens.iconSm))
        }
    }
}

@Composable
private fun StatusDot(status: BenchmarkStatus) {
    val color = statusColor(status)
    Box(
        modifier = Modifier
            .size(LocalDimens.current.spacingSm)
            .clip(CircleShape)
            .background(color),
    )
}

@Composable
internal fun statusColor(status: BenchmarkStatus): Color = when (status) {
    BenchmarkStatus.COMPLETED -> primaryGreen
    BenchmarkStatus.RUNNING -> MaterialTheme.colorScheme.primary
    BenchmarkStatus.CANCELLED -> MaterialTheme.colorScheme.tertiary
    BenchmarkStatus.FAILED -> MaterialTheme.colorScheme.error
}
