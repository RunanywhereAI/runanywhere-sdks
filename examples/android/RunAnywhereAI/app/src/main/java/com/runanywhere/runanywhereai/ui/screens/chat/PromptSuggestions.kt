package com.runanywhere.runanywhereai.ui.screens.chat

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.Dp
import com.runanywhere.runanywhereai.ui.theme.AppMotion
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons

data class PromptSuggestion(val label: String, val prompt: String, val icon: ImageVector? = null)

private val generalSuggestions = listOf(
    PromptSuggestion("Plan my day", "Turn this messy list into a realistic plan with the top three priorities:"),
    PromptSuggestion("Rewrite clearly", "Rewrite this so it is clear, warm, and concise:"),
    PromptSuggestion("Compare options", "Compare these options, explain the tradeoffs, and recommend one:"),
    PromptSuggestion("Summarize notes", "Summarize these notes into decisions, action items, and open questions:"),
)

private val toolSuggestions = listOf(
    PromptSuggestion("Trip plan", "Help me make a practical packing list for a weekend city trip.", RACIcons.Outline.Stack),
    PromptSuggestion("Time check", "What time is it in London, Tokyo, and San Francisco?", RACIcons.Outline.Clock),
    PromptSuggestion("Device status", "Check my battery level and tell me if I should charge before leaving.", RACIcons.Outline.Battery),
    PromptSuggestion("Quick math", "Calculate 15% of 240, then show the shortcut.", RACIcons.Outline.Calculator),
)

private val personalizedSuggestions = listOf(
    PromptSuggestion("Draft reply", "Draft a concise, kind reply to this message:", RACIcons.Outline.User),
    PromptSuggestion("Tighten tone", "Make this message more direct while keeping it friendly:", RACIcons.Outline.Adjustments),
    PromptSuggestion("Decision memo", "Turn this into a one-page decision memo with risks and next steps:", RACIcons.Outline.Clock),
    PromptSuggestion("Coach me", "Help me think through this situation and suggest my next move:", RACIcons.Outline.Bolt),
)

private enum class PromptMode { GENERAL, TOOLS, PERSONALIZED }

@Composable
fun PromptSuggestions(
    toolsEnabled: Boolean,
    loraActive: Boolean,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val dimens = LocalDimens.current
    val mode = when {
        loraActive -> PromptMode.PERSONALIZED
        toolsEnabled -> PromptMode.TOOLS
        else -> PromptMode.GENERAL
    }
    AnimatedContent(
        targetState = mode,
        modifier = modifier,
        transitionSpec = {
            (fadeIn(AppMotion.standard()) + slideInHorizontally(AppMotion.springDefault()) { it / 5 })
                .togetherWith(
                    fadeOut(AppMotion.exit()) + slideOutHorizontally(AppMotion.exit()) { -it / 5 },
                )
        },
        label = "promptMode",
    ) { current ->
        val items = when (current) {
            PromptMode.GENERAL -> generalSuggestions
            PromptMode.TOOLS -> toolSuggestions
            PromptMode.PERSONALIZED -> personalizedSuggestions
        }
        val listState = rememberLazyListState()
        // The row overflows by design, but a chip sliced flush at the bezel reads as a
        // rendering bug rather than "scroll for more". Fading the overflowing edge is the
        // affordance; it's drawn only on the side that actually has content off-screen so
        // a row that happens to fit stays crisp.
        val fadeStart by remember { derivedStateOf { listState.canScrollBackward } }
        val fadeEnd by remember { derivedStateOf { listState.canScrollForward } }
        val surface = MaterialTheme.colorScheme.surface
        LazyRow(
            state = listState,
            contentPadding = PaddingValues(horizontal = dimens.screenPadding),
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm),
            modifier = Modifier.edgeFade(
                color = surface,
                width = dimens.spacingXl,
                atStart = fadeStart,
                atEnd = fadeEnd,
            ),
        ) {
            items(items, key = { it.label }) { suggestion ->
                SuggestionPill(suggestion) { onSelect(suggestion.prompt) }
            }
        }
    }
}

/**
 * Paints a horizontal scrim over whichever edge still has content beyond it, so an
 * overflowing row looks scrollable instead of cropped. Uses `drawWithContent` rather
 * than a stacked Box so it costs one draw pass and never affects layout or hit testing.
 */
private fun Modifier.edgeFade(color: Color, width: Dp, atStart: Boolean, atEnd: Boolean): Modifier =
    this.drawWithContent {
        drawContent()
        val px = width.toPx()
        if (atStart) {
            drawRect(
                brush = Brush.horizontalGradient(
                    listOf(color, Color.Transparent),
                    startX = 0f,
                    endX = px,
                ),
                size = Size(px, size.height),
            )
        }
        if (atEnd) {
            drawRect(
                brush = Brush.horizontalGradient(
                    listOf(Color.Transparent, color),
                    startX = size.width - px,
                    endX = size.width,
                ),
                topLeft = Offset(size.width - px, 0f),
                size = Size(px, size.height),
            )
        }
    }

@Composable
private fun SuggestionPill(suggestion: PromptSuggestion, onClick: () -> Unit) {
    val dimens = LocalDimens.current
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(dimens.radiusFull),
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        contentColor = MaterialTheme.colorScheme.onSurface,
    ) {
        Row(
            modifier = Modifier.padding(horizontal = dimens.spacingMd, vertical = dimens.spacingSm),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingXs),
        ) {
            suggestion.icon?.let {
                Icon(
                    imageVector = it,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(dimens.iconSm),
                )
            }
            Text(text = suggestion.label, style = MaterialTheme.typography.labelLarge)
        }
    }
}
