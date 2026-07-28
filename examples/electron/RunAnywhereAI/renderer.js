// RunAnywhere demo (renderer) — a product-grade sample: conversation history +
// persistence, markdown chat with per-message metrics (generateStream), a Models
// panel (grouped catalog + add-any-model + download + load/unload + storage), a
// Settings panel (system prompt / temperature / max-tokens / encrypted API key),
// and workbenches for structured output, tools, vision, embeddings, voice, and
// VAD. Feature helpers are shared with the headless self-test.
const ra = window.runanywhere;
const store = window.appStore;
const $ = (id) => document.getElementById(id);
const setStatus = (s) => { $('status').textContent = s; $('statuswrap').classList.toggle('busy', s !== 'ready'); };
// Escape quotes too: md() builds an <a href="…"> from (escaped) text, so an
// unescaped " in a link URL would break out of the attribute.
const escapeHtml = (s) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const fmtSize = (b) => (b > 1e9 ? (b / 1e9).toFixed(1) + ' GB' : b > 1e6 ? (b / 1e6).toFixed(0) + ' MB' : (b / 1e3).toFixed(0) + ' KB');
const fmtMB = (mb) => (mb >= 1000 ? (mb / 1000).toFixed(1) + ' GB' : mb + ' MB');

// Tools the model can call. `execute` actually RUNS locally — a tool call that is
// only parsed and never executed looks broken. get_weather has no offline data
// source, so it returns an openly-labelled sample instead of pretending.
const TOOLS = [
  {
    name: 'get_current_time',
    description: "Get the user's current date and time",
    parameters: { type: 'object', properties: { timezone: { type: 'string' } }, required: [] },
    execute: () => new Date().toLocaleString(),
  },
  {
    name: 'calculate',
    description: 'Evaluate a basic arithmetic expression, e.g. "12 * (3 + 4)"',
    parameters: { type: 'object', properties: { expression: { type: 'string' } }, required: ['expression'] },
    execute: ({ expression }) => {
      // Arithmetic only — never eval() model output.
      const src = String(expression || '');
      if (!/^[\d\s+\-*/().%]+$/.test(src)) return 'unsupported expression (digits and + - * / ( ) only)';
      try { return String(Function(`"use strict";return (${src})`)()); } catch { return 'could not evaluate'; }
    },
  },
  {
    name: 'set_timer',
    description: 'Start a countdown timer',
    parameters: { type: 'object', properties: { seconds: { type: 'integer' }, label: { type: 'string' } }, required: ['seconds'] },
    execute: ({ seconds, label }) => {
      const secs = Math.max(1, Math.min(3600, Number(seconds) || 0));
      setTimeout(() => flashToast(`Timer finished${label ? ': ' + label : ''}`), secs * 1000);
      return `timer started for ${secs}s${label ? ` (${label})` : ''}`;
    },
  },
  {
    name: 'get_weather',
    description: 'Get the current weather for a city',
    parameters: { type: 'object', properties: { city: { type: 'string' }, unit: { type: 'string', enum: ['celsius', 'fahrenheit'] } }, required: ['city'] },
    execute: ({ city, unit }) =>
      `(sample data — this build has no weather source) 18°${unit === 'fahrenheit' ? 'F' : 'C'}, clear in ${city}`,
  },
];

// ---- settings + conversations + custom models (persisted via appStore) ----
// The system prompt has to establish WHO IS WHO — without it a small model
// answers "what is my name" with its own identity. Temperature is low because
// this is factual recall, not creative writing.
const DEFAULT_SYSTEM_PROMPT =
  'You are a helpful assistant talking with a user. ' +
  'Facts the user states are about the USER, never about you. ' +
  'When asked about their name, age or preferences, answer using what the user said earlier, ' +
  'in the second person ("Your name is ..."). Never claim the user\'s details as your own. ' +
  'Answer in one or two short sentences unless asked for more.';
let settings = { systemPrompt: DEFAULT_SYSTEM_PROMPT, temperature: 0.3, maxTokens: 512, reasoning: false };
let conversations = [];
let activeId = null;
let nextConvId = 1;
let customModels = []; // [{ id, source, type, label, downloaded }]

// ---- lazily-loaded model handles ----
const handles = {};
const ensure = (k, fn) => (handles[k] ??= fn());
// 2B rather than 0.8B: at 0.8B the model absorbs the user's facts but
// re-attributes them to itself ("I am 21 years old"). Measured 1/3 vs 3/3 on a
// multi-fact recall probe. 1.2GB is still a small download.
const DEFAULT_LLM = 'qwen3.5-2b';
// The chat's active LLM. Loading another LLM from the Models tab replaces it (the
// backend keeps one loaded at a time), so we track it in loadedById/loadedType too
// to keep the Models badges coherent — exactly one LLM ever shows "loaded".
const llm = () => acquire('llm');
const embedder = () => acquire('embedder');
const vlm = () => acquire('vlm');
const stt = () => acquire('stt');
const tts = () => acquire('tts');

