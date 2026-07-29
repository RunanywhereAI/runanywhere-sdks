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
const CHANNEL_TAG_SOURCE = '<\\|?channel\\|?>';
const MESSAGE_TAG_SOURCE = '<\\|?message\\|?>';
const CONTROL_TAG_RE = /<\|?(?:channel|message|start|end|assistant|model|user|analysis|final|thought|start_of_turn|end_of_turn)\|?>/gi;
const GEMMA_TAG_RE = /<\/?(?:bos|eos|start_of_turn|end_of_turn|start_of_image|end_of_image)>/gi;

/**
 * Remove tokenizer/chat-template protocol markers that some local models emit as
 * ordinary text. Handles canonical Harmony tags (`<|channel|>`) and the
 * asymmetric forms (`<|channel>` / `<channel|>`) produced by some GGUF
 * detokenizers. Thinking tags are intentionally preserved for splitThinking().
 */
export function stripModelProtocol(text: string): string {
  if (!text) return '';
  let value = String(text);

  // Harmony-style output can contain a private analysis channel followed by a
  // final channel. When both exist, expose only the user-facing final message.
  const finalMarker = new RegExp(
    `${CHANNEL_TAG_SOURCE}\\s*final\\s*${MESSAGE_TAG_SOURCE}`,
    'i'
  ).exec(value);
  if (finalMarker) value = value.slice(finalMarker.index + finalMarker[0].length);

  // Gemma 4 GGUF currently emits this label pair before otherwise clean answers:
  // "<|channel>thought\n<channel|>Answer". Remove the whole prefix atomically so
  // "thought" never flashes in a streaming UI.
  value = value.replace(
    new RegExp(
      `^\\s*(?:${CHANNEL_TAG_SOURCE}\\s*)?(?:thought|analysis|reasoning)` +
      `\\s*(?:\\r?\\n\\s*)?${CHANNEL_TAG_SOURCE}\\s*`,
      'i'
    ),
    ''
  );

  value = value.replace(CONTROL_TAG_RE, '').replace(GEMMA_TAG_RE, '');
  // Tolerate a label split across streaming chunks after its tags were removed.
  value = value.replace(/^\s*(?:thought|analysis|final|assistant|model|user)\s*(?:\r?\n)+/i, '');
  if (/^\s*(?:thought|analysis|reasoning|final|assistant|model|user)\s*$/i.test(value)) return '';
  value = value.replace(/<\|?(?:channel|message|start|end)\|?$/i, '');
  return value.trim();
}

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
  const clean = stripModelProtocol(text);
  const open = firstOpen(clean);
  if (!open) return { response: clean, thinking: '' };
  const afterOpen = open.index + open.tag.length;
  const closeTag = CLOSE_OF[open.tag];
  const close = clean.indexOf(closeTag, afterOpen);
  if (close < 0) {
    // Unclosed tag: everything after the open is thinking.
    return { response: clean.slice(0, open.index).trim(), thinking: clean.slice(afterOpen).trim() };
  }
  const thinking = clean.slice(afterOpen, close).trim();
  // Join the text before and after the block with a newline when BOTH are
  // non-empty (parity with commons rac_llm_thinking); the common shape
  // "<think>…</think>Answer" has no `before`, so this is a no-op there.
  const before = clean.slice(0, open.index).trim();
  const after = clean.slice(close + closeTag.length).trim();
  const response = before && after ? `${before}\n${after}` : before + after;
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
