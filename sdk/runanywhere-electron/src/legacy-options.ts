// legacy-options.ts — pre-v3 generation option names and their mapping onto the
// native addon's option keys. The N-API layer (addon.cpp parse_gen_opts)
// predates the max_tokens → max_output_tokens rename and keeps `maxTokens` as
// its wire key, so the facade and the renderer preload both normalize here.

/** Per-request generation controls (all optional). */
export interface GenerateOptions {
  /** Maximum number of tokens to generate. */
  maxOutputTokens?: number;
  temperature?: number;
  topP?: number;
  topK?: number;
  /** System instruction passed to the backend for this request. */
  systemPrompt?: string;
  /** Raw GBNF grammar to constrain decoding (advanced; see generateStructured). */
  grammar?: string;
}

/** The option object shape the native addon parses. */
export interface NativeGenerateOptions {
  maxTokens?: number;
  temperature?: number;
  topP?: number;
  topK?: number;
  systemPrompt?: string;
  grammar?: string;
}

/** Map public option names to the addon's keys (drops unknown properties). */
export function toNativeGenerateOptions(o: GenerateOptions = {}): NativeGenerateOptions {
  const native: NativeGenerateOptions = {};
  if (o.maxOutputTokens !== undefined) native.maxTokens = o.maxOutputTokens;
  if (o.temperature !== undefined) native.temperature = o.temperature;
  if (o.topP !== undefined) native.topP = o.topP;
  if (o.topK !== undefined) native.topK = o.topK;
  if (o.systemPrompt !== undefined) native.systemPrompt = o.systemPrompt;
  if (o.grammar !== undefined) native.grammar = o.grammar;
  return native;
}
