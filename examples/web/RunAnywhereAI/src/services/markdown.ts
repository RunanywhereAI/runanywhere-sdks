/**
 * Markdown rendering for model output.
 *
 * WHY THIS EXISTS. Every app in this repo renders LLM replies as markdown,
 * because that is what the models emit — headings, numbered steps, bullet
 * lists, fenced code. iOS routes through `AdaptiveMarkdownText` and Android
 * through `MarkdownText.kt`, both of which handle headings 1-6, horizontal
 * rules, blockquotes, bullet and numbered lists, fenced code with a language
 * label, and inline bold / italic / code / links.
 *
 * The web app had `renderMarkdownLite`: three inline rules (fence, inline code,
 * bold) and `\n` → `<br>`. So the same reply that showed a heading hierarchy and
 * an indented numbered list on a phone arrived in the browser as one
 * undifferentiated wall of text with visible `###` and `1.` characters in it.
 * This module closes that gap against the same block set, so a model's answer
 * reads the same on all four surfaces.
 *
 * SECURITY. Model output is untrusted input: it is text from a generative model
 * that may be steered by a document the user ingested or a page they pasted. The
 * order here is deliberate and load-bearing — **every** span of model text is
 * passed through `escapeHtml` before any tag is added, and the only tags in the
 * output are the fixed literals in this file. Nothing from the model is ever
 * interpolated into a tag name, an attribute name, or an unquoted attribute.
 * Link targets are additionally allowlisted by scheme, so `javascript:` and
 * `data:` URLs render as inert text rather than as a live link.
 *
 * STREAMING. This runs on every token, against a reply whose last line is
 * usually half-written. So the parser must degrade rather than fail: an
 * unterminated fence renders as a code block that grows, and an unterminated
 * `**` or `` ` `` renders as the literal characters the model has emitted so far
 * and becomes styled once the closing delimiter arrives. That is the same
 * behaviour as the Android inline parser, which also emits the remainder
 * verbatim when it cannot find a closing delimiter — so the two stay in step
 * mid-stream, not just at the end.
 */

import { escapeHtml } from './escape-html';

// ---------------------------------------------------------------------------
// Block model
// ---------------------------------------------------------------------------

/**
 * The block set is deliberately identical to `MdBlock` in Android's
 * `MarkdownText.kt`. Keeping the two enumerations the same is what makes
 * "consistent across apps" checkable rather than aspirational: a block that
 * exists on one platform and not another is a visible difference in the same
 * reply.
 */
type Block =
  | { kind: 'paragraph'; text: string }
  | { kind: 'heading'; level: number; text: string }
  | { kind: 'bullet'; items: string[] }
  | { kind: 'numbered'; start: number; items: string[] }
  | { kind: 'quote'; text: string }
  | { kind: 'code'; code: string; language: string | null }
  | { kind: 'rule' };

