// RunAnywhere demo (renderer). Each feature is a function used by BOTH the UI
// buttons and the headless self-test, so the self-test exercises real code paths.
const ra = window.runanywhere;
const $ = (id) => document.getElementById(id);
const setStatus = (s) => ($('status').textContent = s);

const TOOLS = [
  {
    name: 'get_weather',
    description: 'Get the current weather for a city',
    parameters: {
      type: 'object',
      properties: { city: { type: 'string' }, unit: { type: 'string', enum: ['celsius', 'fahrenheit'] } },
      required: ['city', 'unit'],
    },
  },
  {
    name: 'set_timer',
    description: 'Start a countdown timer',
    parameters: {
      type: 'object',
      properties: { seconds: { type: 'integer' }, label: { type: 'string' } },
      required: ['seconds', 'label'],
    },
  },
];

// Lazily-loaded model handles (shared across a session).
const models = {};
const load = async (key, fn) => (models[key] ??= await fn());
const llm = () => load('llm', () => ra.loadLLM('qwen2.5-0.5b'));
const embedder = () => load('embedder', () => ra.loadEmbedder('minilm'));
const vlm = () => load('vlm', () => ra.loadVLM('smolvlm-256m'));
const stt = () => load('stt', () => ra.loadSTT('whisper-tiny'));
const tts = () => load('tts', () => ra.loadTTS('piper-lessac'));

// ---- feature functions (shared by UI + self-test) ----
const history = [];
function buildPrompt() {
  let p = 'You are a concise, friendly assistant. Answer in one short sentence.\n\n';
  for (const m of history) p += (m.role === 'user' ? 'User: ' : 'Assistant: ') + m.content + '\n';
  return p + 'Assistant:';
}
async function runChat(text, onToken) {
  const h = await llm();
  history.push({ role: 'user', content: text });
  let reply = '';
  await ra.generate(h, buildPrompt(), (t) => { reply += t; onToken?.(t); });
  reply = reply.trim();
  history.push({ role: 'assistant', content: reply });
  return reply;
}
async function runStructured(text) {
  const h = await llm();
  return ra.generateObject(h, `Extract the person as JSON. Text: "${text}"`, {
    type: 'object',
    properties: {
      name: { type: 'string' },
      age: { type: 'integer' },
      interests: { type: 'array', items: { type: 'string' }, maxItems: 5 },
    },
    required: ['name', 'age', 'interests'],
  });
}
async function runTools(text) {
  const h = await llm();
  return ra.generateToolCall(h, text, TOOLS);
}
async function runEmbeddings(a, b) {
  const h = await embedder();
  const [ea, eb] = await Promise.all([ra.embed(h, a), ra.embed(h, b)]);
  let dot = 0, na = 0, nb = 0;
  for (let i = 0; i < ea.length; i++) { dot += ea[i] * eb[i]; na += ea[i] * ea[i]; nb += eb[i] * eb[i]; }
  return dot / (Math.sqrt(na) * Math.sqrt(nb) || 1);
}

// ---- tabs ----
document.querySelectorAll('nav button').forEach((b) => {
  b.addEventListener('click', () => {
    document.querySelectorAll('nav button').forEach((x) => x.classList.remove('active'));
    document.querySelectorAll('.panel').forEach((x) => x.classList.remove('active'));
    b.classList.add('active');
    $(b.dataset.tab).classList.add('active');
  });
});

// ---- UI wiring ----
function wireUi() {
  const send = async () => {
    const text = $('chatinput').value.trim();
    if (!text) return;
    $('chatinput').value = '';
    $('chatlog').innerHTML += `<div class="msg"><div class="who">you</div>${escape(text)}</div>`;
    const el = document.createElement('div');
    el.className = 'msg';
    el.innerHTML = '<div class="who">assistant</div><span></span>';
    $('chatlog').appendChild(el);
    setStatus('generating…');
    await runChat(text, (t) => { el.querySelector('span').textContent += t; });
    setStatus('ready');
  };
  $('chatsend').addEventListener('click', send);
  $('chatinput').addEventListener('keydown', (e) => { if (e.key === 'Enter') send(); });

  $('structgo').addEventListener('click', async () => {
    setStatus('extracting…');
    $('structout').textContent = '…';
    try { $('structout').textContent = JSON.stringify(await runStructured($('structtext').value), null, 2); }
    catch (e) { $('structout').textContent = 'error: ' + e.message; }
    setStatus('ready');
  });

  $('toolsgo').addEventListener('click', async () => {
    setStatus('choosing tool…');
    $('toolsout').textContent = '…';
    try { const c = await runTools($('toolstext').value); $('toolsout').textContent = `${c.name}(${JSON.stringify(c.arguments)})`; }
    catch (e) { $('toolsout').textContent = 'error: ' + e.message; }
    setStatus('ready');
  });

  $('embgo').addEventListener('click', async () => {
    setStatus('embedding…');
    $('embout').textContent = '…';
    try { $('embout').textContent = 'cosine similarity: ' + (await runEmbeddings($('emba').value, $('embb').value)).toFixed(3); }
    catch (e) { $('embout').textContent = 'error: ' + e.message; }
    setStatus('ready');
  });

  const vf = $('visionfile');
  vf.addEventListener('change', () => ($('visiongo').disabled = !vf.files.length));
  $('visiongo').addEventListener('click', async () => {
    const file = vf.files[0];
    if (!file) return;
    setStatus('captioning…');
    $('visionout').textContent = '…';
    try {
      const h = await vlm();
      let cap = '';
      await ra.generateVlm(h, file.path, 'Describe this image in one sentence.', (t) => { cap += t; $('visionout').textContent = cap; });
    } catch (e) { $('visionout').textContent = 'error: ' + e.message; }
    setStatus('ready');
  });

  wireVoice();
}

