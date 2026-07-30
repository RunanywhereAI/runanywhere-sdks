// RunAnywhere demo (renderer) — a product-grade sample built entirely on the v3
// SDK surface: window.runanywhere is the same object shape the main process gets
// from createRunAnywhere(), so every call here (llm.generateStream, models.download,
// rag.open, voice.createSession) is the documented public API and nothing else.
//
// Two Electron-specific rules the demo follows:
//  1. contextBridge does not carry symbol-keyed properties, so a bridged stream is
//     consumed through next() (see each()) rather than for-await.
//  2. Model files, handles, and inference all live in the utility host; the page
//     only ever sees ids, plain results, and streams.
const ra = window.runanywhere;
const store = window.demoStore;
const $ = (id) => document.getElementById(id);
const setStatus = (s) => { $('status').textContent = s; $('statuswrap').classList.toggle('busy', s !== 'ready'); };
// Escape quotes too: md() builds an <a href="…"> from (escaped) text, so an
// unescaped " in a link URL would break out of the attribute.
const escapeHtml = (s) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const fmtSize = (b) => (b > 1e9 ? (b / 1e9).toFixed(1) + ' GB' : b > 1e6 ? (b / 1e6).toFixed(0) + ' MB' : (b / 1e3).toFixed(0) + ' KB');

// Consume a bridged AsyncIterable. contextBridge drops Symbol.asyncIterator, so
// the page drives next() itself; breaking out calls return() to cancel the request.
async function each(stream, fn) {
  try {
    for (;;) {
      const step = await stream.next();
      if (step.done) return;
      await fn(step.value);
    }
  } catch (e) {
    if (stream.return) await stream.return();
    throw e;
  }
}

// The models this demo reaches for, by modality. Generation verbs auto-load (and
// download) whatever `options.model` names, so nothing here is pre-loaded.
const MODELS = { llm: 'qwen2.5-0.5b', vlm: 'smolvlm-256m', embedder: 'minilm', stt: 'whisper-tiny', tts: 'piper-lessac' };
// Loading another language model from the Models tab makes it the chat model.
let activeLlm = MODELS.llm;

const TOOLS = [
  { name: 'get_weather', description: 'Get the current weather for a city', parameters: { type: 'object', properties: { city: { type: 'string' }, unit: { type: 'string', enum: ['celsius', 'fahrenheit'] } }, required: ['city', 'unit'] } },
  { name: 'set_timer', description: 'Start a countdown timer', parameters: { type: 'object', properties: { seconds: { type: 'integer' }, label: { type: 'string' } }, required: ['seconds', 'label'] } },
];
// Executors run in the page. The SDK calls them through the contextBridge proxy,
// so a tool cannot be executed inside the utility host — see the README note.
const EXECUTORS = {
  get_weather: ({ city, unit }) => ({ city, unit, temperature: unit === 'fahrenheit' ? 68 : 20, sky: 'clear' }),
  set_timer: ({ seconds, label }) => ({ started: true, seconds, label }),
};

// ---- settings + conversations + custom models (persisted via demoStore) ----
let settings = { systemPrompt: 'You are a concise, helpful assistant.', temperature: 0.7, maxTokens: 256, reasoning: false };
let conversations = [];
let activeId = null;
let nextConvId = 1;
let customModels = []; // [{ id, source, category, label }]

// Every generation request in the demo is shaped here, so the spec option names
// (maxOutputTokens, reasoning.includeInOutput) live in exactly one place.
function genOptions(extra = {}) {
  return {
    model: activeLlm,
    temperature: settings.temperature,
    maxOutputTokens: settings.maxTokens,
    systemPrompt: settings.systemPrompt,
    reasoning: settings.reasoning ? { mode: 'ON', includeInOutput: true } : { mode: 'OFF' },
    // Registered tools apply to every request by default. This demo keeps tool
    // calling on the Tools tab, so chat and RAG opt out and skip the extra
    // selection round; runTools() overrides this with REQUIRED.
    toolChoice: 'NONE',
    ...extra,
  };
}

// ---- minimal, XSS-safe markdown (escape first, then format) ----
// Code blocks are stashed behind private-use sentinels () so inline
// formatting doesn't touch them; they're restored last. (Private-use chars keep
// the source ASCII and avoid embedding NUL bytes.)
function md(text) {
  const blocks = [];
  let s = escapeHtml(text).replace(/```([\s\S]*?)```/g, (_m, c) => { blocks.push(c); return `${blocks.length - 1}`; });
  s = s.replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/(^|[^*])\*([^*]+)\*/g, '$1<em>$2</em>')
    .replace(/\[([^\]]+)\]\((https?:[^)]+)\)/g, '<a href="$2">$1</a>');
  s = s.split(/\n{2,}/).map((p) => {
    // A standalone code block: emit <pre> at the top level, not nested in a <p>.
    const t = p.trim();
    if (/^\d+$/.test(t)) return t.replace(/(\d+)/g, (_m, i) => `<pre><code>${blocks[+i]}</code></pre>`);
    // A list: only when every non-blank line is a bullet (don't fold stray lines).
    const lines = p.split('\n');
    if (lines.some((l) => /^\s*[-*] /.test(l)) && lines.every((l) => !l.trim() || /^\s*[-*] /.test(l))) {
      return '<ul>' + lines.filter((l) => l.trim()).map((l) => '<li>' + l.replace(/^\s*[-*] /, '') + '</li>').join('') + '</ul>';
    }
    if (/^#{1,3} /.test(p)) { const n = p.match(/^#+/)[0].length; return `<h${n + 2}>${p.replace(/^#+ /, '')}</h${n + 2}>`; }
    return '<p>' + p.replace(/\n/g, '<br>') + '</p>';
  }).join('');
  return s.replace(/(\d+)/g, (_m, i) => `<pre><code>${blocks[+i]}</code></pre>`);
}

