/**
 * ESpeakPhonemizer — converts English text to IPA phonemes.
 *
 * Two implementations:
 * 1. **SherpaONNX integration** (preferred): Calls espeak-ng functions exposed from
 *    the sherpa-onnx WASM module via `_ra_espeak_phonemize`. This requires rebuilding
 *    the sherpa-onnx WASM with the espeak phonemization wrapper. See:
 *    `wasm/src/ra_espeak_phonemize.c` and the build script modifications.
 *
 * 2. **Built-in rule-based G2P** (fallback): Basic English grapheme-to-phoneme rules
 *    that produce approximate IPA. Works immediately without WASM rebuilds.
 *    Quality is lower than espeak-ng but produces intelligible TTS output.
 *
 * The phonemizer implementation can be swapped at runtime via `setPhonemizer()`.
 */

import { SDKLogger } from '@runanywhere/web';

const logger = new SDKLogger('ESpeakPhonemizer');

// ---------------------------------------------------------------------------
// Public Interface
// ---------------------------------------------------------------------------

export interface Phonemizer {
  phonemize(text: string): Promise<string>;
}

let _activePhonemizer: Phonemizer | null = null;

/**
 * Override the default phonemizer implementation.
 * Call this to plug in a custom or external phonemizer.
 */
export function setPhonemizer(impl: Phonemizer): void {
  _activePhonemizer = impl;
  logger.info(`Phonemizer set: ${impl.constructor?.name ?? 'custom'}`);
}

/**
 * Phonemize text to IPA string.
 * Uses the active phonemizer or falls back to built-in rules.
 */
export async function phonemize(text: string): Promise<string> {
  if (_activePhonemizer) {
    return _activePhonemizer.phonemize(text);
  }
  return builtinPhonemize(text);
}

// ---------------------------------------------------------------------------
// Sherpa-ONNX espeak-ng Integration
// ---------------------------------------------------------------------------

/**
 * Create a phonemizer backed by the sherpa-onnx WASM module's espeak-ng.
 *
 * Prerequisites: The sherpa-onnx WASM must be rebuilt with the espeak
 * phonemization wrapper. See the build instructions.
 *
 * @param sherpaModule - The loaded SherpaONNX Emscripten module
 */
export function createSherpaEspeakPhonemizer(sherpaModule: SherpaWASMModule): Phonemizer | null {
  // Check if the espeak phonemization function is exported
  const hasFn = typeof sherpaModule._ra_espeak_phonemize === 'function';
  if (!hasFn) {
    logger.debug(
      'sherpa-onnx WASM does not export _ra_espeak_phonemize. ' +
      'Using built-in rule-based phonemizer. Rebuild sherpa-onnx WASM ' +
      'with espeak exports for better quality.',
    );
    return null;
  }

  return {
    async phonemize(text: string): Promise<string> {
      const m = sherpaModule;
      const textLen = m.lengthBytesUTF8(text) + 1;
      const textPtr = m._malloc(textLen);
      m.stringToUTF8(text, textPtr, textLen);

      const resultPtr = m._ra_espeak_phonemize!(textPtr, 0);
      m._free(textPtr);

      if (!resultPtr) return '';

      const result = m.UTF8ToString(resultPtr);
      m._free(resultPtr);
      return result;
    },
  };
}

interface SherpaWASMModule {
  _malloc: (size: number) => number;
  _free: (ptr: number) => void;
  lengthBytesUTF8: (str: string) => number;
  stringToUTF8: (str: string, ptr: number, maxLen: number) => void;
  UTF8ToString: (ptr: number) => string;
  _ra_espeak_phonemize?: (textPtr: number, langPtr: number) => number;
}

// ---------------------------------------------------------------------------
// Built-in Rule-Based English G2P (Fallback)
// ---------------------------------------------------------------------------

/**
 * Basic English grapheme-to-phoneme conversion using rule-based patterns.
 * Produces approximate IPA that KittenTTS can work with.
 *
 * This is a fallback — espeak-ng via sherpa-onnx produces significantly
 * better phonemization.
 */
