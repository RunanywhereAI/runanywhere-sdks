package com.runanywhere.runanywhereai.ui.screens.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.RACTextStyles

@Composable
fun MarkdownText(
    markdown: String,
    color: Color,
    modifier: Modifier = Modifier,
    style: TextStyle = MaterialTheme.typography.bodyLarge,
) {
    val dimens = LocalDimens.current
    val blocks = remember(markdown) { parseMarkdown(markdown) }
    val codeBackground = MaterialTheme.colorScheme.surfaceContainerHighest
    val linkColor = MaterialTheme.colorScheme.primary

    Column(modifier = modifier) {
        blocks.forEach { block ->
            when (block) {
                is MdBlock.Code -> CodeBlock(block.code, block.language)
                MdBlock.Rule -> HorizontalDivider(
                    modifier = Modifier.padding(vertical = dimens.spacingSm),
                    color = MaterialTheme.colorScheme.outlineVariant,
                )
                is MdBlock.Header -> Text(
                    text = inline(block.text, codeBackground, linkColor),
                    style = headerStyle(block.level),
                    color = color,
                    modifier = Modifier.padding(top = dimens.spacingSm, bottom = dimens.spacingXs),
                )
                is MdBlock.Quote -> Row(
                    modifier = Modifier
                        .height(IntrinsicSize.Min)
                        .padding(vertical = dimens.spacingXs),
                ) {
                    Box(
                        modifier = Modifier
                            .padding(end = dimens.spacingSm)
                            .width(3.dp)
                            .fillMaxHeight()
                            .clip(RoundedCornerShape(dimens.radiusFull))
                            .background(MaterialTheme.colorScheme.outline),
                    )
                    Text(
                        text = inline(block.text, codeBackground, linkColor),
                        style = style,
                        color = color.copy(alpha = 0.8f),
                    )
                }
                is MdBlock.Bullet -> ListRow("•", block.text, style, color, codeBackground, linkColor)
                is MdBlock.Numbered -> ListRow("${block.number}.", block.text, style, color, codeBackground, linkColor)
                is MdBlock.Paragraph -> Text(
                    text = inline(block.text, codeBackground, linkColor),
                    style = style,
                    color = color,
                    modifier = Modifier.padding(vertical = dimens.spacingXs),
                )
            }
        }
    }
}

@Composable
private fun ListRow(
    marker: String,
    text: String,
    style: TextStyle,
    color: Color,
    codeBackground: Color,
    linkColor: Color,
) {
    val dimens = LocalDimens.current
    Row(modifier = Modifier.padding(vertical = dimens.spacingXs / 2)) {
        Text(text = "$marker ", style = style, color = color.copy(alpha = 0.7f))
        Text(text = inline(text, codeBackground, linkColor), style = style, color = color)
    }
}

@Composable
private fun CodeBlock(code: String, language: String?) {
    val dimens = LocalDimens.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = dimens.spacingXs)
            .clip(RoundedCornerShape(dimens.radiusSm))
            .background(MaterialTheme.colorScheme.surfaceContainerHighest),
    ) {
        if (!language.isNullOrBlank()) {
            Text(
                text = language,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = dimens.spacingMd, vertical = dimens.spacingXs),
            )
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
        }
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState())
                .padding(dimens.spacingMd),
        ) {
            Text(text = code, style = RACTextStyles.Code, color = MaterialTheme.colorScheme.onSurface)
        }
    }
}

@Composable
private fun headerStyle(level: Int): TextStyle = when (level) {
    1 -> MaterialTheme.typography.titleLarge
    2 -> MaterialTheme.typography.titleMedium
    else -> MaterialTheme.typography.titleSmall
}

private sealed interface MdBlock {
    data class Paragraph(val text: String) : MdBlock
    data class Header(val level: Int, val text: String) : MdBlock
    data class Bullet(val text: String) : MdBlock
    data class Numbered(val number: Int, val text: String) : MdBlock
    data class Quote(val text: String) : MdBlock
    data class Code(val code: String, val language: String?) : MdBlock
    data object Rule : MdBlock
}

