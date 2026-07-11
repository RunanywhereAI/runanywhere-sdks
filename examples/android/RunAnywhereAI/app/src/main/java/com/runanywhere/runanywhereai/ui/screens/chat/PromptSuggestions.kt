package com.runanywhere.runanywhereai.ui.screens.chat

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.core.tween
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
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
            (fadeIn(tween(220)) + slideInHorizontally { it / 5 })
                .togetherWith(fadeOut(tween(140)) + slideOutHorizontally { -it / 5 })
        },
        label = "promptMode",
    ) { current ->
        val items = when (current) {
            PromptMode.GENERAL -> generalSuggestions
            PromptMode.TOOLS -> toolSuggestions
            PromptMode.PERSONALIZED -> personalizedSuggestions
        }
        LazyRow(
            contentPadding = PaddingValues(horizontal = dimens.screenPadding),
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm),
        ) {
            items(items) { suggestion ->
                SuggestionPill(suggestion) { onSelect(suggestion.prompt) }
            }
        }
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