function builtinPhonemize(text: string): string {
  const words = text.toLowerCase().split(/\s+/);
  const phonemeWords: string[] = [];

  for (const word of words) {
    // Pass through punctuation
    if (/^[.,!?;:\-—…]+$/.test(word)) {
      phonemeWords.push(word);
      continue;
    }

    // Strip trailing punctuation, phonemize word, re-attach punctuation
    const trailingPunct = word.match(/[.,!?;:\-—…]+$/)?.[0] ?? '';
    const cleanWord = trailingPunct ? word.slice(0, -trailingPunct.length) : word;

    if (cleanWord.length === 0) {
      if (trailingPunct) phonemeWords.push(trailingPunct);
      continue;
    }

    // Dictionary lookup first
    const dictResult = DICT.get(cleanWord);
    if (dictResult) {
      phonemeWords.push(dictResult + trailingPunct);
      continue;
    }

    // Rule-based conversion
    const phonemes = applyRules(cleanWord);
    phonemeWords.push(phonemes + trailingPunct);
  }

  return phonemeWords.join(' ');
}

// Common English words → IPA (small dict for high-frequency words)
const DICT = new Map<string, string>([
  ['the', 'ðə'],
  ['a', 'ə'],
  ['an', 'æn'],
  ['and', 'ænd'],
  ['or', 'ɔːɹ'],
  ['is', 'ɪz'],
  ['are', 'ɑːɹ'],
  ['was', 'wɑːz'],
  ['were', 'wɜːɹ'],
  ['be', 'biː'],
  ['been', 'bɪn'],
  ['being', 'biːɪŋ'],
  ['have', 'hæv'],
  ['has', 'hæz'],
  ['had', 'hæd'],
  ['do', 'duː'],
  ['does', 'dʌz'],
  ['did', 'dɪd'],
  ['will', 'wɪl'],
  ['would', 'wʊd'],
  ['could', 'kʊd'],
  ['should', 'ʃʊd'],
  ['can', 'kæn'],
  ['may', 'meɪ'],
  ['might', 'maɪt'],
  ['must', 'mʌst'],
  ['shall', 'ʃæl'],
  ['not', 'nɑːt'],
  ['no', 'noʊ'],
  ['yes', 'jɛs'],
  ['this', 'ðɪs'],
  ['that', 'ðæt'],
  ['these', 'ðiːz'],
  ['those', 'ðoʊz'],
  ['it', 'ɪt'],
  ['its', 'ɪts'],
  ['he', 'hiː'],
  ['she', 'ʃiː'],
  ['we', 'wiː'],
  ['they', 'ðeɪ'],
  ['you', 'juː'],
  ['me', 'miː'],
  ['him', 'hɪm'],
  ['her', 'hɜːɹ'],
  ['us', 'ʌs'],
  ['them', 'ðɛm'],
  ['my', 'maɪ'],
  ['your', 'jɔːɹ'],
  ['his', 'hɪz'],
  ['our', 'aʊɹ'],
  ['their', 'ðɛɹ'],
  ['i', 'aɪ'],
  ['in', 'ɪn'],
  ['on', 'ɑːn'],
  ['at', 'æt'],
  ['to', 'tuː'],
  ['for', 'fɔːɹ'],
  ['with', 'wɪð'],
  ['from', 'fɹʌm'],
  ['by', 'baɪ'],
  ['of', 'ʌv'],
  ['about', 'əbaʊt'],
  ['into', 'ɪntuː'],
  ['through', 'θɹuː'],
  ['after', 'æftɹ̩'],
  ['before', 'bɪfɔːɹ'],
  ['between', 'bɪtwiːn'],
  ['under', 'ʌndɹ̩'],
  ['over', 'oʊvɹ̩'],
  ['what', 'wɑːt'],
  ['where', 'wɛɹ'],
  ['when', 'wɛn'],
  ['why', 'waɪ'],
  ['how', 'haʊ'],
  ['who', 'huː'],
  ['which', 'wɪtʃ'],
  ['there', 'ðɛɹ'],
  ['here', 'hɪɹ'],
  ['just', 'dʒʌst'],
  ['also', 'ɔːlsoʊ'],
  ['very', 'vɛɹi'],
  ['well', 'wɛl'],
  ['good', 'ɡʊd'],
  ['new', 'nuː'],
  ['first', 'fɜːɹst'],
  ['last', 'læst'],
  ['long', 'lɔːŋ'],
  ['great', 'ɡɹeɪt'],
  ['little', 'lɪtl̩'],
  ['own', 'oʊn'],
  ['other', 'ʌðɹ̩'],
  ['old', 'oʊld'],
  ['right', 'ɹaɪt'],
  ['big', 'bɪɡ'],
  ['high', 'haɪ'],
  ['different', 'dɪfɹənt'],
  ['small', 'smɔːl'],
  ['large', 'lɑːɹdʒ'],
  ['hello', 'hɛloʊ'],
  ['world', 'wɜːɹld'],
  ['today', 'tʊdeɪ'],
  ['people', 'piːpl̩'],
  ['like', 'laɪk'],
  ['time', 'taɪm'],
  ['know', 'noʊ'],
  ['think', 'θɪŋk'],
  ['make', 'meɪk'],
  ['go', 'ɡoʊ'],
  ['come', 'kʌm'],
  ['see', 'siː'],
  ['say', 'seɪ'],
  ['get', 'ɡɛt'],
  ['give', 'ɡɪv'],
  ['take', 'teɪk'],
  ['because', 'bɪkɔːz'],
  ['one', 'wʌn'],
  ['two', 'tuː'],
  ['three', 'θɹiː'],
  ['four', 'fɔːɹ'],
  ['five', 'faɪv'],
  ['six', 'sɪks'],
  ['seven', 'sɛvn̩'],
  ['eight', 'eɪt'],
  ['nine', 'naɪn'],
  ['ten', 'tɛn'],
  ['hundred', 'hʌndɹəd'],
  ['thousand', 'θaʊzənd'],
  ['million', 'mɪljən'],
  ['billion', 'bɪljən'],
  ['zero', 'zɪɹoʊ'],
  ['point', 'pɔɪnt'],
]);

