package com.runanywhere.runanywhereai.ui.screens.chat

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.runanywhere.runanywhereai.ui.theme.RACTextStyles
import java.util.Locale

@Composable
fun AnalyticsFooter(stats: GenerationStats, modifier: Modifier = Modifier) {
    val parts = buildList {
        add(String.format(Locale.US, "%.1fs", stats.totalTimeMs / 1000.0))
        if (stats.tokensPerSecond > 0) add(String.format(Locale.US, "%.0f tok/s", stats.tokensPerSecond))
        if (stats.tokens > 0) add("${stats.tokens} tok")
        stats.timeToFirstTokenMs?.takeIf { it > 0 }?.let { add("${it}ms ttft") }
    }
    Text(
        text = parts.joinToString("  ·  "),
        style = RACTextStyles.Metric,
        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
        modifier = modifier,
    )
}
