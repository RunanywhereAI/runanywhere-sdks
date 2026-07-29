// Unit tests for the pure audio DSP + WAV codec (src/audio.ts). The renderer-only
// MicRecorder/SpeakerPlayer need Web Audio and are covered by the example app; the
// pure conversions here are the testable core the voice pipeline depends on.
const { test } = require('node:test');
const assert = require('node:assert/strict');

const {
  float32ToPcm16,
  pcm16ToFloat32,
  pcm16Bytes,
  downsample,
  rms,
  encodeWav,
  decodeWav,
  MicRecorder,
  SpeakerPlayer,
} = require('../../dist/audio');

// --------------------------------------------------------------------------
// float32 <-> pcm16
// --------------------------------------------------------------------------
test('float32ToPcm16 maps the full-scale endpoints', () => {
  const out = float32ToPcm16(new Float32Array([0, 1, -1, 0.5, -0.5]));
  assert.equal(out[0], 0);
  assert.equal(out[1], 32767);
  assert.equal(out[2], -32768);
  assert.equal(out[3], 16384); // round(0.5 * 32767)
  assert.equal(out[4], -16384); // round(-0.5 * 32768)
});

test('float32ToPcm16 clamps out-of-range input', () => {
  const out = float32ToPcm16(new Float32Array([2, -2, 1.0001, -1.0001]));
  assert.equal(out[0], 32767);
  assert.equal(out[1], -32768);
  assert.equal(out[2], 32767);
  assert.equal(out[3], -32768);
});

test('pcm16ToFloat32 inverts the scale', () => {
  const f = pcm16ToFloat32(new Int16Array([0, -32768, 16384, -16384]));
  assert.equal(f[0], 0);
  assert.equal(f[1], -1);
  assert.equal(f[2], 0.5);
  assert.equal(f[3], -0.5);
});

test('float32 -> pcm16 -> float32 round-trips within quantization error', () => {
  const src = new Float32Array([0, 0.25, -0.25, 0.5, -0.75, 0.999]);
  const back = pcm16ToFloat32(float32ToPcm16(src));
  for (let i = 0; i < src.length; i++) {
    assert.ok(Math.abs(back[i] - src[i]) < 1 / 32768, `sample ${i} off by too much`);
  }
});

test('pcm16Bytes returns little-endian int16 bytes, 2 per sample', () => {
  const bytes = pcm16Bytes(new Float32Array([0, 1, -1]));
  assert.equal(bytes.length, 6);
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  assert.equal(view.getInt16(0, true), 0);
  assert.equal(view.getInt16(2, true), 32767);
  assert.equal(view.getInt16(4, true), -32768);
});

// --------------------------------------------------------------------------
// downsample
// --------------------------------------------------------------------------
test('downsample block-averages when reducing the rate', () => {
  const out = downsample(new Float32Array([0, 1, 2, 3, 4, 5]), 2, 1);
  assert.deepEqual(Array.from(out), [0.5, 2.5, 4.5]);
});

test('downsample 48k -> 16k gives roughly a third of the samples', () => {
  const input = new Float32Array(4800).fill(0.2);
  const out = downsample(input, 48000, 16000);
  assert.equal(out.length, 1600);
  for (const v of out) assert.ok(Math.abs(v - 0.2) < 1e-6);
});

test('downsample returns a copy (not the same ref) when rates match or upsampling', () => {
  const input = new Float32Array([1, 2, 3]);
  const same = downsample(input, 16000, 16000);
  assert.deepEqual(Array.from(same), [1, 2, 3]);
  assert.notEqual(same, input);
  const up = downsample(input, 16000, 48000);
  assert.deepEqual(Array.from(up), [1, 2, 3]);
});

test('downsample rejects non-positive rates', () => {
  assert.throws(() => downsample(new Float32Array([1]), 0, 16000), /positive/);
  assert.throws(() => downsample(new Float32Array([1]), 16000, 0), /positive/);
});

// --------------------------------------------------------------------------
// rms
// --------------------------------------------------------------------------
test('rms is zero for silence and empty input', () => {
  assert.equal(rms(new Float32Array(0)), 0);
  assert.equal(rms(new Float32Array([0, 0, 0])), 0);
});

test('rms of a constant equals its absolute value', () => {
  assert.ok(Math.abs(rms(new Float32Array([0.5, 0.5, 0.5])) - 0.5) < 1e-6);
  assert.ok(Math.abs(rms(new Float32Array([-0.5, -0.5])) - 0.5) < 1e-6);
});

