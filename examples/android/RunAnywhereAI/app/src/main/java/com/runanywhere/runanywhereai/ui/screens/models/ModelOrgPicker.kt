package com.runanywhere.runanywhereai.ui.screens.models

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import ai.runanywhere.proto.v1.InferenceFramework
import com.runanywhere.runanywhereai.data.settings.SettingsRepository
import com.runanywhere.runanywhereai.download.DownloadProgressInfo
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.sdk.public.extensions.Models.isBuiltIn
import com.runanywhere.sdk.public.extensions.Models.isDownloadedOnDisk
import com.runanywhere.sdk.public.types.RAModelInfo

/** One organisation and every model it publishes in the current picker scope. */
data class OrgGroup(
    val org: ModelOrg,
    val models: List<RAModelInfo>,
) {
    val optionCount: Int get() = models.size

    val hasNpuVariant: Boolean
        get() = models.any { it.framework == InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT }

    val hasReadyVariant: Boolean
        get() = models.any { it.isBuiltIn || it.isDownloadedOnDisk }
}

/** Groups models by organisation, variants smaller → larger, orgs in declaration order. */
fun List<RAModelInfo>.toOrgGroups(): List<OrgGroup> =
    groupBy { it.org() }
        .map { (org, models) -> OrgGroup(org, models.sortedBy { it.effectiveBytes() }) }
        .sortedBy { it.org.ordinal }

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun OrgCard(
    group: OrgGroup,
    viewModel: ModelSelectionViewModel,
    state: ModelSelectionState,
    onSelect: (RAModelInfo) -> Unit,
    onDownload: (RAModelInfo) -> Unit,
    onDelete: (RAModelInfo) -> Unit,
    modifier: Modifier = Modifier,
    initiallyExpanded: Boolean = false,
) {
    val dimens = LocalDimens.current
    var expanded by remember { mutableStateOf(initiallyExpanded) }
    val readyCount = group.models.count { viewModel.isReady(it) }

    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(dimens.radiusLg),
        color = MaterialTheme.colorScheme.surface,
    ) {
        Column {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { expanded = !expanded }
                    .padding(horizontal = dimens.spacingLg, vertical = dimens.spacingMd),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    imageVector = group.org.brand.icon,
                    contentDescription = null,
                    tint = group.org.brand.color,
                    modifier = Modifier.size(dimens.iconLg),
                )
                Spacer(modifier = Modifier.width(dimens.spacingMd))
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(dimens.spacingXs),
                ) {
                    Text(
                        group.org.displayName,
                        style = MaterialTheme.typography.bodyLarge,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(dimens.spacingXs),
                        verticalArrangement = Arrangement.spacedBy(dimens.spacingXs),
                    ) {
                        if (group.hasNpuVariant) {
                            ModelPill("NPU", ModelPillColors.Capability, icon = RACIcons.Filled.Bolt)
                        }
                        if (readyCount > 0) {
                            ModelPill("$readyCount ready", ModelPillColors.Availability)
                        } else {
                            val optionsLabel =
                                if (group.optionCount == 1) "1 model" else "${group.optionCount} models"
                            ModelPill(optionsLabel, ModelPillColors.Neutral)
                        }
                    }
                }
                Spacer(modifier = Modifier.width(dimens.spacingSm))
                Icon(
                    imageVector = if (expanded) RACIcons.Outline.ChevronUp else RACIcons.Outline.ChevronDown,
                    contentDescription = if (expanded) "Collapse" else "Expand",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(dimens.iconMd),
                )
            }

            AnimatedVisibility(visible = expanded) {
                Column {
                    HorizontalDivider(
                        modifier = Modifier.padding(horizontal = dimens.spacingLg),
                        thickness = 0.5.dp,
                        color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
                    )
                    group.models.forEachIndexed { index, model ->
                        OrgModelRow(
                            model = model,
                            isRecommended = index == 0 && group.models.size > 1,
                            isCurrent = state.currentModelId == model.id,
                            isReady = viewModel.isReady(model),
                            isBusy = state.busyModelId == model.id,
                            progress = if (state.busyModelId == model.id) state.downloadProgress else null,
                            interruption = state.interruptionFor(model.id),
                            onSelect = { onSelect(model) },
                            onDownload = { onDownload(model) },
                            onCancel = { viewModel.cancelDownload(model.id) },
                            onDelete = if (viewModel.isDeletable(model)) ({ onDelete(model) }) else null,
                        )
                        if (index < group.models.lastIndex) {
                            HorizontalDivider(
                                modifier = Modifier.padding(start = dimens.spacingLg + 42.dp, end = dimens.spacingLg),
                                thickness = 0.5.dp,
                                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f),
                            )
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun OrgModelRow(
    model: RAModelInfo,
    isRecommended: Boolean,
    isCurrent: Boolean,
    isReady: Boolean,
    isBusy: Boolean,
    progress: DownloadProgressInfo?,
    interruption: DownloadInterruption?,
    onSelect: () -> Unit,
    onDownload: () -> Unit,
    onCancel: (() -> Unit)? = null,
    onDelete: (() -> Unit)?,
) {
    val dimens = LocalDimens.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .then(if (isReady) Modifier.clickable(onClick = onSelect) else Modifier)
            .padding(horizontal = dimens.spacingLg, vertical = dimens.spacingMd),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(dimens.spacingXs),
        ) {
            Text(
                model.displayTitle(),
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm),
                verticalArrangement = Arrangement.spacedBy(dimens.spacingXs),
            ) {
                Text(
                    "${model.sizeLabel()} · ${model.variantFeelLabel()}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                BackendBadge(framework = model.framework, compact = true)
            }
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(dimens.spacingXs),
                verticalArrangement = Arrangement.spacedBy(dimens.spacingXs),
            ) {
                if (isRecommended) ModelPill("Recommended", ModelPillColors.Availability)
                model.consumerTags()
                    .filter { it.kind == ConsumerTagKind.CAPABILITY }
                    .forEach { ModelPill(it.label, it.kind.pillColor()) }
                if (model.requiresHfAuth()) {
                    val hasToken = SettingsRepository.settings.hfToken.isNotBlank()
                    ModelPill(
                        "Private",
                        if (hasToken) ModelPillColors.Capability else ModelPillColors.Warning,
                    )
                }
            }
            // Same bar and the same detail line as the flat picker list: an org-grouped row is a
            // different layout of the same transfer, not a different amount of information.
            if (isBusy) {
                DownloadProgressBlock(progress)
            } else if (interruption != null) {
                DownloadInterruptionNote(interruption)
            }
        }
        Spacer(Modifier.width(dimens.spacingSm))
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(dimens.spacingXs)) {
            DownloadRowAction(
                model = model,
                isCurrent = isCurrent,
                isReady = isReady,
                isBusy = isBusy,
                interruption = interruption,
                onDownload = onDownload,
                onCancel = onCancel,
            )
            if (onDelete != null && isReady) {
                IconButton(onClick = onDelete, modifier = Modifier.size(ROW_TAP_TARGET)) {
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

