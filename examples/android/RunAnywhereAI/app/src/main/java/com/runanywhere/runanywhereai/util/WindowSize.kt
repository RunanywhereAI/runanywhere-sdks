package com.runanywhere.runanywhereai.util

import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

// Material breakpoint: at/above this width use a side nav rail instead of a bottom bar.
const val EXPANDED_WIDTH_DP = 600

val LocalIsExpandedLayout = staticCompositionLocalOf { false }

@Composable
fun isExpandedScreen(): Boolean =
    LocalConfiguration.current.screenWidthDp >= EXPANDED_WIDTH_DP

// Caps content to a comfortable reading width and centers it, so single-purpose
// screens don't stretch edge-to-edge on tablets/landscape. No-op on narrow screens.
// Apply right after fillMaxSize() on a screen's root: Modifier.fillMaxSize().readableWidth()
fun Modifier.readableWidth(maxWidth: Dp = 640.dp): Modifier =
    this.wrapContentWidth().widthIn(max = maxWidth)