function reasoningHtml(thinking, open) {
  if (!thinking) return '';
  return `<details class="reason"${open ? ' open' : ''}><summary>💭 Reasoning</summary><div class="reasonbody">${escapeHtml(thinking)}</div></details>`;
}

// The stream tags each token TEXT or THOUGHT, so reasoning and answer arrive
// already separated. Messages persisted by an older build still hold raw thinking
// tags in `content`, so those get split on read.
function assistantHtml(m, streaming) {
  let { content, thinking } = m;
  if (!thinking && content && content.includes('<think>')) {
    const split = ra.splitThinking(content);
    content = split.response;
    thinking = split.thinking;
  }
  return reasoningHtml(thinking, streaming && !content) + md(content || (streaming ? '…' : ''));
}

// ---- conversations ----
const activeConv = () => conversations.find((c) => c.id === activeId);
function newConversation() {
  const conv = { id: nextConvId++, title: '', messages: [] };
  conversations.unshift(conv);
  activeId = conv.id;
  renderSidebar();
  renderChat();
  return conv;
}
function persist() {
  try { store.saveConversations({ nextConvId, conversations }); } catch { /* demo store optional */ }
}
function renderSidebar() {
  const el = $('convlist'); el.innerHTML = '';
  for (const c of conversations) {
    const d = document.createElement('div');
    d.className = 'conv' + (c.id === activeId ? ' active' : '');
    d.innerHTML = `<span class="title">${escapeHtml(c.title || 'New chat')}</span><span class="del">✕</span>`;
    d.querySelector('.title').onclick = () => { activeId = c.id; renderSidebar(); renderChat(); showTab('chat'); };
    d.querySelector('.del').onclick = (e) => { e.stopPropagation(); conversations = conversations.filter((x) => x.id !== c.id); if (activeId === c.id) activeId = conversations[0] ? conversations[0].id : null; persist(); renderSidebar(); renderChat(); };
    el.appendChild(d);
  }
}
// Conversations persisted by an older build carry the pre-v3 metric names, so a
// bubble renders whichever fields it actually has instead of throwing on load.
function metricsHtml(m) {
  if (!m) return '';
  const tokens = m.outputTokens ?? m.tokens;
  const tps = m.tokensPerSecond ?? m.tps;
  const ttft = m.timeToFirstTokenMs ?? m.ttft;
  const bits = [];
  if (typeof tokens === 'number') bits.push(`${tokens} tokens`);
  if (typeof tps === 'number') bits.push(`${tps.toFixed(1)} tok/s`);
  if (typeof ttft === 'number') bits.push(`TTFT ${Math.round(ttft)}ms`);
  if (m.model) bits.push(escapeHtml(m.model));
  return bits.length ? `<div class="metrics">⚡ ${bits.join(' · ')}</div>` : '';
}

function bubbleHtml(m) {
  const body = m.role === 'assistant' ? assistantHtml(m) : escapeHtml(m.content);
  const metrics = metricsHtml(m.metrics);
  const av = m.role === 'assistant' ? '✦' : 'U';
  const who = m.role === 'assistant' ? 'RunAnywhere' : 'You';
  return `<div class="msg ${m.role}"><div class="av">${av}</div><div class="col"><div class="who">${who}</div><div class="bubble">${body}</div>${metrics}</div></div>`;
}
const SUGGESTIONS = [
  ['Explain on-device AI', 'Explain on-device AI in one sentence.'],
  ['Write a haiku', 'Write a haiku about the ocean.'],
  ['Dinner ideas', 'Give me three quick dinner ideas with chicken.'],
];
function emptyStateHtml() {
  const chips = SUGGESTIONS.map(([l], i) => `<button class="chip" data-i="${i}">${escapeHtml(l)}</button>`).join('');
  return `<div class="empty">
    <div class="logo"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2 4 7v10l8 5 8-5V7z"/><path d="m8 12 3 3 5-6"/></svg></div>
    <h3>On-device AI, privately</h3>
    <p>Ask anything — everything runs locally on your machine, nothing leaves your device.</p>
    <div class="chips">${chips}</div>
  </div>`;
}
function renderChat() {
  const conv = activeConv();
  if (conv && conv.messages.length) {
    $('chatlog').innerHTML = '<div class="thread">' + conv.messages.map(bubbleHtml).join('') + '</div>';
  } else {
    $('chatlog').innerHTML = emptyStateHtml();
    document.querySelectorAll('.chip').forEach((c) => c.addEventListener('click', () => {
      $('chatinput').value = SUGGESTIONS[+c.dataset.i][1];
      sendChat();
    }));
  }
  $('chatlog').scrollTop = $('chatlog').scrollHeight;
}

// The conversation goes to the SDK as ChatMessages; prompt assembly (chat
// template, history alternation) is the SDK's job, not the app's.
function chatMessages(prior, userText) {
  const msgs = prior.map((m) => ({ role: m.role, content: m.content }));
  msgs.push({ role: 'user', content: userText });
  return msgs;
}

