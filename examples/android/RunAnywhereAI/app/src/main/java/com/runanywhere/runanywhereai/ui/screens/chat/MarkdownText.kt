package com.runanywhere.runanywhereai.ui.screens.chat

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
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
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import kotlinx.coroutines.delay
import java.util.Locale

/**
 * Renders model output as markdown, because markdown is what the models emit.
 *
 * CROSS-APP CONTRACT. The [MdBlock] set here is the shared block vocabulary for all four example
 * apps — headings 1-6, horizontal rules, blockquotes, bullet and numbered lists, fenced code with a
 * language label and a copy button, and inline bold / italic / strikethrough / code / links. Web's
 * `services/markdown.ts` mirrors it block for block and rule for rule, so the same reply reads the
 * same on a phone and in a browser. A block or an inline marker that exists on one surface and not
 * another is a visible difference in the same answer, which is why the two files are kept in step
 * rather than each evolving on its own.
 *
 * STREAMING. This runs on every token, against a reply whose last line is usually half-written. So
 * the parser degrades rather than fails: an unterminated fence renders as a code block that grows,
 * and an unterminated `**`, `~~`, `_` or `` ` `` renders as the literal characters the model has
 * emitted so far, becoming styled only once the closing delimiter arrives. Nothing re-flows when
 * that happens, so a half-arrived marker never flickers styled-then-plain.
 *
 * Every consumer of a model's prose goes through here — chat, the RAG answer, and the VLM
 * description — so none of them can quietly fall back to raw `###` and `1.` characters.
 */
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
                is MdBlock.Bullet -> ListRow(
                    bulletGlyph(block.depth), block.depth, block.text,
                    style, color, codeBackground, linkColor,
                )
                is MdBlock.Numbered -> ListRow(
                    "${block.number}.", block.depth, block.text,
                    style, color, codeBackground, linkColor,
                )
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

/**
 * One list row, indented by its nesting level.
 *
 * The indent is a start padding on the row rather than a gutter per level, so the markers of
 * one level still line up with each other and a sublist reads as belonging to the row above it.
 * One `spacingLg` step per level is the same visual relationship iOS gets from its shared
 * gutter, without laying the whole list out as a grid.
 */
@Composable
private fun ListRow(
    marker: String,
    depth: Int,
    text: String,
    style: TextStyle,
    color: Color,
    codeBackground: Color,
    linkColor: Color,
) {
    val dimens = LocalDimens.current
    Row(
        modifier = Modifier.padding(
            start = dimens.spacingLg * depth,
            top = dimens.spacingXs / 2,
            bottom = dimens.spacingXs / 2,
        ),
    ) {
        Text(text = "$marker ", style = style, color = color.copy(alpha = 0.7f))
        Text(text = inline(text, codeBackground, linkColor), style = style, color = color)
    }
}

/**
 * A fenced block, with its language named and its text copyable.
 *
 * Both are parity items: iOS and the web app render fences with a language header and a copy button,
 * and code is the one part of a reply a user most often wants verbatim — hand-selecting it out of a
 * horizontally scrolling box is the worst way to get it. The header is always present, even for a
 * fence with no info string, because a copy affordance that appears only sometimes is harder to find
 * than one that is always in the same place.
 */
