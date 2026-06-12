package com.runanywhere.runanywhereai.ui.screens.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.RACTextStyles
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.runanywhereai.ui.theme.primaryGreen

@Composable
fun ToolCallChip(tool: ToolCallInfo, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val dimens = LocalDimens.current
    val accent = if (tool.success) primaryGreen else MaterialTheme.colorScheme.error
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(dimens.radiusSm))
            .background(accent.copy(alpha = 0.1f))
            .border(0.5.dp, accent.copy(alpha = 0.3f), RoundedCornerShape(dimens.radiusSm))
            .clickable(onClick = onClick)
            .padding(horizontal = dimens.spacingSm, vertical = dimens.spacingXs),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(dimens.spacingXs),
    ) {
        Icon(
            imageVector = if (tool.success) RACIcons.Outline.Tool else RACIcons.Outline.AlertTriangle,
            contentDescription = null,
            tint = accent,
            modifier = Modifier.size(dimens.iconSm),
        )
        Text(
            text = tool.name,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurface,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ToolCallDetailSheet(tool: ToolCallInfo, onDismiss: () -> Unit) {
    val dimens = LocalDimens.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = MaterialTheme.colorScheme.surfaceContainer,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = dimens.spacingLg)
                .padding(bottom = dimens.spacingXl),
            verticalArrangement = Arrangement.spacedBy(dimens.spacingLg),
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm),
            ) {
                val accent = if (tool.success) primaryGreen else MaterialTheme.colorScheme.error
                Icon(
                    imageVector = if (tool.success) RACIcons.Outline.Tool else RACIcons.Outline.AlertTriangle,
                    contentDescription = null,
                    tint = accent,
                    modifier = Modifier.size(dimens.iconMd),
                )
                Text(tool.name, style = MaterialTheme.typography.titleMedium)
            }

            CodeSection("Arguments", tool.arguments)
            tool.result?.let { CodeSection("Result", it) }
            tool.error?.let {
                CodeSection("Error", it, tint = MaterialTheme.colorScheme.error)
            }
        }
    }
}

@Composable
private fun CodeSection(title: String, code: String, tint: Color = Color.Unspecified) {
    val dimens = LocalDimens.current
    Column(verticalArrangement = Arrangement.spacedBy(dimens.spacingXs)) {
        Text(
            text = title,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(dimens.radiusSm))
                .background(MaterialTheme.colorScheme.surfaceContainerHighest)
                .horizontalScroll(rememberScrollState())
                .padding(dimens.spacingMd),
        ) {
            Text(
                text = code,
                style = RACTextStyles.CodeSmall,
                color = if (tint == Color.Unspecified) MaterialTheme.colorScheme.onSurface else tint,
            )
        }
    }
}
