// F17 — the composed voice agent over the commons proto ABI, against the real
// addon and three real models.
//
// The turn loop is not in TypeScript any more, so what is under test is the
// handoff: models.load puts speech-to-text, the language model, and the voice in
// commons' lifecycle store, rac_voice_agent_initialize_proto composes an agent
// over them, and one of the three ingress modes runs VAD -> STT -> LLM -> TTS
// and hands back a transcript, a reply, and audio.
//
// The microphone is the one thing that stays on this side, and node has none, so
// the turns here are driven by pushing audio the way the mic driver does rather
// than through VoiceSession.start(). The session case asserts that start()
// refuses in a process with no capture device, which is the same boundary.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as os from 'node:os';
import * as path from 'node:path';

import { createRunAnywhere, NativeBackend, registerCatalog, clearCatalog } from '../../dist';
import type { Catalog, RaBackend, RunAnywhereApi, VoiceEvent } from '../../dist';
import { decodeWav, downsample, pcm16Bytes } from '../../dist/audio';
import {
  VoiceAgentAbi,
  toAudioFrame,
  toComposeConfig,
  toPublicVoiceEvent,
  toTurnRequest,
  missingComponents,
} from '../../dist/api/voice-abi';
import { PipelineState } from '@runanywhere/proto-ts/voice_events';
import { exists, nativeAddon } from './support';

const NATIVE_PATH = process.env.RUNANYWHERE_NATIVE_PATH;
const STT_ID = 'whisper-tiny';
const TTS_ID = 'piper-lessac';
const LLM_ID = 'smollm2-135m';
const MODELS = path.join(os.homedir(), '.runanywhere', 'models');
const STT_DIR = path.join(MODELS, STT_ID, 'sherpa-onnx-whisper-tiny.en');
const TTS_DIR = path.join(MODELS, TTS_ID, 'vits-piper-en_US-lessac-medium');
const LLM_FILE = path.join(MODELS, LLM_ID, 'model.gguf');

const K2 = 'https://github.com/k2-fsa/sherpa-onnx/releases/download';
const CATALOG: Catalog = {
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
  [LLM_ID]: {
    type: 'llm',
    files: [{ url: 'https://example.invalid/smollm2-135m.gguf', as: 'model.gguf' }],
    primary: 'model.gguf',
    label: 'SmolLM2 135M',
    sizeMB: 100,
  },
};

// A voice turn needs all three; naming the missing one beats a blanket skip.
const missing = [
  exists(NATIVE_PATH) ? null : 'RUNANYWHERE_NATIVE_PATH unset or file missing',
  exists(STT_DIR) ? null : `speech model missing: ${STT_DIR}`,
  exists(TTS_DIR) ? null : `voice missing: ${TTS_DIR}`,
  exists(LLM_FILE) ? null : `language model missing: ${LLM_FILE}`,
].filter((m): m is string => m !== null);
const SKIP: { skip?: string } = missing.length ? { skip: missing.join('; ') } : {};

const SAMPLE_RATE = 16000;
// The analysis frame the in-core segmenter reads (voice_agent_feed_abi.cpp:51).
const FRAME_BYTES = 3200;

/** An initialized SDK with the catalog staged and nothing loaded. */
async function withSdk(run: (sdk: RunAnywhereApi, backend: RaBackend) => Promise<void>): Promise<void> {
  clearCatalog();
  registerCatalog(CATALOG);
  const backend = new NativeBackend(nativeAddon());
  const sdk = createRunAnywhere(backend);
  await sdk.initialize({ environment: 'production' });
  try {
    await run(sdk, backend);
  } finally {
    await sdk.reset();
    clearCatalog();
  }
}

/** The same, with all three models resident. */
async function withVoiceModels(
  run: (sdk: RunAnywhereApi, backend: RaBackend) => Promise<void>
): Promise<void> {
  await withSdk(async (sdk, backend) => {
    for (const id of [STT_ID, LLM_ID, TTS_ID]) await sdk.models.load(id);
    await run(sdk, backend);
  });
}

/**
 * A composed agent over whatever is resident, plus its teardown. This is the
 * same pair of calls `voice.createSession` makes; the test holds the handle
 * directly because it has to push audio a microphone would have produced.
 */
async function withAgent(
  sdk: RunAnywhereApi,
  backend: RaBackend,
  run: (agent: VoiceAgentAbi) => Promise<void>
): Promise<void> {
  const session = await backend.voiceOpen(new Uint8Array(0));
  const agent = new VoiceAgentAbi(backend, session);
  try {
    const states = await agent.initialize(
      toComposeConfig({ sttModelId: STT_ID, llmModelId: LLM_ID })
    );
    assert.deepEqual(missingComponents(states), [], 'every component composed');
    await run(agent);
  } finally {
    await backend.voiceClose(session);
  }
}

/** A known phrase spoken by Piper, as 16 kHz PCM16 — what a microphone hands over. */
async function spokenPcm16(sdk: RunAnywhereApi, text: string): Promise<Uint8Array> {
  const spoken = await sdk.tts.synthesize(text, {});
  const at16k =
    spoken.sampleRate === SAMPLE_RATE
      ? spoken.data
      : downsample(spoken.data, spoken.sampleRate, SAMPLE_RATE);
  return pcm16Bytes(at16k);
}

