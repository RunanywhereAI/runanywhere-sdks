package com.runanywhere.runanywhereai.ui.screens.models

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.unit.sp
import ai.runanywhere.proto.v1.InferenceFramework
import com.runanywhere.runanywhereai.data.settings.SettingsRepository
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.sdk.public.extensions.Models.isBuiltIn
import com.runanywhere.sdk.public.extensions.Models.isDownloadedOnDisk
import com.runanywhere.sdk.public.types.RAModelInfo

// A family plus its variants, ordered smaller → larger (by footprint) so the
// recommended / default variant surfaces first and feel labels read naturally.
data class FamilyGroup(
    val family: ModelFamily,
    val variants: List<RAModelInfo>,
) {
    val optionCount: Int get() = variants.size

    val maker: ModelMaker get() = family.maker

    // True when the family has an NPU build, which is what earns the accelerated badge.
    // A family spans backends, so this is a property of the variants, not of the name.
    val hasNpuVariant: Boolean
        get() = variants.any { it.framework == InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT }

    // Capability bucket of the lead variant — drives the bucket-based family sort.
    val bucket: ModelCategoryBucket get() = variants.first().categoryBucket()

    // True when any variant is already downloaded or built in — the picker lifts these
    // into its "On this device" section.
    val hasReadyVariant: Boolean get() = variants.any { it.isBuiltIn || it.isDownloadedOnDisk }

    // The single cleanest tag on the collapsed family card. The picker is scoped to one
    // modality, so a MODALITY tag would say the same word on every card — prefer a real
    // capability from the lead variant and fall back to its feel word.
    val headlineTag: ConsumerTag?
        get() = variants.firstOrNull()?.consumerTags()?.let { tags ->
            tags.firstOrNull { it.kind == ConsumerTagKind.CAPABILITY }
                ?: tags.firstOrNull { it.kind == ConsumerTagKind.FEEL }
        }
}

// Groups models into families, ordering variants smaller → larger and families by
// capability bucket, then maker, then name — so a maker's families always sit together.
fun List<RAModelInfo>.toFamilyGroups(): List<FamilyGroup> =
    groupBy { it.family().key }
        .map { (_, models) ->
            val family = models.first().family()
            FamilyGroup(family, models.sortedBy { it.effectiveBytes() })
        }
        .sortedWith(
            compareBy<FamilyGroup> { it.bucket.ordinal }
                .thenBy { it.maker.ordinal }
                .thenBy { it.family.title.lowercase() },
        )

