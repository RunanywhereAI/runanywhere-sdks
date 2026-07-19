package com.runanywhere.runanywhereai.ui.screens.models

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import ai.runanywhere.proto.v1.ModelCategory
import com.runanywhere.runanywhereai.data.settings.SettingsRepository
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.runanywhereai.ui.theme.primaryGreen
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
    val hasNpuVariant: Boolean get() = family.key.endsWith("-npu")

    // Category of the primary (lead) variant — drives the category-based family sort.
    val category: ModelCategory get() = variants.first().category

    // True when any variant is already downloaded or built in — ready families sort first.
    val hasReadyVariant: Boolean get() = variants.any { it.isBuiltIn || it.isDownloadedOnDisk }

    // The single cleanest tag shown on the collapsed family card: prefer a notable
    // capability from the lead variant, else the lead variant's feel word.
    val headlineTag: ConsumerTag?
        get() = variants.firstOrNull()?.consumerTags()?.let { tags ->
            tags.firstOrNull { it.kind == ConsumerTagKind.CAPABILITY } ?: tags.firstOrNull()
        }
}

// Chat → vision → voice → documents → other. Mirrors iOS ModelFamilyCatalog.categoryRank.
private fun ModelCategory.familyRank(): Int = when (this) {
    ModelCategory.MODEL_CATEGORY_LANGUAGE -> 0
    ModelCategory.MODEL_CATEGORY_MULTIMODAL,
    ModelCategory.MODEL_CATEGORY_VISION,
    ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION -> 1
    ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
    ModelCategory.MODEL_CATEGORY_AUDIO,
    ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION -> 2
    ModelCategory.MODEL_CATEGORY_EMBEDDING -> 3
    else -> 4
}

// Groups models into families, ordering variants smaller → larger and families by
// category (chat → vision → voice → docs → other), then ready-first, then name.
fun List<RAModelInfo>.toFamilyGroups(): List<FamilyGroup> =
    groupBy { it.family().key }
        .map { (_, models) ->
            val family = models.first().family()
            FamilyGroup(family, models.sortedBy { it.effectiveBytes() })
        }
        .sortedWith(
            compareBy<FamilyGroup> { it.category.familyRank() }
                .thenByDescending { it.hasReadyVariant }
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
                    imageVector = group.variants.first().brand().icon,
                    contentDescription = null,
                    tint = group.variants.first().brand().color,
                    modifier = Modifier.size(dimens.iconLg),
                )
                Spacer(Modifier.width(dimens.spacingMd))
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(dimens.spacingXs),
                ) {
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
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(dimens.spacingXs)) {
                        group.headlineTag?.let { TagPill(it.label, MaterialTheme.colorScheme.primary) }
                        val optionsLabel = if (group.optionCount == 1) "1 option" else "${group.optionCount} options"
                        TagPill(optionsLabel, MaterialTheme.colorScheme.onSurfaceVariant)
                        if (readyCount > 0) TagPill("$readyCount ready", primaryGreen)
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
            FlowRow(horizontalArrangement = Arrangement.spacedBy(dimens.spacingXs)) {
                if (isRecommended) TagPill("Recommended", primaryGreen)
                variant.consumerTags()
                    .filter { it.kind == ConsumerTagKind.CAPABILITY }
                    .forEach { TagPill(it.label, MaterialTheme.colorScheme.primary) }
                if (variant.requiresHfAuth()) {
                    val hasToken = SettingsRepository.settings.hfToken.isNotBlank()
                    TagPill("Private", if (hasToken) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error)
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
        isCurrent -> TagPill("Loaded", primaryGreen)
        isBusy -> VariantProgressAction(onCancel)
        isReady -> TagPill("Use", primaryGreen)
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

@Composable
private fun TagPill(text: String, color: Color) {
    val dimens = LocalDimens.current
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(dimens.radiusSm))
            .background(color.copy(alpha = 0.12f))
            .padding(horizontal = dimens.spacingSm, vertical = dimens.spacingXs),
    ) {
        Text(
            text,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold,
            color = color,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}
