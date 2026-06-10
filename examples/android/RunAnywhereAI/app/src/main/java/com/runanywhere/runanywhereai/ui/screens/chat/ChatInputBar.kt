package com.runanywhere.runanywhereai.ui.screens.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons

@Composable
fun ChatInputBar(
    input: String,
    onInputChange: (String) -> Unit,
    onSend: () -> Unit,
    canSend: Boolean,
    isGenerating: Boolean,
    onStop: () -> Unit,
    toolsEnabled: Boolean,
    onToggleTools: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val dimens = LocalDimens.current
    androidx.compose.foundation.layout.Column(
        modifier = modifier.background(MaterialTheme.colorScheme.surface),
    ) {
        HorizontalDivider(
            thickness = 0.5.dp,
            color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = dimens.spacingMd, vertical = dimens.spacingSm),
            verticalAlignment = Alignment.Bottom,
        ) {
            IconButton(
                onClick = onToggleTools,
                modifier = Modifier
                    .padding(end = dimens.spacingSm)
                    .size(dimens.inputBarMinHeight),
                colors = IconButtonDefaults.iconButtonColors(
                    containerColor = if (toolsEnabled) {
                        MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)
                    } else {
                        MaterialTheme.colorScheme.surfaceContainerHigh
                    },
                    contentColor = if (toolsEnabled) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                ),
            ) {
                Icon(
                    imageVector = RACIcons.Outline.Tool,
                    contentDescription = if (toolsEnabled) "Disable tools" else "Enable tools",
                    modifier = Modifier.size(dimens.iconMd),
                )
            }

            Box(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(dimens.radiusLg))
                    .background(MaterialTheme.colorScheme.surfaceContainerHigh)
                    .heightIn(min = dimens.inputBarMinHeight)
                    .padding(horizontal = dimens.spacingLg, vertical = dimens.spacingMd),
                contentAlignment = Alignment.CenterStart,
            ) {
                if (input.isEmpty()) {
                    Text(
                        text = "Message…",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                    )
                }
                BasicTextField(
                    value = input,
                    onValueChange = onInputChange,
                    modifier = Modifier.fillMaxWidth(),
                    textStyle = MaterialTheme.typography.bodyLarge.copy(
                        color = MaterialTheme.colorScheme.onSurface,
                    ),
                    cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                    maxLines = 5,
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.Sentences,
                        imeAction = ImeAction.Default,
                    ),
                )
            }

            IconButton(
                onClick = if (isGenerating) onStop else onSend,
                enabled = isGenerating || canSend,
                modifier = Modifier
                    .padding(start = dimens.spacingSm)
                    .size(dimens.inputBarMinHeight),
                colors = IconButtonDefaults.iconButtonColors(
                    containerColor = MaterialTheme.colorScheme.primary,
                    contentColor = MaterialTheme.colorScheme.onPrimary,
                    disabledContainerColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                    disabledContentColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.38f),
                ),
            ) {
                Icon(
                    imageVector = if (isGenerating) RACIcons.Outline.PlayerStop else RACIcons.Outline.Send,
                    contentDescription = if (isGenerating) "Stop" else "Send message",
                    modifier = Modifier.size(dimens.iconMd),
                )
            }
        }
    }
}