// --------------------------------------------------------------------------
// WAV codec
// --------------------------------------------------------------------------
test('encodeWav writes a valid 44-byte 16-bit mono PCM header', () => {
  const wav = encodeWav(new Float32Array([0, 0.5, -0.5]), 16000);
  const ascii = (o, n) => String.fromCharCode(...wav.slice(o, o + n));
  const view = new DataView(wav.buffer, wav.byteOffset, wav.byteLength);
  assert.equal(ascii(0, 4), 'RIFF');
  assert.equal(ascii(8, 4), 'WAVE');
  assert.equal(ascii(12, 4), 'fmt ');
  assert.equal(view.getUint16(20, true), 1, 'PCM format');
  assert.equal(view.getUint16(22, true), 1, 'mono');
  assert.equal(view.getUint32(24, true), 16000, 'sample rate');
  assert.equal(view.getUint32(28, true), 16000 * 2, 'byte rate');
  assert.equal(view.getUint16(32, true), 2, 'block align');
  assert.equal(view.getUint16(34, true), 16, 'bits per sample');
  assert.equal(ascii(36, 4), 'data');
  assert.equal(view.getUint32(40, true), 3 * 2, 'data length');
  assert.equal(wav.length, 44 + 3 * 2);
});

test('decodeWav round-trips encodeWav (rate + samples within quantization)', () => {
  const src = new Float32Array([0, 0.25, -0.25, 0.5, -0.5, 0.75]);
  const { sampleRate, samples } = decodeWav(encodeWav(src, 22050));
  assert.equal(sampleRate, 22050);
  assert.equal(samples.length, src.length);
  for (let i = 0; i < src.length; i++) {
    assert.ok(Math.abs(samples[i] - src[i]) < 1 / 32768, `sample ${i} drifted`);
  }
});

// A stereo / extra-chunk WAV to exercise the chunk scanner + down-mix.
function buildWav(channels, sampleRate, interleaved, opts = {}) {
  const dataLen = interleaved.length * 2;
  const extra = opts.extraChunk ? 8 + opts.extraChunk.length : 0;
  const buf = Buffer.alloc(44 + extra + dataLen);
  buf.write('RIFF', 0);
  buf.writeUInt32LE(36 + extra + dataLen, 4);
  buf.write('WAVE', 8);
  buf.write('fmt ', 12);
  buf.writeUInt32LE(16, 16);
  buf.writeUInt16LE(1, 20);
  buf.writeUInt16LE(channels, 22);
  buf.writeUInt32LE(sampleRate, 24);
  buf.writeUInt32LE(sampleRate * channels * 2, 28);
  buf.writeUInt16LE(channels * 2, 32);
  buf.writeUInt16LE(16, 34);
  let p = 36;
  if (opts.extraChunk) {
    buf.write('LIST', p);
    buf.writeUInt32LE(opts.extraChunk.length, p + 4);
    Buffer.from(opts.extraChunk).copy(buf, p + 8);
    p += 8 + opts.extraChunk.length;
  }
  buf.write('data', p);
  buf.writeUInt32LE(dataLen, p + 4);
  for (let i = 0; i < interleaved.length; i++) buf.writeInt16LE(interleaved[i], p + 8 + i * 2);
  return new Uint8Array(buf);
}

test('decodeWav down-mixes stereo to mono', () => {
  // Frame 0: L=32767, R=-32768 -> avg ~ 0 ; Frame 1: L=16384, R=16384 -> 0.5
  const wav = buildWav(2, 8000, [32767, -32768, 16384, 16384]);
  const { sampleRate, samples } = decodeWav(wav);
  assert.equal(sampleRate, 8000);
  assert.equal(samples.length, 2);
  assert.ok(Math.abs(samples[0]) < 1 / 32768 + 1e-4);
  assert.ok(Math.abs(samples[1] - 0.5) < 1e-3);
});

test('decodeWav skips unknown chunks (LIST) before data', () => {
  const wav = buildWav(1, 16000, [0, 16384, -16384], { extraChunk: 'INFOxx' });
  const { sampleRate, samples } = decodeWav(wav);
  assert.equal(sampleRate, 16000);
  assert.deepEqual(Array.from(samples), [0, 0.5, -0.5]);
});

test('decodeWav rejects a non-RIFF buffer', () => {
  assert.throws(() => decodeWav(new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])), /RIFF/);
});

test('decodeWav rejects a WAV with no data chunk', () => {
  // RIFF/WAVE + fmt only, no data.
  const buf = Buffer.alloc(36);
  buf.write('RIFF', 0);
  buf.writeUInt32LE(28, 4);
  buf.write('WAVE', 8);
  buf.write('fmt ', 12);
  buf.writeUInt32LE(16, 16);
  buf.writeUInt16LE(1, 20);
  buf.writeUInt16LE(1, 22);
  buf.writeUInt32LE(16000, 24);
  assert.throws(() => decodeWav(new Uint8Array(buf)), /data chunk/);
});

// --------------------------------------------------------------------------
// Renderer helpers: importable in Node, but instantiating/using outside a
// browser fails with a clear message (they must not silently no-op).
// --------------------------------------------------------------------------
test('MicRecorder and SpeakerPlayer are constructible in Node but guard Web Audio', async () => {
  assert.equal(typeof MicRecorder, 'function');
  assert.equal(typeof SpeakerPlayer, 'function');
  // Constructing is fine (no browser access in the ctor).
  const rec = new MicRecorder();
  await assert.rejects(() => rec.start(), /renderer|navigator|Web Audio/);
  const player = new SpeakerPlayer();
  assert.throws(() => player.play(new Float32Array([0]), 16000), /Web Audio|renderer/);
});
