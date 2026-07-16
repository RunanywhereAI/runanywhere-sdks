// voice.js — a full voice turn: audio in -> STT -> LLM -> TTS -> audio out.
//   node examples/voice.js
const path = require('path');
const fs = require('fs');
const os = require('os');
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
function writeWav(file, float32, sr) {
  const n = float32.length;
  const buf = Buffer.alloc(44 + n * 2);
  buf.write('RIFF', 0); buf.writeUInt32LE(36 + n * 2, 4); buf.write('WAVE', 8);
  buf.write('fmt ', 12); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(1, 22);
  buf.writeUInt32LE(sr, 24); buf.writeUInt32LE(sr * 2, 28); buf.writeUInt16LE(2, 32); buf.writeUInt16LE(16, 34);
  buf.write('data', 36); buf.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i++) buf.writeInt16LE((Math.max(-1, Math.min(1, float32[i])) * 32767) | 0, 44 + i * 2);
  fs.writeFileSync(file, buf);
}

(async () => {
  console.log('@runanywhere/electron — commons version:', RunAnywhere.version);
  RunAnywhere.initialize();

  const stt = await RunAnywhere.loadSTT(path.join(MODELS, 'sherpa-onnx-whisper-tiny.en'));
  const llm = await RunAnywhere.loadLLM(path.join(MODELS, 'smollm2-135m.gguf'));
  const tts = await RunAnywhere.loadTTS(path.join(MODELS, 'vits-piper-en_US-lessac-medium'));

  const agent = RunAnywhere.createVoiceAgent(
    { stt, llm, tts },
    { systemPrompt: 'You are a concise helpful assistant. Reply in one short sentence.' }
  );

  const pcm = readWavPcm(path.join(MODELS, 'sherpa-onnx-whisper-tiny.en', 'test_wavs', '0.wav'));
  process.stdout.write('[voice] response: ');
  const turn = await agent.processTurn(pcm, {
    onTranscript: (t) => console.log('\n[voice] heard: ' + JSON.stringify(t) + '\n[voice] response: '),
    onToken: (t) => process.stdout.write(t),
  });
  console.log('\n[voice] transcript :', JSON.stringify(turn.transcript));
  console.log('[voice] response   :', JSON.stringify(turn.response));
  console.log('[voice] reply audio:', turn.audio.samples.length, 'samples @', turn.audio.sampleRate, 'Hz',
              '(' + (turn.audio.samples.length / turn.audio.sampleRate).toFixed(2) + 's)');

  const outWav = path.join(os.tmpdir(), 'ra_voice_reply.wav');
  writeWav(outWav, turn.audio.samples, turn.audio.sampleRate);
  console.log('[voice] wrote reply audio:', outWav);

  stt.unload();
  llm.unload();
  tts.unload();
  RunAnywhere.shutdown();
  console.log('[voice] OK — full STT -> LLM -> TTS voice turn.');
})().catch((e) => {
  console.error('FAILED:', e);
  process.exit(1);
});