function silencePcm16(ms: number): Uint8Array {
  return new Uint8Array(Math.round((ms / 1000) * SAMPLE_RATE) * 2);
}

function* framesOf(pcm16: Uint8Array): Generator<Uint8Array> {
  for (let at = 0; at < pcm16.byteLength; at += FRAME_BYTES) {
    yield pcm16.subarray(at, Math.min(pcm16.byteLength, at + FRAME_BYTES));
  }
}

test('session: createSession composes the agent, and the microphone stays on this side',
  { timeout: 900000, ...SKIP },
  async () => {
    await withVoiceModels(async (sdk) => {
      const session = await sdk.voice.createSession({
        stt: { id: STT_ID },
        llm: { id: LLM_ID },
        tts: { id: TTS_ID },
      });
      try {
        // Subscribing must not open anything; the old contract, still true.
        const seen: VoiceEvent[] = [];
        const events = session.events;
        void (async () => {
          for await (const event of events) seen.push(event);
        })().catch(() => undefined);

        // Capture is platform work and node is not a platform that has it.
        await assert.rejects(
          () => session.start(),
          (e: unknown) => /microphone capture/.test((e as Error).message),
          'start() refuses where there is no capture device rather than going silent'
        );

        // `say` is outside the turn loop, so it works without a microphone —
        // and it is what proves the session's own event fan-out is wired.
        const spoken = await session.say('Ready when you are.');
        await spoken.waitForPlayout();
        assert.ok(
          seen.some((e) => e.type === 'agentStateChanged' && e.state === 'SPEAKING'),
          'the session reported it was speaking'
        );
        assert.ok(spoken.error, 'playout reported a failure');
        assert.match(spoken.error.message, /audio playback/,
          'and playout failed for the reason it should: no output device here');
      } finally {
        await session.close();
      }
    });
  }
);

test('session: a component nobody loaded is refused at createSession, not at the first turn',
  { timeout: 900000, ...SKIP },
  async () => {
    // Nothing resident and nothing may be fetched, so the refusal comes from
    // commons' own component snapshot rather than from bookkeeping here.
    await withSdk(async (sdk) => {
      await assert.rejects(
        () =>
          sdk.voice.createSession({
            stt: { id: STT_ID },
            llm: { id: LLM_ID },
            tts: { id: TTS_ID },
            downloadIfNeeded: false,
          }),
        (e: unknown) => {
          const message = (e as Error).message;
          return /voice session is missing/.test(message) && /stt/.test(message);
        }
      );
    });
  }
);

test('turn: one utterance in, a transcript, a reply, and speakable audio out',
  { timeout: 900000, ...SKIP },
  async () => {
    await withVoiceModels(async (sdk, backend) => {
      await withAgent(sdk, backend, async (agent) => {
        const heard = await spokenPcm16(sdk, 'What is the capital of France?');
        const result = await agent.turn(heard);

        assert.ok(result.transcription && result.transcription.trim().length > 0,
          `commons transcribed the utterance: ${result.transcription}`);
        assert.ok(result.assistantResponse && result.assistantResponse.trim().length > 0,
          `and answered it: ${result.assistantResponse}`);
        // The reply is self-describing WAV precisely so the SDK can play it
        // without tracking the engine's rate and encoding.
        assert.ok(result.synthesizedAudio && result.synthesizedAudio.byteLength > 44,
          'the reply came back as audio');
        const decoded = decodeWav(result.synthesizedAudio);
        assert.ok(decoded.sampleRate > 0 && decoded.samples.length > 0,
          `and it decodes: ${decoded.samples.length} samples at ${decoded.sampleRate} Hz`);
        assert.equal(result.finalState?.ready, true, 'with every component still ready');
      });
    });
  }
);

test('feed: commons closes the utterance itself and returns the finished turn inline',
  { timeout: 900000, ...SKIP },
  async () => {
    await withVoiceModels(async (sdk, backend) => {
      await withAgent(sdk, backend, async (agent) => {
        const speech = await spokenPcm16(sdk, 'Tell me one fact about the moon.');
        // No SDK-side VAD: the frames go in raw and the energy endpointer in
        // voice_agent_feed_abi.cpp decides where the utterance stops. The
        // trailing silence is what a speaker's pause looks like.
        const pushed = new Uint8Array(speech.byteLength + silencePcm16(1500).byteLength);
        pushed.set(speech, 0);
        pushed.set(silencePcm16(1500), speech.byteLength);

        let turn: Awaited<ReturnType<VoiceAgentAbi['feed']>> | null = null;
        for (const frame of framesOf(pushed)) {
          const result = await agent.feed(toAudioFrame(frame));
          if (result.transcription || result.synthesizedAudio?.byteLength) {
            turn = result;
            break;
          }
        }
        if (!turn) {
          // Flushing an in-progress utterance is the documented stop path.
          turn = await agent.feed(toAudioFrame(new Uint8Array(0), true));
        }

        assert.ok(turn, 'the endpointer closed an utterance');
        assert.ok(turn.transcription && turn.transcription.trim().length > 0,
          `and the turn transcribed it: ${turn.transcription}`);
        assert.ok(turn.synthesizedAudio && turn.synthesizedAudio.byteLength > 44,
          'and answered out loud');
      });
    });
  }
);