let generating = false;
async function sendChat() {
  if (generating) return;
  const text = $('chatinput').value.trim();
  if (!text) return;
  generating = true;
  $('chatsend').disabled = true;
  $('chatinput').value = '';
  const conv = activeConv() || newConversation();
  const prior = conv.messages.filter((m) => m.content);
  const messages = chatMessages(prior, text);
  conv.messages.push({ role: 'user', content: text });
  const asst = { role: 'assistant', content: '', thinking: '' };
  conv.messages.push(asst);
  if (!conv.title) { conv.title = text.slice(0, 40); renderSidebar(); }
  renderChat();
  const bubble = [...$('chatlog').querySelectorAll('.msg.assistant .bubble')].pop();
  bubble.classList.add('streaming');
  setStatus('generating…');
  try {
    await each(ra.llm.generateStream(messages, genOptions()), (e) => {
      if (e.type === 'token') {
        if (e.kind === 'THOUGHT') asst.thinking += e.text;
        else asst.content += e.text;
        bubble.innerHTML = assistantHtml(asst, true);
        $('chatlog').scrollTop = $('chatlog').scrollHeight;
      } else if (e.type === 'completed') {
        asst.content = e.result.text.trim();
        asst.thinking = e.result.thinkingText || '';
        asst.metrics = {
          outputTokens: e.result.outputTokens,
          tokensPerSecond: e.result.tokensPerSecond,
          timeToFirstTokenMs: e.result.timeToFirstTokenMs,
          model: e.result.model,
        };
      }
    });
    bubble.classList.remove('streaming');
    renderChat();
    persist();
  } catch (e) { asst.content = 'error: ' + e.message; renderChat(); }
  finally { generating = false; $('chatsend').disabled = false; setStatus('ready'); }
}