// ---- voice (inline Web Audio capture/playback) ----
function wireVoice() {
  let cap = null;
  const btn = $('voicebtn');
  const begin = async () => {
    setStatus('listening…');
    const stream = await navigator.mediaDevices.getUserMedia({ audio: { channelCount: 1 } });
    const ctx = new AudioContext();
    const src = ctx.createMediaStreamSource(stream);
    const node = ctx.createScriptProcessor(4096, 1, 1);
    const chunks = [];
    node.onaudioprocess = (e) => chunks.push(new Float32Array(e.inputBuffer.getChannelData(0)));
    src.connect(node); node.connect(ctx.destination);
    cap = { stream, ctx, node, chunks, rate: ctx.sampleRate };
  };
  const end = async () => {
    if (!cap) return;
    const { stream, ctx, node, chunks, rate } = cap; cap = null;
    node.disconnect(); stream.getTracks().forEach((t) => t.stop()); ctx.close();
    setStatus('thinking…');
    let total = 0; for (const c of chunks) total += c.length;
    const merged = new Float32Array(total); let o = 0; for (const c of chunks) { merged.set(c, o); o += c.length; }
    const ratio = rate / 16000, outLen = Math.floor(merged.length / ratio), pcm = new Int16Array(outLen);
    for (let i = 0; i < outLen; i++) { const s = Math.max(-1, Math.min(1, merged[Math.floor(i * ratio)])); pcm[i] = Math.max(-32768, Math.min(32767, Math.round(s * 32768))); }
    const heard = await ra.transcribe(await stt(), new Uint8Array(pcm.buffer));
    $('voiceheard').textContent = heard;
    let reply = ''; $('voicereply').textContent = '';
    await ra.generate(await llm(), `You are concise. Reply in one sentence.\n\n${heard}`, (t) => { reply += t; $('voicereply').textContent = reply; });
    const audio = await ra.synthesize(await tts(), reply.trim());
    setStatus('speaking…');
    const pctx = new AudioContext();
    const buf = pctx.createBuffer(1, audio.samples.length, audio.sampleRate);
    buf.getChannelData(0).set(audio.samples);
    const s = pctx.createBufferSource(); s.buffer = buf; s.connect(pctx.destination);
    await new Promise((r) => { s.onended = () => { pctx.close(); r(); }; s.start(); });
    setStatus('ready');
  };
  btn.addEventListener('mousedown', begin);
  btn.addEventListener('mouseup', end);
  btn.addEventListener('mouseleave', end);
}

function escape(s) { return s.replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c])); }

// ---- headless self-test ----
async function selfTest() {
  const log = (s) => window.runanywhereTest.log(s + '\n');
  try {
    log('[selftest] commons ' + (await ra.version()));

    const reply = await runChat('Say hello in one short sentence.');
    if (!reply || reply.length < 2) throw new Error('empty chat reply');
    log('[selftest] chat OK: ' + JSON.stringify(reply.slice(0, 70)));

    const obj = await runStructured('Marie Curie was a 66 year old Polish physicist who loved chemistry.');
    if (typeof obj.name !== 'string' || typeof obj.age !== 'number' || !Array.isArray(obj.interests)) {
      throw new Error('structured shape wrong: ' + JSON.stringify(obj));
    }
    log('[selftest] structured OK: ' + JSON.stringify(obj));

    const call = await runTools('What is the weather in Tokyo in celsius?');
    if (!TOOLS.some((t) => t.name === call.name)) throw new Error('bad tool: ' + JSON.stringify(call));
    log('[selftest] tools OK: ' + call.name + ' ' + JSON.stringify(call.arguments));

    const close = await runEmbeddings('a cat sat on the mat', 'a kitten rested on the rug');
    const far = await runEmbeddings('a cat sat on the mat', 'the stock market fell today');
    if (!(close > far)) throw new Error(`embedding ordering wrong: ${close} !> ${far}`);
    log(`[selftest] embeddings OK: close=${close.toFixed(3)} far=${far.toFixed(3)}`);

    log('[selftest] ALL PASS');
    window.runanywhereTest.done(true);
  } catch (e) {
    log('[selftest] FAIL: ' + (e && e.message));
    window.runanywhereTest.done(false);
  }
}

const IS_SELFTEST = new URLSearchParams(location.search).get('selftest') === '1';
(async () => {
  await ra.ready();
  await ra.initialize();
  setStatus('ready');
  if (IS_SELFTEST) {
    setStatus('self-test…');
    await selfTest();
  } else {
    wireUi();
  }
})().catch((e) => {
  setStatus('error: ' + (e && e.message));
  console.error(e);
  // In self-test mode, report failure instead of hanging until the timeout.
  if (IS_SELFTEST) {
    try {
      window.runanywhereTest.log('[selftest] STARTUP ERROR: ' + (e && e.message) + '\n');
      window.runanywhereTest.done(false);
    } catch { /* ignore */ }
  }
});
