package com.runanywhere.runanywhereai.ui.theme.icons

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector

// A brand logo paired with its signature color, so it can be tinted with the brand color
// instead of the default content/primary tint.
data class Brand(val label: String, val icon: ImageVector, val color: Color)

/**
 * One entry per model maker the catalog ships.
 *
 * Makers we hold a real mark for use it. For the rest, the *colour* is the identity and the
 * glyph is deliberately neutral — [RACIcons.Outline.Model], the same "a model is an artifact"
 * mark used wherever the subject is the file the user picked. Borrowing an unrelated logo is
 * how NVIDIA rows once ended up wearing Meta's mark.
 *
 * These six previously shared [RACIcons.Outline.Stack] with the llama.cpp backend badge, the
 * Advanced-hub nav entry, a Settings row and a prompt chip — one picture across five unrelated
 * meanings. `Stack` is now the inference-framework mark only.
 */
object RACBrands {
    val Nvidia = Brand("NVIDIA", RACIcons.Outline.Model, Color(0xFF76B900))
    val Meta = Brand("Meta", RACIcons.Brands.Meta, Color(0xFF0866FF))
    val Alibaba = Brand("Alibaba", RACIcons.Brands.Qwen, Color(0xFF615CED))
    val Google = Brand("Google", RACIcons.Outline.Model, Color(0xFF4285F4))
    val Microsoft = Brand("Microsoft", RACIcons.Outline.Model, Color(0xFF00A4EF))
    val DeepSeek = Brand("DeepSeek", RACIcons.Outline.Model, Color(0xFF4D6BFE))
    val Liquid = Brand("Liquid AI", RACIcons.Brands.Liquid, Color(0xFF1E6FFF))
    val Mistral = Brand("Mistral AI", RACIcons.Brands.Mistral, Color(0xFFFA520F))
    val Prism = Brand("Prism", RACIcons.Outline.Model, Color(0xFF2FA98C))
    val OpenAI = Brand("OpenAI", RACIcons.Brands.Whisper, Color(0xFF10A37F))
    val HuggingFace = Brand("Hugging Face", RACIcons.Brands.HuggingFace, Color(0xFFFFD21E))
    val Apple = Brand("Apple", RACIcons.Brands.Foundation, Color(0xFF00C2A8))
    val OpenSource = Brand("Open source", RACIcons.Outline.Model, Color(0xFF9AA0A6))
}
