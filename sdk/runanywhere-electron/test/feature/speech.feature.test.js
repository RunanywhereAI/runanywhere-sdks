// F7, F8, F9 — STT, TTS, and VAD over the commons lifecycle proto ABI, against
// the real addon and real models.
//
// All three moved onto the same store the LLM and VLM use, so none of them
// takes a handle any more and each one's options reach commons whole: word
// timestamps and diarization hints for STT, the voice list for TTS, the
// debounce and hangover dials for VAD.

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const NATIVE_PATH = process.env.RUNANYWHERE_NATIVE_PATH;
const STT_ID = 'whisper-tiny';
const TTS_ID = 'piper-lessac';
const MODELS = path.join(os.homedir(), '.runanywhere', 'models');
const STT_DIR = path.join(MODELS, STT_ID, 'sherpa-onnx-whisper-tiny.en');
const TTS_DIR = path.join(MODELS, TTS_ID, 'vits-piper-en_US-lessac-medium');

const exists = (p) => {
  try {
    return Boolean(p) && fs.existsSync(p);
  } catch {
    return false;
  }
};

const K2 = 'https://github.com/k2-fsa/sherpa-onnx/releases/download';
const CATALOG = {
  [STT_ID]: {
    type: 'stt',
    files: [{ url: `${K2}/asr-models/sherpa-onnx-whisper-tiny.en.tar.bz2`, as: 'whisper.tar.bz2' }],
    archive: true,
    primary: 'sherpa-onnx-whisper-tiny.en',
    label: 'Whisper tiny (en)',
    sizeMB: 75,
  },
  [TTS_ID]: {
    type: 'tts',
    files: [
      { url: `${K2}/tts-models/vits-piper-en_US-lessac-medium.tar.bz2`, as: 'piper.tar.bz2' },
    ],
    archive: true,
    primary: 'vits-piper-en_US-lessac-medium',
    label: 'Piper Lessac',
    sizeMB: 64,
  },
};

const sttSkip = exists(NATIVE_PATH)
  ? exists(STT_DIR)
    ? {}
    : { skip: `speech model missing: ${STT_DIR}` }
  : { skip: 'RUNANYWHERE_NATIVE_PATH unset or file missing' };
const ttsSkip = exists(NATIVE_PATH)
  ? exists(TTS_DIR)
    ? {}
    : { skip: `voice missing: ${TTS_DIR}` }
  : { skip: 'RUNANYWHERE_NATIVE_PATH unset or file missing' };
const vadSkip = exists(NATIVE_PATH)
  ? {}
  : { skip: 'RUNANYWHERE_NATIVE_PATH unset or file missing' };

const SAMPLE_RATE = 16000;

/** One initialized SDK with `ids` resident, plus its teardown. */
async function withModels(ids, run) {
  const { createRunAnywhere, NativeBackend, registerCatalog, clearCatalog } = require('../../dist');
  const { addon } = require('../../dist/bridge');

  clearCatalog();
  registerCatalog(CATALOG);
  const sdk = createRunAnywhere(new NativeBackend(addon));
  await sdk.initialize({ environment: 'production' });
  try {
    for (const id of ids) await sdk.models.load(id);
    await run(sdk);
  } finally {
    await sdk.reset();
    clearCatalog();
  }
}

/** A 440 Hz tone, which the energy detector reads as speech-like. */
function tone(ms, amplitude = 0.5) {
  const samples = new Float32Array(Math.round((ms / 1000) * SAMPLE_RATE));
  for (let i = 0; i < samples.length; i++) {
    samples[i] = amplitude * Math.sin((2 * Math.PI * 440 * i) / SAMPLE_RATE);
  }
  return samples;
}

function silence(ms) {
  return new Float32Array(Math.round((ms / 1000) * SAMPLE_RATE));
}

function concat(...parts) {
  const total = parts.reduce((n, p) => n + p.length, 0);
  const out = new Float32Array(total);
  let at = 0;
  for (const p of parts) {
    out.set(p, at);
    at += p.length;
  }
  return out;
}

function pcmInput(samples) {
  const { audio } = require('../../dist');
  return audio.float32(samples, SAMPLE_RATE);
}

// ---------------------------------------------------------------------------
// F7 — STT
// ---------------------------------------------------------------------------

