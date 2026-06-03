package com.runanywhere.runanywhereai.ui.theme.icons

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector

// A brand logo paired with its signature color, so it can be tinted with the brand color
// instead of the default content/primary tint.
data class Brand(val label: String, val icon: ImageVector, val color: Color)

object RACBrands {
    val Meta = Brand("Meta", RACIcons.Brands.Meta, Color(0xFF0866FF))
    val Mistral = Brand("Mistral", RACIcons.Brands.Mistral, Color(0xFFFA520F))
    val Qwen = Brand("Qwen", RACIcons.Brands.Qwen, Color(0xFF615CED))
    val HuggingFace = Brand("HuggingFace", RACIcons.Brands.HuggingFace, Color(0xFFFFD21E))
    val Whisper = Brand("Whisper", RACIcons.Brands.Whisper, Color(0xFF10A37F))
    val Liquid = Brand("Liquid", RACIcons.Brands.Liquid, Color(0xFF1E6FFF))
    val Foundation = Brand("Foundation", RACIcons.Brands.Foundation, Color(0xFF00C2A8))

    val all = listOf(Meta, Mistral, Qwen, HuggingFace, Whisper, Liquid, Foundation)
}
