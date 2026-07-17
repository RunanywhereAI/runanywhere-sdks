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

/**
 * Responsive benchmark entry point: a dashboard on compact widths and a two-pane
 * dashboard/detail layout on expanded widths.
 *
 * [isModelSheetVisible] lets the dashboard refresh downloaded-model availability when
 * the model sheet closes while this screen remains mounted.
 */
@Composable
fun BenchmarkScreen(
    onOpenDetail: (String) -> Unit,
    onOpenModels: () -> Unit = {},
    isModelSheetVisible: Boolean = false,
) {
    if (!isExpandedScreen()) {
        BenchmarkDashboardScreen(
            onOpenRun = onOpenDetail,
            onOpenModels = onOpenModels,
            isModelSheetVisible = isModelSheetVisible,
        )
        return
    }

    var selectedRunId by rememberSaveable { mutableStateOf<String?>(null) }
    Row(modifier = Modifier.fillMaxSize()) {
        BenchmarkDashboardScreen(
            onOpenRun = { selectedRunId = it },
            onOpenModels = onOpenModels,
            isModelSheetVisible = isModelSheetVisible,
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
