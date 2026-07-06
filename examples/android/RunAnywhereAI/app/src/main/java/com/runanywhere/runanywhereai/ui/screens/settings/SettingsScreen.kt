package com.runanywhere.runanywhereai.ui.screens.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.BuildConfig
import com.runanywhere.runanywhereai.ui.screens.models.BackendBadge
import com.runanywhere.runanywhereai.ui.screens.models.formatModelSize
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.RACTextStyles
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.runanywhereai.util.readableWidth
import com.runanywhere.sdk.public.types.RAModelInfo
import java.util.Locale
import kotlin.math.roundToInt

@Composable
fun SettingsScreen(viewModel: SettingsViewModel = viewModel()) {
    val dimens = LocalDimens.current
    val settings = viewModel.settings
    val storage = viewModel.storage

    Column(
        modifier = Modifier
            .fillMaxSize()
            .readableWidth()
            .verticalScroll(rememberScrollState())
            .padding(dimens.screenPadding),
        verticalArrangement = Arrangement.spacedBy(dimens.spacingLg),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(dimens.spacingXs)) {
            Text(
                text = "Settings",
                style = MaterialTheme.typography.headlineSmall,
            )
            Text(
                text = "Personalize the assistant, manage local models, and keep downloads private.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        Section("Assistant") {
            SliderRow(
                label = "Temperature",
                valueText = String.format(Locale.US, "%.1f", settings.temperature),
                value = settings.temperature,
                valueRange = 0f..2f,
                steps = 19,
                onValueChange = viewModel::setTemperature,
            )
            SliderRow(
                label = "Max tokens",
                valueText = settings.maxTokens.toString(),
                value = settings.maxTokens.toFloat(),
                valueRange = 256f..4096f,
                steps = 14,
                onValueChange = { viewModel.setMaxTokens(it.roundToInt()) },
            )
            Column(verticalArrangement = Arrangement.spacedBy(dimens.spacingXs)) {
                Text("System prompt", style = MaterialTheme.typography.bodyLarge)
                OutlinedTextField(
                    value = settings.systemPrompt,
                    onValueChange = viewModel::setSystemPrompt,
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("Optional — sets the assistant's behavior") },
                    minLines = 2,
                    maxLines = 5,
                )
            }
            ToggleRow(
                label = "Streaming",
                description = "Show the reply token-by-token",
                checked = settings.streaming,
                onCheckedChange = viewModel::setStreaming,
            )
            ToggleRow(
                label = "Show reasoning when available",
                description = "Thinking models can show a collapsible reasoning trace before the answer.",
                checked = !settings.disableThinking,
                onCheckedChange = { viewModel.setDisableThinking(!it) },
            )
        }

        Section("Models & Storage") {
            Text(
                text = "Models ${formatModelSize(storage.modelsBytes)}  ·  ${formatModelSize(storage.freeBytes)} free",
                style = RACTextStyles.Metric,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (storage.downloaded.isEmpty() && !storage.isLoading) {
                Text(
                    "No downloaded models",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                storage.downloaded.forEach { model ->
                    DownloadedModelRow(
                        model = model,
                        busy = storage.busyId == model.id,
                        onDelete = { viewModel.deleteModel(model) },
                    )
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm)) {
                TextButton(onClick = viewModel::clearCache) { Text("Clear cache") }
                TextButton(onClick = viewModel::cleanTempFiles) { Text("Clean temp files") }
            }
            storage.message?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
            }
        }

        Section("Private Downloads") {
            Column(verticalArrangement = Arrangement.spacedBy(dimens.spacingXs)) {
                Text("Hugging Face token", style = MaterialTheme.typography.bodyLarge)
                OutlinedTextField(
                    value = settings.hfToken,
                    onValueChange = viewModel::setHfToken,
                    modifier = Modifier
                        .fillMaxWidth()
                        .onFocusChanged { state ->
                            if (!state.isFocused) viewModel.commitHfToken()
                        },
                    placeholder = { Text("hf_…") },
                    supportingText = { Text("Used to download private Hugging Face model repos") },
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { viewModel.commitHfToken() }),
                )
            }
        }

        Section("About") {
            InfoRow("SDK version", viewModel.sdkVersion)
            InfoRow("App version", BuildConfig.VERSION_NAME)
            val uriHandler = LocalUriHandler.current
            Text(
                text = "Documentation",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { uriHandler.openUri("https://docs.runanywhere.ai") }
                    .padding(vertical = dimens.spacingXs),
            )
        }
    }
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    val dimens = LocalDimens.current
    Column(verticalArrangement = Arrangement.spacedBy(dimens.spacingSm)) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Surface(
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
            shape = RoundedCornerShape(dimens.radiusLg),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(
                modifier = Modifier.padding(dimens.spacingLg),
                verticalArrangement = Arrangement.spacedBy(dimens.spacingMd),
            ) {
                content()
            }
        }
    }
}

@Composable
private fun SliderRow(
    label: String,
    valueText: String,
    value: Float,
    valueRange: ClosedFloatingPointRange<Float>,
    steps: Int,
    onValueChange: (Float) -> Unit,
) {
    Column {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(label, style = MaterialTheme.typography.bodyLarge)
            Text(valueText, style = RACTextStyles.Metric, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Slider(value = value, onValueChange = onValueChange, valueRange = valueRange, steps = steps)
    }
}

@Composable
private fun ToggleRow(label: String, description: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .toggleable(
                value = checked,
                role = Role.Switch,
                onValueChange = onCheckedChange,
            ),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.bodyLarge)
            Text(description, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Switch(checked = checked, onCheckedChange = null)
    }
}

@Composable
private fun DownloadedModelRow(model: RAModelInfo, busy: Boolean, onDelete: () -> Unit) {
    val dimens = LocalDimens.current
    Surface(
        color = MaterialTheme.colorScheme.surface,
        shape = RoundedCornerShape(dimens.radiusMd),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier.padding(start = dimens.spacingMd, top = dimens.spacingSm, bottom = dimens.spacingSm),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(model.name, style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(dimens.spacingXs),
                ) {
                    BackendBadge(framework = model.framework, compact = true)
                    Text(
                        formatModelSize(model.download_size_bytes),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            if (busy) {
                CircularProgressIndicator(
                    modifier = Modifier
                        .padding(horizontal = dimens.spacingMd)
                        .size(dimens.iconSm),
                    strokeWidth = 2.dp,
                )
            } else {
                IconButton(onClick = onDelete) {
                    Icon(
                        imageVector = RACIcons.Outline.Trash,
                        contentDescription = "Delete ${model.name}",
                        tint = MaterialTheme.colorScheme.error,
                        modifier = Modifier.size(dimens.iconSm),
                    )
                }
            }
        }
    }
}

@Composable
private fun InfoRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, style = MaterialTheme.typography.bodyLarge)
        Text(value, style = RACTextStyles.Metric, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
