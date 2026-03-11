package com.runanywhere.runanywhereai.ui.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.theme.AppMotion

/** Visual variant for [RACard]. */
enum class RACardVariant {
    /** Surface container background, no border. */
    Standard,
    /** Thin outline border. */
    Outlined,
    /** Soft shadow elevation. */
    Elevated,
}

/**
 * Reusable card with header / content / footer slots.
 *
 * @param variant visual treatment (Standard, Outlined, Elevated)
 * @param containerColor override background; defaults to surfaceContainerLow
 * @param contentPadding inner padding applied to the column that hosts the three slots
 * @param header optional top slot (e.g. section title row)
 * @param footer optional bottom slot (e.g. action buttons)
 * @param content main body slot
 */
@Composable
fun RACard(
    modifier: Modifier = Modifier,
    variant: RACardVariant = RACardVariant.Standard,
    containerColor: Color = MaterialTheme.colorScheme.surfaceContainerLow,
    contentPadding: Dp = 16.dp,
    header: @Composable (ColumnScope.() -> Unit)? = null,
    footer: @Composable (ColumnScope.() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val animatedColor by animateColorAsState(
        targetValue = containerColor,
        animationSpec = AppMotion.tweenMedium(),
        label = "RACardColor",
    )

    when (variant) {
        RACardVariant.Standard -> {
            Surface(
                modifier = modifier.fillMaxWidth(),
                shape = MaterialTheme.shapes.large,
                color = animatedColor,
                tonalElevation = 0.dp,
            ) {
                CardContent(contentPadding, header, footer, content)
            }
        }

        RACardVariant.Outlined -> {
            OutlinedCard(
                modifier = modifier.fillMaxWidth(),
                shape = MaterialTheme.shapes.large,
                colors = CardDefaults.outlinedCardColors(containerColor = animatedColor),
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
            ) {
                CardContent(contentPadding, header, footer, content)
            }
        }

        RACardVariant.Elevated -> {
            ElevatedCard(
                modifier = modifier.fillMaxWidth(),
                shape = MaterialTheme.shapes.large,
                colors = CardDefaults.elevatedCardColors(containerColor = animatedColor),
                elevation = CardDefaults.elevatedCardElevation(defaultElevation = 2.dp),
            ) {
                CardContent(contentPadding, header, footer, content)
            }
        }
    }
}

@Composable
private fun CardContent(
    contentPadding: Dp,
    header: @Composable (ColumnScope.() -> Unit)?,
    footer: @Composable (ColumnScope.() -> Unit)?,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(modifier = Modifier.padding(contentPadding)) {
        header?.invoke(this)
        content()
        footer?.invoke(this)
    }
}
