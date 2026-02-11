package com.runanywhere.runanywhereai.presentation.chat.components

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.ClickableText
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Lightweight Compose-native Markdown renderer for chat messages.
 *
 * Supports:
 * - **Bold** and *italic* inline formatting
 * - `inline code`
 * - [links](url)
 * - Fenced code blocks (``` ```)
 * - Headers (#, ##, ###)
 * - Bullet lists (-, *)
 * - Numbered lists (1., 2.)
 * - Horizontal rules (---, ***)
 * - Blockquotes (>)
 */
@Composable
fun MarkdownText(
    markdown: String,
    modifier: Modifier = Modifier,
    style: TextStyle = MaterialTheme.typography.bodyLarge,
    color: Color = Color.Unspecified,
) {
    val blocks = remember(markdown) { parseMarkdownBlocks(markdown) }
    val context = LocalContext.current

    Column(modifier = modifier) {
        blocks.forEachIndexed { index, block ->
            when (block) {
                is MarkdownBlock.CodeBlock -> {
                    CodeBlockView(
                        code = block.code,
                        language = block.language,
                    )
                }

                is MarkdownBlock.Header -> {
                    val headerStyle = when (block.level) {
                        1 -> style.copy(fontSize = 22.sp, fontWeight = FontWeight.Bold)
                        2 -> style.copy(fontSize = 19.sp, fontWeight = FontWeight.SemiBold)
                        3 -> style.copy(fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                        else -> style.copy(fontWeight = FontWeight.SemiBold)
                    }
                    val annotated = parseInlineMarkdown(block.text, color)
                    ClickableText(
                        text = annotated,
                        style = headerStyle.merge(TextStyle(color = color)),
                        onClick = { offset ->
                            annotated.getStringAnnotations("URL", offset, offset)
                                .firstOrNull()?.let { annotation ->
                                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(annotation.item))
                                    context.startActivity(intent)
                                }
                        },
                    )
                }

                is MarkdownBlock.BulletItem -> {
                    Row(modifier = Modifier.padding(start = 8.dp)) {
                        Text(
                            text = "\u2022",
                            style = style,
                            color = color,
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        val annotated = parseInlineMarkdown(block.text, color)
                        ClickableText(
                            text = annotated,
                            style = style.merge(TextStyle(color = color)),
                            modifier = Modifier.weight(1f),
                            onClick = { offset ->
                                annotated.getStringAnnotations("URL", offset, offset)
                                    .firstOrNull()?.let { annotation ->
                                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(annotation.item))
                                        context.startActivity(intent)
                                    }
                            },
                        )
                    }
                }

                is MarkdownBlock.NumberedItem -> {
                    Row(modifier = Modifier.padding(start = 8.dp)) {
                        Text(
                            text = "${block.number}.",
                            style = style,
                            color = color,
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        val annotated = parseInlineMarkdown(block.text, color)
                        ClickableText(
                            text = annotated,
                            style = style.merge(TextStyle(color = color)),
                            modifier = Modifier.weight(1f),
                            onClick = { offset ->
                                annotated.getStringAnnotations("URL", offset, offset)
                                    .firstOrNull()?.let { annotation ->
                                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(annotation.item))
                                        context.startActivity(intent)
                                    }
                            },
                        )
                    }
                }

                is MarkdownBlock.HorizontalRule -> {
                    HorizontalDivider(
                        modifier = Modifier.padding(vertical = 8.dp),
                        thickness = 1.dp,
                        color = color.copy(alpha = 0.2f),
                    )
                }

                is MarkdownBlock.Blockquote -> {
                    Row(modifier = Modifier.padding(vertical = 2.dp)) {
                        Box(
                            modifier = Modifier
                                .width(3.dp)
                                .height(20.dp)
                                .background(color.copy(alpha = 0.3f)),
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        val annotated = parseInlineMarkdown(block.text, color)
                        ClickableText(
                            text = annotated,
                            style = style.copy(fontStyle = FontStyle.Italic).merge(TextStyle(color = color)),
                            modifier = Modifier.weight(1f),
                            onClick = { offset ->
                                annotated.getStringAnnotations("URL", offset, offset)
                                    .firstOrNull()?.let { annotation ->
                                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(annotation.item))
                                        context.startActivity(intent)
                                    }
                            },
                        )
                    }
                }

                is MarkdownBlock.Paragraph -> {
                    val annotated = parseInlineMarkdown(block.text, color)
                    ClickableText(
                        text = annotated,
                        style = style.merge(TextStyle(color = color)),
                        onClick = { offset ->
                            annotated.getStringAnnotations("URL", offset, offset)
                                .firstOrNull()?.let { annotation ->
                                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(annotation.item))
                                    context.startActivity(intent)
                                }
                        },
                    )
                }
            }

            // Add spacing between blocks (except last)
            if (index < blocks.lastIndex) {
                val spacing = when (block) {
                    is MarkdownBlock.Header -> 8.dp
                    is MarkdownBlock.CodeBlock -> 8.dp
                    is MarkdownBlock.HorizontalRule -> 0.dp
                    is MarkdownBlock.BulletItem -> 4.dp
                    is MarkdownBlock.NumberedItem -> 4.dp
                    else -> 6.dp
                }
                Spacer(modifier = Modifier.height(spacing))
            }
        }
    }
}

