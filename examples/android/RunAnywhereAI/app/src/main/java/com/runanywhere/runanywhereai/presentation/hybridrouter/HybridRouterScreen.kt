/*
 * Hybrid Router Demo screen.
 *
 * Shows the public dev-facing HybridRouter API in action:
 *  - Pick a local STT model (loaded by SDK; auto-registered with router).
 *  - Optionally register Sarvam cloud as a second backend.
 *  - Pick a routing Policy (Auto / PreferLocal / etc).
 *  - Toggle/adjust the cascade threshold.
 *  - Record audio, transcribe through the router, see chosen backend +
 *    cascade outcome.
 *
 * Layout sections (top → bottom):
 *  1) Backend pills row (count + names of registered backends)
 *  2) Policy selector chips
 *  3) Cascade controls (switch + slider)
 *  4) Sarvam cloud register/unregister (with API key input)
 *  5) Transcript card
 *  6) Routing-info card (chosenBackend, confidence, fallback)
 *  7) Record button
 */
package com.runanywhere.runanywhereai.presentation.hybridrouter

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.presentation.chat.components.ModelRequiredOverlay
import com.runanywhere.runanywhereai.presentation.components.ConfigureTopBar
import com.runanywhere.runanywhereai.presentation.models.ModelSelectionBottomSheet
import com.runanywhere.runanywhereai.ui.theme.AppColors
import com.runanywhere.sdk.public.extensions.Models.ModelSelectionContext
import com.runanywhere.sdk.public.routing.Policy

@Composable
fun HybridRouterScreen(
    onBack: () -> Unit = {},
    vm: HybridRouterViewModel = viewModel(),
) {
    val context = LocalContext.current
    val ui by vm.ui.collectAsStateWithLifecycle()
    var showPicker by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) { vm.init(context) }

    val permLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted -> if (granted) vm.toggleRecord() }

    ConfigureTopBar(
        title = "Hybrid Router Demo",
        showBack = true,
        onBack = onBack,
        actions = {
            TextButton(onClick = { showPicker = true }) {
                Text(ui.modelName?.take(18) ?: "Select model")
            }
        },
    )

    Box(modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        if (!ui.isModelLoaded) {
            ModelRequiredOverlay(
                modality = ModelSelectionContext.STT,
                onSelectModel = { showPicker = true },
                modifier = Modifier.matchParentSize(),
            )
        } else {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                BackendsRow(count = ui.backendCount, sarvamOn = ui.sarvamRegistered)
                PolicyChips(selected = ui.policy, onSelect = vm::setPolicy)
                CascadeControls(
                    enabled = ui.cascadeEnabled,
                    threshold = ui.cascadeThreshold,
                    onChange = vm::setCascade,
                )
                SarvamCard(
                    registered = ui.sarvamRegistered,
                    onRegister = vm::registerSarvam,
                    onUnregister = vm::unregisterSarvam,
                )
                TranscriptCard(text = ui.transcript, error = ui.error)
                if (ui.chosenBackend != null) {
                    RoutingInfo(
                        backend = ui.chosenBackend!!,
                        confidence = ui.confidence,
                        primary = ui.primaryConfidence,
                        wasFallback = ui.wasFallback,
                        attempts = ui.attemptCount,
                    )
                }
                if (ui.cascadeErrorCode != 0) {
                    CascadeErrorBanner(
                        moduleId = ui.cascadeErrorModuleId,
                        errorCode = ui.cascadeErrorCode,
                    )
                }
                Spacer(Modifier.height(8.dp))
                RecordButton(state = ui.recState) {
                    val granted = ContextCompat.checkSelfPermission(
                        context, Manifest.permission.RECORD_AUDIO,
                    ) == PackageManager.PERMISSION_GRANTED
                    if (granted) vm.toggleRecord() else permLauncher.launch(Manifest.permission.RECORD_AUDIO)
                }
            }
        }
    }

    if (showPicker) {
        ModelSelectionBottomSheet(
            context = ModelSelectionContext.STT,
            onDismiss = { showPicker = false },
            onModelSelected = { model -> vm.onModelLoaded(model.name) },
        )
    }
}

// --- Section composables ----------------------------------------------------

@Composable
private fun BackendsRow(count: Int, sarvamOn: Boolean) {
    Card(shape = RoundedCornerShape(12.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column {
                Text("Router state", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                Text(
                    "$count backend${if (count == 1) "" else "s"} registered",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            BackendDot(label = "local-stt", on = count >= 1)
            BackendDot(label = "sarvam", on = sarvamOn)
        }
    }
}

@Composable
private fun BackendDot(label: String, on: Boolean) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            modifier = Modifier.size(8.dp).clip(CircleShape)
                .background(if (on) AppColors.primaryGreen else AppColors.statusGray.copy(alpha = 0.4f)),
        )
        Spacer(Modifier.width(4.dp))
        Text(label, style = MaterialTheme.typography.labelSmall)
    }
}

@Composable
private fun PolicyChips(selected: Policy, onSelect: (Policy) -> Unit) {
    val opts = listOf(
        "Auto" to Policy.Auto,
        "Prefer Local" to Policy.PreferLocal,
        "Prefer Accuracy" to Policy.PreferAccuracy,
        "Local Only" to Policy.LocalOnly,
        "Cloud Only" to Policy.CloudOnly,
    )
    Column {
        Text("Routing Policy", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(8.dp))
        FlowRow(opts) { (label, p) ->
            FilterChip(
                selected = selected::class == p::class,
                onClick = { onSelect(p) },
                label = { Text(label) },
            )
        }
    }
}

