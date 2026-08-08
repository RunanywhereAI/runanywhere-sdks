package com.runanywhere.runanywhereai.ui.screens.voice

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.screens.models.BackendBadge
import com.runanywhere.runanywhereai.ui.screens.models.DownloadProgressBlock
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionViewModel
import com.runanywhere.runanywhereai.ui.screens.models.displayTitle
import com.runanywhere.runanywhereai.ui.screens.models.sizeLabel
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.runanywhereai.ui.theme.primaryGreen
import com.runanywhere.sdk.public.types.RAModelInfo

// A single pre-selected Voice AI component (STT / LLM / TTS / VAD) plus everything the
// card needs to render its state and open its scoped picker. `model` is the
// recommendation-engine pick; null means the catalog had nothing that fits.
data class VoiceComponent(
    val role: String,
    val icon: ImageVector,
    val viewModel: ModelSelectionViewModel,
    val model: RAModelInfo?,
    val optional: Boolean = false,
)

// Card that lists the pre-selected pipeline components with their state and a single
// primary action that downloads + loads all of them. Per-component progress is read
// from each component's own view-model state.
@Composable
fun VoiceSetupCard(
    components: List<VoiceComponent>,
    allReady: Boolean,
    isPreparing: Boolean,
    onPrepareAll: () -> Unit,
    onChange: (VoiceComponent) -> Unit,
    modifier: Modifier = Modifier,
    // true: a row is "ready" only when the model is loaded (co-resident agent path); false: ready when
    // merely downloaded (NPU per-turn-swap path loads on demand).
    requireLoaded: Boolean = true,
) {
    val dimens = LocalDimens.current
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = RoundedCornerShape(dimens.radiusLg),
        modifier = modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.padding(vertical = dimens.spacingSm)) {
            Row(
                modifier = Modifier.padding(horizontal = dimens.spacingLg, vertical = dimens.spacingSm),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd),
            ) {
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier
                        .size(36.dp)
                        .clip(RoundedCornerShape(dimens.radiusMd))
                        .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.14f)),
                ) {
                    Icon(
                        RACIcons.Filled.Bolt,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(dimens.iconMd),
                    )
                }
                Column(modifier = Modifier.weight(1f)) {
                    Text("Voice AI", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                    Text(
                        if (allReady) "Ready to talk" else "Best-for-device setup, one tap away",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            components.forEachIndexed { index, component ->
                if (index == 0) Divider()
                ComponentRow(component, enabled = !isPreparing, requireLoaded = requireLoaded, onChange = { onChange(component) })
                if (index < components.lastIndex) Divider()
            }

            if (!allReady) {
                Button(
                    onClick = onPrepareAll,
                    enabled = !isPreparing && components.any { it.model != null },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = dimens.spacingLg, vertical = dimens.spacingMd),
                    shape = RoundedCornerShape(dimens.radiusLg),
                ) {
                    if (isPreparing) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(18.dp),
                            strokeWidth = 2.dp,
                            // The button is disabled while it spins, so its content colour is the
                            // disabled one — a hardcoded onPrimary put white on grey and the
                            // spinner all but vanished at the moment it mattered most.
                            color = LocalContentColor.current,
                        )
                        Spacer(Modifier.size(dimens.spacingSm))
                        Text("Setting up…")
                    } else {
                        // A download arrow over four components that are already on disk promises a
                        // fetch that will not happen — all that is left then is loading them into
                        // memory, which is seconds rather than hundreds of megabytes. Say which of
                        // the two the tap is about to do.
                        val fetches = components.any { c -> c.model?.let { !c.viewModel.isReady(it) } == true }
                        Icon(
                            imageVector = if (fetches) RACIcons.Outline.Download else RACIcons.Outline.Bolt,
                            contentDescription = null,
                            modifier = Modifier.size(dimens.iconSm),
                        )
                        Spacer(Modifier.size(dimens.spacingSm))
                        Text(if (fetches) "Set up Voice AI" else "Load Voice AI")
                    }
                }
            }
        }
    }
}

@Composable
private fun ComponentRow(component: VoiceComponent, enabled: Boolean, requireLoaded: Boolean, onChange: () -> Unit) {
    val dimens = LocalDimens.current
    val vmState = component.viewModel.state
    val model = component.model
    // "Ready" (green) must match the mic gate: LOADED for the co-resident agent path, or merely
    // DOWNLOADED for the NPU per-turn-swap path (which loads on demand) — otherwise the check lies.
    val ready = model != null &&
        (if (requireLoaded) component.viewModel.isLoaded(model) else component.viewModel.isReady(model))
    // Distinct from [ready]: staging the next component unloads this one to free RAM, so a model
    // can be on disk and not resident. Without this the row flipped back to a download glyph
    // mid-setup and looked like the file it had just fetched had been thrown away.
    val onDisk = model != null && component.viewModel.isReady(model)
    val busy = model != null && vmState.busyModelId == model.id
    val progress = if (busy) vmState.downloadProgress else null

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = dimens.spacingLg, vertical = dimens.spacingMd),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd),
        ) {
            Icon(
                imageVector = component.icon,
                contentDescription = null,
                tint = if (ready) primaryGreen else MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(dimens.iconMd),
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    component.role,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    text = model?.displayTitle() ?: if (component.optional) "Auto" else "Not available",
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (model != null) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm),
                    ) {
                        Text(
                            model.sizeLabel(),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        BackendBadge(framework = model.framework, compact = true)
                    }
                }
            }
            StatusIndicator(ready = ready, onDisk = onDisk, busy = busy)
            if (enabled && model != null) {
                Text(
                    "Change",
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier
                        .clip(RoundedCornerShape(dimens.radiusSm))
                        .clickable(onClick = onChange)
                        .padding(horizontal = dimens.spacingSm, vertical = dimens.spacingXs),
                )
            }
        }
        // The setup card stages several multi-gigabyte components in sequence, so it needs the same
        // rate and time-remaining line the picker shows — a bare percentage here reads as stalled.
        AnimatedVisibility(visible = busy) {
            DownloadProgressBlock(progress, modifier = Modifier.padding(top = dimens.spacingSm))
        }
    }
}

/**
 * Three states, not two.
 *
 * "On disk but not resident" is its own thing here — the setup sequence unloads each component to
 * make room for the next download — and collapsing it into "needs download" put a download arrow
 * beside a file that was already fetched, which reads as the app having lost it.
 */
@Composable
private fun StatusIndicator(ready: Boolean, onDisk: Boolean, busy: Boolean) {
    val dimens = LocalDimens.current
    when {
        busy -> CircularProgressIndicator(
            modifier = Modifier.size(18.dp),
            strokeWidth = 2.dp,
            color = MaterialTheme.colorScheme.primary,
        )
        ready -> Icon(
            RACIcons.Filled.Check,
            contentDescription = "Ready",
            tint = primaryGreen,
            modifier = Modifier.size(dimens.iconSm),
        )
        onDisk -> Icon(
            // The same tick, in the low-emphasis colour: the file is here, it simply is not the
            // one currently loaded.
            RACIcons.Outline.Check,
            contentDescription = "Downloaded — loads when the pipeline starts",
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(dimens.iconSm),
        )
        else -> Icon(
            RACIcons.Outline.Download,
            contentDescription = "Needs download",
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(dimens.iconSm),
        )
    }
}

@Composable
private fun Divider() {
    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f))
}
