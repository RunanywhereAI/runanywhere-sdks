package com.runanywhere.runanywhereai.ui.screens.chat

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons



@Composable
fun ScrollToBottomButton(
    modifier: Modifier = Modifier,
    visible: Boolean,
    onClick: () -> Unit = {},
) {
    val dimens = LocalDimens.current
    AnimatedVisibility(
        visible = visible,
        enter = fadeIn() + scaleIn(initialScale = 0.8f),
        exit = fadeOut() + scaleOut(targetScale = 0.8f),
        modifier = modifier,
    ) {
        Surface(
            onClick = onClick,
            shape = CircleShape,
            color = MaterialTheme.colorScheme.background,
            contentColor = MaterialTheme.colorScheme.onSurface,
            shadowElevation = 0.dp,
            border = BorderStroke(1.dp, MaterialTheme.colorScheme.onSurface),
            modifier = Modifier.size(36.dp),
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    imageVector = RACIcons.Outline.ChevronDown,
                    contentDescription = "Scroll to latest",
                    modifier = Modifier.size(dimens.iconMd),
                )
            }
        }
    }
}