@Composable
fun FamilyCard(
    group: FamilyGroup,
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
    val readyCount = group.variants.count { viewModel.isReady(it) }

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
                    imageVector = group.maker.brand.icon,
                    contentDescription = null,
                    tint = group.maker.brand.color,
                    modifier = Modifier.size(dimens.iconLg),
                )
                Spacer(Modifier.width(dimens.spacingMd))
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(dimens.spacingXs),
                ) {
                    // The maker line is what makes the taxonomy visible: every card says
                    // who built the family before it says what the family is called.
                    Text(
                        group.maker.displayName.uppercase(),
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.SemiBold,
                        letterSpacing = 0.8.sp,
                        color = group.maker.brand.color,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        group.family.title,
                        style = MaterialTheme.typography.bodyLarge,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        group.family.tagline,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                    // Three pills at most: what it is good at, whether it runs on the NPU,
                    // and how many builds are on hand. Any more and the row wraps to mush.
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(dimens.spacingXs),
                        verticalArrangement = Arrangement.spacedBy(dimens.spacingXs),
                    ) {
                        group.headlineTag?.let { ModelPill(it.label, it.kind.pillColor()) }
                        if (group.hasNpuVariant) {
                            ModelPill("NPU", ModelPillColors.Capability, icon = RACIcons.Outline.Cpu)
                        }
                        if (readyCount > 0) {
                            ModelPill("$readyCount ready", ModelPillColors.Availability)
                        } else {
                            val optionsLabel =
                                if (group.optionCount == 1) "1 option" else "${group.optionCount} options"
                            ModelPill(optionsLabel, ModelPillColors.Neutral)
                        }
                    }
                }
                Spacer(Modifier.width(dimens.spacingSm))
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
                    group.variants.forEachIndexed { index, variant ->
                        VariantRow(
                            variant = variant,
                            // Auto-highlight the first (best-fit for device) variant.
                            isRecommended = index == 0 && group.variants.size > 1,
                            isCurrent = state.currentModelId == variant.id,
                            isReady = viewModel.isReady(variant),
                            isBusy = state.busyModelId == variant.id,
                            progressPercent = if (state.busyModelId == variant.id) state.progressPercent else null,
                            onSelect = { onSelect(variant) },
                            onDownload = { onDownload(variant) },
                            onCancel = { viewModel.cancelDownload(variant.id) },
                            onDelete = if (viewModel.isDeletable(variant)) ({ onDelete(variant) }) else null,
                        )
                        if (index < group.variants.lastIndex) {
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
private fun VariantRow(
    variant: RAModelInfo,
    isRecommended: Boolean,
    isCurrent: Boolean,
    isReady: Boolean,
    isBusy: Boolean,
    progressPercent: Int?,
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
            // Clean human name is the primary identifier of every variant.
            Text(
                variant.displayTitle(),
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            // Size always visible; backend as a subtle badge; feel as secondary text.
            // FlowRow so the badge wraps below instead of truncating on narrow rows.
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm),
                verticalArrangement = Arrangement.spacedBy(dimens.spacingXs),
            ) {
                Text(
                    "${variant.sizeLabel()} · ${variant.variantFeelLabel()}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                BackendBadge(framework = variant.framework, compact = true)
            }
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(dimens.spacingXs),
                verticalArrangement = Arrangement.spacedBy(dimens.spacingXs),
            ) {
                if (isRecommended) ModelPill("Recommended", ModelPillColors.Availability)
                variant.consumerTags()
                    .filter { it.kind == ConsumerTagKind.CAPABILITY }
                    .forEach { ModelPill(it.label, it.kind.pillColor()) }
                if (variant.requiresHfAuth()) {
                    val hasToken = SettingsRepository.settings.hfToken.isNotBlank()
                    ModelPill(
                        "Private",
                        if (hasToken) ModelPillColors.Capability else ModelPillColors.Warning,
                    )
                }
            }
            if (isBusy && progressPercent != null) {
                Text(
                    "Downloading… $progressPercent%",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        Spacer(Modifier.width(dimens.spacingSm))
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(dimens.spacingXs)) {
            VariantAction(isCurrent, isReady, isBusy, variant, onDownload, onCancel)
            if (onDelete != null && isReady) {
                IconButton(onClick = onDelete, modifier = Modifier.size(32.dp)) {
                    Icon(
                        imageVector = RACIcons.Outline.Trash,
                        contentDescription = "Delete ${variant.name}",
                        tint = MaterialTheme.colorScheme.error,
                        modifier = Modifier.size(dimens.iconSm),
                    )
                }
            }
        }
    }
}

@Composable
private fun VariantAction(
    isCurrent: Boolean,
    isReady: Boolean,
    isBusy: Boolean,
    variant: RAModelInfo,
    onDownload: () -> Unit,
    onCancel: (() -> Unit)? = null,
) {
    when {
        isCurrent -> ModelPill("Loaded", ModelPillColors.Availability)
        isBusy -> VariantProgressAction(onCancel)
        isReady -> ModelPill("Use", ModelPillColors.Availability)
        else -> {
            val dimens = LocalDimens.current
            val needsToken = variant.requiresHfAuth() && SettingsRepository.settings.hfToken.isBlank()
            TextButton(onClick = onDownload) {
                Icon(
                    imageVector = RACIcons.Outline.Download,
                    contentDescription = null,
                    modifier = Modifier.size(dimens.iconSm),
                )
                Spacer(Modifier.width(dimens.spacingXs))
                Text(
                    text = if (needsToken) "Set token" else "Get",
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }
    }
}

// Busy-state control. With [onCancel] the spinner becomes a tap-to-cancel target
// that stops the in-flight download; without it, a plain progress indicator.
@Composable
private fun VariantProgressAction(onCancel: (() -> Unit)?) {
    if (onCancel == null) {
        CircularProgressIndicator(
            modifier = Modifier.size(20.dp),
            strokeWidth = 2.dp,
            color = MaterialTheme.colorScheme.primary,
        )
        return
    }
    IconButton(onClick = onCancel, modifier = Modifier.size(32.dp)) {
        Box(contentAlignment = Alignment.Center) {
            CircularProgressIndicator(
                modifier = Modifier.size(24.dp),
                strokeWidth = 2.dp,
                color = MaterialTheme.colorScheme.primary,
            )
            Icon(
                imageVector = RACIcons.Outline.Close,
                contentDescription = "Cancel download",
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(12.dp),
            )
        }
    }
}