package com.runanywhere.runanywhereai.ui.theme

import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

// Spacing / size / radius scale. Read via LocalDimens.current — no magic numbers in UI code.
data class Dimens(
    val screenPadding: Dp,
    val spacingXs: Dp,
    val spacingSm: Dp,
    val spacingMd: Dp,
    val spacingLg: Dp,
    val spacingXl: Dp,
    val iconSm: Dp,
    val iconMd: Dp,
    val iconLg: Dp,
    val radiusSm: Dp,
    val radiusMd: Dp,
    val radiusLg: Dp,
    val radiusFull: Dp,
    val inputBarMinHeight: Dp,
    val contentMaxWidth: Dp,
    val navDrawerWidth: Dp,
)

val CompactDimens = Dimens(
    screenPadding = 16.dp,
    spacingXs = 4.dp,
    spacingSm = 8.dp,
    spacingMd = 12.dp,
    spacingLg = 16.dp,
    spacingXl = 24.dp,
    iconSm = 18.dp,
    iconMd = 22.dp,
    iconLg = 28.dp,
    radiusSm = 8.dp,
    radiusMd = 12.dp,
    radiusLg = 20.dp,
    radiusFull = 999.dp,
    inputBarMinHeight = 48.dp,
    contentMaxWidth = 760.dp,
    navDrawerWidth = 260.dp,
)

val LocalDimens = staticCompositionLocalOf { CompactDimens }
