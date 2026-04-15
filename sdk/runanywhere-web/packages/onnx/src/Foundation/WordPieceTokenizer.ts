/**
 * WordPieceTokenizer
 * -----------------------------------------------------------------------------
 * HuggingFace BERT-compatible WordPiece tokenizer, reimplemented in TypeScript.
 *
 * Matches the behavior of `transformers.BertTokenizer` with `do_lower_case=True`
 * and `strip_accents=True` — the default configuration used by the
 * `sentence-transformers/all-MiniLM-L6-v2` / `bge-small-en` families that are
 * our primary RAG embedding targets.
 *
 * Pipeline:
 *   1. BasicTokenizer:
 *      - Clean control characters
 *      - NFD-normalize + strip combining accents
 *      - Lowercase (if configured)
 *      - Split on whitespace AND punctuation
 *   2. WordPiece:
 *      - For each basic-token, greedy longest-prefix-first lookup in vocab
 *      - If no prefix is in vocab → emit [UNK]
 *
 * Special tokens: [CLS] prefix, [SEP] suffix, [PAD] for batch padding,
 *                 [UNK] for unknown subwords.
 *
 * Reference: https://github.com/huggingface/transformers/blob/main/src/
 * transformers/models/bert/tokenization_bert.py
 */

export interface TokenizerOptions {
  doLowerCase?: boolean;
  stripAccents?: boolean;
  maxInputCharsPerWord?: number;
  unkToken?: string;
  clsToken?: string;
  sepToken?: string;
  padToken?: string;
}

export interface EncodeResult {
  inputIds: number[];
  attentionMask: number[];
  tokenTypeIds: number[];
}

const DEFAULT_OPTIONS: Required<TokenizerOptions> = {
  doLowerCase: true,
  stripAccents: true,
  maxInputCharsPerWord: 100,
  unkToken: '[UNK]',
  clsToken: '[CLS]',
  sepToken: '[SEP]',
  padToken: '[PAD]',
};

export class WordPieceTokenizer {
  private vocab: Map<string, number>;
  private ids: string[];
  private opts: Required<TokenizerOptions>;
  private unkId: number;
  private clsId: number;
  private sepId: number;
  /** Reserved for future batch-padding support — kept so the vocab check fails
   *  early if the required [PAD] token is missing. */
  readonly padId: number;

  private constructor(vocab: Map<string, number>, opts: Required<TokenizerOptions>) {
    this.vocab = vocab;
    this.opts = opts;
    this.ids = new Array(vocab.size);
    for (const [tok, id] of vocab) this.ids[id] = tok;
    const resolve = (tok: string): number => {
      const id = vocab.get(tok);
      if (id === undefined) {
        throw new Error(`Vocabulary missing required special token: ${tok}`);
      }
      return id;
    };
    this.unkId = resolve(opts.unkToken);
    this.clsId = resolve(opts.clsToken);
    this.sepId = resolve(opts.sepToken);
    this.padId = resolve(opts.padToken);
  }

  /**
   * Build a tokenizer from a vocab.txt blob (one token per line, line-index
   * equal to token id).
   */
  static fromVocabText(vocabText: string, options: TokenizerOptions = {}): WordPieceTokenizer {
    const opts = { ...DEFAULT_OPTIONS, ...options };
    const vocab = new Map<string, number>();
    // Windows line endings, BOM, trailing blank line — all handled here.
    const lines = vocabText.replace(/\r\n/g, '\n').replace(/^\uFEFF/, '').split('\n');
    for (let i = 0; i < lines.length; i++) {
      const tok = lines[i];
      if (tok === undefined || tok === '') continue;
      if (!vocab.has(tok)) vocab.set(tok, vocab.size);
    }
    return new WordPieceTokenizer(vocab, opts);
  }

  /**
   * Build a tokenizer from a HuggingFace tokenizer.json blob. Only the
   * subset of fields we care about is read (model.vocab + special tokens).
   */
  static fromTokenizerJson(
    json: { model?: { vocab?: Record<string, number> } },
    options: TokenizerOptions = {},
  ): WordPieceTokenizer {
    const opts = { ...DEFAULT_OPTIONS, ...options };
    const raw = json.model?.vocab;
    if (!raw) throw new Error('tokenizer.json missing model.vocab');
    const vocab = new Map<string, number>(Object.entries(raw));
    return new WordPieceTokenizer(vocab, opts);
  }

  /**
   * Encode a single string for BERT-style inference:
   *   [CLS] <tokens> [SEP]  truncated to maxSeqLength
   */
  encode(text: string, maxSeqLength: number): EncodeResult {
    const basic = this.basicTokenize(text);

    const subwords: number[] = [];
    for (const word of basic) {
      for (const id of this.wordPiece(word)) subwords.push(id);
    }

    // Reserve two slots for [CLS] / [SEP].
    const room = Math.max(0, maxSeqLength - 2);
    const truncated = subwords.slice(0, room);

    const inputIds = [this.clsId, ...truncated, this.sepId];
    const attentionMask = new Array<number>(inputIds.length).fill(1);
    const tokenTypeIds = new Array<number>(inputIds.length).fill(0);
    return { inputIds, attentionMask, tokenTypeIds };
  }