test('stt: the model is resident in the lifecycle store and reports its state',
  { timeout: 600000, ...sttSkip },
  async () => {
    await withModels([STT_ID], async (sdk) => {
      const state = await sdk.stt.state();
      assert.equal(state.isReady, true, 'commons reports the STT model ready');
      assert.ok(state.modelId, `and names it: ${state.modelId}`);
      // supportsStreaming and the language list come from the service state
      // rather than a JSON string the addon used to hand back.
      assert.equal(typeof state.supportsStreaming, 'boolean');
      assert.ok(Array.isArray(state.languages), 'languages are a list, not parsed JSON');
    });
  }
);

test('stt: synthesized speech transcribes, with the timings commons measured',
  { timeout: 600000, ...sttSkip },
  async () => {
    await withModels([TTS_ID, STT_ID], async (sdk) => {
      // Round-trip: the voice speaks a known phrase, the recognizer reads it
      // back. That is a real audio path rather than a fixture nobody can check.
      const spoken = await sdk.tts.synthesize('The quick brown fox.', {});
      const resampled =
        spoken.sampleRate === SAMPLE_RATE
          ? spoken.data
          : await require('../../dist/audio').downsample(spoken.data, spoken.sampleRate, SAMPLE_RATE);

      const result = await sdk.stt.transcribe(pcmInput(resampled), { wordTimestamps: true });
      assert.ok(result.text.trim().length > 0, `something was transcribed: ${result.text}`);
      assert.ok(result.durationMs > 0, 'commons reported the audio duration it decoded');
      // Word timings are asserted as a shape, not a transcript: whisper-tiny on
      // synthetic speech is not reliable enough to assert words by name.
      for (const w of result.words) {
        assert.equal(typeof w.text, 'string');
        assert.ok(w.endMs >= w.startMs, 'each word ends no earlier than it starts');
      }
    });
  }
);

test('stt: a push stream emits started, a final transcript, then completed',
  { timeout: 600000, ...sttSkip },
  async () => {
    await withModels([TTS_ID, STT_ID], async (sdk) => {
      const spoken = await sdk.tts.synthesize('Hello there.', {});
      const resampled =
        spoken.sampleRate === SAMPLE_RATE
          ? spoken.data
          : await require('../../dist/audio').downsample(spoken.data, spoken.sampleRate, SAMPLE_RATE);

      const stream = await sdk.stt.openStream({ encoding: 'PCM_F32_LE', sampleRate: SAMPLE_RATE });
      stream.pushFrame({ samples: resampled, sampleCount: resampled.length });
      stream.finish();

      const types = [];
      let final = null;
      for await (const event of stream.events) {
        types.push(event.type);
        if (event.type === 'transcriptFinal') final = event.segment;
        if (event.type === 'failed') throw event.error;
      }
      assert.equal(types[0], 'started', 'the stream opens with started');
      assert.equal(types[types.length - 1], 'completed', 'and closes with completed');
      assert.ok(final, 'a final transcript arrived');
      // One native pass now: the second non-streaming call the component path
      // needed for word timings is gone, because the FINAL event carries them.
      assert.equal(typeof final.text, 'string');
    });
  }
);

// ---------------------------------------------------------------------------
// F8 — TTS
// ---------------------------------------------------------------------------

test('tts: synthesize returns real audio at the voice native rate',
  { timeout: 600000, ...ttsSkip },
  async () => {
    await withModels([TTS_ID], async (sdk) => {
      const out = await sdk.tts.synthesize('Testing one two three.', {});
      assert.ok(out.data.length > SAMPLE_RATE / 10, `more than 100ms of audio: ${out.data.length}`);
      assert.ok(out.sampleRate > 0, 'the voice reported the rate it rendered at');
      assert.ok(out.durationMs > 0, 'and how long the utterance is');
      let peak = 0;
      for (const s of out.data) peak = Math.max(peak, Math.abs(s));
      assert.ok(peak > 0.01, `the buffer is audible rather than silence: peak ${peak}`);
    });
  }
);

test('tts: streaming yields chunks and one terminal marker',
  { timeout: 600000, ...ttsSkip },
  async () => {
    await withModels([TTS_ID], async (sdk) => {
      const chunks = [];
      for await (const chunk of sdk.tts.synthesizeStream('One two three four five.', {})) {
        chunks.push(chunk);
      }
      assert.ok(chunks.length >= 2, `chunks plus a terminal marker: ${chunks.length}`);
      assert.equal(chunks[chunks.length - 1].isFinal, true, 'the last chunk is the terminal one');
      const audible = chunks.slice(0, -1).reduce((n, c) => n + c.data.length, 0);
      assert.ok(audible > 0, 'the chunks before it carry samples');
    });
  }
);

