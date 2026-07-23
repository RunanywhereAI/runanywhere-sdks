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

/** First opening think tag in `text` (linear scan — no regex backtracking). */
function firstOpen(text: string): { index: number; tag: string } | null {
  let index = -1;
  let tag = '';
  for (const t of OPEN_TAGS) {
    const i = text.indexOf(t);
    if (i >= 0 && (index < 0 || i < index)) { index = i; tag = t; }
  }
  return index < 0 ? null : { index, tag };
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
  const open = firstOpen(text);
  if (!open) return { response: text.trim(), thinking: '' };
  const afterOpen = open.index + open.tag.length;
  const closeTag = CLOSE_OF[open.tag];
  const close = text.indexOf(closeTag, afterOpen);
  if (close < 0) {
    // Unclosed tag: everything after the open is thinking.
    return { response: text.slice(0, open.index).trim(), thinking: text.slice(afterOpen).trim() };
  }
  const thinking = text.slice(afterOpen, close).trim();
  const response = (text.slice(0, open.index) + text.slice(close + closeTag.length)).trim();
  return { response, thinking };
}

/** The answer with any thinking blocks removed (equivalent to `rac_llm_strip_thinking`). */
export function stripThinking(text: string): string {
  return splitThinking(text).response;
}

/** True while `text` is inside an as-yet-unclosed thinking block (for live streaming UIs). */
export function isThinking(text: string): boolean {
  const lastOpen = Math.max(text.lastIndexOf('<think>'), text.lastIndexOf('<thinking>'));
  if (lastOpen < 0) return false;
  const lastClose = Math.max(text.lastIndexOf('</think>'), text.lastIndexOf('</thinking>'));
  return lastClose < lastOpen;
}
