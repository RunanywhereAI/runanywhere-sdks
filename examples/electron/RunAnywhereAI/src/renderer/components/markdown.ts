/**
 * Markdown presentation for model output.
 *
 * Escape-first, then format — same security order as the legacy Electron `md()`
 * and the Web `renderMarkdown`. Safe to assign to `innerHTML`: every model span
 * passes through `escapeHtml`, and the only tags are literals in this file.
 *
 * Streaming: an unterminated fence grows as a code block; unclosed inline
 * markers render as literal characters until their closer arrives. Callers must
 * not re-parse on every token into the whole transcript — use `StreamingText`
 * and refresh only the tail.
 */
import { escapeHtml } from '../services/format';

type Block =
  | { kind: 'paragraph'; text: string }
  | { kind: 'heading'; level: number; text: string }
  | { kind: 'list'; items: ListItem[] }
  | { kind: 'quote'; text: string }
  | { kind: 'code'; code: string; language: string | null }
  | { kind: 'rule' };

interface ListItem {
  depth: number;
  text: string;
  ordered: boolean;
  number: number | null;
}

const HEADING = /^(#{1,6})\s+(.*)$/;
const NUMBERED = /^(\d{1,9})[.)]\s+(.*)$/;
const BULLET = /^[-*+]\s+(.*)$/;
const RULE = /^(?:-{3,}|\*{3,}|_{3,})$/;
const FENCE = /^(?:```|~~~)(.*)$/;

function listDepth(line: string): number {
  let columns = 0;
  for (const character of line) {
    if (character === ' ') columns += 1;
    else if (character === '\t') columns += 2;
    else break;
  }
  return Math.min(Math.floor(columns / 2), 3);
}

function parseBlocks(markdown: string): Block[] {
  const lines = markdown.replace(/\r\n?/g, '\n').split('\n');
  const blocks: Block[] = [];
  let i = 0;

  while (i < lines.length) {
    const line = lines[i];

    if (line.trim() === '') {
      i += 1;
      continue;
    }

    const fence = line.match(FENCE);
    if (fence !== null) {
      const language = fence[1].trim() === '' ? null : fence[1].trim().split(/\s+/)[0] ?? null;
      const body: string[] = [];
      i += 1;
      while (i < lines.length && !FENCE.test(lines[i])) {
        body.push(lines[i]);
        i += 1;
      }
      if (i < lines.length) i += 1;
      blocks.push({ kind: 'code', code: body.join('\n'), language });
      continue;
    }

    if (RULE.test(line.trim())) {
      blocks.push({ kind: 'rule' });
      i += 1;
      continue;
    }

    const heading = line.match(HEADING);
    if (heading !== null) {
      blocks.push({ kind: 'heading', level: heading[1].length, text: heading[2] });
      i += 1;
      continue;
    }

    if (line.startsWith('>')) {
      const quoted: string[] = [];
      while (i < lines.length && lines[i].startsWith('>')) {
        quoted.push(lines[i].replace(/^>\s?/, ''));
        i += 1;
      }
      blocks.push({ kind: 'quote', text: quoted.join('\n') });
      continue;
    }

    const trimmed = line.trimStart();
    if (BULLET.test(trimmed) || NUMBERED.test(trimmed)) {
      const items: ListItem[] = [];
      while (i < lines.length) {
        const raw = lines[i];
        if (raw.trim() === '') break;
        const depth = listDepth(raw);
        const content = raw.trimStart();
        const bullet = content.match(BULLET);
        const numbered = content.match(NUMBERED);
        if (bullet === null && numbered === null) break;
        if (bullet !== null) {
          items.push({ depth, text: bullet[1], ordered: false, number: null });
        } else if (numbered !== null) {
          items.push({ depth, text: numbered[2], ordered: true, number: Number(numbered[1]) });
        }
        i += 1;
      }
      blocks.push({ kind: 'list', items });
      continue;
    }

    const paragraph: string[] = [];
    while (i < lines.length) {
      const raw = lines[i];
      if (raw.trim() === '') break;
      if (FENCE.test(raw) || HEADING.test(raw) || RULE.test(raw.trim()) || raw.startsWith('>')) break;
      const content = raw.trimStart();
      if (BULLET.test(content) || NUMBERED.test(content)) break;
      paragraph.push(raw);
      i += 1;
    }
    blocks.push({ kind: 'paragraph', text: paragraph.join('\n') });
  }

  return blocks;
}

function renderInline(text: string): string {
  let out = '';
  let plain = '';
  const flush = (): void => {
    if (plain !== '') {
      out += escapeHtml(plain);
      plain = '';
    }
  };

  let i = 0;
  while (i < text.length) {
    if (text[i] === '`') {
      const end = text.indexOf('`', i + 1);
      if (end > i) {
        flush();
        out += `<code class="ra-md-inline-code">${escapeHtml(text.slice(i + 1, end))}</code>`;
        i = end + 1;
        continue;
      }
    }

    if (text.startsWith('**', i)) {
      const end = text.indexOf('**', i + 2);
      if (end > i) {
        flush();
        out += `<strong>${renderInline(text.slice(i + 2, end))}</strong>`;
        i = end + 2;
        continue;
      }
    }

    if (text[i] === '*' && text[i + 1] !== '*') {
      const end = text.indexOf('*', i + 1);
      if (end > i && text[end + 1] !== '*') {
        flush();
        out += `<em>${renderInline(text.slice(i + 1, end))}</em>`;
        i = end + 1;
        continue;
      }
    }

    if (text[i] === '[') {
      const closeLabel = text.indexOf(']', i + 1);
      if (closeLabel > i && text[closeLabel + 1] === '(') {
        const closeUrl = text.indexOf(')', closeLabel + 2);
        if (closeUrl > closeLabel) {
          const label = text.slice(i + 1, closeLabel);
          const href = text.slice(closeLabel + 2, closeUrl);
          flush();
          if (/^https?:\/\//i.test(href)) {
            out += `<a href="${escapeHtml(href)}" rel="noopener noreferrer" target="_blank">${escapeHtml(label)}</a>`;
          } else {
            out += escapeHtml(text.slice(i, closeUrl + 1));
          }
          i = closeUrl + 1;
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

function renderCode(code: string, language: string | null): string {
  const label = language !== null ? `<span class="ra-code-lang">${escapeHtml(language)}</span>` : '';
  return (
    `<div class="ra-code ra-md-code">` +
    `<div class="ra-code-head">${label}` +
    `<button type="button" class="ra-code-copy" data-ra-code="${escapeHtml(code)}" aria-label="Copy code">Copy</button>` +
    `</div>` +
    `<pre class="ra-code-body"><code>${escapeHtml(code)}</code></pre>` +
    `</div>`
  );
}

function renderListLevel(
  items: ListItem[],
  from: number,
  depth: number,
): { html: string; next: number } {
  const first = items[from];
  const tag = first.ordered ? 'ol' : 'ul';
  const start = first.ordered && first.number !== null ? ` start="${first.number}"` : '';
  let html = `<${tag} class="ra-md-list"${start}>`;
  let i = from;

  while (i < items.length && items[i].depth >= depth) {
    if (items[i].depth > depth) {
      const nested = renderListLevel(items, i, items[i].depth);
      html += nested.html;
      i = nested.next;
      continue;
    }
    if (items[i].ordered !== first.ordered) break;

    html += `<li>${renderInline(items[i].text)}`;
    i += 1;
    if (i < items.length && items[i].depth > depth) {
      const nested = renderListLevel(items, i, items[i].depth);
      html += nested.html;
      i = nested.next;
    }
    html += '</li>';
  }

  return { html: `${html}</${tag}>`, next: i };
}

function renderListRun(items: ListItem[]): string {
  let html = '';
  let i = 0;
  while (i < items.length) {
    const level = renderListLevel(items, i, items[i].depth);
    html += level.html;
    i = level.next;
  }
  return html;
}

function renderBlock(block: Block): string {
  switch (block.kind) {
    case 'heading':
      return (
        `<h${Math.min(6, block.level + 2)} class="ra-md-heading ra-md-heading--${block.level}">` +
        `${renderInline(block.text)}</h${Math.min(6, block.level + 2)}>`
      );
    case 'list':
      return renderListRun(block.items);
    case 'quote':
      return `<blockquote class="ra-md-quote">${renderInline(block.text)}</blockquote>`;
    case 'code':
      return renderCode(block.code, block.language);
    case 'rule':
      return '<hr class="ra-md-rule" />';
    case 'paragraph':
      return `<p class="ra-md-p">${renderInline(block.text).replace(/\n/g, '<br />')}</p>`;
    default: {
      const _exhaustive: never = block;
      return _exhaustive;
    }
  }
}

/** Render model output to HTML. Safe for `innerHTML`. */
export function renderMarkdown(markdown: string): string {
  return parseBlocks(markdown).map(renderBlock).join('');
}

/**
 * Wire copy buttons inside a markdown root.
 * Uses `navigator.clipboard` when available; falls back to a silent no-op.
 */
export function wireMarkdown(root: ParentNode): void {
  root.querySelectorAll<HTMLButtonElement>('button.ra-code-copy[data-ra-code]').forEach((button) => {
    if (button.dataset.wired === '1') return;
    button.dataset.wired = '1';
    button.addEventListener('click', () => {
      const code = button.dataset.raCode ?? '';
      if (typeof navigator.clipboard === 'undefined') return;
      void navigator.clipboard.writeText(code).then(() => {
        const previous = button.textContent;
        button.textContent = 'Copied';
        window.setTimeout(() => {
          button.textContent = previous;
        }, 1200);
      });
    });
  });
}

/** Standalone fenced code block for non-markdown surfaces. */
export function codeBlock(code: string, language: string | null = null): HTMLElement {
  const wrap = document.createElement('div');
  wrap.innerHTML = renderCode(code, language);
  wireMarkdown(wrap);
  const element = wrap.firstElementChild;
  if (!(element instanceof HTMLElement)) {
    throw new Error('codeBlock failed to render');
  }
  return element;
}