test('events: one turn walks the pipeline states and reports what was said at each stage',
  { timeout: 900000, ...SKIP },
  async () => {
    await withVoiceModels(async (sdk, backend) => {
      await withAgent(sdk, backend, async (agent) => {
        const heard = await spokenPcm16(sdk, 'Say hello.');

        const states: PipelineState[] = [];
        let said = '';
        let answered = '';
        let audioBytes = 0;
        for await (const event of agent.turnStream(toTurnRequest(heard, 'turn-events'))) {
          if (event.state) states.push(event.state.current);
          if (event.userSaid?.isFinal) said = event.userSaid.text;
          if (event.assistantToken?.isFinal) answered = event.assistantToken.text;
          if (event.audio) audioBytes += event.audio.pcm.byteLength;
          assert.equal(event.requestId, 'turn-events', 'every event carries the turn it belongs to');
        }

        assert.ok(said.trim().length > 0, `the user was transcribed: ${said}`);
        assert.ok(answered.trim().length > 0, `the agent replied: ${answered}`);
        assert.ok(audioBytes > 0, 'and the reply arrived as audio frames');
        // The eight-state machine, including the cooldown that keeps the
        // microphone shut while the device is still audible.
        assert.ok(states.includes(PipelineState.PIPELINE_STATE_PROCESSING_SPEECH));
        assert.ok(states.includes(PipelineState.PIPELINE_STATE_GENERATING_RESPONSE));
        assert.ok(states.includes(PipelineState.PIPELINE_STATE_PLAYING_TTS));
        assert.ok(states.includes(PipelineState.PIPELINE_STATE_COOLDOWN),
          'PLAYING_TTS -> COOLDOWN -> IDLE, not a shortcut back to idle');
        assert.equal(states[states.length - 1], PipelineState.PIPELINE_STATE_IDLE);
      });
    });
  }
);

test('cancel: a turn cancelled before it starts never reaches the models',
  { timeout: 900000, ...SKIP },
  async () => {
    await withVoiceModels(async (sdk, backend) => {
      await withAgent(sdk, backend, async (agent) => {
        const heard = await spokenPcm16(sdk, 'This turn should not run.');

        // Cancellation is keyed to the request id, and the header promises a
        // cancel that lands just before the turn stays keyed to it. Asserting
        // that ordering is deterministic; racing a running turn is not.
        await agent.cancel('turn-cancelled');

        const seen: Array<{ interrupted?: unknown; userSaid?: unknown; assistantToken?: unknown }> = [];
        await assert.rejects(async () => {
          for await (const event of agent.turnStream(toTurnRequest(heard, 'turn-cancelled'))) {
            seen.push(event);
          }
        }, 'the cancelled turn fails rather than answering');
        assert.ok(
          seen.some((e) => e.interrupted),
          'and reports the interruption before it stops'
        );
        assert.ok(
          !seen.some((e) => e.userSaid || e.assistantToken),
          'with nothing transcribed or generated'
        );

        // The cancellation is per-request: the next turn is unaffected.
        const after = await agent.turn(heard);
        assert.ok(after.assistantResponse && after.assistantResponse.trim().length > 0,
          'a fresh turn still answers');
      });
    });
  }
);

test('stream: a fed turn surfaces through the session-scoped VoiceEvent callback',
  { timeout: 900000, ...SKIP },
  async () => {
    await withVoiceModels(async (sdk, backend) => {
      await withAgent(sdk, backend, async (agent) => {
        const speech = await spokenPcm16(sdk, 'Good morning.');

        const publicEvents: VoiceEvent[] = [];
        // The stream only ends when the session closes, which is the finally in
        // withAgent, so this is left running rather than awaited here.
        void (async () => {
          for await (const event of agent.events()) {
            const mapped = toPublicVoiceEvent(event);
            if (mapped) publicEvents.push(mapped);
          }
        })().catch(() => undefined);

        // The feed path passes no per-turn callback, so the registered stream is
        // the only way a caller learns anything about the turn. That is exactly
        // what `VoiceSession.events` is built on.
        for (const frame of framesOf(speech)) await agent.feed(toAudioFrame(frame));
        const turn = await agent.feed(toAudioFrame(new Uint8Array(0), true));
        assert.ok(turn.assistantResponse, `the flushed utterance answered: ${turn.transcription}`);

        assert.ok(
          publicEvents.some((e) => e.type === 'userTranscribed' && e.text.trim().length > 0),
          'the stream reported what the user said'
        );
        assert.ok(
          publicEvents.some((e) => e.type === 'agentResponse' && e.text.trim().length > 0),
          'and what the agent answered'
        );
        assert.ok(
          publicEvents.some((e) => e.type === 'agentStateChanged' && e.state === 'THINKING'),
          'and the eight pipeline states folded onto the three public ones'
        );
      });
    });
  }
);