// ---- models panel ----
const CATEGORY_LABEL = {
  LANGUAGE: 'Language model',
  VISION: 'Vision-language',
  EMBEDDING: 'Embeddings',
  SPEECH_TO_TEXT: 'Speech-to-text',
  TEXT_TO_SPEECH: 'Text-to-speech',
};
const GROUP_ORDER = [
  ['LANGUAGE', 'Language models'],
  ['VISION', 'Vision-language'],
  ['SPEECH_TO_TEXT', 'Speech-to-text'],
  ['TEXT_TO_SPEECH', 'Text-to-speech'],
  ['EMBEDDING', 'Embeddings'],
];
const ADD_CATEGORY = { llm: 'LANGUAGE', vlm: 'VISION', embedder: 'EMBEDDING', stt: 'SPEECH_TO_TEXT', tts: 'TEXT_TO_SPEECH' };
const svg = (d) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${d}</svg>`;
const CATEGORY_ICON = {
  LANGUAGE: svg('<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>'),
  VISION: svg('<rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="9" cy="9" r="2"/><path d="m21 15-5-5L5 21"/>'),
  EMBEDDING: svg('<circle cx="5" cy="6" r="2"/><circle cx="19" cy="7" r="2"/><circle cx="12" cy="18" r="2"/><path d="M7 6h10M6 8l5 8M18 9l-5 7"/>'),
  SPEECH_TO_TEXT: svg('<rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 10a7 7 0 0 0 14 0M12 19v3"/>'),
  TEXT_TO_SPEECH: svg('<path d="M11 5 6 9H2v6h4l5 4zM19 9a5 5 0 0 1 0 6"/>'),
};
function mkbtn(label, fn) { const b = document.createElement('button'); b.className = 'btn ghost'; b.textContent = label; b.onclick = fn; return b; }
function persistCustom() { try { store.saveCustomModels(customModels); } catch { /* optional */ } }

// One model card over a ModelInfo. Load/unload/download all go through the
// models namespace, which owns slot eviction and download progress.
function buildCard(info, loadedId, custom) {
  const loaded = loadedId === info.id;
  const div = document.createElement('div'); div.className = 'model';
  const bits = [CATEGORY_LABEL[info.category] || info.category];
  if (info.parameters) bits.push(info.parameters);
  if (info.sizeBytes) bits.push(fmtSize(info.sizeBytes));
  div.innerHTML =
    '<div class="hd">' +
      `<span class="mi">${CATEGORY_ICON[info.category] || ''}</span>` +
      `<div style="min-width:0"><div class="name">${escapeHtml(info.name)}</div>` +
      `<div class="sub">${bits.join(' · ')}</div></div>` +
      '<span class="actions"></span>' +
    '</div><div class="bar" style="display:none"><div></div></div>';
  const actions = div.querySelector('.actions');
  if (loaded) { const b = document.createElement('span'); b.className = 'badge on'; b.textContent = 'loaded'; actions.appendChild(b); }
  if (!info.downloaded) {
    const dl = mkbtn('Download', async () => {
      dl.disabled = true; dl.textContent = 'Downloading…';
      const bar = div.querySelector('.bar'); bar.style.display = 'block';
      try {
        await each(ra.models.download(info.id), (e) => {
          if (e.type === 'progress') bar.firstElementChild.style.width = (e.percent || 0) + '%';
          else if (e.type === 'extracting') dl.textContent = 'Extracting…';
        });
      } catch (e) { dl.textContent = 'Failed'; dl.disabled = false; console.error(e); return; }
      renderModels();
    });
    actions.appendChild(dl);
  } else {
    const b = mkbtn(loaded ? 'Unload' : 'Load', async () => {
      const btns = actions.querySelectorAll('button');
      btns.forEach((x) => (x.disabled = true));
      b.textContent = loaded ? 'Unloading…' : 'Loading…';
      try {
        if (loaded) {
          await ra.models.unload(info.category);
        } else {
          // models.load evicts whatever else occupies the category's slot.
          await ra.models.load(info.id);
          if (info.category === 'LANGUAGE') activeLlm = info.id;
        }
      } catch (e) { b.textContent = 'Error'; btns.forEach((x) => (x.disabled = false)); console.error(e); return; }
      renderModels();
    });
    actions.appendChild(b);
  }
  if (custom) {
    actions.appendChild(mkbtn('Remove', async () => {
      if (loaded) { try { await ra.models.unload(info.category); } catch { /* already gone */ } }
      customModels = customModels.filter((m) => m.id !== info.id); persistCustom(); renderModels();
    }));
  }
  return div;
}

async function renderModels() {
  // Re-register the demo's own models each render so models.list() reports them
  // alongside the built-in catalog (the registry is per-session).
  for (const m of customModels) {
    try {
      await ra.models.register({ id: m.id, category: m.category, url: m.source, name: m.label });
    } catch (e) {
      console.warn('skipping saved model', m.id, e.message);
    }
  }
  const [all, state] = await Promise.all([ra.models.list(), ra.models.state()]);
  const loadedByCategory = {};
  for (const [category, info] of Object.entries(state.loaded)) loadedByCategory[category] = info.id;
  const customIds = new Set(customModels.map((m) => m.id));
  const el = $('modellist'); el.innerHTML = '';
  const byCategory = {};
  for (const info of all) {
    if (customIds.has(info.id)) continue;
    (byCategory[info.category] ??= []).push(info);
  }
  for (const [category, title] of GROUP_ORDER) {
    const items = byCategory[category];
    if (!items || !items.length) continue;
    const h = document.createElement('div'); h.className = 'mgroup'; h.textContent = title; el.appendChild(h);
    for (const info of items) el.appendChild(buildCard(info, loadedByCategory[info.category], false));
  }
  if (customModels.length) {
    const h = document.createElement('div'); h.className = 'mgroup'; h.textContent = 'Your models'; el.appendChild(h);
    for (const m of customModels) {
      const info = all.find((x) => x.id === m.id) || { id: m.id, name: m.label, category: m.category, downloaded: false, sizeBytes: 0 };
      el.appendChild(buildCard(info, loadedByCategory[info.category], true));
    }
  }
  const used = fmtSize(state.storageUsedBytes);
  const free = fmtSize(state.storageFreeBytes);
  const foot = document.createElement('p'); foot.className = 'muted'; foot.style.marginTop = '18px';
  foot.textContent = `${used} of models on disk · ${free} free`;
  el.appendChild(foot);
}

// Derive a friendly label from a source (repo / url / path). ':' means different
// things per format (URL scheme, Windows drive, HF :file), so handle each.
function deriveLabel(source) {
  let s = source;
  if (/^https?:\/\//i.test(s)) { try { s = new URL(s).pathname; } catch (_) { /* keep */ } }
  else { s = s.replace(/^[A-Za-z]:/, ''); const ci = s.indexOf(':'); if (ci >= 0) s = s.slice(0, ci); }
  s = s.replace(/[\\/]+$/, '');
  const seg = s.split(/[\\/]/).pop() || s;
  return seg.replace(/\.tar\.bz2$/i, '').replace(/\.(gguf|onnx|bin)$/i, '') || source;
}
// A URL or a HuggingFace owner/repo (vs a local path). Mirrors the SDK's
// isRemoteSource loosely — only to gate what the add-form allows.
function looksRemote(source) {
  if (/^https?:\/\//i.test(source)) return true;
  return /^[A-Za-z0-9][\w.-]*\/[A-Za-z0-9][\w.-]*$/.test(source) && !source.includes('\\') && !/^[A-Za-z]:/.test(source);
}
// Reflect the actual compute device (passed by main.js from the addon path).
function applyDeviceUi() {
  const device = new URLSearchParams(location.search).get('device') || 'cpu';
  if (device !== 'gpu') return;
  const sel = $('device');
  const gpuOpt = sel && sel.querySelector('option[value="gpu"]');
  if (gpuOpt) { gpuOpt.disabled = false; gpuOpt.textContent = 'GPU · CUDA'; }
  if (sel) sel.value = 'gpu';
  const pill = $('devicepill');
  if (pill) pill.title = 'Inference runs on the NVIDIA GPU (CUDA) — all model layers are offloaded.';
  const note = $('devicenote');
  if (note) note.innerHTML = 'Inference runs on the <b style="color:var(--fg)">NVIDIA GPU (CUDA)</b> — llama.cpp offloads all model layers to the GPU.';
}
function wireModels() {
  const hintEl = $('addhint');
  const hintHtml = hintEl.innerHTML;
  const flash = (msg) => { hintEl.textContent = msg; hintEl.style.color = 'var(--accent-lift)'; setTimeout(() => { hintEl.innerHTML = hintHtml; hintEl.style.color = ''; }, 2800); };
  const add = () => {
    const raw = $('addsrc').value.trim();
    if (!raw) return flash('Enter a HuggingFace repo, URL, or file path.');
    const source = raw.replace(/[\\/]+$/, ''); // normalize so owner/repo and owner/repo/ don't double
    const type = $('addtype').value;
    // The remote resolver is GGUF/single-file-only; speech/embedding models need a
    // directory or ONNX+vocab, so the SDK rejects remote STT/TTS/embedder. Block it
    // here too instead of letting the user download bytes that won't load.
    if (looksRemote(source) && (type === 'stt' || type === 'tts' || type === 'embedder')) {
      return flash('Speech/embedding models can’t be added from a URL or HF repo yet — use a built-in catalog entry or a local path.');
    }
    const id = 'custom:' + source;
    if (customModels.some((m) => m.id === id)) return flash('That model is already in your list.');
    customModels.unshift({ id, source, category: ADD_CATEGORY[type], label: deriveLabel(source) });
    persistCustom();
    $('addsrc').value = '';
    renderModels();
    flash('Added to “Your models” — hit Download to fetch it.');
  };
  $('addgo').addEventListener('click', add);
  $('addsrc').addEventListener('keydown', (e) => { if (e.key === 'Enter') add(); });
}

// ---- settings ----
function applySettingsToUi() {
  $('setsystem').value = settings.systemPrompt;
  $('settemp').value = settings.temperature; $('settempval').textContent = settings.temperature;
  $('setmax').value = settings.maxTokens;
  if ($('setreason')) $('setreason').checked = !!settings.reasoning;
}
async function saveSettings() {
  settings = { systemPrompt: $('setsystem').value, temperature: parseFloat($('settemp').value), maxTokens: parseInt($('setmax').value, 10) || 256, reasoning: !!($('setreason') && $('setreason').checked) };
  try { await store.saveSettings(settings); } catch { /* optional */ }
  $('setstatus').textContent = 'saved'; setTimeout(() => ($('setstatus').textContent = ''), 1500);
}

// ---- shared feature helpers (used by UI + self-test) ----
const PERSON_SCHEMA = {
  type: 'object',
  properties: { name: { type: 'string' }, age: { type: 'integer' }, interests: { type: 'array', items: { type: 'string' }, maxItems: 5 } },
  required: ['name', 'age', 'interests'],
};
async function runStructured(text) {
  return ra.llm.generateStructured(`Extract the person as JSON. Text: "${text}"`, PERSON_SCHEMA, genOptions());
}
// Tools are registered once at startup; REQUIRED makes the model pick one, and the
// SDK runs the executor and folds its result back into the loop.
async function runTools(text) {
  const result = await ra.llm.generate(text, genOptions({ toolChoice: 'REQUIRED' }));
  if (!result.toolCalls.length) throw new Error('the model did not call a tool');
  return result.toolCalls[0];
}
async function runEmbeddings(a, b) {
  await ra.models.load(MODELS.embedder);
  const [ea, eb] = await ra.embeddings.embed([a, b]);
  let dot = 0, na = 0, nb = 0;
  for (let i = 0; i < ea.vector.length; i++) { dot += ea.vector[i] * eb.vector[i]; na += ea.vector[i] ** 2; nb += eb.vector[i] ** 2; }
  return dot / (Math.sqrt(na) * Math.sqrt(nb) || 1);
}
async function runVision(imagePath, onToken) {
  let caption = '';
  await each(
    ra.vlm.generateStream(ra.image.file(imagePath), 'Describe this image in one sentence.', { model: MODELS.vlm, maxOutputTokens: 64 }),
    (e) => { if (e.type === 'token') { caption += e.text; onToken?.(e.text); } }
  );
  return caption.trim();
}
async function runSecure(key, value) {
  await ra.secure.set(key, value);
  const got = await ra.secure.get(key);
  await ra.secure.delete(key);
  return got;
}
// A synthetic tone against silence, so the VAD self-test needs no microphone.
async function runVad() {
  const samples = new Float32Array(16000 * 2);
  for (let i = 16000 * 0.5; i < 16000 * 1.2; i++) samples[i] = 0.5 * Math.sin((2 * Math.PI * 300 * i) / 16000);
  const r = await ra.vad.detect(ra.audio.float32(samples, 16000), { activationThreshold: 0.015 });
  return r;
}

// ---- RAG (Knowledge tab) ----
// Lazy singleton: memoize the in-flight promise so concurrent first-use (ingest
// + ask) share one open() instead of orphaning a session.
let ragSession = null;
let ragSessionPromise = null;
async function ragEnsureSession() {
  if (ragSession) return ragSession;
  if (ragSessionPromise) return ragSessionPromise;
  ragSessionPromise = (async () => {
    setStatus('preparing knowledge base…');
    // One entry point: rag.open downloads, registers, and wires both models.
    ragSession = await ra.rag.open({ id: MODELS.embedder }, { id: activeLlm }, { topK: 3, chunkSize: 512, chunkOverlap: 64 });
    return ragSession;
  })().catch((e) => {
    ragSessionPromise = null; // allow retry after failure
    throw e;
  });
  return ragSessionPromise;
}
function ragStatsText(s) {
  if (!s) return '';
  return `${s.documentCount} document${s.documentCount === 1 ? '' : 's'} · ${s.chunkCount} chunk${s.chunkCount === 1 ? '' : 's'} indexed`;
}
function renderRagSources(matches) {
  const el = $('ragsources');
  if (!matches || !matches.length) { el.innerHTML = ''; return; }
  el.innerHTML = '<div class="label" style="margin-top:16px">Sources</div>' + matches.map((m) => {
    const src = m.metadata && m.metadata.sourceDocument ? escapeHtml(m.metadata.sourceDocument) : 'document';
    const score = typeof m.score === 'number' ? m.score.toFixed(3) : '';
    return `<div class="ragchunk"><div class="meta"><span>${src}</span><span class="ragscore">${score}</span></div><div class="txt">${escapeHtml(m.text || '')}</div></div>`;
  }).join('');
}

// ---- tabs ----
function showTab(name) {
  document.querySelectorAll('.nav button').forEach((x) => x.classList.toggle('active', x.dataset.tab === name));
  document.querySelectorAll('.panel').forEach((x) => x.classList.toggle('active', x.id === name));
  const btn = document.querySelector(`.nav button[data-tab="${name}"]`);
  if (btn) $('sectiontitle').textContent = btn.textContent.trim();
  if (name === 'models') renderModels();
}
document.querySelectorAll('.nav button').forEach((b) => b.addEventListener('click', () => showTab(b.dataset.tab)));

// ---- UI wiring ----
function wireUi() {
  applySettingsToUi();
  applyDeviceUi();
  renderSidebar(); renderChat();
  wireModels();
  $('newchat').addEventListener('click', () => { newConversation(); showTab('chat'); $('chatinput').focus(); });
  $('chatsend').addEventListener('click', sendChat);
  $('chatinput').addEventListener('keydown', (e) => { if (e.key === 'Enter') sendChat(); });

  $('settemp').addEventListener('input', () => ($('settempval').textContent = $('settemp').value));
  $('setsave').addEventListener('click', saveSettings);
  $('setapisave').addEventListener('click', async () => {
    const v = $('setapikey').value.trim(); if (!v) return;
    try { await ra.secure.set('api-key', v); $('setstatus').textContent = 'API key stored (encrypted)'; $('setapikey').value = ''; }
    catch (e) { $('setstatus').textContent = 'error: ' + e.message; }
  });

  const out = (id, fn) => async () => { setStatus('working…'); $(id).textContent = '…'; try { $(id).textContent = await fn(); } catch (e) { $(id).textContent = 'error: ' + e.message; } setStatus('ready'); };
  $('structgo').addEventListener('click', out('structout', async () => {
    const r = await runStructured($('structtext').value);
    return JSON.stringify(r.value, null, 2) + (r.valid ? '' : '\n\n(raw output did not parse: ' + r.raw + ')');
  }));
  $('toolsgo').addEventListener('click', out('toolsout', async () => {
    const c = await runTools($('toolstext').value);
    return `${c.name}(${JSON.stringify(c.arguments)})\n→ ${JSON.stringify(c.result)}`;
  }));
  $('embgo').addEventListener('click', out('embout', async () => 'cosine similarity: ' + (await runEmbeddings($('emba').value, $('embb').value)).toFixed(3)));

  $('ragadd').addEventListener('click', async () => {
    const text = $('ragdoc').value.trim();
    if (!text) return;
    $('ragadd').disabled = true;
    try {
      const s = await ragEnsureSession();
      await s.ingest(ra.ragDocument.text(text));
      $('ragstats').textContent = ragStatsText(await s.stats());
      $('ragdoc').value = '';
    } catch (e) { $('ragstats').textContent = 'error: ' + e.message; }
    finally { $('ragadd').disabled = false; setStatus('ready'); }
  });
  $('ragclear').addEventListener('click', async () => {
    if (!ragSession) { $('ragstats').textContent = ''; return; }
    try {
      await ragSession.clear();
      $('ragstats').textContent = ragStatsText(await ragSession.stats());
      $('ragout').textContent = ''; renderRagSources([]);
    } catch (e) { $('ragstats').textContent = 'error: ' + e.message; }
  });
  let ragQuerying = false;
  const askRag = async () => {
    if (ragQuerying) return; // one query at a time (Enter can re-fire past the disabled button)
    const q = $('ragq').value.trim();
    if (!q) return;
    ragQuerying = true;
    $('ragask').disabled = true; $('ragq').value = ''; $('ragout').innerHTML = '…'; renderRagSources([]);
    setStatus('retrieving + answering…');
    try {
      const s = await ragEnsureSession();
      let answer = '';
      await each(s.queryStream(q, genOptions()), (e) => {
        if (e.type === 'retrieved') renderRagSources(e.matches);
        else if (e.type === 'token') { answer += e.text; $('ragout').innerHTML = md(answer); }
        else if (e.type === 'completed') {
          $('ragout').innerHTML = reasoningHtml(e.result.thinkingText, false) + md(e.result.answer || answer);
          renderRagSources(e.result.sources);
        }
      });
    } catch (e) { $('ragout').textContent = 'error: ' + e.message; }
    finally { ragQuerying = false; $('ragask').disabled = false; setStatus('ready'); }
  };
  $('ragask').addEventListener('click', askRag);
  $('ragq').addEventListener('keydown', (e) => { if (e.key === 'Enter') askRag(); });

  const vf = $('visionfile');
  vf.addEventListener('change', () => {
    $('visiongo').disabled = !vf.files.length;
    $('visionfname').textContent = vf.files[0] ? vf.files[0].name : 'No image selected';
  });
  $('visiongo').addEventListener('click', async () => {
    const file = vf.files[0];
    if (!file) return;
    // Electron removed File.path; resolve the on-disk path via webUtils.
    let imagePath = file.path;
    try { if (!imagePath && store && store.getPathForFile) imagePath = store.getPathForFile(file); } catch (_) { /* ignore */ }
    if (!imagePath) { $('visionout').textContent = 'error: could not resolve the image path'; return; }
    setStatus('captioning…'); $('visionout').textContent = '…';
    let cap = '';
    try { await runVision(imagePath, (t) => { cap += t; $('visionout').textContent = cap; }); }
    catch (e) { $('visionout').textContent = 'error: ' + e.message; }
    setStatus('ready');
  });

  wireVoice();
  wireVad();
}

// ---- voice ----
// One SDK call owns the whole pipeline: it downloads and loads stt/llm/tts,
// ensures a VAD, opens the mic on start(), and reports turns as events.
function wireVoice() {
  const btn = $('voicebtn');
  let session = null;
  const setState = (s) => { $('voicestate').textContent = s; };

  const stop = async () => {
    const s = session;
    session = null;
    btn.textContent = 'Start conversation';
    if (s) await s.close();
    setState('idle');
    setStatus('ready');
  };

  btn.addEventListener('click', async () => {
    if (session) return stop();
    btn.disabled = true;
    btn.textContent = 'Preparing…';
    setStatus('loading voice models…');
    $('voiceheard').textContent = ''; $('voicereply').textContent = '';
    try {
      session = await ra.voice.createSession({
        stt: { id: MODELS.stt },
        llm: { id: activeLlm },
        tts: { id: MODELS.tts },
        generation: genOptions({ maxOutputTokens: 96 }),
      });
      // Subscribing never opens the mic; start() does.
      const events = session.events;
      void each(events, (e) => {
        if (e.type === 'userTranscribed') $('voiceheard').textContent = e.text;
        else if (e.type === 'agentResponse') $('voicereply').textContent = e.text;
        else if (e.type === 'agentStateChanged') setState(e.state.toLowerCase());
        else if (e.type === 'speechStarted') setState('hearing you…');
        else if (e.type === 'error') setState('error: ' + e.message);
      }).catch((err) => setState('error: ' + err.message));
      await session.start();
      btn.textContent = 'Stop conversation';
      setStatus('listening…');
    } catch (e) {
      setState('error: ' + e.message);
      await stop();
    } finally { btn.disabled = false; }
  });

  $('voicesay').addEventListener('click', async () => {
    if (!session) return setState('start the conversation first');
    await session.say('Hello — I am running entirely on this device.');
  });
  $('voiceinterrupt').addEventListener('click', () => session && session.interrupt());
  window.addEventListener('beforeunload', () => { if (session) void session.close(); });
}

// ---- VAD ----
// Records a buffer, then runs one vad.detect over it; the SDK returns debounced
// speech segments rather than raw per-frame flags.
function wireVad() {
  const btn = $('vadbtn');
  let cap = null;
  $('vadth').addEventListener('input', () => ($('vadthval').textContent = $('vadth').value));

  const begin = async () => {
    if (cap) return;
    setStatus('recording…'); $('vadout').textContent = 'recording — speak now…';
    const stream = await navigator.mediaDevices.getUserMedia({ audio: { channelCount: 1 } });
    const ctx = new AudioContext();
    const src = ctx.createMediaStreamSource(stream);
    const node = ctx.createScriptProcessor(4096, 1, 1);
    const chunks = [];
    node.onaudioprocess = (e) => chunks.push(new Float32Array(e.inputBuffer.getChannelData(0)));
    src.connect(node); node.connect(ctx.destination);
    cap = { stream, ctx, node, chunks };
  };
  const end = async () => {
    if (!cap) return;
    const { stream, ctx, node, chunks } = cap;
    const rate = ctx.sampleRate;
    cap = null;
    node.disconnect(); stream.getTracks().forEach((t) => t.stop()); void ctx.close();
    let n = 0; for (const c of chunks) n += c.length;
    const merged = new Float32Array(n);
    let o = 0; for (const c of chunks) { merged.set(c, o); o += c.length; }
    if (!n) { $('vadout').textContent = '—'; setStatus('ready'); return; }
    setStatus('detecting…');
    try {
      const r = await ra.vad.detect(ra.audio.float32(merged, rate), { activationThreshold: parseFloat($('vadth').value) });
      const segs = r.segments.map((s) => `${(s.startMs / 1000).toFixed(2)}s–${(s.endMs / 1000).toFixed(2)}s`).join(', ');
      $('vadout').textContent = r.isSpeech
        ? `🎤 speech in ${r.segments.length} segment(s): ${segs} · ${(r.probability * 100).toFixed(0)}% of frames`
        : '· no speech detected';
    } catch (e) { $('vadout').textContent = 'error: ' + e.message; }
    setStatus('ready');
  };
  btn.addEventListener('mousedown', begin);
  btn.addEventListener('mouseup', end);
  btn.addEventListener('mouseleave', end);
}

// ---- headless self-test ----
async function selfTest() {
  const log = (s) => window.runanywhereTest.log(s + '\n');
  try {
    log('[selftest] commons ' + ra.version + ' · device ' + ra.deviceId + ' · env ' + ra.environment);
    if (!ra.isReady) throw new Error('isReady false after initialize');

    let reply = '';
    let metrics = null;
    await each(ra.llm.generateStream('Say hello in one short sentence.', genOptions({ maxOutputTokens: 24 })), (e) => {
      if (e.type === 'token') reply += e.text;
      else if (e.type === 'completed') metrics = e.result;
    });
    if (!reply.trim()) throw new Error('empty chat reply');
    if (!metrics || !metrics.requestId || !metrics.model) throw new Error('completed event carried no metrics');
    log(`[selftest] chat OK: ${JSON.stringify(reply.trim().slice(0, 60))} (${metrics.outputTokens} tok, ${metrics.tokensPerSecond.toFixed(1)} tok/s, finish=${metrics.finishReason})`);

    const structured = await runStructured('Marie Curie was a 66 year old Polish physicist who loved chemistry.');
    const obj = structured.value;
    if (!structured.valid || typeof obj.name !== 'string' || typeof obj.age !== 'number' || !Array.isArray(obj.interests)) throw new Error('structured shape wrong');
    log('[selftest] structured OK: ' + JSON.stringify(obj));

    const registered = ra.llm.tools.list();
    if (registered.length !== TOOLS.length) throw new Error('tool registry wrong size');
    const call = await runTools('What is the weather in Tokyo in celsius?');
    if (!TOOLS.some((t) => t.name === call.name)) throw new Error('bad tool');
    if (!call.result) throw new Error('the executor did not run');
    log('[selftest] tools OK: ' + call.name + ' ' + JSON.stringify(call.arguments) + ' -> ' + JSON.stringify(call.result));

    const close = await runEmbeddings('a cat sat on the mat', 'a kitten rested on the rug');
    const far = await runEmbeddings('a cat sat on the mat', 'the stock market fell today');
    if (!(close > far)) throw new Error('embedding ordering wrong');
    log(`[selftest] embeddings OK: close=${close.toFixed(3)} far=${far.toFixed(3)}`);

    const list = await ra.models.list();
    if (!list.some((m) => m.id === MODELS.llm)) throw new Error('catalog missing the chat model');
    const state = await ra.models.state();
    log(`[selftest] models OK: ${list.length} known, loaded=${Object.keys(state.loaded).join('/') || 'none'}, ${fmtSize(state.storageUsedBytes)} on disk`);

    const image = new URLSearchParams(location.search).get('image');
    if (image) { const c = await runVision(image); if (!c || c.length < 3) throw new Error('empty caption'); log('[selftest] vision OK: ' + JSON.stringify(c.slice(0, 70))); }
    else log('[selftest] vision SKIPPED (no image)');

    const secret = 'sk-demo-secret-12345';
    if ((await runSecure('demo-selftest-key', secret)) !== secret) throw new Error('secure store failed');
    log('[selftest] secure store OK (encrypted round-trip)');

    const vad = await runVad();
    if (!vad.isSpeech || !vad.segments.length) throw new Error('vad did not detect the tone');
    log(`[selftest] vad OK: ${vad.segments.length} segment(s), first ${Math.round(vad.segments[0].startMs)}–${Math.round(vad.segments[0].endMs)}ms`);

    log('[selftest] ALL PASS');
    window.runanywhereTest.done(true);
  } catch (e) { log('[selftest] FAIL: ' + (e && e.message)); window.runanywhereTest.done(false); }
}

const IS_SELFTEST = new URLSearchParams(location.search).get('selftest') === '1';
(async () => {
  // One call. It brings up the native runtime, the model store, and the secure
  // store; there is no second phase. apiKey/baseUrl are accepted but unused —
  // Electron has no control plane yet (see the README).
  await ra.initialize({ environment: 'production' });
  for (const t of TOOLS) ra.llm.tools.register(t, EXECUTORS[t.name]);
  if (!IS_SELFTEST) {
    try { const s = await store.loadSettings(); if (s && s.systemPrompt) settings = { ...settings, ...s }; } catch { /* ignore */ }
    try { const c = await store.loadConversations(); if (c && Array.isArray(c.conversations)) { conversations = c.conversations; nextConvId = c.nextConvId || conversations.length + 1; activeId = conversations[0] ? conversations[0].id : null; } } catch { /* ignore */ }
    try { const cm = await store.loadCustomModels(); if (Array.isArray(cm)) customModels = cm; } catch { /* ignore */ }
  }
  // SDK breadcrumbs (ready / modelLoaded / modelUnloaded / error) drive the pill.
  void each(ra.events, (e) => {
    if (e.type === 'modelLoaded') setStatus(`loaded ${e.id}`);
    else if (e.type === 'error') setStatus('error: ' + e.message);
  }).catch(() => { /* the stream ends on reset() */ });
  setStatus('ready');
  if (IS_SELFTEST) { setStatus('self-test…'); await selfTest(); } else { wireUi(); }
})().catch((e) => {
  setStatus('error: ' + (e && e.message)); console.error(e);
  if (IS_SELFTEST) { try { window.runanywhereTest.log('[selftest] STARTUP ERROR: ' + (e && e.message) + '\n'); window.runanywhereTest.done(false); } catch { /* ignore */ } }
});
