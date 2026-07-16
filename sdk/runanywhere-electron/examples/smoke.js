// smoke.js — exercise the compiled @runanywhere/electron TS facade end-to-end
// across all five modalities. Point RA_MODELS at the model dir and
// RUNANYWHERE_NATIVE_PATH at the built .node (or rely on the dev-build default).
//
//   node examples/smoke.js
const path = require('path');
const fs = require('fs');
const { RunAnywhere } = require('../dist');

const MODELS = process.env.RA_MODELS || 'e:\\codes\\qual\\models';

function readWavPcm(file) {
  const b = fs.readFileSync(file);
  let off = 12;
  while (off + 8 <= b.length) {
    const id = b.toString('ascii', off, off + 4);
    const size = b.readUInt32LE(off + 4);
    if (id === 'data') return b.subarray(off + 8, off + 8 + size);
    off += 8 + size + (size & 1);
  }
  return b.subarray(44);
}

(async () => {
  console.log('@runanywhere/electron — commons version:', RunAnywhere.version);
  RunAnywhere.initialize();

  // LLM (streaming AsyncIterable)
  const llm = await RunAnywhere.loadLLM(path.join(MODELS, 'smollm2-135m.gguf'));
  process.stdout.write('LLM  : ');
  for await (const t of llm.generate('What is the capital of France? Answer in one word.')) {
    process.stdout.write(t);
  }
  console.log();
  llm.unload();

  // Embeddings
  const emb = await RunAnywhere.loadEmbedder(path.join(MODELS, 'minilm', 'model.onnx'));
  console.log('EMBED:', emb.embed('hello world').length, 'dims');
  emb.unload();

  // VLM
  const vlm = await RunAnywhere.loadVLM(
    path.join(MODELS, 'smolvlm-256m.gguf'),
    path.join(MODELS, 'smolvlm-256m-mmproj.gguf')
  );
  const caption = await vlm.captionText(
    path.join(MODELS, 'test_red_circle.jpg'),
    'Describe this image in one short sentence.'
  );
  console.log('VLM  :', caption.trim());
  vlm.unload();

  // STT
  const stt = await RunAnywhere.loadSTT(path.join(MODELS, 'sherpa-onnx-whisper-tiny.en'));
  const pcm = readWavPcm(path.join(MODELS, 'sherpa-onnx-whisper-tiny.en', 'test_wavs', '0.wav'));
  console.log('STT  :', JSON.stringify(stt.transcribe(pcm).trim()));
  stt.unload();

  // TTS
  const tts = await RunAnywhere.loadTTS(path.join(MODELS, 'vits-piper-en_US-lessac-medium'));
  const { sampleRate, samples } = tts.synthesize('Hello from the RunAnywhere Electron SDK.');
  console.log('TTS  :', samples.length, 'samples @', sampleRate, 'Hz');
  tts.unload();

  RunAnywhere.shutdown();
  console.log('\nAll five modalities OK through the TypeScript facade.');
})().catch((e) => {
  console.error('FAILED:', e);
  process.exit(1);
});
