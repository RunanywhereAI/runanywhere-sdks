package com.runanywhere.runanywhereai.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp

/**
 * Lightweight Compose-native Markdown renderer for chat messages.
 *
 * Supports: **bold**, *italic*, ***bold italic***, `inline code`, [links](url),
 * fenced code blocks, headers (#-###), bullet/numbered lists, blockquotes, horizontal rules.
 *
 * Uses Column internally — safe to place inside a LazyColumn item.
 */
@Composable
fun MarkdownText(
    text: String,
    modifier: Modifier = Modifier,
    style: TextStyle = MaterialTheme.typography.bodyLarge,
) {
    val blocks = remember(text) { parseMarkdownBlocks(text) }
    val contentColor = MaterialTheme.colorScheme.onSurface
    val linkColor = MaterialTheme.colorScheme.primary

    Column(modifier = modifier) {
        blocks.forEachIndexed { index, block ->
            when (block) {
                is MarkdownBlock.CodeBlock -> {
                    CodeBlockView(code = block.code, language = block.language)
                }

                is MarkdownBlock.Header -> {
                    val headerStyle = when (block.level) {
                        1 -> MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold)
                        2 -> MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.SemiBold)
                        3 -> MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold)
                        else -> style.copy(fontWeight = FontWeight.SemiBold)
                    }
                    Text(
                        text = parseInlineMarkdown(block.text, contentColor, linkColor),
                        style = headerStyle,
                        color = contentColor,
                    )
                }

                is MarkdownBlock.BulletItem -> {
                    Row(modifier = Modifier.padding(start = 8.dp)) {
                        Text(text = "\u2022", style = style, color = contentColor)
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            text = parseInlineMarkdown(block.text, contentColor, linkColor),
                            style = style,
                            color = contentColor,
                            modifier = Modifier.weight(1f),
                        )
                    }
                }

                is MarkdownBlock.NumberedItem -> {
                    Row(modifier = Modifier.padding(start = 8.dp)) {
                        Text(text = "${block.number}.", style = style, color = contentColor)
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            text = parseInlineMarkdown(block.text, contentColor, linkColor),
                            style = style,
                            color = contentColor,
                            modifier = Modifier.weight(1f),
                        )
                    }
                }

                is MarkdownBlock.HorizontalRule -> {
                    HorizontalDivider(
                        modifier = Modifier.padding(vertical = 8.dp),
                        thickness = 1.dp,
                        color = MaterialTheme.colorScheme.outlineVariant,
                    )
                }

                is MarkdownBlock.Blockquote -> {
                    Row(modifier = Modifier.padding(vertical = 2.dp)) {
                        Box(
                            modifier = Modifier
                                .width(3.dp)
                                .height(20.dp)
                                .background(MaterialTheme.colorScheme.outline.copy(alpha = 0.4f)),
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            text = parseInlineMarkdown(block.text, contentColor, linkColor),
                            style = style.copy(fontStyle = FontStyle.Italic),
                            color = contentColor,
                            modifier = Modifier.weight(1f),
                        )
                    }
                }

                is MarkdownBlock.Paragraph -> {
                    Text(
                        text = parseInlineMarkdown(block.text, contentColor, linkColor),
                        style = style,
                        color = contentColor,
                    )
                }
            }

            if (index < blocks.lastIndex) {
                val spacing = when (block) {
                    is MarkdownBlock.Header, is MarkdownBlock.CodeBlock -> 8.dp
                    is MarkdownBlock.BulletItem, is MarkdownBlock.NumberedItem -> 4.dp
                    is MarkdownBlock.HorizontalRule -> 0.dp
                    else -> 6.dp
                }
                Spacer(modifier = Modifier.height(spacing))
            }
        }
    }
}

// -- Block-level model --

sealed interface MarkdownBlock {
    data class Paragraph(val text: String) : MarkdownBlock
    data class Header(val level: Int, val text: String) : MarkdownBlock
    data class CodeBlock(val code: String, val language: String?) : MarkdownBlock
    data class BulletItem(val text: String) : MarkdownBlock
    data class NumberedItem(val number: Int, val text: String) : MarkdownBlock
    data class Blockquote(val text: String) : MarkdownBlock
    data object HorizontalRule : MarkdownBlock
}

// -- Block-level parser --

private val NUMBERED_LIST_REGEX = Regex("^\\d+\\.\\s+(.*)")
private val HORIZONTAL_RULE_REGEX = Regex("^[-*_]{3,}$")

