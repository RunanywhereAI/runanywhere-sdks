package com.runanywhere.runanywhereai.ui.screens.cloud

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.data.cloud.CloudPreset
import com.runanywhere.runanywhereai.data.cloud.CloudProviderConfig
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons

@Composable
fun CloudProvidersScreen() {
    val dimens = LocalDimens.current
    val vm: CloudProvidersViewModel = viewModel()
    var editing by remember { mutableStateOf<EditTarget?>(null) }

    Box(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(dimens.screenPadding),
            verticalArrangement = Arrangement.spacedBy(dimens.spacingMd),
        ) {
            Text(
                "Register any cloud STT provider — its key, endpoint and format. " +
                    "Registered providers can back the online side of Hybrid transcription.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            vm.providers.forEach { config ->
                ProviderCard(
                    config = config,
                    onEdit = { editing = EditTarget(config) },
                    onDelete = { vm.delete(config.id) },
                )
            }

            OutlinedButton(
                onClick = { editing = EditTarget(null) },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(RACIcons.Outline.Plus, contentDescription = null, modifier = Modifier.size(dimens.iconSm))
                Text("Add provider", modifier = Modifier.padding(start = dimens.spacingSm))
            }
        }
    }

    editing?.let { target ->
        ProviderSheet(
            initial = target.config,
            onDismiss = { editing = null },
            onSave = { label, preset, model, apiKey, baseUrl ->
                vm.save(target.config?.id, label, preset, model, apiKey, baseUrl)
                editing = null
            },
        )
    }
}

private class EditTarget(val config: CloudProviderConfig?)

@Composable
private fun ProviderCard(config: CloudProviderConfig, onEdit: () -> Unit, onDelete: () -> Unit) {
    val dimens = LocalDimens.current
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = RoundedCornerShape(dimens.radiusLg),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier
                .clickable(onClick = onEdit)
                .padding(dimens.spacingLg),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd),
        ) {
            Icon(
                RACIcons.Outline.Cloud,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(dimens.iconMd),
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(config.label, style = MaterialTheme.typography.bodyLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(
                    "${config.preset.label} · ${config.model.ifBlank { "—" }}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            IconButton(onClick = onDelete) {
                Icon(
                    RACIcons.Outline.Trash,
                    contentDescription = "Delete",
                    tint = MaterialTheme.colorScheme.error,
                    modifier = Modifier.size(dimens.iconSm),
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ProviderSheet(
    initial: CloudProviderConfig?,
    onDismiss: () -> Unit,
    onSave: (label: String, preset: CloudPreset, model: String, apiKey: String, baseUrl: String) -> Unit,
) {
    val dimens = LocalDimens.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    var label by remember { mutableStateOf(initial?.label.orEmpty()) }
    var preset by remember { mutableStateOf(initial?.preset ?: CloudPreset.OPENAI) }
    var model by remember { mutableStateOf(initial?.model ?: preset.defaultModel) }
    var apiKey by remember { mutableStateOf(initial?.apiKey.orEmpty()) }
    var baseUrl by remember { mutableStateOf(initial?.baseUrl ?: preset.defaultBaseUrl) }

    fun applyPreset(value: CloudPreset) {
        // Only overwrite untouched preset-derived fields so editing stays predictable.
        if (model.isBlank() || model == preset.defaultModel) model = value.defaultModel
        if (baseUrl.isBlank() || baseUrl == preset.defaultBaseUrl) baseUrl = value.defaultBaseUrl
        if (label.isBlank() || label == preset.label) label = value.label
        preset = value
    }

    val canSave = apiKey.isNotBlank()

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        shape = RoundedCornerShape(topStart = dimens.radiusLg, topEnd = dimens.radiusLg),
        containerColor = MaterialTheme.colorScheme.surfaceContainer,
        contentWindowInsets = { WindowInsets.systemBars },
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .imePadding()
                .padding(horizontal = dimens.spacingLg)
                .padding(bottom = dimens.spacingXl),
            verticalArrangement = Arrangement.spacedBy(dimens.spacingMd),
        ) {
            Text(
                if (initial == null) "Add cloud provider" else "Edit provider",
                style = MaterialTheme.typography.titleLarge,
            )

            Text("Format", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Row(horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm)) {
                CloudPreset.entries.forEach { value ->
                    FilterChip(
                        selected = preset == value,
                        onClick = { applyPreset(value) },
                        label = { Text(value.label, maxLines = 1) },
                    )
                }
            }

            OutlinedTextField(
                value = label, onValueChange = { label = it },
                label = { Text("Name") }, singleLine = true, modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = model, onValueChange = { model = it },
                label = { Text("Model") }, singleLine = true, modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = apiKey, onValueChange = { apiKey = it },
                label = { Text("API key") }, singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = baseUrl, onValueChange = { baseUrl = it },
                label = { Text("Base URL") }, singleLine = true,
                placeholder = { Text(preset.defaultBaseUrl.ifBlank { "https://…" }) },
                modifier = Modifier.fillMaxWidth(),
            )

            Row(horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd)) {
                TextButton(onClick = onDismiss, modifier = Modifier.weight(1f)) { Text("Cancel") }
                Button(
                    onClick = { onSave(label, preset, model, apiKey, baseUrl) },
                    enabled = canSave,
                    modifier = Modifier.weight(1f),
                ) { Text("Save") }
            }
        }
    }
}
