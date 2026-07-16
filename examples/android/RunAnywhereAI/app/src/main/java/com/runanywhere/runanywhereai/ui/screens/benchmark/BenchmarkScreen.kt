package com.runanywhere.runanywhereai.ui.screens.benchmark

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.runanywhere.runanywhereai.util.isExpandedScreen

// Responsive entry for the benchmark feature: a single dashboard on compact widths
// (detail is a separate nav route), or a two-pane list ↔ detail layout on expanded
// widths with in-pane selection.
@Composable
fun BenchmarkScreen(onOpenDetail: (String) -> Unit, onOpenModels: () -> Unit = {}) {
    if (!isExpandedScreen()) {
        BenchmarkDashboardScreen(onOpenRun = onOpenDetail, onOpenModels = onOpenModels)
        return
    }

    var selectedRunId by rememberSaveable { mutableStateOf<String?>(null) }
    Row(modifier = Modifier.fillMaxSize()) {
        BenchmarkDashboardScreen(
            onOpenRun = { selectedRunId = it },
            onOpenModels = onOpenModels,
            selectedRunId = selectedRunId,
            modifier = Modifier.weight(1f),
        )
        VerticalDivider()
        Box(modifier = Modifier.weight(1.2f).fillMaxSize(), contentAlignment = Alignment.Center) {
            val id = selectedRunId
            if (id != null) {
                BenchmarkDetailScreen(runId = id)
            } else {
                Text(
                    "Select a run to see details",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}
