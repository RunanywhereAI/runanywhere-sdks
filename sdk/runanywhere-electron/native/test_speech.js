// M1b STT + TTS smoke test via the sherpa engine.
// Usage: node test_speech.js <.node> <sttModelDir> <ttsVoiceDir> <inputWav>
const os = require('os');
const path = require('path');
const fs = require('fs');

const [, , addonPath, sttDir, ttsDir, wavPath] = process.argv;
if (!addonPath || !sttDir || !ttsDir || !wavPath) {
  console.error('usage: node test_speech.js <.node> <sttModelDir> <ttsVoiceDir> <inputWav>');
  process.exit(2);
}

const ra = require(path.resolve(addonPath));
console.log('[speech] .node loaded; commons version =', ra.version);
ra.initialize(path.join(os.tmpdir(), 'ra-electron-m1', 'secure'));

// Extract raw PCM from a WAV by locating the 'data' chunk.
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

// ---- STT ----
const pcm = readWavPcm(wavPath);
console.log('[stt] pcm bytes =', pcm.length);
const sh = ra.loadSttModel(sttDir, 'sherpa-onnx-whisper-tiny.en');
console.log('[stt] model loaded, handle =', sh);
const text = ra.transcribe(sh, pcm);
console.log('[stt] TRANSCRIPT:', JSON.stringify(text));
ra.unloadSttModel(sh);

// ---- TTS ----
const th = ra.loadTtsVoice(ttsDir, 'vits-piper-en_US-lessac-medium');
console.log('[tts] voice loaded, handle =', th);
const { sampleRate, samples } = ra.synthesize(th, 'Hello from RunAnywhere, running on Windows.');
console.log('[tts] samples =', samples.length, 'sampleRate =', sampleRate,
            'duration =', (samples.length / sampleRate).toFixed(2) + 's');

function writeWav(file, float32, sr) {
  const n = float32.length;
  const buf = Buffer.alloc(44 + n * 2);
  buf.write('RIFF', 0); buf.writeUInt32LE(36 + n * 2, 4); buf.write('WAVE', 8);
  buf.write('fmt ', 12); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(1, 22);
  buf.writeUInt32LE(sr, 24); buf.writeUInt32LE(sr * 2, 28); buf.writeUInt16LE(2, 32); buf.writeUInt16LE(16, 34);
  buf.write('data', 36); buf.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i++) {
    const s = Math.max(-1, Math.min(1, float32[i]));
    buf.writeInt16LE((s * 32767) | 0, 44 + i * 2);
  }
  fs.writeFileSync(file, buf);
}
const outWav = path.join(os.tmpdir(), 'ra_tts_out.wav');
writeWav(outWav, samples, sampleRate);
console.log('[tts] wrote', outWav);

ra.unloadTtsVoice(th);
ra.shutdown();
console.log('[speech] done.');
