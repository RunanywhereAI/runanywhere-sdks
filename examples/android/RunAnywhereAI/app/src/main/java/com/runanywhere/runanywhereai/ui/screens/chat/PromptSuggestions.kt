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
    PromptSuggestion("Explain LLMs", "Explain how large language models work, in simple terms."),
    PromptSuggestion("Write a poem", "Write a short poem about the ocean at night."),
    PromptSuggestion("Summarize a story", "Summarize Romeo and Juliet in three sentences."),
    PromptSuggestion("Name ideas", "Give me five creative names for a coffee shop."),
)

private val toolSuggestions = listOf(
    PromptSuggestion("Weather in Tokyo", "What's the weather in Tokyo right now?", RACIcons.Outline.Cloud),
    PromptSuggestion("Current time", "What time is it right now?", RACIcons.Outline.Clock),
    PromptSuggestion("Battery level", "What's my battery level?", RACIcons.Outline.Battery),
    PromptSuggestion("Quick math", "What is 15% of 240?", RACIcons.Outline.Calculator),
)

private val uncensoredSuggestions = listOf(
    PromptSuggestion("Brutally honest", "Give me brutally honest feedback on a weak startup idea.", RACIcons.Outline.Bolt),
    PromptSuggestion("Dark joke", "Tell me a dark joke.", RACIcons.Outline.Bolt),
    PromptSuggestion("Hot take", "Give me a controversial tech opinion and defend it hard.", RACIcons.Outline.Bolt),
    PromptSuggestion("Roast me", "Roast my code in one savage paragraph, no holding back.", RACIcons.Outline.Bolt),
)

private enum class PromptMode { GENERAL, TOOLS, UNCENSORED }

@Composable
fun PromptSuggestions(
    toolsEnabled: Boolean,
    loraActive: Boolean,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val dimens = LocalDimens.current
    val mode = when {
        loraActive -> PromptMode.UNCENSORED
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
            PromptMode.UNCENSORED -> uncensoredSuggestions
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
