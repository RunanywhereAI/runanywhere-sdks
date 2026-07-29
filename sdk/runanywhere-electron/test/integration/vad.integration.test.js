// Integration test for the built-in energy VAD against the real addon (no model).
// The energy VAD calibrates on the first ~20 frames of ambient audio, then flags
// speech once a frame's energy exceeds the calibrated threshold — so a correct
// test primes it with silence before presenting speech.
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const NATIVE_PATH = process.env.RUNANYWHERE_NATIVE_PATH;
const HAVE_ADDON = Boolean(NATIVE_PATH) && (() => {
  try { return fs.existsSync(NATIVE_PATH); } catch { return false; }
})();
const SKIP = HAVE_ADDON ? {} : { skip: 'RUNANYWHERE_NATIVE_PATH unset or file missing' };

const FRAME = 1600; // 100 ms @ 16 kHz
const CAL = 24; // > RAC_VAD_CALIBRATION_FRAMES_NEEDED (20)

let RunAnywhere = null;
before(() => {
  if (!HAVE_ADDON) return;
  ({ RunAnywhere } = require('../../dist'));
  RunAnywhere.initialize();
});
after(() => {
  if (RunAnywhere) try { RunAnywhere.shutdown(); } catch {}
});

const silence = () => new Float32Array(FRAME);
function loudSine(phase, amp = 0.5, freq = 300, sr = 16000) {
  const f = new Float32Array(FRAME);
  for (let i = 0; i < FRAME; i++) f[i] = amp * Math.sin((2 * Math.PI * freq * (phase + i)) / sr);
  return f;
}
const calibrate = (vad) => { for (let i = 0; i < CAL; i++) vad.detect(silence()); };

test('detects speech after calibrating on ambient silence', SKIP, () => {
  const vad = RunAnywhere.createVad();
  calibrate(vad);
  let detected = false;
  let phase = 0;
  for (let i = 0; i < 8; i++) {
    if (vad.detect(loudSine(phase))) detected = true;
    phase += FRAME;
  }
  assert.ok(detected || vad.isSpeechActive(), 'speech detected after calibration');
  vad.close();
});

test('silence stays non-speech through and after calibration', SKIP, () => {
  const vad = RunAnywhere.createVad();
  let any = false;
  for (let i = 0; i < CAL + 10; i++) if (vad.detect(silence())) any = true;
  assert.equal(any, false);
  assert.equal(vad.isSpeechActive(), false);
  vad.close();
});

test('a high threshold suppresses speech even after calibration', SKIP, () => {
  const vad = RunAnywhere.createVad();
  calibrate(vad);
  vad.setThreshold(0.9); // above the loud-frame energy
  let detected = false;
  let phase = 0;
  for (let i = 0; i < 8; i++) {
    if (vad.detect(loudSine(phase))) detected = true;
    phase += FRAME;
  }
  assert.equal(detected, false);
  vad.close();
});

test('reset re-enters calibration (speech not immediately reported)', SKIP, () => {
  const vad = RunAnywhere.createVad();
  calibrate(vad);
  vad.detect(loudSine(0)); // would detect now
  vad.reset();
  // Right after reset it recalibrates, so a single loud frame should not report.
  assert.equal(vad.detect(loudSine(FRAME)), false);
  vad.close();
});

test('isSpeechActive is a boolean', SKIP, () => {
  const vad = RunAnywhere.createVad();
  assert.equal(typeof vad.isSpeechActive(), 'boolean');
  vad.close();
});
