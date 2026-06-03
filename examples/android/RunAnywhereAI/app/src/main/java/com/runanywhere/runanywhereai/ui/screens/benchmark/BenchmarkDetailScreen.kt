package com.runanywhere.runanywhereai.ui.screens.benchmark

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import com.runanywhere.runanywhereai.data.benchmark.BenchmarkCategory
import com.runanywhere.runanywhereai.data.benchmark.BenchmarkReport
import com.runanywhere.runanywhereai.data.benchmark.BenchmarkResult
import com.runanywhere.runanywhereai.data.benchmark.BenchmarkRun
import com.runanywhere.runanywhereai.data.benchmark.BenchmarkStore
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.RACTextStyles
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.runanywhereai.ui.theme.primaryGreen
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun BenchmarkDetailScreen(runId: String) {
    val dimens = LocalDimens.current
    val context = LocalContext.current
    val run = BenchmarkStore.find(runId)

    if (run == null) {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text("Run not found.", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        return
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(dimens.screenPadding),
        verticalArrangement = Arrangement.spacedBy(dimens.spacingMd),
    ) {
        RunInfoCard(run)
        ExportCard(
            onCopyMarkdown = { copy(context, "Benchmark (Markdown)", BenchmarkReport.toMarkdown(run)) },
            onCopyJson = { copy(context, "Benchmark (JSON)", BenchmarkReport.toJson(run)) },
            onCopyCsv = { copy(context, "Benchmark (CSV)", BenchmarkReport.toCsv(run)) },
            onShare = { share(context, BenchmarkReport.toMarkdown(run)) },
        )
        BenchmarkCategory.entries.forEach { category ->
            val results = run.results.filter { it.category == category }
            if (results.isEmpty()) return@forEach
            Text(category.label, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            results.forEach { ResultCard(it) }
        }
    }
}

@Composable
private fun RunInfoCard(run: BenchmarkRun) {
    val dimens = LocalDimens.current
    val date = remember(run.id) { SimpleDateFormat("MMM d, yyyy HH:mm", Locale.US).format(Date(run.startedAt)) }
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = RoundedCornerShape(dimens.radiusLg),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.padding(dimens.spacingLg), verticalArrangement = Arrangement.spacedBy(dimens.spacingXs)) {
            Text("${run.device.manufacturer} ${run.device.device}", style = MaterialTheme.typography.titleMedium)
            Text(
                "$date · ${run.status.name.lowercase()} · ${"%.1f".format(run.durationMs / 1000.0)}s",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                "${run.results.size} results · ${run.passed} passed · ${run.failed} failed · Android SDK ${run.device.androidSdk} · ${BenchmarkReport.gb(run.device.totalRamBytes)} RAM",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun ExportCard(
    onCopyMarkdown: () -> Unit,
    onCopyJson: () -> Unit,
    onCopyCsv: () -> Unit,
    onShare: () -> Unit,
) {
    val dimens = LocalDimens.current
    Column(verticalArrangement = Arrangement.spacedBy(dimens.spacingSm)) {
        Row(horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm)) {
            OutlinedButton(onClick = onCopyMarkdown, modifier = Modifier.weight(1f)) { Text("Copy MD") }
            OutlinedButton(onClick = onCopyJson, modifier = Modifier.weight(1f)) { Text("Copy JSON") }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm)) {
            OutlinedButton(onClick = onCopyCsv, modifier = Modifier.weight(1f)) { Text("Copy CSV") }
            OutlinedButton(onClick = onShare, modifier = Modifier.weight(1f)) {
                Icon(RACIcons.Outline.Send, contentDescription = null, modifier = Modifier.size(dimens.iconSm))
                Text("Share", modifier = Modifier.padding(start = dimens.spacingSm))
            }
        }
    }
}

@Composable
private fun ResultCard(result: BenchmarkResult) {
    val dimens = LocalDimens.current
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = RoundedCornerShape(dimens.radiusMd),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.padding(dimens.spacingLg), verticalArrangement = Arrangement.spacedBy(dimens.spacingSm)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm)) {
                Icon(
                    imageVector = if (result.success) RACIcons.Outline.Check else RACIcons.Outline.Close,
                    contentDescription = null,
                    tint = if (result.success) primaryGreen else MaterialTheme.colorScheme.error,
                    modifier = Modifier.size(dimens.iconSm),
                )
                Column(modifier = Modifier.weight(1f)) {
                    Text(result.scenario, style = MaterialTheme.typography.bodyLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(
                        "${result.modelName} · ${result.framework}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            if (!result.success) {
                Text(
                    result.errorMessage ?: "Failed",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            } else {
                BenchmarkReport.metricRows(result).chunked(2).forEach { pair ->
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd)) {
                        pair.forEach { (label, value) -> MetricCell(label, value, Modifier.weight(1f)) }
                        if (pair.size == 1) Spacer(Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

@Composable
private fun MetricCell(label: String, value: String, modifier: Modifier = Modifier) {
    Column(modifier = modifier) {
        Text(label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = RACTextStyles.Metric)
    }
}

private fun copy(context: Context, label: String, text: String) {
    val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    cm.setPrimaryClip(ClipData.newPlainText(label, text))
    Toast.makeText(context, "Copied", Toast.LENGTH_SHORT).show()
}

private fun share(context: Context, text: String) {
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_TEXT, text)
    }
    context.startActivity(Intent.createChooser(intent, "Share benchmark"))
}
