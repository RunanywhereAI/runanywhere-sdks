// thinking.ts — split a reasoning model's "thinking" from its answer. Mirrors
// commons `rac_llm_thinking` semantics (which the C ABI marks SDK-internal): the
// default parser recognizes <think>…</think> and <thinking>…</thinking>, and
// treats an unclosed open tag as "everything after it is thinking".

export interface ThinkingSplit {
  /** The user-facing answer (thinking removed). */
  response: string;
  /** The extracted reasoning (empty if the text has none). */
  thinking: string;
}

const OPEN_TAGS = ['<think>', '<thinking>'] as const;
const CLOSE_OF: Record<string, string> = { '<think>': '</think>', '<thinking>': '</thinking>' };

/**
 * The next opening think tag at or after `from` (linear scan — no regex backtracking).
 *
 * Searches for the prefix BOTH tags share and then disambiguates, rather than
 * running one indexOf per tag. Looking for each tag separately costs a full scan
 * of the remaining text for whichever tag is absent, which is O(n) per call and
 * quadratic when a caller loops over many blocks. Here the search cursor only ever
 * moves forward, so a whole traversal is amortised O(n).
 */
const OPEN_PREFIX = '<think';
function nextOpen(text: string, from: number): { index: number; tag: string } | null {
  let i = from;
  for (;;) {
    const at = text.indexOf(OPEN_PREFIX, i);
    if (at < 0) return null;
    for (const t of OPEN_TAGS) if (text.startsWith(t, at)) return { index: at, tag: t };
    i = at + OPEN_PREFIX.length; // e.g. "<thinker" — always advances
  }
}

/**
 * Split `text` into `{ response, thinking }`. Extracts the first thinking block;
 * an unclosed `<think>` means the rest of the text is thinking. Never throws.
 *
 * Uses indexOf scanning (O(n)) rather than a regex with a backreference, which
 * would backtrack polynomially on adversarial model output (js/polynomial-redos).
 */
export function splitThinking(text: string): ThinkingSplit {
  if (!text) return { response: '', thinking: '' };
  const open = nextOpen(text, 0);
  if (!open) return { response: text.trim(), thinking: '' };
  const afterOpen = open.index + open.tag.length;
  const closeTag = CLOSE_OF[open.tag];
  const close = text.indexOf(closeTag, afterOpen);
  if (close < 0) {
    // Unclosed tag: everything after the open is thinking.
    return { response: text.slice(0, open.index).trim(), thinking: text.slice(afterOpen).trim() };
  }
  const thinking = text.slice(afterOpen, close).trim();
  // Join the text before and after the block with a newline when BOTH are
  // non-empty (parity with commons rac_llm_thinking); the common shape
  // "<think>…</think>Answer" has no `before`, so this is a no-op there.
  const before = text.slice(0, open.index).trim();
  const after = text.slice(close + closeTag.length).trim();
  const response = before && after ? `${before}\n${after}` : before + after;
  return { response, thinking };
}

/** The answer with any thinking blocks removed (equivalent to `rac_llm_strip_thinking`). */
export function stripThinking(text: string): string {
  return splitThinking(text).response;
}

/**
 * Remove EVERY thinking block from `text`, not just the first — used when a past
 * assistant turn is replayed as conversation context.
 *
 * Deliberately an indexOf scan rather than a regex: `/<(think|thinking)>[\s\S]*?<\/>/`
 * backtracks polynomially on input with many repeated `<think>` openers
 * (js/polynomial-redos), and model output is untrusted input.
 *
 * LINEAR, not merely regex-free. Two traps make the obvious loop quadratic on
 * `"<think>x</think>".repeat(n)` — measured at 2.9s for n=32000:
 *   - searching for each tag separately rescans the whole remainder for the tag
 *     that is absent, on every iteration (see nextOpen);
 *   - carrying a shrinking `rest` string recopies the remainder, on every iteration.
 * So this walks ONE cursor over the original string and slices only the pieces it
 * keeps. Every indexOf here resumes from a strictly increasing offset.
 */
export function stripAllThinking(text: string): string {
  if (!text) return '';
  const kept: string[] = [];
  let cursor = 0;
  for (;;) {
    const open = nextOpen(text, cursor);
    if (!open) break;
    const closeTag = CLOSE_OF[open.tag];
    const close = text.indexOf(closeTag, open.index + open.tag.length);
    kept.push(text.slice(cursor, open.index));
    if (close < 0) return kept.join('').trim();   // unterminated: drop the remainder
    cursor = close + closeTag.length;
  }
  kept.push(text.slice(cursor));
  return kept.join('').trim();
}

/** True while `text` is inside an as-yet-unclosed thinking block (for live streaming UIs). */
export function isThinking(text: string): boolean {
  const lastOpen = Math.max(text.lastIndexOf('<think>'), text.lastIndexOf('<thinking>'));
  if (lastOpen < 0) return false;
  const lastClose = Math.max(text.lastIndexOf('</think>'), text.lastIndexOf('</thinking>'));
  return lastClose < lastOpen;
}
