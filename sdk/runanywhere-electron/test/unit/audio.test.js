// Unit tests for audio.ts — DSP is owned by commons and reached through the
// N-API addon. These tests inject a fake AudioNative so they run without the
// .node, and assert the TypeScript layer only forwards (no local PCM math).
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
  pcmDurationMs,
  float32DurationMs,
  setAudioNativeForTests,
  MicRecorder,
  SpeakerPlayer,
} = require('../../dist/audio');

function installForwardingNative() {
  const calls = [];
  const native = {
    audioFloat32ToPcm16(samples) {
      calls.push(['float32ToPcm16', samples.length]);
      return new Int16Array(samples.length);
    },
    audioPcm16ToFloat32(samples) {
      calls.push(['pcm16ToFloat32', samples.length]);
      return new Float32Array(samples.length);
    },
    audioResampleF32(samples, inRate, outRate) {
      calls.push(['resample', samples.length, inRate, outRate]);
      return new Float32Array(Math.max(1, Math.floor((samples.length * outRate) / inRate)));
    },
    audioComputeRms(samples) {
      calls.push(['rms', samples.length]);
      return 0.25;
    },
    audioFloat32ToWav(samples, sampleRate) {
      calls.push(['encodeWav', samples.length, sampleRate]);
      return new Uint8Array([1, 2, 3]);
    },
    audioWavToFloat32(bytes) {
      calls.push(['decodeWav', bytes.length]);
      return { sampleRate: 16000, samples: new Float32Array([0, 0.5]) };
    },
    audioPcmBytesToMs(byteCount, format) {
      calls.push(['pcmBytesToMs', byteCount, format.sampleRate]);
      if (!format.sampleRate) return 0;
      const bps = (format.bitsPerSample ?? 32) / 8;
      const ch = format.channels ?? 1;
      return Math.floor((byteCount / (bps * ch) / format.sampleRate) * 1000);
    },
  };
  setAudioNativeForTests(native);
  return calls;
}

test.afterEach(() => {
  setAudioNativeForTests(null);
});

test('float32ToPcm16 / pcm16ToFloat32 / pcm16Bytes forward to commons', () => {
  const calls = installForwardingNative();
  const pcm = float32ToPcm16(new Float32Array([0, 1, -1]));
  assert.equal(pcm.length, 3);
  const f = pcm16ToFloat32(new Int16Array([0, 1, 2]));
  assert.equal(f.length, 3);
  const bytes = pcm16Bytes(new Float32Array([0, 1]));
  assert.equal(bytes.length, 4);
  assert.deepEqual(
    calls.map((c) => c[0]),
    ['float32ToPcm16', 'pcm16ToFloat32', 'float32ToPcm16']
  );
});

test('downsample / rms / encodeWav / decodeWav forward to commons', () => {
  const calls = installForwardingNative();
  const down = downsample(new Float32Array(4800), 48000, 16000);
  assert.ok(down.length > 0);
  assert.equal(rms(new Float32Array([0.5, 0.5])), 0.25);
  assert.equal(rms(new Float32Array(0)), 0);
  assert.deepEqual(Array.from(encodeWav(new Float32Array([0]), 16000)), [1, 2, 3]);
  const decoded = decodeWav(new Uint8Array([9, 9, 9]));
  assert.equal(decoded.sampleRate, 16000);
  assert.deepEqual(Array.from(decoded.samples), [0, 0.5]);
  assert.ok(calls.some((c) => c[0] === 'resample'));
  assert.ok(calls.some((c) => c[0] === 'rms'));
  assert.ok(calls.some((c) => c[0] === 'encodeWav'));
  assert.ok(calls.some((c) => c[0] === 'decodeWav'));
});

test('pcmDurationMs / float32DurationMs forward to commons; missing stays 0', () => {
  const calls = installForwardingNative();
  assert.equal(pcmDurationMs(32000, { sampleRate: 16000, channels: 1, bitsPerSample: 16 }), 1000);
  assert.equal(float32DurationMs(16000, 16000), 1000);
  assert.equal(pcmDurationMs(0, { sampleRate: 16000 }), 0);
  assert.equal(float32DurationMs(100, 0), 0);
  assert.ok(calls.some((c) => c[0] === 'pcmBytesToMs'));
});

test('downsample rejects non-positive rates before touching native', () => {
  installForwardingNative();
  assert.throws(() => downsample(new Float32Array([1]), 0, 16000), /positive/);
  assert.throws(() => downsample(new Float32Array([1]), 16000, 0), /positive/);
});

test('MicRecorder and SpeakerPlayer are constructible in Node but guard Web Audio', async () => {
  assert.equal(typeof MicRecorder, 'function');
  assert.equal(typeof SpeakerPlayer, 'function');
  const rec = new MicRecorder();
  await assert.rejects(() => rec.start(), /renderer|navigator|Web Audio/);
  const player = new SpeakerPlayer();
  assert.throws(() => player.play(new Float32Array([0]), 16000), /Web Audio|renderer/);
});