const HEADING = /^(#{1,6})\s+(.*)$/;
const NUMBERED = /^(\d{1,9})[.)]\s+(.*)$/;
const BULLET = /^[-*+]\s+(.*)$/;
const RULE = /^(?:-{3,}|\*{3,}|_{3,})$/;
const FENCE = /^(?:```|~~~)(.*)$/;

/**
 * Group lines into blocks.
 *
 * Consecutive list items become one block rather than one block each, so the
 * markup can be a real `<ul>`/`<ol>`. The lite renderer had no lists at all, and
 * emitting one single-item list per line would give a screen reader "list of one
 * item" over and over for what the user sees as a single list.
 */
function parseBlocks(markdown: string): Block[] {
  const blocks: Block[] = [];
  const lines = markdown.split('\n');
  let paragraph: string[] = [];

  const flushParagraph = (): void => {
    if (paragraph.length > 0) {
      blocks.push({ kind: 'paragraph', text: paragraph.join('\n') });
      paragraph = [];
    }
  };

  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    const trimmed = line.trim();

    const fence = FENCE.exec(trimmed);
    if (fence) {
      flushParagraph();
      // An info string may carry more than the language ("ts title=x"); the
      // language is the first word, which is what the label shows.
      const language = fence[1].trim().split(/\s+/)[0] || null;
      const code: string[] = [];
      i += 1;
      // No closing fence is the normal mid-stream case, not an error: the loop
      // ends at the end of what the model has produced and the block renders
      // with what is there so far.
      while (i < lines.length && !FENCE.test(lines[i].trim())) {
        code.push(lines[i]);
        i += 1;
      }
      blocks.push({ kind: 'code', code: code.join('\n'), language });
      continue;
    }

    if (trimmed === '') {
      flushParagraph();
      continue;
    }

    if (RULE.test(trimmed)) {
      flushParagraph();
      blocks.push({ kind: 'rule' });
      continue;
    }

    const heading = HEADING.exec(trimmed);
    if (heading) {
      flushParagraph();
      blocks.push({ kind: 'heading', level: heading[1].length, text: heading[2] });
      continue;
    }

    if (trimmed.startsWith('>')) {
      flushParagraph();
      // Fold a run of quoted lines into one quote, so a wrapped quotation is a
      // single bar rather than one bar per line.
      const quoted = [trimmed.replace(/^>\s?/, '')];
      while (i + 1 < lines.length && lines[i + 1].trim().startsWith('>')) {
        i += 1;
        quoted.push(lines[i].trim().replace(/^>\s?/, ''));
      }
      blocks.push({ kind: 'quote', text: quoted.join('\n') });
      continue;
    }

    const bullet = BULLET.exec(trimmed);
    if (bullet) {
      flushParagraph();
      const items = [bullet[1]];
      while (i + 1 < lines.length) {
        const next = BULLET.exec(lines[i + 1].trim());
        if (!next) break;
        i += 1;
        items.push(next[1]);
      }
      blocks.push({ kind: 'bullet', items });
      continue;
    }

    const numbered = NUMBERED.exec(trimmed);
    if (numbered) {
      flushParagraph();
      const items = [numbered[2]];
      while (i + 1 < lines.length) {
        const next = NUMBERED.exec(lines[i + 1].trim());
        if (!next) break;
        i += 1;
        items.push(next[2]);
      }
      // Honour the model's first number: a list that starts at 3 is usually a
      // continuation, and renumbering it from 1 silently rewrites the answer.
      blocks.push({ kind: 'numbered', start: Number(numbered[1]), items });
      continue;
    }

    paragraph.push(trimmed);
  }

  flushParagraph();
  return blocks;
}

// ---------------------------------------------------------------------------
// Inline
// ---------------------------------------------------------------------------

/**
 * Only these schemes become live links.
 *
 * A model can be induced to emit `[click here](javascript:...)`, and an `href`
 * the browser will execute is the one thing an escaped-text pipeline still lets
 * through — escaping protects the tag structure, not the semantics of a URL. A
 * rejected target renders as plain text so the user still sees what the model
 * said and simply cannot activate it.
 */
const SAFE_SCHEME = /^(?:https?:|mailto:)/i;

const isSpace = (ch: string | undefined): boolean => ch === undefined || /\s/.test(ch);
const isWord = (ch: string | undefined): boolean => ch !== undefined && /[\p{L}\p{N}]/u.test(ch);

/**
 * Can a delimiter at `i` open an emphasis run?
 *
 * The rule that matters in practice: a marker followed by whitespace is not a
 * delimiter, it is punctuation the model typed. Without this check `a * b` reads
 * the `*` as an opening marker and everything after it becomes emphasised — the
 * bug that made a footnote marker or a shell glob italicise the rest of a line.
 *
 * `_` additionally may not open inside a word, so `snake_case_name` survives
 * intact. Asterisks are exempt from that restriction because `2*3*4` is
 * arithmetic to a human but valid emphasis to every markdown parser, and models
 * write `*` intra-word deliberately far more often than they write `_`.
 */
function opensEmphasis(text: string, i: number, marker: string): boolean {
  if (isSpace(text[i + marker.length])) return false;
  if (marker[0] === '_' && isWord(text[i - 1])) return false;
  return true;
}

/**
 * Find the delimiter that closes a run opened at `start`.
 *
 * Scans rather than taking the first `indexOf` hit, because the first occurrence
 * is often not a valid closer: in `*a * b*` the middle marker is preceded by a
 * space, so it closes nothing and the run continues to the real one at the end.
 * Taking the first hit produced `<em>a </em>b*` — emphasis in the wrong place
 * plus a stray marker.
 *
 * Returns -1 when there is no closer, which is the ordinary mid-stream state:
 * the caller then emits the marker literally and it becomes styled on the token
 * that completes it.
 */
function findCloser(text: string, start: number, marker: string): number {
  for (let j = start; j <= text.length - marker.length; j += 1) {
    if (!text.startsWith(marker, j)) continue;
    if (isSpace(text[j - 1])) continue;
    if (marker[0] === '_' && isWord(text[j + marker.length])) continue;
    return j;
  }
  return -1;
}

/**
 * Render inline markers inside one block's text.
 *
 * Hand-written rather than a chain of `String.replace` calls because the lite
 * version's regexes could not tell a delimiter inside a code span from a real
 * one: `` `**not bold**` `` came out bold, and a lone `*` in prose (a footnote
 * marker, a glob) started an italic run that swallowed the rest of the line.
 * Scanning left to right lets code spans win over the emphasis markers they
 * contain, which is what every markdown implementation does — including the
 * Android one this mirrors.
 */
function renderInline(text: string): string {
  let out = '';
  let plain = '';

  // Buffered so a run of ordinary characters is escaped in one pass, and so the
  // escape can never be applied twice to the same span.
  const flush = (): void => {
    if (plain) {
      out += escapeHtml(plain);
      plain = '';
    }
  };

  let i = 0;
  while (i < text.length) {
    const rest = text.slice(i);

    // Code first: a code span's contents are literal, delimiters included.
    if (text[i] === '`') {
      const end = text.indexOf('`', i + 1);
      if (end > i) {
        flush();
        out += `<code>${escapeHtml(text.slice(i + 1, end))}</code>`;
        i = end + 1;
        continue;
      }
    }

    // Bold before italic, so `**x**` is not read as an italic `*` wrapping `*x*`.
    if (rest.startsWith('**') || rest.startsWith('__')) {
      const marker = rest.slice(0, 2);
      if (opensEmphasis(text, i, marker)) {
        const end = findCloser(text, i + 2, marker);
        if (end > i + 1) {
          flush();
          out += `<strong>${renderInline(text.slice(i + 2, end))}</strong>`;
          i = end + 2;
          continue;
        }
      }
    }

    if (text[i] === '*' || text[i] === '_') {
      const marker = text[i];
      if (opensEmphasis(text, i, marker)) {
        const end = findCloser(text, i + 1, marker);
        // Reject an empty span so `**` (a bold marker whose partner has not
        // streamed in yet) is not mistaken for italic-wrapping-nothing.
        if (end > i + 1) {
          flush();
          out += `<em>${renderInline(text.slice(i + 1, end))}</em>`;
          i = end + 1;
          continue;
        }
      }
    }

    if (rest.startsWith('~~') && opensEmphasis(text, i, '~~')) {
      const end = findCloser(text, i + 2, '~~');
      if (end > i + 1) {
        flush();
        out += `<del>${renderInline(text.slice(i + 2, end))}</del>`;
        i = end + 2;
        continue;
      }
    }

    if (text[i] === '[') {
      const close = text.indexOf(']', i);
      if (close > i && text[close + 1] === '(') {
        const end = text.indexOf(')', close + 2);
        if (end > close) {
          const label = text.slice(i + 1, close);
          const href = text.slice(close + 2, end).trim();
          flush();
          out += SAFE_SCHEME.test(href)
            // `noopener` because `target="_blank"` otherwise hands the opened
            // page a live reference back to this one.
            ? `<a href="${escapeHtml(href)}" target="_blank" rel="noopener noreferrer">`
              + `${renderInline(label)}</a>`
            // Rejected scheme: show exactly what the model wrote, inert.
            : escapeHtml(text.slice(i, end + 1));
          i = end + 1;
          continue;
        }
      }
    }

    plain += text[i];
    i += 1;
  }

  flush();
  return out;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Render model output to HTML.
 *
 * Safe to assign to `innerHTML`: the only tags present are the literals in this
 * file, and every span of model text has been through `escapeHtml`.
 */
