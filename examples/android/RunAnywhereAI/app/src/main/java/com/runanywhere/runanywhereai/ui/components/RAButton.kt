package com.runanywhere.runanywhereai.ui.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.theme.AppMotion

/** Visual style for [RAButton]. */
enum class RAButtonStyle {
    Filled,
    Tonal,
    Outlined,
}

// -- Press-scale modifier (shared) -----------------------------------------------

@Composable
private fun pressScale(interactionSource: MutableInteractionSource): Float {
    val pressed by interactionSource.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (pressed) 0.96f else 1f,
        animationSpec = AppMotion.tweenShort(),
        label = "RAButtonPressScale",
    )
    return scale
}

// -- Icon-only button ------------------------------------------------------------

/**
 * Circular icon-only button with press-scale feedback.
 */
@Composable
fun RAIconButton(
    icon: ImageVector,
    contentDescription: String?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    tint: Color = MaterialTheme.colorScheme.primary,
    containerColor: Color = Color.Transparent,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val scale = pressScale(interactionSource)

    IconButton(
        onClick = onClick,
        modifier = modifier
            .size(40.dp)
            .scale(scale),
        enabled = enabled,
        interactionSource = interactionSource,
        colors = IconButtonDefaults.iconButtonColors(containerColor = containerColor),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = contentDescription,
            tint = if (enabled) tint else tint.copy(alpha = 0.38f),
            modifier = Modifier.size(20.dp),
        )
    }
}

// -- Text / icon+text button -----------------------------------------------------

/**
 * Versatile button supporting text-only or leading-icon + text.
 *
 * @param text label text
 * @param icon optional leading icon
 * @param style Filled / Tonal / Outlined
 * @param contentColor override content color; defaults per style
 */
@Composable
fun RAButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    style: RAButtonStyle = RAButtonStyle.Filled,
    enabled: Boolean = true,
    contentColor: Color = Color.Unspecified,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val scale = pressScale(interactionSource)
    val scaledModifier = modifier.scale(scale)

    val innerContent: @Composable () -> Unit = {
        if (icon != null) {
            Icon(imageVector = icon, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(modifier = Modifier.width(6.dp))
        }
        Text(text)
    }

    when (style) {
        RAButtonStyle.Filled -> {
            Button(
                onClick = onClick,
                modifier = scaledModifier,
                enabled = enabled,
                interactionSource = interactionSource,
                colors = if (contentColor != Color.Unspecified) {
                    ButtonDefaults.buttonColors(contentColor = contentColor)
                } else {
                    ButtonDefaults.buttonColors()
                },
                contentPadding = buttonPadding(icon != null),
            ) { innerContent() }
        }

        RAButtonStyle.Tonal -> {
            FilledTonalButton(
                onClick = onClick,
                modifier = scaledModifier,
                enabled = enabled,
                interactionSource = interactionSource,
                colors = if (contentColor != Color.Unspecified) {
                    ButtonDefaults.filledTonalButtonColors(contentColor = contentColor)
                } else {
                    ButtonDefaults.filledTonalButtonColors()
                },
                contentPadding = buttonPadding(icon != null),
            ) { innerContent() }
        }

        RAButtonStyle.Outlined -> {
            OutlinedButton(
                onClick = onClick,
                modifier = scaledModifier,
                enabled = enabled,
                interactionSource = interactionSource,
                colors = if (contentColor != Color.Unspecified) {
                    ButtonDefaults.outlinedButtonColors(contentColor = contentColor)
                } else {
                    ButtonDefaults.outlinedButtonColors()
                },
                contentPadding = buttonPadding(icon != null),
            ) { innerContent() }
        }
    }
}

private fun buttonPadding(hasIcon: Boolean): PaddingValues =
    if (hasIcon) {
        PaddingValues(start = 16.dp, top = 8.dp, end = 20.dp, bottom = 8.dp)
    } else {
        PaddingValues(horizontal = 20.dp, vertical = 8.dp)
    }
