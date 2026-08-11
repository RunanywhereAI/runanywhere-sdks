// speech.ts — turn model output into something a TTS voice can actually read.
//
// LLMs answer in markdown ("**Paris** is the capital") and lean on symbols
// ("5 * 3 = 15", "~20%"). A TTS engine has no idea those are formatting: Piper
// happily pronounces "asterisk asterisk Paris asterisk asterisk". Strip the
// formatting, say the symbols that carry meaning out loud, and drop the rest.

/** Symbols that mean something when spoken, longest-first where it matters. */
const SPOKEN: Array<[RegExp, string]> = [
  [/≈/g, ' approximately '],
  [/≠/g, ' not equal to '],
  [/≤/g, ' less than or equal to '],
  [/≥/g, ' greater than or equal to '],
  [/±/g, ' plus or minus '],
  [/×/g, ' times '],
  [/÷/g, ' divided by '],
  [/√/g, ' square root of '],
  [/∞/g, ' infinity '],
  [/π/g, ' pi '],
  [/°\s*C\b/g, ' degrees Celsius'],
  [/°\s*F\b/g, ' degrees Fahrenheit'],
  [/°/g, ' degrees '],
  [/→|->/g, ' to '],
  [/&/g, ' and '],
];

/**
 * Rewrite `text` so a speech-synthesis voice reads it naturally.
 *
 * Removes markdown syntax (emphasis, headings, bullets, links, code, tables,
 * rules), speaks the symbols that carry meaning (%, °, ≈, arithmetic between
 * numbers), and drops emoji and leftover punctuation noise. Never throws.
 */
export function speakableText(text: string): string {
  if (!text) return '';
  let s = text;

  // --- structure that should not be read at all -----------------------------
  s = s.replace(/```[\s\S]*?```/g, ' ');          // fenced code: unspeakable
  s = s.replace(/~~~[\s\S]*?~~~/g, ' ');
  s = s.replace(/<[^>]+>/g, ' ');                  // stray html/xml tags
  s = s.replace(/^\s*([-*_]\s*){3,}$/gm, ' ');     // horizontal rules

  // --- inline markdown: keep the words, drop the marks ----------------------
  s = s.replace(/!\[([^\]]*)\]\([^)]*\)/g, '$1');  // images -> alt text
  s = s.replace(/\[([^\]]+)\]\([^)]*\)/g, '$1');   // links  -> link text
  s = s.replace(/`([^`]+)`/g, '$1');               // inline code -> contents
  s = s.replace(/\*\*([^*]+)\*\*/g, '$1');         // **bold**
  s = s.replace(/__([^_]+)__/g, '$1');             // __bold__
  s = s.replace(/(^|[^\w*])\*([^*\n]+)\*/g, '$1$2');   // *italic*
  s = s.replace(/(^|[^\w_])_([^_\n]+)_/g, '$1$2');     // _italic_
  s = s.replace(/~~([^~]+)~~/g, '$1');             // ~~strike~~

  // --- block markdown -------------------------------------------------------
  s = s.replace(/^\s{0,3}#{1,6}\s+/gm, '');        // headings
  s = s.replace(/^\s{0,3}>\s?/gm, '');             // blockquotes
  s = s.replace(/^\s*[-*+•]\s+/gm, '');            // bullets
  s = s.replace(/^\s*\d+[.)]\s+/gm, '');           // numbered lists
  s = s.replace(/^\s*\|.*\|\s*$/gm, (row) =>       // table rows -> comma list
    row.split('|').map((c) => c.trim()).filter((c) => c && !/^-{2,}$/.test(c)).join(', '));

  // --- arithmetic: only between numbers, so prose keeps its hyphens ---------
  s = s.replace(/(\d)\s*\*\s*(\d)/g, '$1 times $2');
  s = s.replace(/(\d)\s*\/\s*(\d)/g, '$1 divided by $2');
  s = s.replace(/(\d)\s+-\s+(\d)/g, '$1 minus $2');
  s = s.replace(/(\d)\s*\+\s*(\d)/g, '$1 plus $2');
  s = s.replace(/(\d)\s*=\s*/g, '$1 equals ');
  s = s.replace(/(\d)\s*%/g, '$1 percent');
  s = s.replace(/\$\s?(\d[\d,.]*)/g, '$1 dollars');

  for (const [re, word] of SPOKEN) s = s.replace(re, word);

  // --- leftovers ------------------------------------------------------------
  // Emoji + pictographs: a voice either skips them or says something absurd.
  s = s.replace(/[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{2190}-\u{21FF}]/gu, ' ');
  s = s.replace(/[*_`#|~^]/g, ' ');                // any surviving markdown marks
  s = s.replace(/\s*\n\s*\n\s*/g, '. ');           // paragraph break -> a real pause
  s = s.replace(/\s*\n\s*/g, ' ');
  s = s.replace(/[ \t]{2,}/g, ' ');
  s = s.replace(/\s+([,.!?;:])/g, '$1');           // no space before punctuation
  s = s.replace(/([.!?])\s*\1+/g, '$1');           // "..", "!!" -> one mark
  return s.trim();
}