  /** Look up a token by id — primarily useful for debugging. */
  idToToken(id: number): string | undefined {
    return this.ids[id];
  }

  get vocabSize(): number {
    return this.vocab.size;
  }

  // =====================================================================
  // Internal — BasicTokenizer + WordPiece
  // =====================================================================

  private basicTokenize(text: string): string[] {
    // Clean control characters and normalize whitespace.
    let cleaned = '';
    for (const ch of text) {
      const cp = ch.codePointAt(0)!;
      if (cp === 0 || cp === 0xfffd || this.isControl(cp)) continue;
      cleaned += this.isWhitespace(cp) ? ' ' : ch;
    }

    // Split on whitespace to get "orig tokens".
    const origTokens = cleaned.split(/\s+/).filter((t) => t.length > 0);

    const tokens: string[] = [];
    for (let tok of origTokens) {
      if (this.opts.doLowerCase) tok = tok.toLowerCase();
      if (this.opts.stripAccents) tok = this.stripAccents(tok);
      // Re-split on punctuation boundaries.
      for (const piece of this.splitPunctuation(tok)) {
        if (piece.length > 0) tokens.push(piece);
      }
    }
    return tokens;
  }

  private wordPiece(token: string): number[] {
    if (token.length > this.opts.maxInputCharsPerWord) {
      return [this.unkId];
    }

    const chars = [...token];
    const output: number[] = [];
    let start = 0;
    while (start < chars.length) {
      let end = chars.length;
      let curSubstr: number | null = null;
      while (start < end) {
        let substr = chars.slice(start, end).join('');
        if (start > 0) substr = '##' + substr;
        const id = this.vocab.get(substr);
        if (id !== undefined) {
          curSubstr = id;
          break;
        }
        end--;
      }
      if (curSubstr === null) {
        return [this.unkId];
      }
      output.push(curSubstr);
      start = end;
    }
    return output.length > 0 ? output : [this.unkId];
  }

  private stripAccents(text: string): string {
    const nfd = text.normalize('NFD');
    let out = '';
    for (const ch of nfd) {
      // Unicode category Mn = Mark, Nonspacing (combining marks).
      if (ch.match(/[\u0300-\u036f\u1ab0-\u1aff\u1dc0-\u1dff\u20d0-\u20ff\ufe20-\ufe2f]/u)) {
        continue;
      }
      out += ch;
    }
    return out;
  }

  private splitPunctuation(text: string): string[] {
    const out: string[] = [];
    let start = 0;
    for (let i = 0; i < text.length; i++) {
      const cp = text.codePointAt(i)!;
      if (this.isPunctuation(cp)) {
        if (i > start) out.push(text.slice(start, i));
        out.push(text[i]!);
        start = i + 1;
      }
      // Surrogate-pair safety: advance past the low-surrogate.
      if (cp > 0xffff) i += 1;
    }
    if (start < text.length) out.push(text.slice(start));
    return out;
  }

  // --- Unicode category helpers mirroring HF's implementation ------------

  private isWhitespace(cp: number): boolean {
    if (cp === 0x20 || cp === 0x09 || cp === 0x0a || cp === 0x0d) return true;
    // \p{White_Space} approximation covering the common BMP cases.
    return (
      cp === 0xa0 ||
      cp === 0x1680 ||
      (cp >= 0x2000 && cp <= 0x200a) ||
      cp === 0x2028 ||
      cp === 0x2029 ||
      cp === 0x202f ||
      cp === 0x205f ||
      cp === 0x3000
    );
  }

  private isControl(cp: number): boolean {
    // \t \n \r are whitespace, not control, per HF.
    if (cp === 0x09 || cp === 0x0a || cp === 0x0d) return false;
    return (cp >= 0 && cp <= 0x1f) || (cp >= 0x7f && cp <= 0x9f);
  }

  private isPunctuation(cp: number): boolean {
    // ASCII punctuation.
    if ((cp >= 33 && cp <= 47) || (cp >= 58 && cp <= 64) ||
        (cp >= 91 && cp <= 96) || (cp >= 123 && cp <= 126)) {
      return true;
    }
    // Common Unicode punctuation ranges.
    return (
      (cp >= 0x2000 && cp <= 0x206f) ||
      (cp >= 0x3000 && cp <= 0x303f) ||
      (cp >= 0xfe30 && cp <= 0xfe4f) ||
      (cp >= 0xff00 && cp <= 0xffef && this.isFullwidthPunct(cp))
    );
  }

  private isFullwidthPunct(cp: number): boolean {
    // Fullwidth ASCII punctuation (but not fullwidth letters / digits).
    return (
      (cp >= 0xff01 && cp <= 0xff0f) ||
      (cp >= 0xff1a && cp <= 0xff20) ||
      (cp >= 0xff3b && cp <= 0xff40) ||
      (cp >= 0xff5b && cp <= 0xff65)
    );
  }
}