export function renderMarkdown(markdown: string): string {
  return parseBlocks(markdown).map(renderBlock).join('');
}

function renderBlock(block: Block): string {
  switch (block.kind) {
    case 'heading':
      // Clamped to h3..h6. The bubble sits inside the page's own heading
      // outline, so a model emitting `#` must not inject an h1 that outranks
      // the view's title and scrambles the document structure for a screen
      // reader. Relative sizes are preserved, the absolute level is not.
      return `<h${Math.min(6, block.level + 2)} class="md-heading md-heading--${block.level}">`
        + `${renderInline(block.text)}</h${Math.min(6, block.level + 2)}>`;

    case 'bullet':
      return `<ul class="md-list">${block.items
        .map((item) => `<li>${renderInline(item)}</li>`)
        .join('')}</ul>`;

    case 'numbered':
      return `<ol class="md-list" start="${block.start}">${block.items
        .map((item) => `<li>${renderInline(item)}</li>`)
        .join('')}</ol>`;

    case 'quote':
      return `<blockquote class="md-quote">${renderInline(block.text)}</blockquote>`;

    case 'code':
      return renderCode(block.code, block.language);

    case 'rule':
      return '<hr class="md-rule" />';

    case 'paragraph':
      // Single newlines inside a paragraph are the model's own line breaks —
      // a wrapped sentence, an address, a short list it chose not to mark up.
      // Dropping them would join unrelated lines into one run-on sentence.
      return `<p class="md-p">${renderInline(block.text).replace(/\n/g, '<br />')}</p>`;
  }
}

/**
 * A fenced block, with its language named and its text copyable.
 *
 * The language label and the copy button are both parity items: iOS renders
 * fences with a language header and a copy button, so a browser user reading the
 * same reply should not have to hand-select code out of a scrolling box. The raw
 * text rides along in `data-md-code` — attribute-escaped, and read back with
 * `dataset`, which un-escapes it — because the click handler needs the code the
 * model actually wrote, not the highlighted DOM's `textContent`.
 */
function renderCode(code: string, language: string | null): string {
  const label = language ? `<span class="md-code__lang">${escapeHtml(language)}</span>` : '';
  return '<div class="md-code">'
    + `<div class="md-code__head">${label}`
    + `<button type="button" class="md-code__copy" data-md-code="${escapeHtml(code)}"`
    + ' aria-label="Copy code">Copy</button></div>'
    + `<pre class="md-code__body"><code>${escapeHtml(code)}</code></pre>`
    + '</div>';
}
