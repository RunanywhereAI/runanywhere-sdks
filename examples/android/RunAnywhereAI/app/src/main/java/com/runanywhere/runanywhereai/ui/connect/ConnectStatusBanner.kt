package com.runanywhere.runanywhereai.ui.connect

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.runanywhereai.ui.theme.primaryGreen
import com.runanywhere.sdk.public.connect.ConnectState
import com.runanywhere.sdk.public.connect.ConnectStatus
import kotlinx.coroutines.delay

@Composable
fun ConnectStatusBanner(
    state: ConnectState,
    onConnect: () -> Unit,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val key = state.bannerKey()
    var dismissedKey by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(key) {
        if (key == null) return@LaunchedEffect
        dismissedKey = null
        if (state.status == ConnectStatus.CONNECTED) {
            delay(6_000)
            if (key == state.bannerKey()) dismissedKey = key
        }
    }

    AnimatedVisibility(
        visible = key != null && dismissedKey != key,
        enter = slideInVertically { -it } + fadeIn(),
        exit = slideOutVertically { -it } + fadeOut(),
        modifier = modifier,
    ) {
        val presentation = state.presentation()
        Surface(
            shape = RoundedCornerShape(22.dp),
            color = MaterialTheme.colorScheme.surface.copy(alpha = 0.96f),
            tonalElevation = 6.dp,
            shadowElevation = 10.dp,
            modifier = Modifier
                .fillMaxWidth()
                .widthIn(max = 680.dp)
                .padding(horizontal = 16.dp, vertical = 8.dp),
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Box(
                    modifier = Modifier
                        .size(36.dp)
                        .background(presentation.tint.copy(alpha = 0.14f), CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = presentation.icon,
                        contentDescription = null,
                        tint = presentation.tint,
                        modifier = Modifier.size(20.dp),
                    )
                }
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = presentation.title,
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        text = presentation.subtitle,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                when (state.status) {
                    ConnectStatus.IDLE, ConnectStatus.DISCOVERING -> if (state.availableHosts.isNotEmpty()) {
                        RoundAction(RACIcons.Outline.Link, "Connect to host", onConnect)
                    }
                    ConnectStatus.CONNECTING -> CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp)
                    ConnectStatus.DISCONNECTED, ConnectStatus.FAILED -> {
                        RoundAction(RACIcons.Outline.Refresh, "Find a host again", onRetry, filled = false)
                    }
                    ConnectStatus.CONNECTED -> Unit
                }
                IconButton(onClick = { dismissedKey = key }, modifier = Modifier.size(36.dp)) {
                    Icon(RACIcons.Outline.Close, contentDescription = "Dismiss Connect status")
                }
            }
        }
    }
}

@Composable
private fun RoundAction(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    description: String,
    onClick: () -> Unit,
    filled: Boolean = true,
) {
    val tint = MaterialTheme.colorScheme.primary
    IconButton(
        onClick = onClick,
        modifier = Modifier
            .size(36.dp)
            .background(if (filled) tint else tint.copy(alpha = 0.12f), CircleShape),
    ) {
        Icon(icon, contentDescription = description, tint = if (filled) Color.White else tint)
    }
}

private data class BannerPresentation(
    val title: String,
    val subtitle: String,
    val icon: androidx.compose.ui.graphics.vector.ImageVector,
    val tint: Color,
)

@Composable
private fun ConnectState.presentation(): BannerPresentation = when (status) {
    ConnectStatus.CONNECTED -> BannerPresentation(
        title = activeHost?.displayName.shortened(42, "Connected Host"),
        subtitle = activeModel?.displayName.shortened(54, "Using a hosted model"),
        icon = RACIcons.Outline.Check,
        tint = primaryGreen,
    )
    ConnectStatus.CONNECTING -> BannerPresentation(
        title = "Connecting to ${connectingHost?.displayName.shortened(28, "host")}",
        subtitle = "Checking the selected model",
        icon = RACIcons.Outline.Refresh,
        tint = MaterialTheme.colorScheme.primary,
    )
    ConnectStatus.DISCONNECTED -> BannerPresentation(
        title = "Connection lost",
        subtitle = message.shortened(72, "The host stopped or left the network"),
        icon = RACIcons.Outline.AlertTriangle,
        tint = MaterialTheme.colorScheme.error,
    )
    ConnectStatus.FAILED -> BannerPresentation(
        title = "Couldn't connect",
        subtitle = message.shortened(72, "Check the host and your local network"),
        icon = RACIcons.Outline.AlertTriangle,
        tint = MaterialTheme.colorScheme.error,
    )
    else -> BannerPresentation(
        title = availableHosts.firstOrNull()?.displayName.shortened(42, "Host available"),
        subtitle = "Language model available on your local network",
        icon = RACIcons.Outline.Desktop,
        tint = MaterialTheme.colorScheme.primary,
    )
}

private fun ConnectState.bannerKey(): String? = when (status) {
    ConnectStatus.CONNECTING -> "connecting:${connectingHost?.id}"
    ConnectStatus.CONNECTED -> "connected:${activeHost?.id}:${activeModel?.id}"
    ConnectStatus.DISCONNECTED -> "disconnected:${lastDisconnectedHost?.id}:$message"
    ConnectStatus.FAILED -> "failed:$message"
    ConnectStatus.IDLE, ConnectStatus.DISCOVERING -> availableHosts.firstOrNull()?.let { "available:${it.id}" }
}

private fun String?.shortened(limit: Int, fallback: String): String {
    val value = this?.trim().orEmpty().ifBlank { fallback }
    return if (value.length <= limit) value else value.take(limit - 1) + "…"
}
