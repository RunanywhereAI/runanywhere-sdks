// RunAnywhere demo (renderer) — a product-grade sample: conversation history +
// persistence, markdown chat with per-message metrics (generateStream), a Models
// panel (grouped catalog + add-any-model + download + load/unload + storage), a
// Settings panel (system prompt / temperature / max-tokens / encrypted API key),
// and workbenches for structured output, tools, vision, embeddings, voice, and
// VAD. Feature helpers are shared with the headless self-test.
const ra = window.runanywhere;
const store = window.demoStore;
const $ = (id) => document.getElementById(id);
const setStatus = (s) => { $('status').textContent = s; $('statuswrap').classList.toggle('busy', s !== 'ready'); };
// Escape quotes too: md() builds an <a href="…"> from (escaped) text, so an
// unescaped " in a link URL would break out of the attribute.
const escapeHtml = (s) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const fmtSize = (b) => (b > 1e9 ? (b / 1e9).toFixed(1) + ' GB' : b > 1e6 ? (b / 1e6).toFixed(0) + ' MB' : (b / 1e3).toFixed(0) + ' KB');
const fmtMB = (mb) => (mb >= 1000 ? (mb / 1000).toFixed(1) + ' GB' : mb + ' MB');

const TOOLS = [
  { name: 'get_weather', description: 'Get the current weather for a city', parameters: { type: 'object', properties: { city: { type: 'string' }, unit: { type: 'string', enum: ['celsius', 'fahrenheit'] } }, required: ['city', 'unit'] } },
  { name: 'set_timer', description: 'Start a countdown timer', parameters: { type: 'object', properties: { seconds: { type: 'integer' }, label: { type: 'string' } }, required: ['seconds', 'label'] } },
];

// ---- settings + conversations + custom models (persisted via demoStore) ----
let settings = { systemPrompt: 'You are a concise, helpful assistant.', temperature: 0.7, maxTokens: 256 };
let conversations = [];
let activeId = null;
let nextConvId = 1;
let customModels = []; // [{ id, source, type, label, downloaded }]

// ---- lazily-loaded model handles ----
const handles = {};
const ensure = (k, fn) => (handles[k] ??= fn());
const llm = () => ensure('llm', () => ra.loadLLM('qwen2.5-0.5b'));
const embedder = () => ensure('embedder', () => ra.loadEmbedder('minilm'));
const vlm = () => ensure('vlm', () => ra.loadVLM('smolvlm-256m'));
const stt = () => ensure('stt', () => ra.loadSTT('whisper-tiny'));
const tts = () => ensure('tts', () => ra.loadTTS('piper-lessac'));