@Composable
private fun CodeBlockView(
    code: String,
    language: String?,
) {
    val codeBackground = MaterialTheme.colorScheme.surfaceVariant
    val codeBorder = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(codeBackground)
            .padding(1.dp),
    ) {
        // Language label
        if (!language.isNullOrBlank()) {
            Text(
                text = language,
                style = MaterialTheme.typography.labelSmall.copy(
                    fontWeight = FontWeight.Medium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                ),
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
            )
            HorizontalDivider(
                thickness = 0.5.dp,
                color = codeBorder,
            )
        }

        // Code content with horizontal scroll
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState())
                .padding(12.dp),
        ) {
            Text(
                text = code,
                style = MaterialTheme.typography.bodyMedium.copy(
                    fontFamily = FontFamily.Monospace,
                    fontSize = 13.sp,
                    lineHeight = 20.sp,
                ),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// ============================================================
// Markdown Parsing
// ============================================================

private sealed class MarkdownBlock {
    data class Paragraph(val text: String) : MarkdownBlock()
    data class Header(val level: Int, val text: String) : MarkdownBlock()
    data class CodeBlock(val code: String, val language: String?) : MarkdownBlock()
    data class BulletItem(val text: String) : MarkdownBlock()
    data class NumberedItem(val number: Int, val text: String) : MarkdownBlock()
    data class Blockquote(val text: String) : MarkdownBlock()
    data object HorizontalRule : MarkdownBlock()
}

private fun parseMarkdownBlocks(markdown: String): List<MarkdownBlock> {
    val blocks = mutableListOf<MarkdownBlock>()
    val lines = markdown.lines()
    var i = 0

    while (i < lines.size) {
        val line = lines[i]
        val trimmed = line.trim()

        when {
            // Fenced code block
            trimmed.startsWith("```") -> {
                val language = trimmed.removePrefix("```").trim().takeIf { it.isNotEmpty() }
                val codeLines = mutableListOf<String>()
                i++
                while (i < lines.size && !lines[i].trim().startsWith("```")) {
                    codeLines.add(lines[i])
                    i++
                }
                blocks.add(MarkdownBlock.CodeBlock(codeLines.joinToString("\n"), language))
                i++ // skip closing ```
            }

            // Horizontal rule
            trimmed.matches(Regex("^[-*_]{3,}$")) -> {
                blocks.add(MarkdownBlock.HorizontalRule)
                i++
            }

            // Headers
            trimmed.startsWith("### ") -> {
                blocks.add(MarkdownBlock.Header(3, trimmed.removePrefix("### ")))
                i++
            }
            trimmed.startsWith("## ") -> {
                blocks.add(MarkdownBlock.Header(2, trimmed.removePrefix("## ")))
                i++
            }
            trimmed.startsWith("# ") -> {
                blocks.add(MarkdownBlock.Header(1, trimmed.removePrefix("# ")))
                i++
            }

            // Bullet lists
            trimmed.startsWith("- ") || trimmed.startsWith("* ") -> {
                blocks.add(MarkdownBlock.BulletItem(trimmed.drop(2)))
                i++
            }

            // Numbered lists
            trimmed.matches(Regex("^\\d+\\.\\s+.*")) -> {
                val match = Regex("^(\\d+)\\.\\s+(.*)").find(trimmed)
                if (match != null) {
                    val (num, text) = match.destructured
                    blocks.add(MarkdownBlock.NumberedItem(num.toInt(), text))
                }
                i++
            }

            // Blockquote
            trimmed.startsWith("> ") -> {
                blocks.add(MarkdownBlock.Blockquote(trimmed.removePrefix("> ")))
                i++
            }
            trimmed.startsWith(">") -> {
                blocks.add(MarkdownBlock.Blockquote(trimmed.removePrefix(">")))
                i++
            }

            // Empty line - skip
            trimmed.isEmpty() -> {
                i++
            }

            // Regular paragraph - merge consecutive non-empty lines
            else -> {
                val paragraphLines = mutableListOf(line)
                i++
                while (i < lines.size) {
                    val nextLine = lines[i].trim()
                    if (nextLine.isEmpty() ||
                        nextLine.startsWith("```") ||
                        nextLine.startsWith("#") ||
                        nextLine.startsWith("- ") ||
                        nextLine.startsWith("* ") ||
                        nextLine.startsWith("> ") ||
                        nextLine.matches(Regex("^\\d+\\.\\s+.*")) ||
                        nextLine.matches(Regex("^[-*_]{3,}$"))
                    ) {
                        break
                    }
                    paragraphLines.add(lines[i])
                    i++
                }
                blocks.add(MarkdownBlock.Paragraph(paragraphLines.joinToString(" ")))
            }
        }
    }

    return blocks
}

/**
 * Parse inline markdown formatting into AnnotatedString.
 * Supports: **bold**, *italic*, `inline code`, [links](url), ***bold italic***
 */
private fun parseInlineMarkdown(text: String, defaultColor: Color): AnnotatedString {
    return buildAnnotatedString {
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
                        append("***")
                        i += 3
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
                        append("**")
                        i += 2
                    }
                }

                // Italic *text* (but not **)
                text[i] == '*' && (i + 1 >= len || text[i + 1] != '*') -> {
                    val end = text.indexOf('*', i + 1)
                    if (end != -1 && end > i + 1) {
                        withStyle(SpanStyle(fontStyle = FontStyle.Italic)) {
                            append(text.substring(i + 1, end))
                        }
                        i = end + 1
                    } else {
                        append('*')
                        i++
                    }
                }

                // Inline code `text`
                text[i] == '`' -> {
                    val end = text.indexOf('`', i + 1)
                    if (end != -1) {
                        withStyle(
                            SpanStyle(
                                fontFamily = FontFamily.Monospace,
                                fontSize = 13.sp,
                                background = defaultColor.copy(alpha = 0.08f),
                            ),
                        ) {
                            append(" ${text.substring(i + 1, end)} ")
                        }
                        i = end + 1
                    } else {
                        append('`')
                        i++
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
                            pushStringAnnotation("URL", url)
                            withStyle(
                                SpanStyle(
                                    color = Color(0xFF3B82F6),
                                    textDecoration = TextDecoration.Underline,
                                ),
                            ) {
                                append(linkText)
                            }
                            pop()
                            i = closeParen + 1
                        } else {
                            append('[')
                            i++
                        }
                    } else {
                        append('[')
                        i++
                    }
                }

                else -> {
                    append(text[i])
                    i++
                }
            }
        }
    }
}