@Composable
private fun CodeBlock(code: String, language: String?) {
    val dimens = LocalDimens.current
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current
    var didCopy by remember(code) { mutableStateOf(false) }

    // Reverts on its own so the tick is a confirmation rather than a new permanent state. Keyed on
    // didCopy, so re-copying restarts the window instead of inheriting the old one's remainder.
    LaunchedEffect(didCopy) {
        if (didCopy) {
            delay(COPY_CONFIRM_MS)
            didCopy = false
        }
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = dimens.spacingXs)
            .clip(RoundedCornerShape(dimens.radiusSm))
            .background(MaterialTheme.colorScheme.surfaceContainerHighest),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = dimens.spacingMd, end = dimens.spacingXs),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = language?.takeIf { it.isNotBlank() }?.lowercase(Locale.US) ?: "code",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.weight(1f),
            )
            val copyLabel = if (didCopy) "Copied" else "Copy code"
            Row(
                modifier = Modifier
                    .clip(RoundedCornerShape(dimens.radiusSm))
                    .clickable(role = Role.Button, onClickLabel = copyLabel) {
                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        val clipboard =
                            context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                        clipboard.setPrimaryClip(ClipData.newPlainText("Code", code))
                        didCopy = true
                    }
                    .padding(horizontal = dimens.spacingSm, vertical = dimens.spacingXs),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(dimens.spacingXs),
            ) {
                Icon(
                    imageVector = if (didCopy) RACIcons.Outline.Check else RACIcons.Outline.Copy,
                    contentDescription = copyLabel,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(dimens.iconSm),
                )
                Text(
                    text = if (didCopy) "Copied" else "Copy",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
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

/** How long the copy tick stands in for the copy icon. Matches the chat message action button. */
private const val COPY_CONFIRM_MS = 2_000L

@Composable
private fun headerStyle(level: Int): TextStyle = when (level) {
    1 -> MaterialTheme.typography.titleLarge
    2 -> MaterialTheme.typography.titleMedium
    else -> MaterialTheme.typography.titleSmall
}

private sealed interface MdBlock {
    data class Paragraph(val text: String) : MdBlock
    data class Header(val level: Int, val text: String) : MdBlock
    /**
     * A list row, with the nesting level the model wrote it at.
     *
     * [depth] used to not exist: the line was trimmed before the marker was matched, so a
     * two-level outline — the shape a model reaches for whenever it answers with a plan or a
     * spec — arrived as one flat run of siblings and the structure it encoded was silently
     * discarded. iOS has carried a depth all along (`MarkdownListItem.depth`), so the same
     * reply read correctly on one of three surfaces; this is the same field with the same rule.
     */
    data class Bullet(val depth: Int, val text: String) : MdBlock
    data class Numbered(val depth: Int, val number: Int, val text: String) : MdBlock
    data class Quote(val text: String) : MdBlock
    data class Code(val code: String, val language: String?) : MdBlock
    data object Rule : MdBlock
}

/** Four tiers, matching iOS's four bullet glyphs. */
private const val MAX_LIST_DEPTH = 3

/**
 * Leading whitespace → nesting level, clamped to four tiers.
 *
 * Two columns per level with a tab counting as two — iOS `MarkdownBlockParser.depth(of:)`
 * verbatim, and the same rule the web `listDepth` uses. Both the 2-space and the 4-space
 * convention a model might emit land on a sane level, and the clamp stops a deeply indented
 * line from indenting off the right edge of a bubble.
 */
private fun listDepth(line: String): Int {
    var columns = 0
    for (c in line) {
        when (c) {
            ' ' -> columns++
            '\t' -> columns += 2
            else -> return minOf(columns / 2, MAX_LIST_DEPTH)
        }
    }
    return minOf(columns / 2, MAX_LIST_DEPTH)
}

/**
 * Bullet glyph by depth: filled → hollow → triangle → dot.
 *
 * Each level reads as subordinate to the one above at body size, and the sequence is iOS
 * `MarkdownBlockParser.bullet(at:)` exactly, so the same reply shows the same tiers on both.
 */
private fun bulletGlyph(depth: Int): String = when (depth) {
    0 -> "\u2022"
    1 -> "\u25E6"
    2 -> "\u2023"
    else -> "\u00B7"
}

private val numberedRegex = Regex("""^(\d{1,9})[.)]\s+(.*)""")
private val headerRegex = Regex("""^(#{1,6})\s+(.*)""")
private val bulletRegex = Regex("""^[-*+]\s+(.*)""")
private val ruleRegex = Regex("""^(?:-{3,}|\*{3,}|_{3,})$""")
private val fenceRegex = Regex("""^(?:```|~~~)(.*)""")

/**
 * Link schemes a model's output may produce as a live, tappable link.
 *
 * Model output is untrusted: it is text that may have been steered by a document the user ingested
 * or a page they pasted. Anything outside this allowlist renders as literal characters, so a
 * `javascript:` or `data:` target cannot become something the user can tap.
 */
private val SAFE_SCHEME = Regex("""^(?:https?://|mailto:|tel:)\S+""", RegexOption.IGNORE_CASE)

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

        val fence = fenceRegex.find(trimmed)
        if (fence != null) {
            flushParagraph()
            // An info string may carry more than the language ("ts title=x"); the language is the
            // first word, which is what the label shows.
            val language = fence.groupValues[1].trim().split(Regex("""\s+""")).firstOrNull()
                ?.ifEmpty { null }
            val code = StringBuilder()
            i++
            // No closing fence is the normal mid-stream case, not an error: the loop ends at the end
            // of what the model has produced and the block renders with what is there so far.
            while (i < lines.size && !fenceRegex.matches(lines[i].trim())) {
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
            ruleRegex.matches(trimmed) -> {
                flushParagraph()
                blocks += MdBlock.Rule
            }
            headerRegex.matches(trimmed) -> {
                flushParagraph()
                val (hashes, content) = headerRegex.find(trimmed)!!.destructured
                blocks += MdBlock.Header(hashes.length, content)
            }
            trimmed.startsWith(">") -> {
                flushParagraph()
                blocks += MdBlock.Quote(trimmed.removePrefix(">").trimStart())
            }
            bulletRegex.matches(trimmed) -> {
                flushParagraph()
                // Depth comes from the RAW line: `trimmed` is what the marker is matched
                // against, but the indentation in front of it is the only record of where
                // the row sits in the outline.
                blocks += MdBlock.Bullet(
                    listDepth(line),
                    bulletRegex.find(trimmed)!!.groupValues[1],
                )
            }
            numberedRegex.matches(trimmed) -> {
                flushParagraph()
                val (number, content) = numberedRegex.find(trimmed)!!.destructured
                blocks += MdBlock.Numbered(listDepth(line), number.toInt(), content)
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

/**
 * Is the character at [i] whitespace — treating "off either end of the string" as whitespace?
 *
 * Out-of-range counting as space is what makes the flanking rules below fall out correctly at a
 * boundary: a marker with nothing after it cannot open a run, and a marker with nothing before it
 * cannot close one. The first of those is the ordinary mid-stream state.
 */
private fun isSpaceAt(text: String, i: Int): Boolean =
    i < 0 || i >= text.length || text[i].isWhitespace()

/** Is the character at [i] a letter or digit — i.e. are we inside a word? */
private fun isWordAt(text: String, i: Int): Boolean =
    i >= 0 && i < text.length && text[i].isLetterOrDigit()

/** How many copies of the character at [i] start at [i] — the length of its delimiter run. */
private fun runLengthAt(text: String, i: Int): Int {
    val c = text[i]
    var n = 0
    while (i + n < text.length && text[i + n] == c) n++
    return n
}

/**
 * Is a single `*` at [i] arithmetic rather than emphasis — a lone asterisk wedged between two
 * alphanumerics, as in `2*3`?
 *
 * CommonMark says intra-word `*` is legal emphasis, so `2*3*4` italicises the `3` by the letter of
 * the spec. That reading is almost always wrong for what these apps render: a model writing `2*3` in
 * prose means multiplication, and the spec-correct reading also lets two unrelated asterisks pair up
 * across a whole sentence. `_` has always been excluded here for the same reason (`get_user_name`);
 * this extends the identical treatment to the single asterisk.
 */
private fun isIntraWordAsterisk(text: String, i: Int, runLength: Int): Boolean =
    text[i] == '*' && runLength == 1 &&
        isWordAt(text, i - 1) && isWordAt(text, i + runLength)

/**
 * Can the delimiter run of [runLength] chars at [i] open an emphasis run?
 *
 * The rule that matters in practice: a marker immediately followed by whitespace is not a
 * delimiter, it is punctuation the model typed. Without this, `a * b` reads the `*` as an opening
 * marker and italicises the rest of the line — the same bug that turned a footnote marker or a
 * shell glob into runaway emphasis.
 *
 * `_` may not open inside a word, so `get_user_name` survives intact, and a single `*` is held to
 * the same rule via [isIntraWordAsterisk].
 *
 * The last clause is the glob guard. An asterisk followed by a dot or a slash is a file pattern —
 * `*.txt` or a directory wildcard — never the start of emphasis, because emphasis opens on a word.
 * Without it, `rm *.txt and a * b and 2*3` italicised everything from `.txt` to the `2`: the glob's
 * asterisk opened a run and the multiplication's asterisk closed it, half a sentence away. Each of
 * those fragments is handled correctly on its own, which is exactly why this only showed up on
 * screen — the interaction needs them on one line, and a real model answer about shell commands puts
 * them there.
 */
private fun opensRun(text: String, i: Int, runLength: Int): Boolean {
    if (isSpaceAt(text, i + runLength)) return false
    if (text[i] == '_' && isWordAt(text, i - 1)) return false
    if (isIntraWordAsterisk(text, i, runLength)) return false
    if (text[i] == '*' && (text[i + runLength] == '.' || text[i + runLength] == '/')) return false
    return true
}

/**
 * Find the run that closes a run of [length] [marker] chars, or -1 when there is none.
 *
 * MATCHED ON RUN LENGTH, and that is the whole point. Markers are matched as *runs* — `**` closes
 * only against another `**`, never against a lone `*` — because during streaming a bold run arrives
 * one character at a time, and the prefix `**bold*` is a real intermediate state. Matching per
 * character let that prefix parse as an italic `*bold`, so `bold` rendered italic for one frame and
 * then re-rendered bold when the final `*` landed: a visible flicker in the middle of a sentence
 * the reader is already partway through. Requiring equal run lengths makes the half-arrived run
 * simply fail to match, so it stays literal until it is complete and each character takes its final
 * style exactly once.
 *
 * A run of the wrong length is skipped whole rather than one character at a time, so a partial run
 * can never be re-entered as a shorter marker.
 *
 * The scan also rejects a candidate preceded by whitespace: in `*a * b*` the middle marker closes
 * nothing and the run continues to the real one at the end. Taking the first `indexOf` hit instead
 * produced emphasis in the wrong place plus a stray marker left over.
 *
 * -1 is the ordinary mid-stream state, not an error.
 */
private fun findCloserRun(text: String, start: Int, marker: Char, length: Int): Int {
    var j = start
    while (j < text.length) {
        if (text[j] != marker) {
            j++
            continue
        }
        val runLength = runLengthAt(text, j)
        val closes = !isSpaceAt(text, j - 1) &&
            !(marker == '_' && isWordAt(text, j + runLength)) &&
            !isIntraWordAsterisk(text, j, runLength)
        if (runLength == length && closes) return j
        j += runLength
    }
    return -1
}

/**
 * The style a run of [length] [marker] characters carries, or null when the run means nothing.
 *
 * `*`/`_`: one is italic, two bold, three both. `~`: two is a strikethrough and a single `~` is just
 * a tilde — models write it in paths and ranges far more often than they mean emphasis by it.
 *
 * Null for a run longer than three, because `****` has no agreed meaning and inventing one would
 * silently eat characters the model actually wrote. It renders as the four asterisks it is.
 */
private fun emphasisStyle(marker: Char, length: Int): SpanStyle? = when {
    marker == '~' -> if (length == 2) SpanStyle(textDecoration = TextDecoration.LineThrough) else null
    length == 1 -> SpanStyle(fontStyle = FontStyle.Italic)
    length == 2 -> SpanStyle(fontWeight = FontWeight.Bold)
    length == 3 -> SpanStyle(fontWeight = FontWeight.Bold, fontStyle = FontStyle.Italic)
    else -> null
}

private fun inline(text: String, codeBackground: Color, linkColor: Color): AnnotatedString =
    buildAnnotatedString { appendInline(text, codeBackground, linkColor) }

/**
 * Append one block's text with its inline markers resolved.
 *
 * Scanned left to right, and recursive, so a span can carry more than one style (`**bold with
 * `code` in it**`) and so a code span wins over the emphasis markers inside it — which is what
 * every markdown implementation does, and what stops `` `**not bold**` `` from coming out bold.
 *
 * Every marker that fails to resolve falls through to "append this one character literally" and the
 * scan continues past it. That is the property the streaming case rests on: the parser degrades to
 * plain text rather than failing, and it never claims a delimiter it cannot close.
 */
private fun AnnotatedString.Builder.appendInline(
    text: String,
    codeBackground: Color,
    linkColor: Color,
) {
    var i = 0
    while (i < text.length) {
        // Code first: a code span's contents are literal, delimiters included.
        if (text[i] == '`') {
            val end = text.indexOf('`', i + 1)
            if (end > i) {
                withStyle(SpanStyle(fontFamily = RACTextStyles.Code.fontFamily, background = codeBackground)) {
                    append(text.substring(i + 1, end))
                }
                i = end + 1
                continue
            }
        }

        // One branch for every emphasis marker, taken a whole delimiter run at a time. The run's
        // length picks the style — one italic, two bold, three both — which gets longest-match for
        // free, so `***x***` can never be read as a bold `*x` that leaves stray asterisks on screen.
        if (text[i] == '*' || text[i] == '_' || text[i] == '~') {
            val marker = text[i]
            val run = runLengthAt(text, i)
            val style = emphasisStyle(marker, run)
            var end = -1
            if (style != null && opensRun(text, i, run)) {
                end = findCloserRun(text, i + run, marker, run)
            }
            if (style != null && end > i + run) {
                withStyle(style) {
                    appendInline(text.substring(i + run, end), codeBackground, linkColor)
                }
                i = end + run
            } else {
                // The whole run goes out literally and the scan resumes after it. Skipping the run
                // rather than one character is what keeps streaming stable: at the prefix `**bold*`
                // the two opening asterisks have no partner yet, and re-entering at the second one
                // would pair it with the trailing asterisk and italicise `bold` for a frame before
                // the closing `**` landed and made it bold. A run is one delimiter, not N chances.
                append(text.substring(i, i + run))
                i += run
            }
            continue
        }

        if (text[i] == '[') {
            val close = text.indexOf(']', i)
            val end = if (close >= 0 && text.getOrNull(close + 1) == '(') {
                text.indexOf(')', close + 2)
            } else {
                -1
            }
            if (end > close) {
                val label = text.substring(i + 1, close)
                val url = text.substring(close + 2, end).trim()
                if (SAFE_SCHEME.matches(url)) {
                    withLink(LinkAnnotation.Url(url)) {
                        withStyle(SpanStyle(color = linkColor, textDecoration = TextDecoration.Underline)) {
                            appendInline(label, codeBackground, linkColor)
                        }
                    }
                } else {
                    // A rejected target shows exactly what the model wrote, inert — never a live
                    // link the user cannot inspect.
                    append(text.substring(i, end + 1))
                }
                i = end + 1
                continue
            }
        }

        append(text[i])
        i++
    }
}
