package com.runanywhere.runanywhereai.presentation.voice.components

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.domain.models.TranscriptSegment
import com.runanywhere.runanywhereai.domain.models.TranscriptType
import java.text.SimpleDateFormat
import java.util.*

/**
 * Component for displaying individual transcript segments
 */
@Composable
fun TranscriptSegmentItem(
    segment: TranscriptSegment,
    modifier: Modifier = Modifier
) {
    val colors = when (segment.type) {
        TranscriptType.PARTIAL_USER -> CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
        )
        TranscriptType.FINAL_USER -> CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
        TranscriptType.ASSISTANT -> CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.primaryContainer
        )
    }

    Card(
        modifier = modifier,
        colors = colors
    ) {
        Column(
            modifier = Modifier.padding(12.dp)
        ) {
            Row(
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top,
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    // Speaker info if available
                    segment.speaker?.let { speaker ->
                        Text(
                            text = speaker.name,
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.primary
                        )
                        Spacer(modifier = Modifier.height(4.dp))
                    }

                    // Transcript text
                    Text(
                        text = segment.text,
                        style = MaterialTheme.typography.bodyMedium,
                        color = if (segment.type == TranscriptType.PARTIAL_USER) {
                            MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                        } else {
                            MaterialTheme.colorScheme.onSurface
                        }
                    )
                }

                Column(
                    horizontalAlignment = Alignment.End
                ) {
                    // Timestamp
                    Text(
                        text = formatTimestamp(segment.timestamp),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                    )

                    // Confidence if available and not 1.0
                    if (segment.confidence < 1.0f && segment.confidence > 0.0f) {
                        Spacer(modifier = Modifier.height(2.dp))
                        Text(
                            text = "${(segment.confidence * 100).toInt()}%",
                            style = MaterialTheme.typography.labelSmall,
                            color = if (segment.confidence > 0.7f) {
                                MaterialTheme.colorScheme.primary
                            } else if (segment.confidence > 0.5f) {
                                MaterialTheme.colorScheme.secondary
                            } else {
                                MaterialTheme.colorScheme.error
                            }
                        )
                    }
                }
            }

            // Type indicator for debugging/development
            if (segment.type == TranscriptType.PARTIAL_USER) {
                Spacer(modifier = Modifier.height(4.dp))
                Row(
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(12.dp),
                        strokeWidth = 1.dp
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(
                        text = "Processing...",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                    )
                }
            }
        }
    }
}

private fun formatTimestamp(timestamp: Long): String {
    val formatter = SimpleDateFormat("HH:mm:ss", Locale.getDefault())
    return formatter.format(Date(timestamp))
}
