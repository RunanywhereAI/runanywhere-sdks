// voice.js — a full voice turn: audio in -> STT -> LLM -> TTS -> audio out,
// using the SDK's own audio helpers (decodeWav / downsample / pcm16Bytes /
// encodeWav) instead of hand-rolled WAV code.
//   node examples/voice.js
const path = require('path');
const fs = require('fs');
const os = require('os');
const { RunAnywhere, decodeWav, downsample, pcm16Bytes, encodeWav } = require('../dist');

const MODELS = process.env.RA_MODELS || 'e:\\codes\\qual\\models';

// Read a WAV file and return 16 kHz mono PCM16 bytes (what STT.transcribe wants).
function wavTo16kPcm(file) {
  const { sampleRate, samples } = decodeWav(fs.readFileSync(file));
  const mono16k = downsample(samples, sampleRate, 16000);
  return pcm16Bytes(mono16k);
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

  const pcm = wavTo16kPcm(path.join(MODELS, 'sherpa-onnx-whisper-tiny.en', 'test_wavs', '0.wav'));
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
  fs.writeFileSync(outWav, encodeWav(turn.audio.samples, turn.audio.sampleRate));
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