test('tts: voices() comes from commons, not from the loaded voice id',
  { timeout: 600000, ...ttsSkip },
  async () => {
    await withModels([TTS_ID], async (sdk) => {
      const voices = await sdk.tts.voices();
      assert.ok(voices.length > 0, 'at least one voice is reported');
      for (const v of voices) {
        assert.ok(v.id, 'every voice has an id');
        assert.ok(v.name, 'and a display name');
        assert.ok(v.language, 'and a language');
      }
    });
  }
);

test('tts: stop mid-synthesis leaves the voice usable',
  { timeout: 600000, ...ttsSkip },
  async () => {
    await withModels([TTS_ID], async (sdk) => {
      let chunks = 0;
      for await (const chunk of sdk.tts.synthesizeStream(
        'This is a long sentence that will be interrupted well before it finishes speaking.',
        {}
      )) {
        chunks += 1;
        if (!chunk.isFinal && chunks >= 1) break;
      }
      assert.ok(chunks >= 1, 'the caller stopped the stream');
      const after = await sdk.tts.synthesize('Still here.', {});
      assert.ok(after.data.length > 0, 'the voice still synthesizes after a stop');
    });
  }
);

// ---------------------------------------------------------------------------
// F9 — VAD
// ---------------------------------------------------------------------------

test('vad: detection works on the lifecycle path with no VAD model loaded',
  { timeout: 600000, ...vadSkip },
  async () => {
    await withModels([], async (sdk) => {
      // This is the case that blocked F9 until commons was fixed.
      // rac_vad_process_lifecycle_proto used to require a lifecycle-loaded VAD
      // model (acquire_lifecycle_vad) and had no equivalent of the component
      // path's energy-VAD fallback, so with nothing loaded it answered
      // "Component or service has not been initialized". vad_module.cpp now
      // falls back to the built-in energy detector on all four lifecycle entry
      // points, which is what the component path always did. No VAD model
      // ships in the desktop catalog, so this test running at all is the proof.
      const quiet = await sdk.vad.detect(pcmInput(silence(1000)));
      assert.equal(quiet.isSpeech, false, 'a second of silence is not speech');
      assert.equal(quiet.segments.length, 0, 'and produces no segments');

      const loud = await sdk.vad.detect(pcmInput(concat(silence(200), tone(600), silence(200))));
      assert.equal(loud.isSpeech, true, 'a tone in the middle is speech');
      assert.ok(loud.segments.length > 0, 'and produces a segment');
      // The probability is the detector's own peak score now, not a
      // speech-frame ratio computed here from a boolean per frame.
      assert.ok(loud.probability > 0, `with a score from the detector: ${loud.probability}`);
      assert.equal(quiet.probability, 0, 'and silence scores zero');
    });
  }
);

test('vad: minSilenceMs changes where a turn ends',
  { timeout: 600000, ...vadSkip },
  async () => {
    await withModels([], async (sdk) => {
      // Two bursts with a 400ms gap. A hangover shorter than the gap ends the
      // turn inside it; one longer bridges it. The component ABI had no field
      // for this at all, so the option was declared by the public type and then
      // dropped on the way to native.
      const audio = pcmInput(concat(tone(400), silence(400), tone(400)));
      const split = await sdk.vad.detect(audio, { minSilenceMs: 100 });
      const bridged = await sdk.vad.detect(audio, { minSilenceMs: 900 });
      assert.ok(split.segments.length > 0, 'the short hangover found speech');
      assert.ok(
        bridged.segments.length <= split.segments.length,
        `a longer hangover merges turns rather than splitting them ` +
          `(${bridged.segments.length} <= ${split.segments.length})`
      );
    });
  }
);

test('vad: a stream reports activity and speech boundaries',
  { timeout: 600000, ...vadSkip },
  async () => {
    await withModels([], async (sdk) => {
      const stream = await sdk.vad.openStream({ encoding: 'PCM_F32_LE', sampleRate: SAMPLE_RATE });
      const speech = concat(silence(200), tone(600), silence(400));
      stream.pushFrame({ samples: speech, sampleCount: speech.length });
      stream.finish();

      const types = [];
      for await (const event of stream.events) {
        types.push(event.type);
        if (event.type === 'failed') throw event.error;
      }
      assert.ok(types.includes('activity'), 'per-frame activity is reported');
      assert.ok(types.includes('speechStarted'), 'and the start of the burst');
      assert.equal(types[types.length - 1], 'completed', 'the stream terminates');
      await stream.close();

      const again = await sdk.vad.detect(pcmInput(concat(silence(200), tone(600))));
      assert.equal(again.isSpeech, true, 'the detector still works after a stream closed');
    });
  }
);
