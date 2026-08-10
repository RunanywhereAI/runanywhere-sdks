package com.runanywhere.runanywhereai.ui.theme

import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

// Primary tonal — RunAnywhere brand orange (#FF6900 hue); see examples/DESIGN_GUIDELINE.md
val Primary20 = Color(0xFF4C1F00)
val Primary30 = Color(0xFF732F00)
val Primary60 = Color(0xFFE65E00)
val Primary70 = Color(0xFFFF7B1F)
val Primary80 = Color(0xFFFFC094)
val Primary90 = Color(0xFFFFE1CC)

// Canonical brand accent — the RunAnywhere logo orange (#FF6900), shared with every example app.
// Used as the dark-scheme primary so brand moments match across platforms.
val BrandOrange = Color(0xFFFF6900)

// The logo gradient's red stop. Only ever painted as a gradient with [BrandOrange].
val BrandRed = Color(0xFFFB2C36)

/**
 * The logo gradient — top-left to bottom-right, matching the web
 * `linear-gradient(135deg, #FF6900, #FB2C36)` and iOS `AppColors.brandGradient`.
 *
 * It marks the reader's *own* words: every user turn in the app (chat, RAG, voice) paints it,
 * and nothing else does. Carrying [Neutral100] on it is the one white-on-orange deviation
 * DESIGN_GUIDELINE §5 keeps for large/bold brand moments, so this is the only place the app is
 * allowed to put white over the brand — a solid `primary` fill must use [OnBrandInk] instead.
 * One `val` rather than a brush per call site so a bubble cannot drift from the mark;
 * `Brush.linearGradient` resolves its end offset against the draw size, so a single instance is
 * correct at every bubble width.
 */
val BrandGradient: Brush = Brush.linearGradient(listOf(BrandOrange, BrandRed))

/**
 * Text and control glyphs sitting ON a solid brand fill.
 *
 * White on #FF6900 measures 2.89:1 and on the light scheme's #E65E00 primary 3.52:1 — both
 * under AA's 4.5:1 for small text and under even the 3:1 floor a control glyph asks
 * (DESIGN_GUIDELINE §5, which also rules out darkening the hue: it is locked identity). This
 * ink is 6.12:1 on #FF6900 and 5.02:1 on #E65E00, so `onPrimary` clears AA in both schemes.
 * Deliberately the same hex as iOS `AppColors.onBrand` and the web `--text-on-primary`, so a
 * filled primary button reads identically on all four surfaces.
 */
val OnBrandInk = Color(0xFF10182B)

// Secondary tonal — Warm Neutral
val Secondary10 = Color(0xFF1F1A17)
val Secondary20 = Color(0xFF352F2B)
val Secondary30 = Color(0xFF4C4541)
val Secondary40 = Color(0xFF655D58)
val Secondary80 = Color(0xFFD0C5BF)
val Secondary90 = Color(0xFFEDE0DA)

// Tertiary tonal — Warm Gold
val Tertiary10 = Color(0xFF231B00)
val Tertiary20 = Color(0xFF3B3000)
val Tertiary30 = Color(0xFF554600)
val Tertiary40 = Color(0xFF705D00)
val Tertiary80 = Color(0xFFE5C52A)
val Tertiary90 = Color(0xFFF4E07A)

// Error tonal
val Error10 = Color(0xFF410002)
val Error20 = Color(0xFF690005)
val Error30 = Color(0xFF93000A)
val Error40 = Color(0xFFBA1A1A)
val Error80 = Color(0xFFFFB4AB)
val Error90 = Color(0xFFFFDAD6)

// Neutral tonal — Surfaces
val Neutral4 = Color(0xFF0F0F0F)
val Neutral6 = Color(0xFF141414)
val Neutral10 = Color(0xFF1C1B1B)
val Neutral12 = Color(0xFF201F1F)
val Neutral17 = Color(0xFF2B2A2A)
val Neutral20 = Color(0xFF313030)
val Neutral22 = Color(0xFF363534)
val Neutral90 = Color(0xFFE6E1E0)
val Neutral92 = Color(0xFFECE6E4)
val Neutral94 = Color(0xFFF2ECEA)
val Neutral95 = Color(0xFFF5F0EE)
val Neutral96 = Color(0xFFF8F2F0)
val Neutral98 = Color(0xFFFEF8F6)
val Neutral99 = Color(0xFFFFFBFF)
val Neutral100 = Color(0xFFFFFFFF)

// Neutral Variant tonal — Outlines & surface tints
val NeutralVariant30 = Color(0xFF4E4542)
val NeutralVariant50 = Color(0xFF807672)
val NeutralVariant60 = Color(0xFF9B908B)
val NeutralVariant80 = Color(0xFFD1C5C0)
val NeutralVariant90 = Color(0xFFEDE0DB)

//Success
val primaryGreen = Color(0xFF10B981) // Emerald-500 - success green