// ---- per-tab model selection -------------------------------------------------
// The backend keeps ONE slot PER MODALITY, so each tab can hold its own model and
// tabs of different modalities never fight. `settings.models` is the user's choice
// per modality (persisted); `acquire()` is the single place that turns a choice
// into a loaded handle — download-if-needed, then load, memoized per modality.
const DEFAULT_MODELS = { llm: DEFAULT_LLM, vlm: 'qwen3.5-0.8b-vl', embedder: 'minilm', stt: 'whisper-tiny', tts: 'piper-lessac' };
const MODALITY_LABEL = { llm: 'Language model', vlm: 'Vision model', embedder: 'Embedding model', stt: 'Speech-to-text', tts: 'Text-to-speech' };
const selectedModel = (m) => (settings.models && settings.models[m]) || DEFAULT_MODELS[m];

async function acquire(modality) {
  const id = selectedModel(modality);
  // Re-loading is only needed when the choice changed or nothing is loaded yet.
  if (handles[modality] && handles[`${modality}:id`] === id) return handles[modality];
  handles[`${modality}:id`] = id;
  const p = (async () => {
    setStatus(`loading ${id}…`);
    try {
      const h = await loaders[modality](id);
      loadedById[id] = h; loadedType[id] = modality;
      return h;
    } finally { setStatus('ready'); }
  })();
  // Don't memoize a rejection — one failed download would poison the modality
  // for the rest of the session.
  handles[modality] = p.catch((e) => { delete handles[modality]; delete handles[`${modality}:id`]; throw e; });
  return handles[modality];
}

// Switch a modality to another model: drop the old handle so the next acquire()
// loads the new one. Persisted so the choice survives a restart.
async function selectModel(modality, id) {
  settings.models = { ...(settings.models || {}), [modality]: id };
  try { await store.saveSettings(settings); } catch { /* optional */ }
  const prev = handles[modality];
  delete handles[modality]; delete handles[`${modality}:id`];
  if (prev) { try { await unloaders[modality](await prev); } catch { /* already gone */ } }
  for (const k of Object.keys(loadedById)) if (loadedType[k] === modality) forgetLoaded(k);
  renderModelChips();
  if (currentTab === 'models') renderModels();
}

// The backend keeps one slot PER MODALITY (verified on device: loading a VLM does
// NOT disturb the LLM, but loading a second LLM evicts the first). So the memoized
// handle above goes stale whenever another LLM is loaded, and every later call
// fails with "No model loaded". A host respawn invalidates it too. EVERY LLM caller
// must go through withLlm so the recovery lives in one place instead of only chat.
const STALE_MODEL_RE = /no model|not loaded|model.*load|invalid handle|host exited/i;
async function withLlm(fn) {
  try {
    return await fn(await llm());
  } catch (e) {
    if (!STALE_MODEL_RE.test(e.message || '')) throw e;
    delete handles.llm; delete handles['llm:id'];
    for (const k of Object.keys(loadedById)) if (loadedType[k] === 'llm') forgetLoaded(k); // stale badges
    return fn(await llm());
  }
}

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

