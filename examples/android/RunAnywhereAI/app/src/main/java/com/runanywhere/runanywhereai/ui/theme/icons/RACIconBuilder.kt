package com.runanywhere.runanywhereai.ui.theme.icons

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.unit.dp

// Tabler Icons (https://tabler.io/icons) as ImageVectors, used like Material icons.
// Pass each <path d="..."> from the SVG as an arg; black base color is overridden by Icon()'s tint.
// To add one: copy the path data from tabler.io/icons into RACIcons.Outline/Filled.

private const val VIEWPORT_SIZE = 24f
private const val TABLER_STROKE_WIDTH = 2f

internal fun racOutlineIcon(name: String, vararg pathData: String): ImageVector =
    ImageVector.Builder(
        name = "RACIcons.Outline.$name",
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = VIEWPORT_SIZE,
        viewportHeight = VIEWPORT_SIZE,
    ).apply {
        for (d in pathData) {
            addPath(
                pathData = addPathNodes(d),
                stroke = SolidColor(Color.Black),
                strokeLineWidth = TABLER_STROKE_WIDTH,
                strokeLineCap = StrokeCap.Round,
                strokeLineJoin = StrokeJoin.Round,
            )
        }
    }.build()

internal fun racFilledIcon(name: String, vararg pathData: String): ImageVector =
    ImageVector.Builder(
        name = "RACIcons.Filled.$name",
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = VIEWPORT_SIZE,
        viewportHeight = VIEWPORT_SIZE,
    ).apply {
        for (d in pathData) {
            addPath(
                pathData = addPathNodes(d),
                fill = SolidColor(Color.Black),
            )
        }
    }.build()
