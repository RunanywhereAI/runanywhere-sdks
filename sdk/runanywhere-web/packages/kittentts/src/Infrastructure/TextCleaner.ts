/**
 * Text Cleaner for KittenTTS
 *
 * Maps IPA phoneme characters to integer token IDs expected by
 * the KittenTTS ONNX model. Direct port of the Python TextCleaner class.
 *
 * The symbol table matches the KittenTTS Python implementation exactly:
 *   pad + punctuation + ASCII letters + IPA characters
 *
 * Reference: https://github.com/KittenML/KittenTTS/blob/main/kittentts/onnx_model.py
 */

// ---------------------------------------------------------------------------
// Symbol Table (must match Python KittenTTS exactly)
// ---------------------------------------------------------------------------

const PAD = '$';
const PUNCTUATION = ';:,.!?¡¿—…"«»"" ';
const LETTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
const LETTERS_IPA =
  'ɑɐɒæɓʙβɔɕçɗɖðʤəɘɚɛɜɝɞɟʄɡɠɢʛɦɧħɥʜɨɪʝɭɬɫɮʟɱɯɰŋɳɲɴøɵɸθœɶʘɹɺɾɻʀʁɽʂʃʈʧʉʊʋⱱʌɣɤʍχʎʏʑʐʒʔʡʕʢǀǁǂǃˈˌːˑʼʴʰʱʲʷˠˤ˞↓↑→↗↘\'̩\'ᵻ';

const ALL_SYMBOLS = PAD + PUNCTUATION + LETTERS + LETTERS_IPA;

// Build the lookup table: character → index
const SYMBOL_TO_INDEX: Map<string, number> = new Map();
for (let i = 0; i < ALL_SYMBOLS.length; i++) {
  SYMBOL_TO_INDEX.set(ALL_SYMBOLS[i], i);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Convert a phoneme string to an array of integer token IDs.
 * Characters not in the symbol table are silently skipped.
 */
export function cleanText(text: string): number[] {
  const indexes: number[] = [];
  for (const char of text) {
    const idx = SYMBOL_TO_INDEX.get(char);
    if (idx !== undefined) {
      indexes.push(idx);
    }
  }
  return indexes;
}

/**
 * Tokenize phonemes into model input format:
 * [0, ...token_ids..., 0] (pad tokens at start and end).
 *
 * Matches the Python implementation:
 *   tokens.insert(0, 0)
 *   tokens.append(0)
 */
export function tokenizePhonemes(phonemeText: string): number[] {
  const tokens = cleanText(phonemeText);
  tokens.unshift(0); // start pad
  tokens.push(0);    // end pad
  return tokens;
}

/**
 * Basic English tokenizer that splits on whitespace and punctuation.
 * Matches the Python `basic_english_tokenize` function.
 */
export function basicEnglishTokenize(text: string): string[] {
  const matches = text.match(/\w+|[^\w\s]/g);
  return matches ?? [];
}

/**
 * Ensure text ends with punctuation. If not, add a comma.
 * Matches the Python `ensure_punctuation` function.
 */
export function ensurePunctuation(text: string): string {
  text = text.trim();
  if (!text) return text;
  if (!'.!?,;:'.includes(text[text.length - 1])) {
    text += ',';
  }
  return text;
}

/**
 * Split text into chunks for processing long texts.
 * Matches the Python `chunk_text` function.
 */
export function chunkText(text: string, maxLen = 400): string[] {
  const sentences = text.split(/[.!?]+/);
  const chunks: string[] = [];

  for (const sentence of sentences) {
    const trimmed = sentence.trim();
    if (!trimmed) continue;

    if (trimmed.length <= maxLen) {
      chunks.push(ensurePunctuation(trimmed));
    } else {
      const words = trimmed.split(/\s+/);
      let tempChunk = '';
      for (const word of words) {
        if (tempChunk.length + word.length + 1 <= maxLen) {
          tempChunk = tempChunk ? `${tempChunk} ${word}` : word;
        } else {
          if (tempChunk) chunks.push(ensurePunctuation(tempChunk));
          tempChunk = word;
        }
      }
      if (tempChunk) chunks.push(ensurePunctuation(tempChunk));
    }
  }

  return chunks;
}
