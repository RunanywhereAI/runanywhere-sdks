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

const CLOSED = /<(think|thinking)>([\s\S]*?)<\/\1>/i;
const OPEN = /<(think|thinking)>/i;

/**
 * Split `text` into `{ response, thinking }`. Extracts the first thinking block;
 * an unclosed `<think>` means the rest of the text is thinking. Never throws.
 */
export function splitThinking(text: string): ThinkingSplit {
  if (!text) return { response: '', thinking: '' };
  const closed = CLOSED.exec(text);
  if (closed) {
    const thinking = closed[2].trim();
    const response = (text.slice(0, closed.index) + text.slice(closed.index + closed[0].length)).trim();
    return { response, thinking };
  }
  const open = OPEN.exec(text);
  if (open) {
    return { response: text.slice(0, open.index).trim(), thinking: text.slice(open.index + open[0].length).trim() };
  }
  return { response: text.trim(), thinking: '' };
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