private val numberedRegex = Regex("""^(\d+)\.\s+(.*)""")
private val headerRegex = Regex("""^(#{1,6})\s+(.*)""")

private fun parseMarkdown(markdown: String): List<MdBlock> {
    val blocks = mutableListOf<MdBlock>()
    val lines = markdown.split("\n")
    val paragraph = StringBuilder()

    fun flushParagraph() {
        if (paragraph.isNotEmpty()) {
            blocks += MdBlock.Paragraph(paragraph.toString().trim())
            paragraph.clear()
        }
    }

    var i = 0
    while (i < lines.size) {
        val line = lines[i]
        val trimmed = line.trim()

        if (trimmed.startsWith("```")) {
            flushParagraph()
            val language = trimmed.removePrefix("```").trim().ifEmpty { null }
            val code = StringBuilder()
            i++
            while (i < lines.size && !lines[i].trim().startsWith("```")) {
                if (code.isNotEmpty()) code.append("\n")
                code.append(lines[i])
                i++
            }
            blocks += MdBlock.Code(code.toString(), language)
            i++
            continue
        }

        when {
            trimmed.isEmpty() -> flushParagraph()
            trimmed == "---" || trimmed == "***" || trimmed == "___" -> {
                flushParagraph()
                blocks += MdBlock.Rule
            }
            headerRegex.matches(trimmed) -> {
                flushParagraph()
                val (hashes, content) = headerRegex.find(trimmed)!!.destructured
                blocks += MdBlock.Header(hashes.length, content)
            }
            trimmed.startsWith("> ") -> {
                flushParagraph()
                blocks += MdBlock.Quote(trimmed.removePrefix("> "))
            }
            trimmed.startsWith("- ") || trimmed.startsWith("* ") -> {
                flushParagraph()
                blocks += MdBlock.Bullet(trimmed.substring(2))
            }
            numberedRegex.matches(trimmed) -> {
                flushParagraph()
                val (number, content) = numberedRegex.find(trimmed)!!.destructured
                blocks += MdBlock.Numbered(number.toInt(), content)
            }
            else -> {
                if (paragraph.isNotEmpty()) paragraph.append("\n")
                paragraph.append(trimmed)
            }
        }
        i++
    }
    flushParagraph()
    return blocks
}

private fun inline(text: String, codeBackground: Color, linkColor: Color): AnnotatedString =
    buildAnnotatedString {
        var i = 0
        while (i < text.length) {
            when {
                text.startsWith("**", i) -> {
                    val end = text.indexOf("**", i + 2)
                    if (end < 0) { append(text.substring(i)); i = text.length } else {
                        withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(text.substring(i + 2, end)) }
                        i = end + 2
                    }
                }
                text[i] == '*' -> {
                    val end = text.indexOf('*', i + 1)
                    if (end < 0) { append(text.substring(i)); i = text.length } else {
                        withStyle(SpanStyle(fontStyle = FontStyle.Italic)) { append(text.substring(i + 1, end)) }
                        i = end + 1
                    }
                }
                text[i] == '`' -> {
                    val end = text.indexOf('`', i + 1)
                    if (end < 0) { append(text.substring(i)); i = text.length } else {
                        withStyle(SpanStyle(fontFamily = RACTextStyles.Code.fontFamily, background = codeBackground)) {
                            append(text.substring(i + 1, end))
                        }
                        i = end + 1
                    }
                }
                text[i] == '[' -> {
                    val close = text.indexOf(']', i)
                    val open = if (close >= 0) text.indexOf('(', close) else -1
                    val end = if (open >= 0) text.indexOf(')', open) else -1
                    if (close < 0 || open != close + 1 || end < 0) { append(text[i]); i++ } else {
                        val label = text.substring(i + 1, close)
                        val url = text.substring(open + 1, end)
                        withLink(LinkAnnotation.Url(url)) {
                            withStyle(SpanStyle(color = linkColor, textDecoration = TextDecoration.Underline)) {
                                append(label)
                            }
                        }
                        i = end + 1
                    }
                }
                else -> { append(text[i]); i++ }
            }
        }
    }
