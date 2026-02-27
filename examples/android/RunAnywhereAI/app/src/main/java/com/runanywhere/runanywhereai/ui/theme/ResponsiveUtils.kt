package com.runanywhere.runanywhereai.ui.theme

import android.annotation.SuppressLint
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.TextUnitType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Responsive Dp — scales a base dp value relative to screen width.
 * Design baseline: 360dp (standard phone). On wider screens values scale up,
 * on narrower screens they scale down.
 */
@SuppressLint("ConfigurationScreenWidthHeight")
@Composable
fun rDp(baseDp: Dp, designWidth: Float = 360f): Dp {
    val screenWidthDp = LocalConfiguration.current.screenWidthDp.toFloat()
    if (screenWidthDp <= 0f) return baseDp
    return (baseDp.value * (screenWidthDp / designWidth)).dp
}

/**
 * Responsive Sp — scales a base sp value relative to screen width.
 * Preserves accessibility fontScale by default.
 */
@SuppressLint("ConfigurationScreenWidthHeight")
@Composable
fun rSp(baseSp: TextUnit, designWidth: Float = 360f): TextUnit {
    if (baseSp.type != TextUnitType.Sp) return baseSp
    val screenWidthDp = LocalConfiguration.current.screenWidthDp.toFloat()
    if (screenWidthDp <= 0f) return baseSp
    return (baseSp.value * (screenWidthDp / designWidth)).sp
}