@Composable
private fun CascadeControls(enabled: Boolean, threshold: Float, onChange: (Boolean, Float) -> Unit) {
    Card(shape = RoundedCornerShape(12.dp)) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                Text("Cascade", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.weight(1f))
                Switch(checked = enabled, onCheckedChange = { onChange(it, threshold) })
            }
            if (enabled) {
                Spacer(Modifier.height(4.dp))
                Text(
                    "Local cascades to cloud below ${"%.2f".format(threshold)} confidence",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Slider(
                    value = threshold,
                    onValueChange = { onChange(true, it) },
                    valueRange = 0f..1f,
                )
            }
        }
    }
}

@Composable
private fun SarvamCard(registered: Boolean, onRegister: (String) -> Unit, onUnregister: () -> Unit) {
    // Test key — replace with your own; will be deleted shortly.
    var key by remember { mutableStateOf("sk_x7budlot_PfLY2e4fP0kdJVMc1Thn33hK") }
    Card(shape = RoundedCornerShape(12.dp)) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = if (registered) Icons.Filled.Cloud else Icons.Filled.CloudOff,
                    contentDescription = null,
                    tint = if (registered) AppColors.primaryGreen else MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    "Sarvam Cloud (cascade target)",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
            }
            Spacer(Modifier.height(8.dp))
            if (registered) {
                OutlinedButton(onClick = onUnregister) { Text("Unregister") }
            } else {
                OutlinedTextField(
                    value = key,
                    onValueChange = { key = it },
                    label = { Text("Sarvam API key") },
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(Modifier.height(8.dp))
                Button(
                    onClick = { if (key.isNotBlank()) onRegister(key.trim()) },
                    enabled = key.isNotBlank(),
                ) { Text("Register Sarvam") }
            }
        }
    }
}

@Composable
private fun TranscriptCard(text: String, error: String?) {
    Card(shape = RoundedCornerShape(12.dp)) {
        Column(modifier = Modifier.fillMaxWidth().padding(12.dp)) {
            Text("Transcript", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(6.dp))
            if (error != null) {
                Text(error, color = AppColors.statusRed, style = MaterialTheme.typography.bodyMedium)
            } else {
                Text(
                    text.ifEmpty { "(record to transcribe)" },
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (text.isEmpty()) MaterialTheme.colorScheme.onSurfaceVariant
                            else MaterialTheme.colorScheme.onSurface,
                )
            }
        }
    }
}

@Composable
private fun RoutingInfo(
    backend: String,
    confidence: Float,
    primary: Float,
    wasFallback: Boolean,
    attempts: Int,
) {
    Card(
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(
            containerColor = (if (wasFallback) AppColors.primaryOrange else AppColors.primaryGreen)
                .copy(alpha = 0.08f),
        ),
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    if (wasFallback) "FALLBACK" else "PRIMARY",
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.Bold,
                    color = if (wasFallback) AppColors.primaryOrange else AppColors.primaryGreen,
                )
                Spacer(Modifier.weight(1f))
                Text("attempts=$attempts", style = MaterialTheme.typography.labelSmall)
            }
            Text(backend, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(4.dp))
            Row {
                ConfidencePill("confidence", confidence)
                if (wasFallback && !primary.isNaN()) {
                    Spacer(Modifier.width(8.dp))
                    ConfidencePill("primary", primary)
                }
            }
        }
    }
}

@Composable
private fun ConfidencePill(label: String, value: Float) {
    val text = if (value.isNaN()) "—" else "${(value * 100).toInt()}%"
    Surface(shape = RoundedCornerShape(6.dp), color = MaterialTheme.colorScheme.surface) {
        Row(
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("$label  ", style = MaterialTheme.typography.labelSmall)
            Text(text, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun RecordButton(state: RecState, onClick: () -> Unit) {
    val (color, icon, label) = when (state) {
        RecState.IDLE -> Triple(AppColors.primaryAccent, Icons.Filled.Mic, "Record")
        RecState.RECORDING -> Triple(AppColors.statusRed, Icons.Filled.Stop, "Stop")
        RecState.PROCESSING -> Triple(AppColors.primaryOrange, Icons.Filled.Sync, "Routing…")
    }
    Box(
        modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
        contentAlignment = Alignment.Center,
    ) {
        Surface(
            modifier = Modifier.size(72.dp).clickable(
                enabled = state != RecState.PROCESSING,
                onClick = onClick,
            ),
            shape = CircleShape,
            color = color,
        ) {
            Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
                if (state == RecState.PROCESSING) {
                    CircularProgressIndicator(modifier = Modifier.size(28.dp), color = Color.White, strokeWidth = 3.dp)
                } else {
                    Icon(icon, contentDescription = label, tint = Color.White, modifier = Modifier.size(28.dp))
                }
            }
        }
    }
}

@Composable
private fun CascadeErrorBanner(moduleId: String, errorCode: Int) {
    Card(
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(containerColor = AppColors.statusRed.copy(alpha = 0.1f)),
    ) {
        Column(modifier = Modifier.fillMaxWidth().padding(12.dp)) {
            Text(
                "Cascade attempted",
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Bold,
                color = AppColors.statusRed,
            )
            Spacer(Modifier.height(4.dp))
            Text(
                "Local was low-confidence; tried '$moduleId' as cloud fallback but it failed " +
                    "(rc=$errorCode). Returned the local result instead. Check API key / network.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}

// Tiny flow-row to avoid pulling in Accompanist; chips wrap to next line.
@Composable
private fun <T> FlowRow(items: List<T>, content: @Composable (T) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        items.chunked(3).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                row.forEach { content(it) }
            }
        }
    }
}