// Assistant bubble inner HTML: a collapsible "Reasoning" block (when present)
// above the rendered answer. `streaming` keeps reasoning open + shows a
// placeholder while the answer is still empty. Use the SDK's splitThinking so
// the demo stays in lockstep with commons (newline join when both sides exist).
function assistantHtml(raw, streaming) {
  const { response, thinking } = ra.splitThinking(raw || '');
  let out = '';
  if (thinking) {
    const open = streaming && !response ? ' open' : '';
    out += `<details class="reason"${open}><summary>💭 Reasoning</summary><div class="reasonbody">${escapeHtml(thinking)}</div></details>`;
  }
  out += md(response || (streaming ? '…' : ''));
  return out;
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
  const body = m.role === 'assistant' ? assistantHtml(m.content || '…') : escapeHtml(m.content);
  // No emoji: ⚡ is rendered by Segoe UI Emoji in its OWN colours, so it was the
  // one bitmap glyph in an all-SVG interface. The .metrics flex gap separates.
  const metrics = m.metrics ? `<div class="metrics"><span>${m.metrics.tokens} tokens</span><span>${m.metrics.tps.toFixed(1)} tok/s</span><span>TTFT ${Math.round(m.metrics.ttft)}ms</span></div>` : '';
  // The assistant reply is typeset as PROSE — the stylesheet drops the avatar and
  // the bubble fill, leaving a small-caps label above plain text. Only the user's
  // turn keeps a bubble. This is the single biggest difference from a chat toy.
  const who = m.role === 'assistant' ? 'RunAnywhere' : 'You';
  return `<div class="msg ${m.role}"><div class="col"><div class="who">${who}</div><div class="bubble">${body}</div>${metrics}</div></div>`;
}
// Four openers, each with an icon, a title and the prompt it prefills. Clicking
// one PREFILLS and focuses the composer (it does not fire a request) so the user
// can edit before sending.
const SUGGESTIONS = [
  { icon: '<path d="M8 2h8M9 2v4M15 2v4"/><rect x="4" y="6" width="16" height="16" rx="2"/><path d="M8 12h8M8 16h5"/>',
    title: 'Plan', sub: 'from messy notes', prompt: 'Turn these notes into a clear plan with next steps:\n' },
  { icon: '<path d="m12 19 7-7 3 3-7 7-3-3z"/><path d="m18 13-1.5-7.5L2 2l3.5 14.5L13 18l5-5z"/><path d="m2 2 7.586 7.586"/><circle cx="11" cy="11" r="2"/>',
    title: 'Rewrite', sub: 'clear and warm', prompt: 'Rewrite this to be clear and warm, keeping my meaning:\n' },
  { icon: '<path d="M8 3 4 7l4 4"/><path d="M4 7h16"/><path d="m16 21 4-4-4-4"/><path d="M20 17H4"/>',
    title: 'Compare', sub: 'weigh options', prompt: 'Compare these options and tell me which you would pick and why:\n' },
  { icon: '<path d="M11 12H3M16 6H3M16 18H3"/><path d="m18 9 3 3-3 3"/>',
    title: 'Summarize', sub: 'into next steps', prompt: 'Summarize this into the decisions and next steps:\n' },
];
function greeting() {
  const h = new Date().getHours();
  if (h < 5) return 'Still up?';
  if (h < 12) return 'Good morning';
  if (h < 18) return 'Good afternoon';
  return 'Good evening';
}
function emptyStateHtml() {
  const cards = SUGGESTIONS.map((s, i) => `<button class="sugg" data-i="${i}">
      <span class="si"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">${s.icon}</svg></span>
      <span class="st"><span class="s1">${escapeHtml(s.title)}</span><span class="s2">${escapeHtml(s.sub)}</span></span>
    </button>`).join('');
  return `<div class="empty">
    <div class="halo"><svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 2.6l1.9 5.6 5.6 1.9-5.6 1.9L12 17.6l-1.9-5.6L4.5 10l5.6-1.9L12 2.6z"/><path d="M19 14.2l.9 2.6 2.6.9-2.6.9-.9 2.6-.9-2.6-2.6-.9 2.6-.9.9-2.6z" opacity=".7"/></svg></div>
    <h3>${escapeHtml(greeting())}</h3>
    <p>Ask anything — everything runs privately on your device.</p>
    <div class="suggs">${cards}</div>
  </div>`;
}
function renderChat() {
  const conv = activeConv();
  if (conv && conv.messages.length) {
    $('chatlog').innerHTML = '<div class="thread">' + conv.messages.map(bubbleHtml).join('') + '</div>';
  } else {
    $('chatlog').innerHTML = emptyStateHtml();
    document.querySelectorAll('.sugg').forEach((c) => c.addEventListener('click', () => {
      const inp = $('chatinput');
      inp.value = SUGGESTIONS[+c.dataset.i].prompt;
      inp.focus();
      inp.setSelectionRange(inp.value.length, inp.value.length);
    }));
  }
  $('chatlog').scrollTop = $('chatlog').scrollHeight;
}
function buildPrompt(priorMessages, userText) {
  let sys = settings.systemPrompt;
  // Reasoning mode: ask the model to think in <think></think> first. The SDK's
  // splitThinking (mirrored by assistantHtml) peels that back out for display.
  if (settings.reasoning) sys += '\n\nThink step by step inside <think></think> tags, then give your final answer after the closing tag.';
  const turns = [{ role: 'system', content: sys }];
  for (const m of priorMessages) turns.push({ role: m.role, content: m.content });
  turns.push({ role: 'user', content: userText });
  // formatChat renders the turn markup THIS model was trained on, and strips old
  // <think> blocks so stale reasoning is never replayed as context.
  return ra.formatChat(turns, activeChatTemplate(), { suppressThinking: !settings.reasoning });
}

