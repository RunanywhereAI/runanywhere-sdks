package com.runanywhere.runanywhereai.ui.components

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import com.runanywhere.runanywhereai.BuildConfig
import com.runanywhere.runanywhereai.data.settings.WebSearchConsentPolicy

internal fun webSearchDisclosureText(backendUrl: String): String {
    val route = WebSearchConsentPolicy.routeFor(backendUrl)
        ?: return "Web search is unavailable because this build does not have a valid secure " +
            "search destination."
    return if (!route.sendsPersistentDeviceId) {
        "When Web & tools is on, a model-generated search query based on your message is sent " +
            "directly to ${route.destinationLabel} to retrieve current results. As with any " +
            "internet request, those services can see your device's IP address. No persistent " +
            "device ID is sent. No query is sent until you choose Allow. Turn Web & tools off " +
            "to revoke this choice."
    } else {
        "When Web & tools is on, a model-generated search query based on your message and this " +
            "app's persistent device ID are sent to ${route.destinationLabel} to retrieve current " +
            "results and prevent abuse. As with any internet request, that service can also see " +
            "your device's IP address. No query is sent until you choose Allow. Turn Web & tools " +
            "off to revoke this choice."
    }
}

@Composable
internal fun WebSearchDisclosureDialog(
    onAllow: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Allow web search?") },
        text = {
            Text(webSearchDisclosureText(backendUrl = BuildConfig.WEB_SEARCH_URL))
        },
        confirmButton = {
            TextButton(onClick = onAllow) { Text("Allow") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Not now") }
        },
    )
}
