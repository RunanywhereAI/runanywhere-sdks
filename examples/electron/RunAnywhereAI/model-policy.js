// model-policy.js — decides which loaded models may stay resident.
//
// The backend keeps one slot PER MODALITY, so nothing evicts anything else
// automatically: chatting loads a ~1.2GB LLM, then captioning an image loads a
// VLM *on top of it*, then voice adds STT and TTS. Without a policy the app
// accumulates every model it has ever used until the machine runs out of memory.
//
// The rule: a model may stay resident only while the CURRENT screen needs it.
// Note this cannot be "one model at a time" — Voice genuinely needs speech-to-text,
// a language model and text-to-speech simultaneously, and Knowledge needs an
// embedder plus a language model.
//
// Loaded as a plain <script> by the app AND require()d by the unit tests.

/** Model slots each screen needs loaded at the same time. */
const TAB_MODALITIES = {
  chat: ['llm'],
  vision: ['vlm'],
  embeddings: ['embedder'],
  voice: ['stt', 'llm', 'tts'], // the spoken reply uses the LLM too
  rag: ['embedder', 'llm'],
  structured: ['llm'],
  tools: ['llm'],
  vad: [],
};

/**
 * The slots that may remain loaded while `tab` is active and `acquiring` is
 * being loaded. `acquiring` is always kept — it is the model being asked for,
 * which matters when a load is triggered from a screen that owns no models
 * (the Models library, for instance).
 */
function modalitiesToKeep(tab, acquiring) {
  const keep = new Set(TAB_MODALITIES[tab] || []);
  if (acquiring) keep.add(acquiring);
  return keep;
}

/**
 * Which of `loaded` should be unloaded before `acquiring` is loaded for `tab`.
 * Order is stable so the caller's behaviour is predictable in tests and logs.
 */
function modalitiesToRelease(tab, acquiring, loaded) {
  const keep = modalitiesToKeep(tab, acquiring);
  return (loaded || []).filter((m) => !keep.has(m));
}

/* eslint-disable no-undef */
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { TAB_MODALITIES, modalitiesToKeep, modalitiesToRelease };
}