// ---- minimal, XSS-safe markdown (escape first, then format) ----
// Code blocks are stashed behind private-use sentinels () so inline
// formatting doesn't touch them; they're restored last. (Private-use chars keep
// the source ASCII and avoid embedding NUL bytes.)
function md(text) {
  const blocks = [];
  let s = escapeHtml(text).replace(/```([\s\S]*?)```/g, (_m, c) => { blocks.push(c); return `${blocks.length - 1}`; });
  s = s.replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/(^|[^*])\*([^*]+)\*/g, '$1<em>$2</em>')
    .replace(/\[([^\]]+)\]\((https?:[^)]+)\)/g, '<a href="$2">$1</a>');
  s = s.split(/\n{2,}/).map((p) => {
    // A standalone code block: emit <pre> at the top level, not nested in a <p>.
    const t = p.trim();
    if (/^\d+$/.test(t)) return t.replace(/(\d+)/g, (_m, i) => `<pre><code>${blocks[+i]}</code></pre>`);
    // A list: only when every non-blank line is a bullet (don't fold stray lines).
    const lines = p.split('\n');
    if (lines.some((l) => /^\s*[-*] /.test(l)) && lines.every((l) => !l.trim() || /^\s*[-*] /.test(l))) {
      return '<ul>' + lines.filter((l) => l.trim()).map((l) => '<li>' + l.replace(/^\s*[-*] /, '') + '</li>').join('') + '</ul>';
    }
    if (/^#{1,3} /.test(p)) { const n = p.match(/^#+/)[0].length; return `<h${n + 2}>${p.replace(/^#+ /, '')}</h${n + 2}>`; }
    return '<p>' + p.replace(/\n/g, '<br>') + '</p>';
  }).join('');
  return s.replace(/(\d+)/g, (_m, i) => `<pre><code>${blocks[+i]}</code></pre>`);
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
function bubbleHtml(m) {
  const body = m.role === 'assistant' ? md(m.content || '…') : escapeHtml(m.content);
  const metrics = m.metrics ? `<div class="metrics">⚡ ${m.metrics.tokens} tokens · ${m.metrics.tps.toFixed(1)} tok/s · TTFT ${Math.round(m.metrics.ttft)}ms</div>` : '';
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
  const chips = SUGGESTIONS.map(([l, q], i) => `<button class="chip" data-i="${i}">${escapeHtml(l)}</button>`).join('');
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
function buildPrompt(priorMessages, userText) {
  let p = settings.systemPrompt + '\n\n';
  for (const m of priorMessages) p += (m.role === 'user' ? 'User: ' : 'Assistant: ') + m.content + '\n';
  return p + 'User: ' + userText + '\nAssistant:';
}
let generating = false;
async function sendChat() {
  // One generation at a time: a second Enter while streaming would run a
  // concurrent generate() on the SAME shared llm() handle.
  if (generating) return;
  const text = $('chatinput').value.trim();
  if (!text) return;
  generating = true;
  $('chatsend').disabled = true;
  $('chatinput').value = '';
  const conv = activeConv() || newConversation();
  const prior = conv.messages.slice();
  conv.messages.push({ role: 'user', content: text });
  const asst = { role: 'assistant', content: '' };
  conv.messages.push(asst);
  if (!conv.title) { conv.title = text.slice(0, 40); renderSidebar(); }
  renderChat();
  const bubble = [...$('chatlog').querySelectorAll('.msg.assistant .bubble')].pop();
  bubble.classList.add('streaming');
  setStatus('generating…');
  try {
    const h = await llm();
    let result = null;
    await ra.generateStream(h, buildPrompt(prior, text), { temperature: settings.temperature, maxTokens: settings.maxTokens }, (e) => {
      if (e.isFinal) { result = e.result; }
      else { asst.content += e.token; bubble.innerHTML = md(asst.content); $('chatlog').scrollTop = $('chatlog').scrollHeight; }
    });
    asst.content = asst.content.trim();
    if (result) asst.metrics = { tokens: result.tokenCount, tps: result.tokensPerSecond, ttft: result.timeToFirstTokenMs };
    bubble.classList.remove('streaming');
    renderChat();
    persist();
  } catch (e) { asst.content = 'error: ' + e.message; renderChat(); }
  finally { generating = false; $('chatsend').disabled = false; setStatus('ready'); }
}

// ---- models panel ----
const loaders = { llm: (id) => ra.loadLLM(id), vlm: (id) => ra.loadVLM(id), embedder: (id) => ra.loadEmbedder(id), stt: (id) => ra.loadSTT(id), tts: (id) => ra.loadTTS(id) };
const unloaders = { llm: (h) => ra.unloadLLM(h), vlm: (h) => ra.unloadVLM(h), embedder: (h) => ra.unloadEmbedder(h), stt: (h) => ra.unloadSTT(h), tts: (h) => ra.unloadTTS(h) };
const loadedById = {};
const svg = (d) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${d}</svg>`;
const TYPE_ICON = {
  llm: svg('<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>'),
  vlm: svg('<rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="9" cy="9" r="2"/><path d="m21 15-5-5L5 21"/>'),
  embedder: svg('<circle cx="5" cy="6" r="2"/><circle cx="19" cy="7" r="2"/><circle cx="12" cy="18" r="2"/><path d="M7 6h10M6 8l5 8M18 9l-5 7"/>'),
  stt: svg('<rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 10a7 7 0 0 0 14 0M12 19v3"/>'),
  tts: svg('<path d="M11 5 6 9H2v6h4l5 4zM19 9a5 5 0 0 1 0 6"/>'),
};
const TYPE_LABEL = { llm: 'Language model', vlm: 'Vision-language', embedder: 'Embeddings', stt: 'Speech-to-text', tts: 'Text-to-speech' };
const GROUP_ORDER = [['llm', 'Language models'], ['vlm', 'Vision-language'], ['stt', 'Speech-to-text'], ['tts', 'Text-to-speech'], ['embedder', 'Embeddings']];
function mkbtn(label, fn) { const b = document.createElement('button'); b.className = 'btn ghost'; b.textContent = label; b.onclick = fn; return b; }
function persistCustom() { try { store.saveCustomModels(customModels); } catch { /* optional */ } }

// Build one model card. `source` is what we hand to download/load (a catalog id,
// a HuggingFace repo, a URL, or a path); `key` identifies the card + load handle.
function buildCard(o) {
  const loaded = loadedById[o.key];
  const div = document.createElement('div'); div.className = 'model';
  div.innerHTML =
    '<div class="hd">' +
      `<span class="mi">${TYPE_ICON[o.type] || ''}</span>` +
      `<div style="min-width:0"><div class="name">${escapeHtml(o.label)}</div>` +
      `<div class="sub">${o.sub}</div></div>` +
      '<span class="actions"></span>' +
    '</div><div class="bar" style="display:none"><div></div></div>';
  const actions = div.querySelector('.actions');
  if (loaded) { const b = document.createElement('span'); b.className = 'badge on'; b.textContent = 'loaded'; actions.appendChild(b); }
  if (!o.downloaded) {
    const dl = mkbtn('Download', async () => {
      dl.disabled = true; dl.textContent = 'Downloading…';
      const bar = div.querySelector('.bar'); bar.style.display = 'block';
      let resolved;
      try { resolved = await ra.downloadModel(o.source, (p) => { bar.firstElementChild.style.width = (p.percent || 0) + '%'; }); }
      catch (e) { dl.textContent = 'Failed'; dl.disabled = false; console.error(e); return; }
      // Persist the resolved primary path so downloaded state is later recomputed
      // from disk (via ra.exists), not trusted from a stale flag.
      if (o.custom) { const c = customModels.find((m) => m.id === o.key); if (c) { c.primary = resolved && resolved.primary; persistCustom(); } }
      renderModels();
    });
    actions.appendChild(dl);
  } else {
    const b = mkbtn(loaded ? 'Unload' : 'Load', async () => {
      // Disable the whole row: Remove during an in-flight Load would drop the card
      // before loadedById[key] is set, leaking the (multi-GB) native handle.
      const btns = actions.querySelectorAll('button');
      btns.forEach((x) => (x.disabled = true));
      b.textContent = loaded ? 'Unloading…' : 'Loading…';
      try {
        if (loaded) { await unloaders[o.type](loaded); delete loadedById[o.key]; }
        else { loadedById[o.key] = await loaders[o.type](o.source); }
      } catch (e) { b.textContent = 'Error'; btns.forEach((x) => (x.disabled = false)); console.error(e); return; }
      renderModels();
    });
    actions.appendChild(b);
  }
  if (o.custom) {
    actions.appendChild(mkbtn('Remove', async () => {
      if (loadedById[o.key]) { try { await unloaders[o.type](loadedById[o.key]); } catch { /* ignore */ } delete loadedById[o.key]; }
      customModels = customModels.filter((m) => m.id !== o.key); persistCustom(); renderModels();
    }));
  }
  return div;
}

async function renderModels() {
  const cat = await ra.catalog();
  const status = await ra.modelStatus();
  const el = $('modellist'); el.innerHTML = '';
  const byType = {};
  for (const [id, entry] of Object.entries(cat)) (byType[entry.type] ??= []).push([id, entry]);
  for (const [type, title] of GROUP_ORDER) {
    const items = byType[type];
    if (!items || !items.length) continue;
    const h = document.createElement('div'); h.className = 'mgroup'; h.textContent = title; el.appendChild(h);
    for (const [id, entry] of items) {
      const st = status[id] || { downloaded: false, sizeBytes: 0 };
      const bits = [TYPE_LABEL[entry.type] || entry.type];
      if (entry.params) bits.push(entry.params);
      if (st.downloaded) bits.push(fmtSize(st.sizeBytes));
      else if (entry.sizeMB) bits.push('~' + fmtMB(entry.sizeMB));
      let sub = bits.join(' · ');
      if (entry.heavy) sub += ' <span class="badge heavy">heavy · CPU</span>';
      el.appendChild(buildCard({ key: id, type: entry.type, label: entry.label || id, sub, source: id, downloaded: st.downloaded, custom: false }));
    }
  }
  if (customModels.length) {
    // Recompute each custom model's downloaded state from disk (its primary may
    // have been deleted since it was fetched), rather than trusting a stale flag.
    const onDisk = await Promise.all(customModels.map((m) => (m.primary ? ra.exists(m.primary) : Promise.resolve(false))));
    const h = document.createElement('div'); h.className = 'mgroup'; h.textContent = 'Your models'; el.appendChild(h);
    customModels.forEach((m, i) => {
      const sub = `${TYPE_LABEL[m.type] || m.type} · <span class="muted">${escapeHtml(m.source)}</span>`;
      el.appendChild(buildCard({ key: m.id, type: m.type, label: m.label || m.id, sub, source: m.source, downloaded: onDisk[i], custom: true }));
    });
  }
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
    customModels.unshift({ id, source, type, label: deriveLabel(source), downloaded: false });
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
}
async function saveSettings() {
  settings = { systemPrompt: $('setsystem').value, temperature: parseFloat($('settemp').value), maxTokens: parseInt($('setmax').value, 10) || 256 };
  try { await store.saveSettings(settings); } catch { /* optional */ }
  $('setstatus').textContent = 'saved'; setTimeout(() => ($('setstatus').textContent = ''), 1500);
}

// ---- shared feature helpers (used by UI + self-test) ----
async function runStructured(text) {
  return ra.generateStructured(await llm(), `Extract the person as JSON. Text: "${text}"`, {
    type: 'object',
    properties: { name: { type: 'string' }, age: { type: 'integer' }, interests: { type: 'array', items: { type: 'string' }, maxItems: 5 } },
    required: ['name', 'age', 'interests'],
  });
}
async function runTools(text) { return ra.generateToolCall(await llm(), text, TOOLS); }
async function runEmbeddings(a, b) {
  const h = await embedder();
  const [ea, eb] = await Promise.all([ra.embed(h, a), ra.embed(h, b)]);
  let dot = 0, na = 0, nb = 0;
  for (let i = 0; i < ea.length; i++) { dot += ea[i] * eb[i]; na += ea[i] * ea[i]; nb += eb[i] * eb[i]; }
  return dot / (Math.sqrt(na) * Math.sqrt(nb) || 1);
}
async function runVision(imagePath, onToken) {
  let caption = '';
  await ra.generateVlm(await vlm(), imagePath, 'Describe this image in one sentence.', (t) => { caption += t; onToken?.(t); });
  return caption.trim();
}
async function runSecure(key, value) { await ra.secureSet(key, value); const got = await ra.secureGet(key); await ra.secureDelete(key); return got; }
async function runVad() {
  const handle = await ra.createVad();
  const silence = () => new Float32Array(1600);
  const loud = () => { const f = new Float32Array(1600); for (let i = 0; i < 1600; i++) f[i] = 0.5 * Math.sin((2 * Math.PI * 300 * i) / 16000); return f; };
  for (let i = 0; i < 24; i++) await ra.vadProcess(handle, silence());
  let detected = false;
  for (let i = 0; i < 8; i++) if (await ra.vadProcess(handle, loud())) detected = true;
  await ra.unloadVad(handle);
  return detected;
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
  renderSidebar(); renderChat();
  wireModels();
  $('newchat').addEventListener('click', () => { newConversation(); showTab('chat'); $('chatinput').focus(); });
  $('chatsend').addEventListener('click', sendChat);
  $('chatinput').addEventListener('keydown', (e) => { if (e.key === 'Enter') sendChat(); });

  $('settemp').addEventListener('input', () => ($('settempval').textContent = $('settemp').value));
  $('setsave').addEventListener('click', saveSettings);
  $('setapisave').addEventListener('click', async () => {
    const v = $('setapikey').value.trim(); if (!v) return;
    try { await ra.secureSet('api-key', v); $('setstatus').textContent = 'API key stored (encrypted)'; $('setapikey').value = ''; }
    catch (e) { $('setstatus').textContent = 'error: ' + e.message; }
  });

  const out = (id, fn) => async () => { setStatus('working…'); $(id).textContent = '…'; try { $(id).textContent = await fn(); } catch (e) { $(id).textContent = 'error: ' + e.message; } setStatus('ready'); };
  $('structgo').addEventListener('click', out('structout', async () => JSON.stringify(await runStructured($('structtext').value), null, 2)));
  $('toolsgo').addEventListener('click', out('toolsout', async () => { const c = await runTools($('toolstext').value); return `${c.name}(${JSON.stringify(c.arguments)})`; }));
  $('embgo').addEventListener('click', out('embout', async () => 'cosine similarity: ' + (await runEmbeddings($('emba').value, $('embb').value)).toFixed(3)));

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

// ---- voice (inline Web Audio) ----
function captureController() {
  let cap = null;
  return {
    async start() {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: { channelCount: 1 } });
      const ctx = new AudioContext();
      const src = ctx.createMediaStreamSource(stream);
      const node = ctx.createScriptProcessor(4096, 1, 1);
      const chunks = []; const onframe = [];
      node.onaudioprocess = (e) => { const f = new Float32Array(e.inputBuffer.getChannelData(0)); chunks.push(f); onframe.forEach((cb) => cb(f, ctx.sampleRate)); };
      src.connect(node); node.connect(ctx.destination);
      cap = { stream, ctx, node, chunks, onframe };
    },
    onFrame(cb) { cap && cap.onframe.push(cb); },
    stop() { if (!cap) return null; const { stream, ctx, node, chunks } = cap; node.disconnect(); stream.getTracks().forEach((t) => t.stop()); ctx.close(); cap = null; let n = 0; for (const c of chunks) n += c.length; const m = new Float32Array(n); let o = 0; for (const c of chunks) { m.set(c, o); o += c.length; } return { samples: m, rate: ctx.sampleRate }; },
  };
}
function toPcm16At16k(samples, rate) {
  const ratio = rate / 16000, outLen = Math.floor(samples.length / ratio), pcm = new Int16Array(outLen);
  for (let i = 0; i < outLen; i++) { const s = Math.max(-1, Math.min(1, samples[Math.floor(i * ratio)])); pcm[i] = Math.max(-32768, Math.min(32767, Math.round(s * 32768))); }
  return new Uint8Array(pcm.buffer);
}
function wireVoice() {
  const btn = $('voicebtn'); const cc = captureController();
  const begin = async () => { setStatus('listening…'); await cc.start(); };
  const end = async () => {
    const rec = cc.stop(); if (!rec) return;
    setStatus('thinking…');
    const heard = await ra.transcribe(await stt(), toPcm16At16k(rec.samples, rec.rate));
    $('voiceheard').textContent = heard;
    let reply = ''; $('voicereply').textContent = '';
    await ra.generate(await llm(), `You are concise. Reply in one sentence.\n\n${heard}`, (t) => { reply += t; $('voicereply').textContent = reply; });
    const audio = await ra.synthesize(await tts(), reply.trim());
    setStatus('speaking…');
    const pctx = new AudioContext(); const buf = pctx.createBuffer(1, audio.samples.length, audio.sampleRate); buf.getChannelData(0).set(audio.samples);
    const s = pctx.createBufferSource(); s.buffer = buf; s.connect(pctx.destination);
    await new Promise((r) => { s.onended = () => { pctx.close(); r(); }; s.start(); });
    setStatus('ready');
  };
  btn.addEventListener('mousedown', begin); btn.addEventListener('mouseup', end); btn.addEventListener('mouseleave', end);
}
function wireVad() {
  const btn = $('vadbtn'); const cc = captureController(); let vadHandle = null; let frames = 0, speech = 0;
  $('vadth').addEventListener('input', async () => { $('vadthval').textContent = $('vadth').value; if (vadHandle != null) await ra.vadSetThreshold(vadHandle, parseFloat($('vadth').value)); });
  const begin = async () => {
    setStatus('listening…'); frames = 0; speech = 0; $('vadout').textContent = 'calibrating…';
    vadHandle = await ra.createVad(parseFloat($('vadth').value));
    await cc.start();
    cc.onFrame(async (f, rate) => {
      if (vadHandle == null) return;
      const ratio = rate / 16000, outLen = Math.floor(f.length / ratio), frame = new Float32Array(outLen);
      for (let i = 0; i < outLen; i++) frame[i] = f[Math.floor(i * ratio)];
      const isSpeech = await ra.vadProcess(vadHandle, frame);
      frames++; if (isSpeech) speech++;
      $('vadout').textContent = (frames < 20 ? 'calibrating… ' : (isSpeech ? '🎤 SPEECH ' : '· silence ')) + `(${speech}/${frames} speech frames)`;
    });
  };
  const end = async () => { cc.stop(); if (vadHandle != null) { await ra.unloadVad(vadHandle); vadHandle = null; } setStatus('ready'); };
  btn.addEventListener('mousedown', begin); btn.addEventListener('mouseup', end); btn.addEventListener('mouseleave', end);
}

// ---- headless self-test ----
async function selfTest() {
  const log = (s) => window.runanywhereTest.log(s + '\n');
  try {
    log('[selftest] commons ' + (await ra.version()));
    const conv = newConversation();
    conv.messages.push({ role: 'assistant', content: '' }); // exercise chat plumbing minimally
    conv.messages.pop();
    let reply = '';
    await ra.generateStream(await llm(), buildPrompt([], 'Say hello in one short sentence.'), { maxTokens: 24 }, (e) => { if (!e.isFinal) reply += e.token; });
    if (!reply.trim()) throw new Error('empty chat reply');
    log('[selftest] chat OK: ' + JSON.stringify(reply.trim().slice(0, 70)));

    const obj = await runStructured('Marie Curie was a 66 year old Polish physicist who loved chemistry.');
    if (typeof obj.name !== 'string' || typeof obj.age !== 'number' || !Array.isArray(obj.interests)) throw new Error('structured shape wrong');
    log('[selftest] structured OK: ' + JSON.stringify(obj));

    const call = await runTools('What is the weather in Tokyo in celsius?');
    if (!TOOLS.some((t) => t.name === call.name)) throw new Error('bad tool');
    log('[selftest] tools OK: ' + call.name + ' ' + JSON.stringify(call.arguments));

    const close = await runEmbeddings('a cat sat on the mat', 'a kitten rested on the rug');
    const far = await runEmbeddings('a cat sat on the mat', 'the stock market fell today');
    if (!(close > far)) throw new Error('embedding ordering wrong');
    log(`[selftest] embeddings OK: close=${close.toFixed(3)} far=${far.toFixed(3)}`);

    const cat = await ra.catalog();
    if (!cat['qwen2.5-0.5b']) throw new Error('catalog missing');
    const status = await ra.modelStatus();
    log('[selftest] models OK: ' + Object.keys(cat).length + ' catalog entries, qwen downloaded=' + status['qwen2.5-0.5b'].downloaded);

    const image = new URLSearchParams(location.search).get('image');
    if (image) { const c = await runVision(image); if (!c || c.length < 3) throw new Error('empty caption'); log('[selftest] vision OK: ' + JSON.stringify(c.slice(0, 70))); }
    else log('[selftest] vision SKIPPED (no image)');

    const secret = 'sk-demo-secret-12345';
    if ((await runSecure('demo-selftest-key', secret)) !== secret) throw new Error('secure store failed');
    log('[selftest] secure store OK (encrypted round-trip)');

    if (!(await runVad())) throw new Error('vad did not detect speech');
    log('[selftest] vad OK (speech detected)');

    log('[selftest] ALL PASS');
    window.runanywhereTest.done(true);
  } catch (e) { log('[selftest] FAIL: ' + (e && e.message)); window.runanywhereTest.done(false); }
}

const IS_SELFTEST = new URLSearchParams(location.search).get('selftest') === '1';
(async () => {
  await ra.ready();
  await ra.initialize();
  if (!IS_SELFTEST) {
    try { const s = await store.loadSettings(); if (s && s.systemPrompt) settings = { ...settings, ...s }; } catch { /* ignore */ }
    try { const c = await store.loadConversations(); if (c && Array.isArray(c.conversations)) { conversations = c.conversations; nextConvId = c.nextConvId || conversations.length + 1; activeId = conversations[0] ? conversations[0].id : null; } } catch { /* ignore */ }
    try { const cm = await store.loadCustomModels(); if (Array.isArray(cm)) customModels = cm; } catch { /* ignore */ }
  }
  setStatus('ready');
  if (IS_SELFTEST) { setStatus('self-test…'); await selfTest(); } else { wireUi(); }
})().catch((e) => {
  setStatus('error: ' + (e && e.message)); console.error(e);
  if (IS_SELFTEST) { try { window.runanywhereTest.log('[selftest] STARTUP ERROR: ' + (e && e.message) + '\n'); window.runanywhereTest.done(false); } catch { /* ignore */ } }
});