internal fun parseMarkdownBlocks(markdown: String): List<MarkdownBlock> {
    val blocks = mutableListOf<MarkdownBlock>()
    val lines = markdown.lines()
    var i = 0

    while (i < lines.size) {
        val trimmed = lines[i].trim()

        when {
            trimmed.startsWith("```") -> {
                val language = trimmed.removePrefix("```").trim().takeIf { it.isNotEmpty() }
                val codeLines = mutableListOf<String>()
                i++
                while (i < lines.size && !lines[i].trim().startsWith("```")) {
                    codeLines.add(lines[i])
                    i++
                }
                blocks += MarkdownBlock.CodeBlock(codeLines.joinToString("\n"), language)
                i++ // skip closing ```
            }

            HORIZONTAL_RULE_REGEX.matches(trimmed) -> {
                blocks += MarkdownBlock.HorizontalRule
                i++
            }

            trimmed.startsWith("### ") -> {
                blocks += MarkdownBlock.Header(3, trimmed.removePrefix("### "))
                i++
            }
            trimmed.startsWith("## ") -> {
                blocks += MarkdownBlock.Header(2, trimmed.removePrefix("## "))
                i++
            }
            trimmed.startsWith("# ") -> {
                blocks += MarkdownBlock.Header(1, trimmed.removePrefix("# "))
                i++
            }

            trimmed.startsWith("- ") || trimmed.startsWith("* ") -> {
                blocks += MarkdownBlock.BulletItem(trimmed.drop(2))
                i++
            }

            NUMBERED_LIST_REGEX.matches(trimmed) -> {
                val match = Regex("^(\\d+)\\.\\s+(.*)").find(trimmed)
                if (match != null) {
                    val (num, text) = match.destructured
                    blocks += MarkdownBlock.NumberedItem(num.toInt(), text)
                }
                i++
            }

            trimmed.startsWith("> ") -> {
                blocks += MarkdownBlock.Blockquote(trimmed.removePrefix("> "))
                i++
            }
            trimmed.startsWith(">") -> {
                blocks += MarkdownBlock.Blockquote(trimmed.removePrefix(">"))
                i++
            }

            trimmed.isEmpty() -> i++

            else -> {
                val paragraphLines = mutableListOf(lines[i])
                i++
                while (i < lines.size) {
                    val next = lines[i].trim()
                    if (next.isEmpty() || next.startsWith("```") || next.startsWith("#") ||
                        next.startsWith("- ") || next.startsWith("* ") || next.startsWith("> ") ||
                        NUMBERED_LIST_REGEX.matches(next) || HORIZONTAL_RULE_REGEX.matches(next)
                    ) break
                    paragraphLines += lines[i]
                    i++
                }
                blocks += MarkdownBlock.Paragraph(paragraphLines.joinToString(" "))
            }
        }
    }

    return blocks
}

// -- Inline parser --

internal fun parseInlineMarkdown(
    text: String,
    contentColor: androidx.compose.ui.graphics.Color,
    linkColor: androidx.compose.ui.graphics.Color,
): AnnotatedString = buildAnnotatedString {
    var i = 0
    val len = text.length

    while (i < len) {
        when {
            // Bold italic ***text***
            i + 2 < len && text.substring(i, i + 3) == "***" -> {
                val end = text.indexOf("***", i + 3)
                if (end != -1) {
                    withStyle(SpanStyle(fontWeight = FontWeight.Bold, fontStyle = FontStyle.Italic)) {
                        append(text.substring(i + 3, end))
                    }
                    i = end + 3
                } else {
                    append("***"); i += 3
                }
            }

            // Bold **text**
            i + 1 < len && text.substring(i, i + 2) == "**" -> {
                val end = text.indexOf("**", i + 2)
                if (end != -1) {
                    withStyle(SpanStyle(fontWeight = FontWeight.Bold)) {
                        append(text.substring(i + 2, end))
                    }
                    i = end + 2
                } else {
                    append("**"); i += 2
                }
            }

            // Italic *text*
            text[i] == '*' && (i + 1 >= len || text[i + 1] != '*') -> {
                val end = text.indexOf('*', i + 1)
                if (end != -1 && end > i + 1) {
                    withStyle(SpanStyle(fontStyle = FontStyle.Italic)) {
                        append(text.substring(i + 1, end))
                    }
                    i = end + 1
                } else {
                    append('*'); i++
                }
            }

            // Inline code `text`
            text[i] == '`' -> {
                val end = text.indexOf('`', i + 1)
                if (end != -1) {
                    withStyle(
                        SpanStyle(
                            fontFamily = FontFamily.Monospace,
                            background = contentColor.copy(alpha = 0.08f),
                        ),
                    ) {
                        append(" ${text.substring(i + 1, end)} ")
                    }
                    i = end + 1
                } else {
                    append('`'); i++
                }
            }

            // Link [text](url)
            text[i] == '[' -> {
                val closeBracket = text.indexOf(']', i + 1)
                if (closeBracket != -1 && closeBracket + 1 < len && text[closeBracket + 1] == '(') {
                    val closeParen = text.indexOf(')', closeBracket + 2)
                    if (closeParen != -1) {
                        val linkText = text.substring(i + 1, closeBracket)
                        val url = text.substring(closeBracket + 2, closeParen)
                        withLink(
                            LinkAnnotation.Url(
                                url,
                                TextLinkStyles(
                                    style = SpanStyle(
                                        color = linkColor,
                                        textDecoration = TextDecoration.Underline,
                                    ),
                                ),
                            ),
                        ) { append(linkText) }
                        i = closeParen + 1
                    } else {
                        append('['); i++
                    }
                } else {
                    append('['); i++
                }
            }

            else -> { append(text[i]); i++ }
        }
    }
}
