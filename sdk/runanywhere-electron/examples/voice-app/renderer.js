// Voice demo (renderer). Captures the mic with Web Audio, runs STT -> LLM -> TTS
// over window.runanywhere (the isolated utility host), and plays the reply.
//
// This renderer uses contextIsolation (no Node), so it inlines the mic capture /
// playback with plain Web Audio. An app that BUNDLES the SDK into its renderer
// (webpack/vite) can instead import { MicRecorder, SpeakerPlayer } from
// '@runanywhere/electron' — they do exactly what capture()/play() do below.
const ra = window.runanywhere;
const $ = (id) => document.getElementById(id);

// --- inline mic capture -> 16 kHz mono PCM16 bytes (see SDK MicRecorder) ---
let capture = null;
async function startCapture() {
  const stream = await navigator.mediaDevices.getUserMedia({ audio: { channelCount: 1 } });
  const ctx = new AudioContext();
  const source = ctx.createMediaStreamSource(stream);
  const node = ctx.createScriptProcessor(4096, 1, 1);
  const chunks = [];
  node.onaudioprocess = (e) => chunks.push(new Float32Array(e.inputBuffer.getChannelData(0)));
  source.connect(node);
  node.connect(ctx.destination);
  capture = { stream, ctx, node, chunks, inRate: ctx.sampleRate };
}
function stopCapture() {
  const { stream, ctx, node, chunks, inRate } = capture;
  node.disconnect();
  stream.getTracks().forEach((t) => t.stop());
  ctx.close();
  capture = null;
  let total = 0;
  for (const c of chunks) total += c.length;
  const merged = new Float32Array(total);
  let off = 0;
  for (const c of chunks) { merged.set(c, off); off += c.length; }
  // downsample to 16 kHz + convert to little-endian int16 bytes.
  const ratio = inRate / 16000;
  const outLen = Math.floor(merged.length / ratio);
  const pcm = new Int16Array(outLen);
  for (let i = 0; i < outLen; i++) {
    const s = Math.max(-1, Math.min(1, merged[Math.floor(i * ratio)]));
    pcm[i] = Math.max(-32768, Math.min(32767, Math.round(s * 32768)));
  }
  return new Uint8Array(pcm.buffer);
}

// --- inline playback of float32 PCM (see SDK SpeakerPlayer) ---
function play(samples, sampleRate) {
  const ctx = new AudioContext();
  const buffer = ctx.createBuffer(1, samples.length, sampleRate);
  buffer.getChannelData(0).set(samples);
  const src = ctx.createBufferSource();
  src.buffer = buffer;
  src.connect(ctx.destination);
  return new Promise((r) => { src.onended = () => { ctx.close(); r(); }; src.start(); });
}

(async () => {
  await ra.ready();
  await ra.initialize();
  const [stt, llm, tts] = await Promise.all([
    ra.loadSTT('whisper-tiny'),
    ra.loadLLM('smollm2-135m'),
    ra.loadTTS('piper-lessac'),
  ]);
  $('status').textContent = 'ready — hold the button and speak';
  const btn = $('hold');
  btn.disabled = false;

  const begin = async () => { $('status').textContent = 'listening…'; await startCapture(); };
  const end = async () => {
    if (!capture) return;
    const pcm = stopCapture();
    $('status').textContent = 'thinking…';
    const heard = await ra.transcribe(stt, pcm);
    $('heard').textContent = heard;
    let reply = '';
    $('reply').textContent = '';
    await ra.generate(llm, `You are concise. Reply in one sentence.\n\n${heard}`, (t) => {
      reply += t;
      $('reply').textContent = reply;
    });
    const audio = await ra.synthesize(tts, reply.trim());
    $('status').textContent = 'speaking…';
    await play(audio.samples, audio.sampleRate);
    $('status').textContent = 'ready — hold the button and speak';
  };

  btn.addEventListener('mousedown', begin);
  btn.addEventListener('mouseup', end);
  btn.addEventListener('mouseleave', end);
})().catch((e) => {
  $('status').textContent = 'error: ' + e.message;
  console.error(e);
});
