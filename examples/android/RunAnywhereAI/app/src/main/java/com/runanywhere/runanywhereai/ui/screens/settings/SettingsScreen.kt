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
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.BuildConfig
import com.runanywhere.runanywhereai.state.GlobalState
import com.runanywhere.runanywhereai.ui.screens.chat.ChatGenerationBudgetPolicy
import com.runanywhere.runanywhereai.ui.screens.models.formatModelSize
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.RACTextStyles
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.runanywhereai.util.readableWidth
import java.util.Locale
import kotlin.math.roundToInt

@Composable
fun SettingsScreen(
    viewModel: SettingsViewModel = viewModel(),
    onOpenModels: () -> Unit = {},
    onOpenAdvanced: () -> Unit = {},
) {
    val dimens = LocalDimens.current
    val settings = viewModel.settings
    val storage = viewModel.storage
    val loadedChatModel = GlobalState.model.loaded
    val chatBudget = ChatGenerationBudgetPolicy.resolve(
        requestedMaxTokens = settings.maxTokens,
        modelContextTokens = loadedChatModel?.context_length ?: 0,
    )
    var deletingModel by remember { mutableStateOf<com.runanywhere.sdk.public.types.RAModelInfo?>(null) }

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

        Section("App") {
            SettingsLinkRow(
                label = "Choose chat model",
                description = "Download or switch the model used by Ask",
                icon = RACIcons.Outline.Cpu,
                onClick = onOpenModels,
            )
            SettingsLinkRow(
                label = "Advanced workbench",
                description = "Voice, documents, tools, and diagnostics",
                icon = RACIcons.Outline.Stack,
                onClick = onOpenAdvanced,
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
                description = chatBudget.explanation(loadedChatModel?.name),
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

        Section("Storage") {
            Text(
                text = "Models ${formatModelSize(storage.modelsBytes).ifBlank { "0 B" }} · " +
                    "${formatModelSize(storage.freeBytes)} free",
                style = RACTextStyles.Metric,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            when {
                storage.isLoading -> CircularProgressIndicator(
                    modifier = Modifier.size(dimens.iconSm),
                    strokeWidth = 2.dp,
                )
                storage.downloaded.isEmpty() -> Text(
                    "No downloaded models yet.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                else -> storage.downloaded.sortedBy { it.name.lowercase() }.forEach { model ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(model.name.ifBlank { model.id }, style = MaterialTheme.typography.bodyMedium)
                            Text(
                                listOfNotNull(
                                    model.framework.name.removePrefix("INFERENCE_FRAMEWORK_").takeIf { it.isNotBlank() },
                                    model.download_size_bytes.takeIf { it > 0 }?.let(::formatModelSize),
                                ).joinToString(" · "),
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        TextButton(
                            onClick = { deletingModel = model },
                            enabled = storage.busyId == null,
                        ) {
                            Text(if (storage.busyId == model.id) "Deleting…" else "Delete")
                        }
                    }
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
                    value = viewModel.hfTokenDraft,
                    onValueChange = viewModel::editHfToken,
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("hf_…") },
                    supportingText = {
                        Text("Stored securely and used only for private Hugging Face repos, including HNPU/QHexRT bundles")
                    },
                    singleLine = true,
                    enabled = !storage.hfTokenBusy,
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.Password,
                        imeAction = ImeAction.Done,
                    ),
                    keyboardActions = KeyboardActions(onDone = { viewModel.commitHfToken() }),
                )
                Row(
                    horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    TextButton(onClick = viewModel::commitHfToken, enabled = !storage.hfTokenBusy) {
                        Text("Save token")
                    }
                    TextButton(onClick = viewModel::clearHfToken, enabled = !storage.hfTokenBusy) {
                        Text("Clear")
                    }
                    if (storage.hfTokenBusy) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(dimens.iconSm),
                            strokeWidth = 2.dp,
                        )
                    }
                }
                storage.hfTokenMessage?.let { message ->
                    Text(
                        message,
                        style = MaterialTheme.typography.bodySmall,
                        color = if (storage.hfTokenMessageIsError) {
                            MaterialTheme.colorScheme.error
                        } else {
                            MaterialTheme.colorScheme.primary
                        },
                    )
                }
            }
        }

        Section("About") {
            InfoRow("SDK version", viewModel.sdkVersion)
            InfoRow("App version", BuildConfig.VERSION_NAME)
            val uriHandler = LocalUriHandler.current
            if (BuildConfig.PRIVACY_POLICY_URL.isNotBlank()) {
                Text(
                    text = "Privacy policy",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { uriHandler.openUri(BuildConfig.PRIVACY_POLICY_URL) }
                        .padding(vertical = dimens.spacingXs),
                )
            }
            Text(
                text = "Documentation",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { uriHandler.openUri("https://docs.runanywhere.ai") }
                    .padding(vertical = dimens.spacingXs),
            )
            Text(
                text = "Follow on X",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { uriHandler.openUri("https://x.com/RunanywhereAI") }
                    .padding(vertical = dimens.spacingXs),
            )
        }
    }

    deletingModel?.let { model ->
        AlertDialog(
            onDismissRequest = { deletingModel = null },
            title = { Text("Delete downloaded model?") },
            text = { Text("Remove ${model.name.ifBlank { model.id }} and its files from this device?") },
            confirmButton = {
                TextButton(
                    onClick = {
                        deletingModel = null
                        viewModel.deleteModel(model)
                    },
                ) { Text("Delete", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { deletingModel = null }) { Text("Cancel") } },
        )
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
    description: String? = null,
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
        description?.let {
            Text(
                text = it,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
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
private fun SettingsLinkRow(
    label: String,
    description: String,
    icon: ImageVector,
    onClick: () -> Unit,
) {
    val dimens = LocalDimens.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(vertical = dimens.spacingXs),
        horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(dimens.iconMd),
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.bodyLarge)
            Text(
                description,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Icon(
            imageVector = RACIcons.Outline.ChevronRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(dimens.iconSm),
        )
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