// Rule-based English grapheme→phoneme patterns
const RULES: Array<[RegExp, string]> = [
  // Digraphs & trigraphs (order matters — longest first)
  [/igh/g, 'aɪ'],
  [/tion/g, 'ʃən'],
  [/sion/g, 'ʒən'],
  [/ous/g, 'əs'],
  [/ture/g, 'tʃɹ̩'],
  [/tch/g, 'tʃ'],
  [/ch/g, 'tʃ'],
  [/sh/g, 'ʃ'],
  [/th/g, 'θ'],
  [/ph/g, 'f'],
  [/wh/g, 'w'],
  [/ck/g, 'k'],
  [/ng/g, 'ŋ'],
  [/qu/g, 'kw'],
  [/wr/g, 'ɹ'],
  [/kn/g, 'n'],
  [/gh/g, ''],
  [/oo/g, 'uː'],
  [/ee/g, 'iː'],
  [/ea/g, 'iː'],
  [/ou/g, 'aʊ'],
  [/ow/g, 'oʊ'],
  [/ai/g, 'eɪ'],
  [/ay/g, 'eɪ'],
  [/oi/g, 'ɔɪ'],
  [/oy/g, 'ɔɪ'],
  [/au/g, 'ɔː'],
  [/aw/g, 'ɔː'],
  [/ie/g, 'iː'],
  [/ei/g, 'eɪ'],
  [/ey/g, 'eɪ'],
  [/ue/g, 'uː'],
  [/oe/g, 'oʊ'],

  // Single consonants
  [/b/g, 'b'],
  [/c(?=[eiy])/g, 's'],
  [/c/g, 'k'],
  [/d/g, 'd'],
  [/f/g, 'f'],
  [/g(?=[eiy])/g, 'dʒ'],
  [/g/g, 'ɡ'],
  [/h/g, 'h'],
  [/j/g, 'dʒ'],
  [/k/g, 'k'],
  [/l/g, 'l'],
  [/m/g, 'm'],
  [/n/g, 'n'],
  [/p/g, 'p'],
  [/r/g, 'ɹ'],
  [/s/g, 's'],
  [/t/g, 't'],
  [/v/g, 'v'],
  [/w/g, 'w'],
  [/x/g, 'ks'],
  [/y(?=[aeiou])/g, 'j'],
  [/y/g, 'ɪ'],
  [/z/g, 'z'],

  // Vowels (simplistic rules)
  [/a/g, 'æ'],
  [/e$/g, ''],  // silent final e
  [/e/g, 'ɛ'],
  [/i/g, 'ɪ'],
  [/o/g, 'ɑː'],
  [/u/g, 'ʌ'],
];

function applyRules(word: string): string {
  let result = word.toLowerCase();
  for (const [pattern, replacement] of RULES) {
    result = result.replace(pattern, replacement);
  }
  return result;
}