// The turn markup the ACTIVE model expects. Getting this wrong is why a chat
// appears to lose its memory: llama.cpp wraps an unrecognised prompt as a SINGLE
// user message, so the whole transcript collapses into one turn and the model
// answers as if every message were the first.
function activeChatTemplate() {
  const entry = catalogEntry(selectedModel('llm'));
  return (entry && entry.chatTemplate) || 'chatml';
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
    let result = null;
    // withLlm re-loads once if the handle was evicted by another model.
    await withLlm((h) => {
      asst.content = '';
      return ra.generateStream(h, buildPrompt(prior, text), { temperature: settings.temperature, maxTokens: settings.maxTokens }, (e) => {
        if (e.isFinal) { result = e.result; }
        else { asst.content += e.token; bubble.innerHTML = assistantHtml(asst.content, true); $('chatlog').scrollTop = $('chatlog').scrollHeight; }
      });
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
const loadedType = {}; // key -> model type, so we can enforce one-LLM-at-a-time
function forgetLoaded(key) { delete loadedById[key]; delete loadedType[key]; }
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
        if (loaded) {
          await unloaders[o.type](loaded); forgetLoaded(o.key);
          delete handles[o.type]; delete handles[`${o.type}:id`];
        } else {
          // Loading from here IS selecting: route through the same choke point the
          // per-tab chips use, so the Models tab and the chips can't disagree.
          await selectModel(o.type, o.source);
          await acquire(o.type);
        }
      } catch (e) { b.textContent = 'Error'; btns.forEach((x) => (x.disabled = false)); console.error(e); return; }
      renderModels();
    });
    actions.appendChild(b);
  }
  if (o.custom) {
    actions.appendChild(mkbtn('Remove', async () => {
      if (loadedById[o.key]) { try { await unloaders[o.type](loadedById[o.key]); } catch { /* ignore */ } forgetLoaded(o.key); delete handles[o.type]; delete handles[`${o.type}:id`]; }
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
      // Non-Apache weights (Gemma, Llama, NVIDIA) restrict use; link the terms.
      if (entry.license) {
        sub += entry.licenseUrl
          ? ` · <a href="${escapeHtml(entry.licenseUrl)}" title="Model licence">${escapeHtml(entry.license)}</a>`
          : ` · ${escapeHtml(entry.license)}`;
      }
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
// Reflect the actual compute device (passed by main.js from the addon path).
function applyDeviceUi() {
  const device = new URLSearchParams(location.search).get('device') || 'cpu';
  if (device !== 'gpu') return;
  const label = $('devicelabel');
  if (label) label.textContent = 'GPU · CUDA';
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
  if ($('setreason')) $('setreason').checked = !!settings.reasoning;
}
async function saveSettings() {
  // MERGE, don't rebuild — a wholesale replace drops keys this panel doesn't own
  // (e.g. the per-tab model choices) on every save.
  settings = {
    ...settings,
    systemPrompt: $('setsystem').value,
    temperature: parseFloat($('settemp').value),
    maxTokens: parseInt($('setmax').value, 10) || 256,
    reasoning: !!($('setreason') && $('setreason').checked),
  };
  try { await store.saveSettings(settings); } catch { /* optional */ }
  $('setstatus').textContent = 'saved'; setTimeout(() => ($('setstatus').textContent = ''), 1500);
}

// ---- shared feature helpers (used by UI + self-test) ----
async function runStructured(text) {
  return withLlm((h) => ra.generateStructured(h, `Extract the person as JSON. Text: "${text}"`, {
    type: 'object',
    properties: { name: { type: 'string' }, age: { type: 'integer' }, interests: { type: 'array', items: { type: 'string' }, maxItems: 5 } },
    required: ['name', 'age', 'interests'],
  }));
}
async function runTools(text) {
  // Honour the user's Settings — the native default is only 100 tokens, which can
  // truncate a longer tool call mid-JSON.
  const call = await withLlm((h) => ra.generateToolCall(h, text, TOOLS.map(({ execute, ...t }) => t), {
    temperature: settings.temperature, maxTokens: settings.maxTokens,
  }));
  // A tool call that is never executed is just a parse. Run it locally.
  const tool = TOOLS.find((t) => t.name === call.name);
  let result;
  try { result = tool && tool.execute ? await tool.execute(call.arguments || {}) : '(no local handler)'; }
  catch (e) { result = 'tool failed: ' + (e.message || e); }
  return { ...call, result };
}

// Small transient toast (used by set_timer when it fires).
function flashToast(msg) {
  const el = document.createElement('div');
  el.textContent = msg;
  el.style.cssText = 'position:fixed;left:50%;bottom:28px;transform:translateX(-50%);z-index:200;background:var(--surface-2);border:1px solid var(--line);border-radius:12px;padding:10px 16px;font-size:13.5px;box-shadow:var(--shadow-3);animation:fadeUp .18s var(--ease)';
  document.body.appendChild(el);
  setTimeout(() => el.remove(), 4000);
}
async function runEmbeddings(a, b) {
  const h = await embedder();
  const [ea, eb] = await Promise.all([ra.embed(h, a), ra.embed(h, b)]);
  let dot = 0, na = 0, nb = 0;
  for (let i = 0; i < ea.length; i++) { dot += ea[i] * eb[i]; na += ea[i] * ea[i]; nb += eb[i] * eb[i]; }
  return dot / (Math.sqrt(na) * Math.sqrt(nb) || 1);
}
// ---- RAG (Knowledge tab) ----
// Lazy singleton: memoize the in-flight promise so concurrent first-use (ingest
// + ask) share one download/register/create instead of orphaning a handle.
let ragSession = null;
let ragSessionPromise = null;
async function ragEnsureSession() {
  if (ragSession != null) return ragSession;
  if (ragSessionPromise) return ragSessionPromise;
  ragSessionPromise = (async () => {
    setStatus('preparing knowledge base…');
    // Single SDK entry point — owns download + registry enums + session create.
    ragSession = await ra.ragCreateSessionFromCatalog({
      embeddingModelId: 'minilm', llmModelId: DEFAULT_LLM,
      topK: 3, chunkSize: 512, chunkOverlap: 64, maxContextTokens: 1024,
    });
    return ragSession;
  })().catch((e) => {
    ragSessionPromise = null; // allow retry after failure
    throw e;
  });
  return ragSessionPromise;
}
function ragStatsText(s) {
  // Never render nothing — an empty slot beside the buttons reads as a failed load.
  if (!s || !s.indexedDocuments) return 'No documents yet';
  return `${s.indexedDocuments} document${s.indexedDocuments === 1 ? '' : 's'} · ${s.indexedChunks} chunk${s.indexedChunks === 1 ? '' : 's'} indexed`;
}
function renderRagSources(chunks) {
  const el = $('ragsources');
  if (!chunks || !chunks.length) { el.innerHTML = ''; return; }
  el.innerHTML = '<div class="label" style="margin-top:16px">Sources</div>' + chunks.map((c) => {
    const src = c.sourceDocument ? escapeHtml(c.sourceDocument) : 'document';
    const score = typeof c.similarityScore === 'number' ? c.similarityScore.toFixed(3) : '';
    return `<div class="ragchunk"><div class="meta"><span>${src}</span><span class="ragscore">${score}</span></div><div class="txt">${escapeHtml(c.text || '')}</div></div>`;
  }).join('');
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
let currentTab = 'chat';
function showTab(name) {
  currentTab = name;
  document.querySelectorAll('.nav button').forEach((x) => x.classList.toggle('active', x.dataset.tab === name));
  document.querySelectorAll('.panel').forEach((x) => x.classList.toggle('active', x.id === name));
  const btn = document.querySelector(`.nav button[data-tab="${name}"]`);
  if (btn) {
    $('sectiontitle').textContent = btn.textContent.trim();
    // Selecting a workbench keeps the Developer group open so the active row is visible.
    const grp = btn.closest('details');
    if (grp) grp.open = true;
  }
  closePicker();
  if (name !== 'voice' && voiceCleanup) voiceCleanup(); // release the mic on tab change
  renderModelChips();
  if (name === 'models') renderModels();
}

// ---- model chip + picker ------------------------------------------------------
// Which modalities each tab lets you choose. Slots are per-modality, so a tab only
// ever shows the models it actually uses.
const TAB_MODALITIES = {
  chat: ['llm'], vision: ['vlm'], embeddings: ['embedder'], voice: ['stt', 'llm', 'tts'],  // the spoken reply uses the LLM too
  rag: ['embedder', 'llm'], structured: ['llm'], tools: ['llm'],
};
const CHIP_ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3 4 7v10l8 4 8-4V7z"/><path d="m8 12 3 3 5-6"/></svg>';

let openPicker = null;
function closePicker() {
  if (openPicker) { openPicker.remove(); openPicker = null; }
}
document.addEventListener('click', (e) => {
  if (openPicker && !openPicker.contains(e.target) && !e.target.closest('.modelchip')) closePicker();
});

function catalogEntry(id) {
  const c = catalogCache || {};
  if (c[id]) return c[id];
  const custom = customModels.find((m) => m.id === id);
  return custom ? { label: custom.label || id, type: custom.type } : null;
}
let catalogCache = null;

function renderModelChips() {
  const slot = $('chipslot');
  if (!slot) return;
  const mods = TAB_MODALITIES[currentTab] || [];
  slot.innerHTML = '';
  for (const m of mods) {
    const id = selectedModel(m);
    const entry = catalogEntry(id);
    const btn = document.createElement('button');
    btn.className = 'modelchip';
    btn.title = `${MODALITY_LABEL[m]} — click to change`;
    btn.innerHTML =
      `<span class="mark">${CHIP_ICON}</span>` +
      `<span class="txt"><span class="t1">${escapeHtml((entry && entry.label) || id)}</span>` +
      `<span class="t2">${escapeHtml(MODALITY_LABEL[m])}</span></span>` +
      '<svg class="chev" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m6 9 6 6 6-6"/></svg>';
    btn.onclick = (e) => { e.stopPropagation(); togglePicker(btn, m); };
    slot.appendChild(btn);
  }
}

async function togglePicker(anchor, modality) {
  if (openPicker && openPicker.dataset.modality === modality) { closePicker(); return; }
  closePicker();
  const box = document.createElement('div');
  box.className = 'picker';
  box.dataset.modality = modality;
  box.innerHTML = `<div class="phead">${escapeHtml(MODALITY_LABEL[modality])}</div><div class="note">Loading…</div>`;
  document.body.appendChild(box);
  const r = anchor.getBoundingClientRect();
  box.style.top = `${r.bottom + 8}px`;
  box.style.left = `${Math.max(12, Math.min(r.left, window.innerWidth - 352))}px`;
  openPicker = box;

  const [cat, status] = await Promise.all([ra.catalog(), ra.modelStatus()]);
  catalogCache = cat;
  if (openPicker !== box) return; // closed while loading
  const items = Object.entries(cat).filter(([, e]) => e.type === modality)
    .concat(customModels.filter((m) => m.type === modality).map((m) => [m.id, { label: m.label, type: m.type, custom: true }]));
  const active = selectedModel(modality);

  box.innerHTML = `<div class="phead">${escapeHtml(MODALITY_LABEL[modality])}</div>`;
  for (const [id, entry] of items) {
    const st = status[id] || {};
    const isActive = id === active;
    const stateCls = isActive ? 'active' : st.downloaded ? 'ready' : 'get';
    const stateTxt = isActive ? 'Active' : st.downloaded ? 'Ready' : 'Download';
    const bits = [entry.params, st.downloaded ? fmtSize(st.sizeBytes) : entry.sizeMB ? '~' + fmtMB(entry.sizeMB) : '', entry.license].filter(Boolean);
    const row = document.createElement('button');
    row.className = 'row';
    row.innerHTML =
      `<span class="info"><span class="nm">${escapeHtml(entry.label || id)}</span>` +
      `<span class="meta">${escapeHtml(bits.join(' · '))}${entry.heavy ? ' · heavy' : ''}</span></span>` +
      `<span class="state ${stateCls}">${stateTxt}</span>`;
    row.onclick = async (e) => {
      e.stopPropagation();
      if (isActive) { closePicker(); return; }
      const stateEl = row.querySelector('.state');
      if (!st.downloaded) {
        stateEl.textContent = '0%';
        const bar = document.createElement('div');
        bar.className = 'bar'; bar.innerHTML = '<div></div>';
        row.after(bar);
        try {
          await ra.downloadModel(id, (p) => {
            const pct = Math.round(p.percent || 0);
            stateEl.textContent = pct + '%';
            bar.firstElementChild.style.width = pct + '%';
          });
        } catch (err) { stateEl.textContent = 'Failed'; console.error(err); return; }
        bar.remove();
      }
      await selectModel(modality, id);
      closePicker();
    };
    box.appendChild(row);
  }
  if (!items.length) box.innerHTML += '<div class="note">No models of this type in the catalog yet.</div>';
}
document.querySelectorAll('.nav button').forEach((b) => b.addEventListener('click', () => showTab(b.dataset.tab)));

// ---- UI wiring ----
// Default to the OS preference; an explicit choice is remembered in settings.
// Nothing in a UI should fail silently. Every handler catches its own errors;
// this is the net that catches whatever a future one forgets.
window.addEventListener('unhandledrejection', (e) => {
  const msg = (e.reason && e.reason.message) || String(e.reason || 'unknown error');
  console.error('unhandled rejection:', e.reason);
  try { flashToast('Something went wrong: ' + msg); } catch { /* toast is best-effort */ }
});
window.addEventListener('error', (e) => { console.error('renderer error:', e.error || e.message); });

function applyTheme(mode) {
  const os = window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark';
  document.documentElement.dataset.theme = mode === 'light' || mode === 'dark' ? mode : os;
}
function toggleTheme() {
  const next = document.documentElement.dataset.theme === 'light' ? 'dark' : 'light';
  settings.theme = next;
  applyTheme(next);
  Promise.resolve(store.saveSettings(settings)).catch(() => {});
}

function wireUi() {
  applyTheme(settings.theme);
  const tt = $('themetoggle');
  if (tt) tt.addEventListener('click', toggleTheme);
  applySettingsToUi();
  applyDeviceUi();
  renderSidebar(); renderChat();
  // Warm the catalog so the model chips can show real labels immediately.
  Promise.resolve(ra.catalog()).then((c) => { catalogCache = c; renderModelChips(); }).catch(() => {});
  renderModelChips();
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
  $('toolsgo').addEventListener('click', out('toolsout', async () => {
    const c = await runTools($('toolstext').value);
    return `${c.name}(${JSON.stringify(c.arguments)})
→ ${c.result}`;
  }));
  $('embgo').addEventListener('click', async () => {
    const a = $('emba').value || $('emba').placeholder;
    const b = $('embb').value || $('embb').placeholder;
    const el = $('embout');
    $('embgo').disabled = true; el.textContent = '…'; setStatus('working…');
    try {
      const score = await runEmbeddings(a, b);
      const pct = Math.max(0, Math.min(1, score)) * 100;
      el.innerHTML = `<div><div class="figure">${score.toFixed(3)}</div>` +
        `<div class="figcap">Cosine similarity</div>` +
        `<div class="meter"><i style="width:${pct.toFixed(1)}%"></i></div></div>`;
    } catch (e) { el.textContent = 'error: ' + e.message; }
    finally { $('embgo').disabled = false; setStatus('ready'); }
  });

  $('ragadd').addEventListener('click', async () => {
    const text = $('ragdoc').value.trim();
    if (!text) return;
    $('ragadd').disabled = true;
    try {
      const h = await ragEnsureSession();
      const stats = await ra.ragIngest(h, { text });
      $('ragstats').textContent = ragStatsText(stats);
      $('ragdoc').value = '';
    } catch (e) { $('ragstats').textContent = 'error: ' + e.message; }
    finally { $('ragadd').disabled = false; setStatus('ready'); }
  });
  $('ragclear').addEventListener('click', async () => {
    if (ragSession == null) { $('ragstats').textContent = ''; return; }
    try { const s = await ra.ragClear(ragSession); $('ragstats').textContent = ragStatsText(s); $('ragout').textContent = ''; renderRagSources([]); } catch (e) { $('ragstats').textContent = 'error: ' + e.message; }
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
      const h = await ragEnsureSession();
      const res = await ra.ragQuery(h, { question: q, maxTokens: settings.maxTokens, temperature: settings.temperature });
      // Render reasoning + answer SEPARATELY (commons already split thinkingContent
      // out) — do NOT re-wrap in <think> tags, or a literal </think> in retrieved
      // document text would mis-split the answer into the reasoning drawer.
      const reason = res.thinkingContent
        ? `<details class="reason"><summary>💭 Reasoning</summary><div class="reasonbody">${escapeHtml(res.thinkingContent)}</div></details>`
        : '';
      $('ragout').innerHTML = reason + md(res.answer || '');
      renderRagSources(res.retrievedChunks);
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
// Mic float samples -> 16 kHz PCM16 bytes for STT. Uses the SDK's block-averaging
// downsample, not a nearest-neighbour pick: at 48k->16k, dropping samples folds
// everything above 8 kHz back into the band Whisper reads.
function toPcm16At16k(samples, rate) {
  return ra.pcm16Bytes(rate === 16000 ? samples : ra.downsample(samples, rate, 16000));
}

// ---- voice: a 4-state machine (idle | listening | thinking | speaking) --------
// Tap to start, tap to stop (or let it end itself on silence); tap while it is
// speaking to barge in. All visual state is driven by data-state on the root, so
// this code only sets state, a --level, and the transcript text.
function wireVoice() {
  const root = $('voiceroot');
  const orb = $('voiceorb');
  const statusEl = $('voicestatus');
  const hintEl = $('voicehint');
  const errEl = $('voiceerror');
  const transcript = $('voicetranscript');
  const cc = captureController();

  // One long-lived output context so a reply can be interrupted (barge-in).
  let playCtx = null;
  let playing = null;
  let state = 'idle';
  let busy = false;          // a turn is in flight; ignore re-entrant taps
  let levelRaf = 0;
  let level = 0;             // smoothed mic RMS, 0..1

  const COPY = {
    idle: ['Tap to talk', 'Speech, reasoning and speech-synthesis all run on this device.'],
    listening: ['Listening…', 'Tap again when you are done — or just stop speaking.'],
    thinking: ['Thinking…', 'Transcribing and composing a reply on-device.'],
    speaking: ['Speaking…', 'Tap to interrupt.'],
  };
  function setVoiceState(s) {
    state = s;
    root.dataset.state = s;
    statusEl.textContent = COPY[s][0];
    hintEl.textContent = COPY[s][1];
    orb.setAttribute('aria-label', COPY[s][0]);
    setStatus(s === 'idle' ? 'ready' : s + '…');
  }
  const showError = (msg) => { errEl.hidden = false; errEl.textContent = msg; };
  const clearError = () => { errEl.hidden = true; errEl.textContent = ''; };

  function stopPlayback() {
    if (playing) { try { playing.onended = null; playing.stop(); } catch { /* already ended */ } playing = null; }
  }

  // Level meter: painted from ONE rAF loop. Never write the DOM from the audio
  // callback — that runs on the audio thread's cadence and thrashes layout.
  function startLevelLoop() {
    cancelAnimationFrame(levelRaf);
    const tick = () => {
      root.style.setProperty('--level', level.toFixed(3));
      if (state === 'listening') levelRaf = requestAnimationFrame(tick);
      else root.style.setProperty('--level', '0');
    };
    levelRaf = requestAnimationFrame(tick);
  }

  async function beginListening() {
    clearError();
    transcript.hidden = true;
    try {
      await cc.start();
    } catch (e) {
      showError('Could not open the microphone: ' + (e.message || e));
      setVoiceState('idle');
      return;
    }
    setVoiceState('listening');
    startLevelLoop();

    // Endpointing: learn the room's noise floor for ~400ms, then commit the turn
    // after a stretch of silence. Self-contained (no calibration state to poison)
    // and always overridable by tapping.
    let noiseFloor = 1, heardSpeech = false, silentFor = 0, elapsed = 0;
    const autoStop = $('voicevad');
    cc.onFrame((frame, rate) => {
      const r = ra.rms(frame);
      level = Math.min(1, Math.max(level * 0.72, r * 9)); // smooth + scale for display
      const ms = (frame.length / rate) * 1000;
      elapsed += ms;
      if (elapsed < 400) { noiseFloor = Math.min(noiseFloor, r); return; }
      const gate = Math.max(noiseFloor * 3, 0.012);
      if (r > gate) { heardSpeech = true; silentFor = 0; } else if (heardSpeech) silentFor += ms;
      const done = (autoStop && autoStop.checked && heardSpeech && silentFor > 800) || elapsed > 30000;
      if (done && state === 'listening') finishTurn();
    });
  }

  async function finishTurn() {
    if (busy) return;
    busy = true;
    const rec = cc.stop();
    level = 0;
    if (!rec || !rec.samples.length) { setVoiceState('idle'); busy = false; return; }
    setVoiceState('thinking');
    try {
      const heard = (await ra.transcribe(await stt(), toPcm16At16k(rec.samples, rec.rate)) || '').trim();
      if (!heard) { showError('I did not catch that — try again a little closer to the mic.'); setVoiceState('idle'); return; }
      transcript.hidden = false;
      $('voiceheard').textContent = heard;
      $('voicereply').textContent = '';
      let reply = '';
      // Ask for speech, not a document — a spoken answer should have no markdown
      // in it at all.
      const spokenStyle = settings.systemPrompt +
        ' You are answering out loud. Reply in one or two short spoken sentences, in plain words.' +
        ' Never use markdown, asterisks, bullet points, headings or mathematical notation.';
      // Same templating as chat — a raw "User:/Assistant:" string would be
      // wrapped as one turn and answered generically.
      // A spoken reply must never wait on visible deliberation.
      const voicePrompt = ra.formatChat(
        [{ role: 'system', content: spokenStyle }, { role: 'user', content: heard }],
        activeChatTemplate(),
        { suppressThinking: true }
      );
      await withLlm((h) => ra.generate(h, voicePrompt, {
        temperature: settings.temperature, maxTokens: settings.maxTokens,
      }, (t) => { reply += t; $('voicereply').textContent = ra.speakableText(ra.splitThinking(reply).response); }));
      // The prompt is a request, not a guarantee: a small model still emits
      // "**Paris**", and the TTS voice pronounces that as "asterisk asterisk
      // Paris". speakableText is what actually makes the audio clean — it also
      // says "20 degrees Celsius" and "5 times 3" instead of spelling symbols.
      reply = ra.speakableText(ra.splitThinking(reply).response);
      $('voicereply').textContent = reply;
      if (!reply) { setVoiceState('idle'); return; }

      const audio = await ra.synthesize(await tts(), reply);
      if (!audio || !audio.samples || !audio.samples.length) { setVoiceState('idle'); return; } // createBuffer(0) throws
      setVoiceState('speaking');
      playCtx = playCtx || new AudioContext();
      if (playCtx.state === 'suspended') await playCtx.resume();
      const buf = playCtx.createBuffer(1, audio.samples.length, audio.sampleRate);
      buf.getChannelData(0).set(audio.samples);
      const src = playCtx.createBufferSource();
      src.buffer = buf; src.connect(playCtx.destination);
      playing = src;
      await new Promise((r) => { src.onended = r; src.start(); });
      playing = null;
    } catch (e) {
      showError(e.message || String(e));
    } finally {
      busy = false;
      if (state !== 'listening') setVoiceState('idle');
    }
  }

  // One tap does the right thing for the current state.
  orb.addEventListener('click', () => {
    if (busy && state === 'thinking') return;         // can't interrupt generation (no cancel API)
    if (state === 'idle') beginListening();
    else if (state === 'listening') finishTurn();
    else if (state === 'speaking') { stopPlayback(); setVoiceState('idle'); } // barge-in
  });
  orb.addEventListener('keydown', (e) => { if (e.key === ' ' || e.key === 'Enter') { e.preventDefault(); orb.click(); } });

  // Leaving the tab must release the mic — otherwise the OS keeps showing the
  // recording indicator and the capture keeps running in the background.
  voiceCleanup = () => {
    if (state === 'listening') { cc.stop(); level = 0; }
    stopPlayback();
    if (state !== 'idle') setVoiceState('idle');
  };
  setVoiceState('idle');
}
let voiceCleanup = null;
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
    await withLlm((h) => ra.generateStream(h, buildPrompt([], 'Say hello in one short sentence.'), { maxTokens: 24 }, (e) => { if (!e.isFinal) reply += e.token; }));
    if (!reply.trim()) throw new Error('empty chat reply');
    log('[selftest] chat OK: ' + JSON.stringify(reply.trim().slice(0, 70)));

    const obj = await runStructured('Marie Curie was a 66 year old Polish physicist who loved chemistry.');
    if (typeof obj.name !== 'string' || typeof obj.age !== 'number' || !Array.isArray(obj.interests)) throw new Error('structured shape wrong');
    log('[selftest] structured OK: ' + JSON.stringify(obj));

    const call = await runTools('What time is it right now?');
    if (!TOOLS.some((t) => t.name === call.name)) throw new Error('bad tool');
    if (call.result == null) throw new Error('tool did not execute');
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
    // Accept ANY persisted object — gating on systemPrompt discarded saved
    // settings whose prompt was cleared, and would drop the model choices too.
    try {
      const s = await store.loadSettings();
      // migrateSettings upgrades a persisted copy of a SUPERSEDED default while
      // leaving anything the user actually customised alone.
      if (s && typeof s === 'object') settings = store.migrateSettings(s, settings);
    } catch { /* ignore */ }
    try { const c = await store.loadConversations(); if (c && Array.isArray(c.conversations)) { conversations = c.conversations; nextConvId = c.nextConvId || conversations.length + 1; activeId = conversations[0] ? conversations[0].id : null; } } catch { /* ignore */ }
    try { const cm = await store.loadCustomModels(); if (Array.isArray(cm)) customModels = cm; } catch { /* ignore */ }
  }
  setStatus('ready');
  if (IS_SELFTEST) { setStatus('self-test…'); await selfTest(); } else { wireUi(); }
})().catch((e) => {
  setStatus('error: ' + (e && e.message)); console.error(e);
  if (IS_SELFTEST) { try { window.runanywhereTest.log('[selftest] STARTUP ERROR: ' + (e && e.message) + '\n'); window.runanywhereTest.done(false); } catch { /* ignore */ } }
});
