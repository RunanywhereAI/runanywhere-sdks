// RunAnywhere demo (renderer) — bundled with esbuild, built on the v3 SDK facade.
//
// The renderer imports the SDK and builds the same RunAnywhere surface the main
// process has, over the MessagePort the preload exposed. Generation names a model
// in `options.model`; the SDK auto-loads (and downloads) it, so there is no
// handle juggling here. The app owns only its model catalog and its UI.
import { connectRenderer } from '../../../sdk/runanywhere-electron/dist/rpc/renderer.js';
import { ModelRegistration } from '../../../sdk/runanywhere-electron/dist/namespaces/models.js';
import * as raAudio from '../../../sdk/runanywhere-electron/dist/audio.js';
import { CATALOG } from './model-catalog.js';
import { TAB_MODALITIES, modalitiesToRelease } from './model-policy.js';
import { createTurnGuard } from './turn-guard.js';

const ra = connectRenderer();
const store = window.appStore;

const $ = (id) => document.getElementById(id);
const setStatus = (s) => { $('status').textContent = s; $('statuswrap').classList.toggle('busy', s !== 'ready'); };
const escapeHtml = (s) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const fmtSize = (b) => (b > 1e9 ? (b / 1e9).toFixed(1) + ' GB' : b > 1e6 ? (b / 1e6).toFixed(0) + ' MB' : (b / 1e3).toFixed(0) + ' KB');
const fmtMB = (mb) => (mb >= 1000 ? (mb / 1000).toFixed(1) + ' GB' : mb + ' MB');

// Built-in tools the model can call, ported from the Android sample's
// BuiltInTools. `execute` runs locally when the model asks for the tool (the SDK
// drives the loop and calls back into this renderer). Each returns an object,
// which the SDK serializes as the tool result.
const TOOLS = [
  {
    name: 'get_current_time',
    description: 'Returns the current date, time and timezone on the device.',
    parameters: { type: 'object', properties: {}, required: [] },
    execute: () => {
      const now = new Date();
      return {
        datetime: now.toLocaleString(),
        iso8601: now.toISOString(),
        timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      };
    },
  },
  {
    name: 'get_device_info',
    description: 'Returns details about the device: platform, browser engine and CPU cores.',
    parameters: { type: 'object', properties: {}, required: [] },
    execute: () => ({
      platform: navigator.platform,
      user_agent: navigator.userAgent,
      language: navigator.language,
      cpu_cores: navigator.hardwareConcurrency,
    }),
  },
  {
    name: 'get_battery_level',
    description: 'Returns the current battery charge level as a percentage.',
    parameters: { type: 'object', properties: {}, required: [] },
    execute: async () => {
      try {
        const b = await navigator.getBattery();
        return { battery_percent: Math.round(b.level * 100) + '%', charging: b.charging };
      } catch {
        return { battery_percent: 'unknown' };
      }
    },
  },
  {
    name: 'calculate',
    description: "Evaluates a math expression with + - * / and parentheses, e.g. '(3 + 4) * 2'.",
    parameters: {
      type: 'object',
      properties: { expression: { type: 'string', description: "The expression to evaluate, e.g. '(3 + 4) * 2'." } },
      required: ['expression'],
    },
    execute: ({ expression }) => {
      const src = String(expression || '');
      // Arithmetic only; never eval() arbitrary model output.
      if (!/^[\d\s+\-*/().%]+$/.test(src)) return { error: 'unsupported expression (digits and + - * / ( ) only)' };
      try { return { result: String(Function(`"use strict";return (${src})`)()) }; }
      catch { return { error: `could not evaluate '${src}'` }; }
    },
  },
];

const DEFAULT_SYSTEM_PROMPT =
  'You are RunAnywhere, a helpful assistant running entirely on the user\'s device. ' +
  'Be accurate and clear, and keep answers to a sentence or two unless the user asks for more. ' +
  'Treat facts the user shares as being about them. If you are unsure, say so instead of guessing.';

// A dedicated spoken-conversation prompt for the Voice tab: the reply is read
// aloud by TTS, so it must be short, plain, and free of anything unspeakable.
const VOICE_SYSTEM_PROMPT =
  'You are RunAnywhere, a friendly voice assistant running on the user\'s device. ' +
  'You are speaking out loud, so answer in one or two short, natural sentences. ' +
  'Use plain conversational language. Never use markdown, bullet points, code, headings, emoji, or symbols; ' +
  'say numbers and units as words. If you do not know, say so briefly.';
let settings = { systemPrompt: DEFAULT_SYSTEM_PROMPT, temperature: 0.3, maxTokens: 1024, reasoning: false, tools: false };
let conversations = [];
let activeId = null;
let nextConvId = 1;
let customModels = []; // [{ id, source, type, label, downloaded, primary? }]

// ---- per-tab model selection -------------------------------------------------
// The SDK keeps one model per modality and auto-loads on demand, so the app only
// tracks the user's chosen id per modality (persisted). `selectedModel` turns a
// modality into the id passed as options.model; the SDK loads/downloads it.
const DEFAULT_LLM = 'qwen3-0.6b-q4_k_m';
const DEFAULT_MODELS = { llm: DEFAULT_LLM, vlm: 'smolvlm2-256m-video-instruct-q8_0', embedder: 'all-minilm-l6-v2', stt: 'sherpa-onnx-whisper-tiny.en', tts: 'vits-piper-en_US-lessac-medium' };
const MODALITY_LABEL = { llm: 'Language model', vlm: 'Vision model', embedder: 'Embedding model', stt: 'Speech-to-text', tts: 'Text-to-speech' };
const selectedModel = (m) => (settings.models && settings.models[m]) || DEFAULT_MODELS[m];

// The app modality -> the SDK registration modality + framework + archive shape.
const MODALITY_TO_SDK = {
  llm: 'language',
  vlm: 'multimodal',
  embedder: 'embedding',
  stt: 'speechRecognition',
  tts: 'speechSynthesis',
  vad: 'voiceActivityDetection',
  segmentation: 'semanticSegmentation',
};

// Track the id last used per modality so leaving a screen can free what it no
// longer needs (the SDK keeps a model resident until it is unloaded or replaced).
const loadedByModality = {};

async function selectModel(modality, id) {
  settings.models = { ...(settings.models || {}), [modality]: id };
  try { await store.saveSettings(settings); } catch { /* optional */ }
  renderModelChips();
  if (currentTab === 'models') renderModels();
}

// Free the models the current screen does not need. Best-effort: an unload of a
// slot that holds nothing is a no-op.
async function releaseUnneeded() {
  const loaded = Object.keys(loadedByModality).filter((m) => loadedByModality[m]);
  const drop = modalitiesToRelease(currentTab, null, loaded);
  for (const m of drop) {
    const id = loadedByModality[m];
    delete loadedByModality[m];
    try { await ra.models.unload(id); } catch { /* already gone */ }
  }
}

// Note the model a tab is about to use, so releaseUnneeded can later free it.
function noteUse(modality) {
  loadedByModality[modality] = selectedModel(modality);
  return selectedModel(modality);
}

// ---- model catalog registration ---------------------------------------------
// The catalog lives in the app (model-catalog.js). At boot we register every row
// with the SDK so it can be named by id, exactly as the iOS/Android samples do.
// Map a filename to its SDK file role so commons pairs projector/vocab/tokenizer
// files with the primary model.
function fileRole(filename, index) {
  const f = (filename || '').toLowerCase();
  if (/mmproj/.test(f)) return 'visionProjector';
  if (/^vocab/.test(f)) return 'vocabulary';
  if (/token/.test(f)) return 'tokenizer';
  if (/config/.test(f)) return 'config';
  return index === 0 ? 'primary' : 'companion';
}

function registrationFor(id, row) {
  const common = { id, name: row.label || id, modality: MODALITY_TO_SDK[row.type], contextLength: row.contextLength };
  if (row.archive) {
    return ModelRegistration.archive(row.files[0].url, row.archive.structure, {
      ...common,
      framework: row.framework,
      archiveType: row.archive.type,
    });
  }
  if (row.files.length > 1 || row.multiFile) {
    return ModelRegistration.multiFile(
      row.files.map((f, i) => ({ url: f.url, filename: f.filename, role: fileRole(f.filename, i) })),
      { ...common, framework: row.framework }
    );
  }
  return ModelRegistration.url(row.files[0].url, {
    ...common,
    framework: row.framework,
    supportsThinking: !!row.thinking,
  });
}

async function registerAllModels() {
  for (const [id, row] of Object.entries(CATALOG)) {
    try { await ra.models.register(registrationFor(id, row)); } catch (e) { console.warn('register', id, e.message); }
  }
  for (const m of customModels) {
    try { await ra.models.register(customRegistration(m)); } catch (e) { console.warn('register custom', m.id, e.message); }
  }
}

function customRegistration(m) {
  const common = { id: m.id, name: m.label || m.id, modality: MODALITY_TO_SDK[m.type] };
  if (looksRemote(m.source)) {
    // A HuggingFace repo/URL for a single-file GGUF.
    const url = /^https?:/i.test(m.source) ? m.source : `https://huggingface.co/${m.source}`;
    return ModelRegistration.url(url, { ...common, framework: m.type === 'llm' ? 'llamaCpp' : 'onnx' });
  }
  return ModelRegistration.local(m.source, { ...common, framework: m.type === 'llm' ? 'llamaCpp' : 'onnx' });
}

// Downloaded-state cache, recomputed from the registry.
let downloadedIds = new Set();
async function refreshStatus() {
  try {
    const models = await ra.models.list();
    downloadedIds = new Set(models.filter((m) => m.downloaded).map((m) => m.id));
  } catch (e) { console.warn('models.list', e.message); }
  return downloadedIds;
}

// ---- minimal, XSS-safe markdown (escape first, then format) ----
function md(text) {
  const blocks = [];
  let s = escapeHtml(text).replace(/```([\s\S]*?)```/g, (_m, c) => { blocks.push(c); return `${blocks.length - 1}`; });
  s = s.replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/(^|[^*])\*([^*]+)\*/g, '$1<em>$2</em>')
    .replace(/\[([^\]]+)\]\((https?:[^)]+)\)/g, '<a href="$2">$1</a>');
  s = s.split(/\n{2,}/).map((p) => {
    const t = p.trim();
    if (/^\d+$/.test(t)) return t.replace(/(\d+)/g, (_m, i) => `<pre><code>${blocks[+i]}</code></pre>`);
    const lines = p.split('\n');
    if (lines.some((l) => /^\s*[-*] /.test(l)) && lines.every((l) => !l.trim() || /^\s*[-*] /.test(l))) {
      return '<ul>' + lines.filter((l) => l.trim()).map((l) => '<li>' + l.replace(/^\s*[-*] /, '') + '</li>').join('') + '</ul>';
    }
    if (/^#{1,3} /.test(p)) { const n = p.match(/^#+/)[0].length; return `<h${n + 2}>${p.replace(/^#+ /, '')}</h${n + 2}>`; }
    return '<p>' + p.replace(/\n/g, '<br>') + '</p>';
  }).join('');
  return s.replace(/(\d+)/g, (_m, i) => `<pre><code>${blocks[+i]}</code></pre>`);
}

// Assistant bubble: a collapsible "Reasoning" block (when present) above the
// answer. The SDK already splits reasoning from the answer, so we render the two
// parts directly rather than re-parsing tags.
function assistantHtml(response, thinking, streaming) {
  let out = '';
  if (thinking && thinking.trim()) {
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
  const body = m.role === 'assistant' ? assistantHtml(m.content || '…', m.thinking || '', false) : escapeHtml(m.content);
  const metrics = m.metrics ? `<div class="metrics"><span>${m.metrics.tokens} tokens</span><span>${m.metrics.tps.toFixed(1)} tok/s</span><span>TTFT ${Math.round(m.metrics.ttft)}ms</span></div>` : '';
  const who = m.role === 'assistant' ? 'RunAnywhere' : 'You';
  return `<div class="msg ${m.role}"><div class="col"><div class="who">${who}</div><div class="bubble">${body}</div>${metrics}</div></div>`;
}
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

// Build the chat message list. The SDK templates it for the active model (system
// turn -> systemPrompt, trailing user -> prompt, the rest -> history).
function buildMessages(priorMessages, userText) {
  const turns = [{ role: 'system', content: settings.systemPrompt }];
  for (const m of priorMessages) turns.push({ role: m.role, content: m.content });
  turns.push({ role: 'user', content: userText });
  return turns;
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
  const prior = conv.messages.slice();
  conv.messages.push({ role: 'user', content: text });
  const asst = { role: 'assistant', content: '', thinking: '' };
  conv.messages.push(asst);
  if (!conv.title) { conv.title = text.slice(0, 40); renderSidebar(); }
  renderChat();
  const bubble = [...$('chatlog').querySelectorAll('.msg.assistant .bubble')].pop();
  bubble.classList.add('streaming');
  setStatus('generating…');
  try {
    // Tool-calling turn: the model may call the built-in tools; the SDK runs the
    // loop and calls back into this renderer to execute each one.
    if (settings.tools) {
      setStatus('running tools…');
      const out = await runTools(text);
      const calls = out.toolCalls.map((c) => `\`${c.name}(${fmtArgs(c.arguments)})\``).join(', ');
      asst.content = (calls ? `Called ${calls}\n\n` : '') + (out.text || (calls ? '' : '(no response)'));
      bubble.classList.remove('streaming');
      renderChat();
      persist();
      return;
    }
    await releaseUnneeded();
    const model = noteUse('llm');
    const messages = buildMessages(prior, text);
    let result = null;
    for await (const ev of ra.llm.generateStream(messages, {
      model,
      reasoning: { mode: settings.reasoning ? 'on' : 'off' },
      temperature: settings.temperature,
      maxOutputTokens: settings.maxTokens,
    })) {
      if (ev.isFinal) { result = ev.result; }
      else if (ev.isThinking) { asst.thinking += ev.token; bubble.innerHTML = assistantHtml(asst.content, asst.thinking, true); $('chatlog').scrollTop = $('chatlog').scrollHeight; }
      else { asst.content += ev.token; bubble.innerHTML = assistantHtml(asst.content, asst.thinking, true); $('chatlog').scrollTop = $('chatlog').scrollHeight; }
    }
    asst.content = (result?.text || asst.content).trim();
    asst.thinking = (result?.thinking || asst.thinking || '').trim();
    if (result) asst.metrics = { tokens: result.metrics.outputTokens, tps: result.metrics.tokensPerSecond, ttft: result.metrics.timeToFirstTokenMs };
    bubble.classList.remove('streaming');
    renderChat();
    persist();
  } catch (e) { asst.content = 'error: ' + e.message; renderChat(); }
  finally { generating = false; $('chatsend').disabled = false; setStatus('ready'); }
}

// ---- models panel ----
const svg = (d) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${d}</svg>`;
const TYPE_ICON = {
  llm: svg('<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>'),
  vlm: svg('<rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="9" cy="9" r="2"/><path d="m21 15-5-5L5 21"/>'),
  embedder: svg('<circle cx="5" cy="6" r="2"/><circle cx="19" cy="7" r="2"/><circle cx="12" cy="18" r="2"/><path d="M7 6h10M6 8l5 8M18 9l-5 7"/>'),
  stt: svg('<rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 10a7 7 0 0 0 14 0M12 19v3"/>'),
  tts: svg('<path d="M11 5 6 9H2v6h4l5 4zM19 9a5 5 0 0 1 0 6"/>'),
  vad: svg('<path d="M2 12h3l3-8 4 16 3-10 2 4h5"/>'),
  segmentation: svg('<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M3 12h18M12 3v18"/>'),
  diarization: svg('<circle cx="9" cy="7" r="3"/><circle cx="17" cy="9" r="2.5"/><path d="M3 20a6 6 0 0 1 12 0M14 20a5 5 0 0 1 7-3"/>'),
};
const TYPE_LABEL = { llm: 'Language model', vlm: 'Vision-language', embedder: 'Embeddings', stt: 'Speech-to-text', tts: 'Text-to-speech', vad: 'Voice activity', segmentation: 'Segmentation', diarization: 'Diarization' };
const GROUP_ORDER = [['llm', 'Language models'], ['vlm', 'Vision-language'], ['stt', 'Speech-to-text'], ['tts', 'Text-to-speech'], ['embedder', 'Embeddings'], ['vad', 'Voice activity'], ['diarization', 'Diarization'], ['segmentation', 'Segmentation']];
function mkbtn(label, fn) { const b = document.createElement('button'); b.className = 'btn ghost'; b.textContent = label; b.onclick = fn; return b; }
function persistCustom() { try { store.saveCustomModels(customModels); } catch { /* optional */ } }

function buildCard(o) {
  const isLoaded = loadedByModality[o.type] === o.key;
  const div = document.createElement('div'); div.className = 'model';
  div.innerHTML =
    '<div class="hd">' +
      `<span class="mi">${TYPE_ICON[o.type] || ''}</span>` +
      `<div style="min-width:0"><div class="name">${escapeHtml(o.label)}</div>` +
      `<div class="sub">${o.sub}</div></div>` +
      '<span class="actions"></span>' +
    '</div><div class="bar" style="display:none"><div></div></div>';
  const actions = div.querySelector('.actions');
  if (isLoaded) { const b = document.createElement('span'); b.className = 'badge on'; b.textContent = 'loaded'; actions.appendChild(b); }
  if (!o.downloaded) {
    const dl = mkbtn('Download', async () => {
      dl.disabled = true; dl.textContent = 'Downloading…';
      const bar = div.querySelector('.bar'); bar.style.display = 'block';
      try {
        for await (const ev of ra.models.download(o.key)) {
          if (ev.type === 'progress') bar.firstElementChild.style.width = (ev.percent || 0) + '%';
          else if (ev.type === 'failed') throw new Error(ev.message);
        }
      } catch (e) { dl.textContent = 'Failed'; dl.disabled = false; console.error(e); return; }
      await refreshStatus();
      renderModels();
    });
    actions.appendChild(dl);
  } else {
    const b = mkbtn(isLoaded ? 'Unload' : 'Load', async () => {
      const btns = actions.querySelectorAll('button');
      btns.forEach((x) => (x.disabled = true));
      b.textContent = isLoaded ? 'Unloading…' : 'Loading…';
      try {
        if (isLoaded) {
          await ra.models.unload(o.key); delete loadedByModality[o.type];
        } else {
          await selectModel(o.type, o.key);
          await ra.models.load(o.key);
          loadedByModality[o.type] = o.key;
        }
      } catch (e) { b.textContent = 'Error'; btns.forEach((x) => (x.disabled = false)); console.error(e); return; }
      renderModels();
    });
    actions.appendChild(b);
  }
  if (o.custom) {
    actions.appendChild(mkbtn('Remove', async () => {
      try { await ra.models.delete(o.key); } catch { /* ignore */ }
      delete loadedByModality[o.type];
      customModels = customModels.filter((m) => m.id !== o.key);
      persistCustom();
      if (settings.models && settings.models[o.type] === o.key) {
        const models = { ...settings.models };
        delete models[o.type];
        settings.models = models;
        try { await store.saveSettings(settings); } catch { /* optional */ }
        renderModelChips();
      }
      renderModels();
    }));
  }
  return div;
}

async function renderModels() {
  await refreshStatus();
  const el = $('modellist'); el.innerHTML = '';
  const byType = {};
  for (const [id, entry] of Object.entries(CATALOG)) (byType[entry.type] ??= []).push([id, entry]);
  for (const [type, title] of GROUP_ORDER) {
    const items = byType[type];
    if (!items || !items.length) continue;
    const h = document.createElement('div'); h.className = 'mgroup'; h.textContent = title; el.appendChild(h);
    for (const [id, entry] of items) {
      const downloaded = downloadedIds.has(id);
      const bits = [TYPE_LABEL[entry.type] || entry.type];
      if (entry.params) bits.push(entry.params);
      if (entry.sizeMB) bits.push((downloaded ? '' : '~') + fmtMB(entry.sizeMB));
      let sub = bits.join(' · ');
      if (entry.heavy) sub += ' <span class="badge heavy">heavy · CPU</span>';
      if (entry.license) {
        sub += entry.licenseUrl
          ? ` · <a href="${escapeHtml(entry.licenseUrl)}" title="Model licence">${escapeHtml(entry.license)}</a>`
          : ` · ${escapeHtml(entry.license)}`;
      }
      el.appendChild(buildCard({ key: id, type: entry.type, label: entry.label || id, sub, downloaded, custom: false }));
    }
  }
  if (customModels.length) {
    const h = document.createElement('div'); h.className = 'mgroup'; h.textContent = 'Your models'; el.appendChild(h);
    customModels.forEach((m) => {
      const sub = `${TYPE_LABEL[m.type] || m.type} · <span class="muted">${escapeHtml(m.source)}</span>`;
      el.appendChild(buildCard({ key: m.id, type: m.type, label: m.label || m.id, sub, downloaded: downloadedIds.has(m.id), custom: true }));
    });
  }
}

function deriveLabel(source) {
  let s = source;
  if (/^https?:\/\//i.test(s)) { try { s = new URL(s).pathname; } catch (_) { /* keep */ } }
  else { s = s.replace(/^[A-Za-z]:/, ''); const ci = s.indexOf(':'); if (ci >= 0) s = s.slice(0, ci); }
  s = s.replace(/[\\/]+$/, '');
  const seg = s.split(/[\\/]/).pop() || s;
  return seg.replace(/\.tar\.bz2$/i, '').replace(/\.(gguf|onnx|bin)$/i, '') || source;
}
function looksRemote(source) {
  if (/^https?:\/\//i.test(source)) return true;
  return /^[A-Za-z0-9][\w.-]*\/[A-Za-z0-9][\w.-]*$/.test(source) && !source.includes('\\') && !/^[A-Za-z]:/.test(source);
}
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
  const add = async () => {
    const raw = $('addsrc').value.trim();
    if (!raw) return flash('Enter a HuggingFace repo, URL, or file path.');
    const source = raw.replace(/[\\/]+$/, '');
    const type = $('addtype').value;
    if (looksRemote(source) && (type === 'stt' || type === 'tts' || type === 'embedder')) {
      return flash('Speech/embedding models can’t be added from a URL or HF repo yet — use a built-in catalog entry or a local path.');
    }
    const id = 'custom:' + source;
    if (customModels.some((m) => m.id === id)) return flash('That model is already in your list.');
    const entry = { id, source, type, label: deriveLabel(source), downloaded: false };
    customModels.unshift(entry);
    persistCustom();
    try { await ra.models.register(customRegistration(entry)); } catch (e) { console.warn(e); }
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
  syncChatToggles();
}
// Reflect the reasoning/tools state on the composer pills (and the Settings checkbox).
function syncChatToggles() {
  const rt = $('reasontoggle'), tt = $('toolstoggle');
  if (rt) rt.classList.toggle('on', !!settings.reasoning);
  if (tt) tt.classList.toggle('on', !!settings.tools);
  if ($('setreason')) $('setreason').checked = !!settings.reasoning;
}
async function saveSettings() {
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
  await releaseUnneeded();
  const model = noteUse('llm');
  return ra.llm.generateStructured(`Extract the person as JSON. Text: "${text}"`, {
    type: 'object',
    properties: { name: { type: 'string' }, age: { type: 'integer' }, interests: { type: 'array', items: { type: 'string' }, maxItems: 5 } },
    required: ['name', 'age', 'interests'],
  }, { model });
}

let toolsRegistered = false;
function ensureToolsRegistered() {
  if (toolsRegistered) return;
  for (const t of TOOLS) ra.llm.tools.register({ name: t.name, description: t.description, parameters: t.parameters }, t.execute);
  toolsRegistered = true;
}
async function runTools(text) {
  ensureToolsRegistered();
  await releaseUnneeded();
  const model = noteUse('llm');
  const out = await ra.llm.tools.run(text, { model, temperature: settings.temperature, maxOutputTokens: settings.maxTokens });
  return out; // { text, toolCalls: [{name, arguments}] }
}

// Render a tool call's arguments, dropping empty keys/values so a no-arg tool
// shows as `name()` rather than `name({"":""})`.
function fmtArgs(a) {
  const entries = Object.entries(a || {}).filter(([k, v]) => k !== '' && v !== '' && v != null);
  return entries.length ? JSON.stringify(Object.fromEntries(entries)) : '';
}

function flashToast(msg) {
  const el = document.createElement('div');
  el.textContent = msg;
  el.style.cssText = 'position:fixed;left:50%;bottom:28px;transform:translateX(-50%);z-index:200;background:var(--surface-2);border:1px solid var(--line);border-radius:12px;padding:10px 16px;font-size:13.5px;box-shadow:var(--shadow-3);animation:fadeUp .18s var(--ease)';
  document.body.appendChild(el);
  setTimeout(() => el.remove(), 4000);
}
async function runEmbeddings(a, b) {
  const model = noteUse('embedder');
  const [ea, eb] = (await ra.embeddings.embed([a, b], { model })).map((e) => e.vector);
  let dot = 0, na = 0, nb = 0;
  for (let i = 0; i < ea.length; i++) { dot += ea[i] * eb[i]; na += ea[i] * ea[i]; nb += eb[i] * eb[i]; }
  return dot / (Math.sqrt(na) * Math.sqrt(nb) || 1);
}

// ---- RAG (Knowledge tab) ----
let ragSession = null;
let ragSessionPromise = null;
async function ragEnsureSession() {
  if (ragSession != null) return ragSession;
  if (ragSessionPromise) return ragSessionPromise;
  ragSessionPromise = (async () => {
    setStatus('preparing knowledge base…');
    noteUse('embedder'); noteUse('llm');
    ragSession = await ra.rag.open(
      { id: 'minilm' },
      { id: DEFAULT_LLM },
      { retrievalTopK: 3, chunkSize: 512, chunkOverlap: 64 }
    );
    return ragSession;
  })().catch((e) => { ragSessionPromise = null; throw e; });
  return ragSessionPromise;
}
function ragStatsText(s) {
  if (!s || !s.documentCount) return 'No documents yet';
  return `${s.documentCount} document${s.documentCount === 1 ? '' : 's'} · ${s.chunkCount} chunk${s.chunkCount === 1 ? '' : 's'} indexed`;
}
function renderRagSources(chunks) {
  const el = $('ragsources');
  if (!chunks || !chunks.length) { el.innerHTML = ''; return; }
  el.innerHTML = '<div class="label" style="margin-top:16px">Sources</div>' + chunks.map((c) => {
    const src = c.metadata && c.metadata.source ? escapeHtml(c.metadata.source) : 'document';
    const score = typeof c.score === 'number' ? c.score.toFixed(3) : '';
    return `<div class="ragchunk"><div class="meta"><span>${src}</span><span class="ragscore">${score}</span></div><div class="txt">${escapeHtml(c.text || '')}</div></div>`;
  }).join('');
}

async function runVision(imagePath, onToken) {
  await releaseUnneeded();
  const model = noteUse('vlm');
  let caption = '';
  for await (const ev of ra.vlm.generateStream({ kind: 'file', path: imagePath }, 'Describe this image in one sentence.', { model })) {
    if (!ev.isFinal && ev.token) { caption += ev.token; onToken?.(ev.token); }
    else if (ev.isFinal && ev.result) caption = ev.result.text;
  }
  return caption.trim();
}
async function runVad() {
  const silence = () => new Float32Array(1600);
  const loud = () => { const f = new Float32Array(1600); for (let i = 0; i < 1600; i++) f[i] = 0.5 * Math.sin((2 * Math.PI * 300 * i) / 16000); return f; };
  for (let i = 0; i < 8; i++) await ra.vad.detect({ kind: 'float32', samples: silence(), sampleRate: 16000 });
  let detected = false;
  for (let i = 0; i < 8; i++) { const r = await ra.vad.detect({ kind: 'float32', samples: loud(), sampleRate: 16000 }); if (r.isSpeech) detected = true; }
  return detected;
}

// Turn synthesized audio into Float32 samples for Web Audio playback, honouring
// the SDK's declared sample format. Piper emits float32 PCM; reading that as int16
// is what produced the "random noise".
async function decodeAudio(audio, ctx) {
  const rate = audio.sampleRate || 22050;
  const view = new DataView(audio.data.buffer, audio.data.byteOffset, audio.data.byteLength);
  if (audio.format === 's16') {
    const n = Math.floor(audio.data.byteLength / 2);
    const buf = ctx.createBuffer(1, n, rate);
    const ch = buf.getChannelData(0);
    for (let i = 0; i < n; i++) ch[i] = view.getInt16(i * 2, true) / 32768;
    return buf;
  }
  if (audio.format === 'encoded') {
    return await ctx.decodeAudioData(audio.data.slice(0).buffer);
  }
  // f32 raw PCM (the default for sherpa/piper).
  const n = Math.floor(audio.data.byteLength / 4);
  const buf = ctx.createBuffer(1, n, rate);
  const ch = buf.getChannelData(0);
  for (let i = 0; i < n; i++) ch[i] = view.getFloat32(i * 4, true);
  return buf;
}

// Clean text for speech: the model still emits markdown a spoken voice would read
// out literally. This is a UI concern, so it stays in the app.
function speakableText(s) {
  return (s || '')
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/[*_#`>|]/g, '')
    .replace(/\[(.*?)\]\(.*?\)/g, '$1')
    .replace(/\s+/g, ' ')
    .trim();
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
    const grp = btn.closest('details');
    if (grp) grp.open = true;
  }
  closePicker();
  if (name !== 'voice' && voiceCleanup) voiceCleanup();
  if (name !== 'diarization' && diarCleanup) diarCleanup();
  releaseUnneeded();
  renderModelChips();
  if (name === 'models') renderModels();
}

// ---- model chip + picker ------------------------------------------------------
const CHIP_ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3 4 7v10l8 4 8-4V7z"/><path d="m8 12 3 3 5-6"/></svg>';
let openPicker = null;
function closePicker() { if (openPicker) { openPicker.remove(); openPicker = null; } }
document.addEventListener('click', (e) => {
  if (openPicker && !openPicker.contains(e.target) && !e.target.closest('.modelchip')) closePicker();
});
function catalogEntry(id) {
  if (CATALOG[id]) return CATALOG[id];
  const custom = customModels.find((m) => m.id === id);
  return custom ? { label: custom.label || id, type: custom.type } : null;
}
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

  await refreshStatus();
  if (openPicker !== box) return;
  const items = Object.entries(CATALOG).filter(([, e]) => e.type === modality)
    .concat(customModels.filter((m) => m.type === modality).map((m) => [m.id, { label: m.label, type: m.type, custom: true }]));
  const active = selectedModel(modality);
  box.innerHTML = `<div class="phead">${escapeHtml(MODALITY_LABEL[modality])}</div>`;
  for (const [id, entry] of items) {
    const downloaded = downloadedIds.has(id);
    const isActive = id === active;
    const stateCls = isActive ? 'active' : downloaded ? 'ready' : 'get';
    const stateTxt = isActive ? 'Active' : downloaded ? 'Ready' : 'Download';
    const bits = [entry.params, entry.sizeMB ? (downloaded ? '' : '~') + fmtMB(entry.sizeMB) : '', entry.license].filter(Boolean);
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
      if (!downloaded) {
        stateEl.textContent = '0%';
        const bar = document.createElement('div'); bar.className = 'bar'; bar.innerHTML = '<div></div>'; row.after(bar);
        try {
          for await (const ev of ra.models.download(id)) {
            if (ev.type === 'progress') { const pct = Math.round(ev.percent || 0); stateEl.textContent = pct + '%'; bar.firstElementChild.style.width = pct + '%'; }
            else if (ev.type === 'failed') throw new Error(ev.message);
          }
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
  renderModelChips();
  wireModels();
  $('newchat').addEventListener('click', () => { newConversation(); showTab('chat'); $('chatinput').focus(); });
  $('chatsend').addEventListener('click', sendChat);
  $('chatinput').addEventListener('keydown', (e) => { if (e.key === 'Enter') sendChat(); });
  const saveQuiet = () => { try { store.saveSettings(settings); } catch { /* optional */ } };
  $('reasontoggle').addEventListener('click', () => { settings.reasoning = !settings.reasoning; syncChatToggles(); saveQuiet(); });
  $('toolstoggle').addEventListener('click', () => { settings.tools = !settings.tools; syncChatToggles(); saveQuiet(); });

  $('settemp').addEventListener('input', () => ($('settempval').textContent = $('settemp').value));
  $('setsave').addEventListener('click', saveSettings);
  const apisave = $('setapisave');
  if (apisave) apisave.addEventListener('click', async () => {
    const v = $('setapikey').value.trim(); if (!v) return;
    settings.apiKey = v;
    try { await store.saveSettings(settings); $('setstatus').textContent = 'API key saved'; $('setapikey').value = ''; }
    catch (e) { $('setstatus').textContent = 'error: ' + e.message; }
  });

  const out = (id, fn) => async () => { setStatus('working…'); $(id).textContent = '…'; try { $(id).textContent = await fn(); } catch (e) { $(id).textContent = 'error: ' + e.message; } setStatus('ready'); };
  $('structgo').addEventListener('click', out('structout', async () => JSON.stringify(await runStructured($('structtext').value), null, 2)));
  $('toolsgo').addEventListener('click', out('toolsout', async () => {
    const r = await runTools($('toolstext').value);
    const calls = (r.toolCalls || []).map((c) => `${c.name}(${fmtArgs(c.arguments)})`).join(', ');
    return (calls ? `called: ${calls}\n\n` : '') + (r.text || '');
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
      const s = await ragEnsureSession();
      const stats = await s.ingest({ text });
      $('ragstats').textContent = ragStatsText(stats);
      $('ragdoc').value = '';
    } catch (e) { $('ragstats').textContent = 'error: ' + e.message; }
    finally { $('ragadd').disabled = false; setStatus('ready'); }
  });
  $('ragclear').addEventListener('click', async () => {
    if (ragSession == null) { $('ragstats').textContent = ''; return; }
    try { const s = await ragSession.clear(); $('ragstats').textContent = ragStatsText(s); $('ragout').textContent = ''; renderRagSources([]); } catch (e) { $('ragstats').textContent = 'error: ' + e.message; }
  });
  let ragQuerying = false;
  const askRag = async () => {
    if (ragQuerying) return;
    const q = $('ragq').value.trim();
    if (!q) return;
    ragQuerying = true;
    $('ragask').disabled = true; $('ragq').value = ''; $('ragout').innerHTML = '…'; renderRagSources([]);
    setStatus('retrieving + answering…');
    try {
      const s = await ragEnsureSession();
      const res = await s.query(q, { generation: { maxOutputTokens: settings.maxTokens, temperature: settings.temperature } });
      $('ragout').innerHTML = md(res.answer || '');
      renderRagSources(res.sources);
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
  wireDiarization();
  wireSegmentation();
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
    stop() {
      if (!cap) return null;
      const { stream, ctx, node, chunks } = cap;
      cap = null;
      const rate = ctx.sampleRate;
      try { node.disconnect(); } catch { /* already detached */ }
      try { stream.getTracks().forEach((t) => t.stop()); } catch { /* already stopped */ }
      try { ctx.close(); } catch { /* already closed */ }
      let n = 0;
      for (const c of chunks) n += c.length;
      const m = new Float32Array(n);
      let o = 0;
      for (const c of chunks) { m.set(c, o); o += c.length; }
      return { samples: m, rate };
    },
  };
}

let voiceSession = null;
async function ensureVoiceSession() {
  if (voiceSession) return voiceSession;
  noteUse('stt'); noteUse('llm'); noteUse('tts');
  voiceSession = await ra.voice.createSession({
    stt: { id: selectedModel('stt') },
    llm: { id: selectedModel('llm') },
    tts: { id: selectedModel('tts'), voice: undefined },
    systemPrompt: VOICE_SYSTEM_PROMPT,
    temperature: settings.temperature,
    // Spoken replies are short; cap tokens so TTS stays snappy and on-topic.
    maxOutputTokens: Math.min(settings.maxTokens, 200),
  });
  return voiceSession;
}

function wireVoice() {
  const root = $('voiceroot');
  const orb = $('voiceorb');
  const statusEl = $('voicestatus');
  const hintEl = $('voicehint');
  const errEl = $('voiceerror');
  const transcript = $('voicetranscript');
  const cc = captureController();

  let playCtx = null;
  let playing = null;
  let state = 'idle';
  let busy = false;
  const turns = createTurnGuard();
  let levelRaf = 0;
  let level = 0;
  let watchdog = 0;
  function phase(text) {
    hintEl.textContent = text;
    clearTimeout(watchdog);
    watchdog = setTimeout(() => { hintEl.textContent = text + ' (taking longer than usual — tap the orb to cancel)'; }, 20000);
  }
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
  function stopPlayback() { if (playing) { try { playing.onended = null; playing.stop(); } catch { /* already ended */ } playing = null; } }
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
    try { await cc.start(); } catch (e) { showError('Could not open the microphone: ' + (e.message || e)); setVoiceState('idle'); return; }
    setVoiceState('listening');
    startLevelLoop();
    let noiseFloor = 1, heardSpeech = false, silentFor = 0, elapsed = 0;
    const autoStop = $('voicevad');
    cc.onFrame((frame, rate) => {
      const r = raAudio.rms(frame);
      level = Math.min(1, Math.max(level * 0.72, r * 9));
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
    const turn = turns.begin();
    const mine = turn.current;
    try {
      const rec = cc.stop();
      level = 0;
      if (!rec || !rec.samples.length) { setVoiceState('idle'); return; }
      setVoiceState('thinking');
      phase('Transcribing and composing a reply…');
      const vs = await ensureVoiceSession();
      // Whisper expects 16 kHz. The mic captures at the AudioContext rate (often
      // 48 kHz); feeding that unresampled makes Whisper hallucinate ("music music…").
      const samples16 = rec.rate === 16000 ? rec.samples : raAudio.downsample(rec.samples, rec.rate, 16000);
      const { transcript: heard, reply, audio } = await vs.respond({ kind: 'float32', samples: samples16, sampleRate: 16000 });
      if (!mine()) return;
      const heardText = (heard.text || '').trim();
      if (!heardText) { showError('I did not catch that — try again a little closer to the mic.'); setVoiceState('idle'); return; }
      transcript.hidden = false;
      $('voiceheard').textContent = heardText;
      $('voicereply').textContent = speakableText(reply.text);
      if (!audio || !audio.data || !audio.data.length) { setVoiceState('idle'); return; }
      setVoiceState('speaking');
      playCtx = playCtx || new AudioContext();
      if (playCtx.state === 'suspended') await playCtx.resume();
      const buf = await decodeAudio(audio, playCtx);
      if (!mine()) return;
      const srcNode = playCtx.createBufferSource();
      srcNode.buffer = buf; srcNode.connect(playCtx.destination);
      playing = srcNode;
      await new Promise((r) => { srcNode.onended = r; srcNode.start(); });
      playing = null;
    } catch (e) {
      if (mine()) showError(e.message || String(e));
    } finally {
      if (mine()) { clearTimeout(watchdog); busy = false; if (state !== 'listening') setVoiceState('idle'); }
    }
  }
  orb.addEventListener('click', () => {
    if (state === 'listening') { finishTurn(); return; }
    if (state === 'speaking') { stopPlayback(); setVoiceState('idle'); return; }
    if (state === 'thinking') { turns.cancel(); busy = false; clearTimeout(watchdog); showError('Turn cancelled.'); setVoiceState('idle'); return; }
    if (busy) { busy = false; turns.cancel(); }
    stopPlayback();
    beginListening();
  });
  orb.addEventListener('keydown', (e) => { if (e.key === ' ' || e.key === 'Enter') { e.preventDefault(); orb.click(); } });
  voiceCleanup = () => {
    if (state === 'listening') { cc.stop(); level = 0; }
    stopPlayback();
    turns.cancel();
    clearTimeout(watchdog);
    busy = false;
    if (state !== 'idle') setVoiceState('idle');
  };
  setVoiceState('idle');
}
let voiceCleanup = null;

function wireVad() {
  const btn = $('vadbtn'); const cc = captureController(); let running = false; let frames = 0, speech = 0; let threshold = 0.5;
  $('vadth').addEventListener('input', () => { $('vadthval').textContent = $('vadth').value; threshold = parseFloat($('vadth').value); });
  const begin = async () => {
    setStatus('listening…'); frames = 0; speech = 0; running = true; $('vadout').textContent = 'calibrating…';
    await cc.start();
    cc.onFrame(async (f, rate) => {
      if (!running) return;
      const frame = rate === 16000 ? f : raAudio.downsample(f, rate, 16000);
      let isSpeech = false;
      try { isSpeech = (await ra.vad.detect({ kind: 'float32', samples: frame, sampleRate: 16000 }, { threshold })).isSpeech; } catch { /* ignore */ }
      frames++; if (isSpeech) speech++;
      $('vadout').textContent = (frames < 20 ? 'calibrating… ' : (isSpeech ? '🎤 SPEECH ' : '· silence ')) + `(${speech}/${frames} speech frames)`;
    });
  };
  const end = async () => { running = false; cc.stop(); setStatus('ready'); };
  btn.addEventListener('mousedown', begin); btn.addEventListener('mouseup', end); btn.addEventListener('mouseleave', end);
}

// Make sure a model is on disk before use, showing progress in `el`. Generation
// verbs auto-download silently; for the big single-model workbenches we surface it.
async function ensureDownloaded(id, el) {
  const info = await ra.models.get(id);
  if (info && info.downloaded) return;
  for await (const ev of ra.models.download(id)) {
    if (ev.type === 'progress') el.textContent = `downloading model… ${Math.round(ev.percent || 0)}%`;
    else if (ev.type === 'failed') throw new Error('model download failed: ' + ev.message);
  }
}

// ---- diarization (who spoke when) — records from the mic, then diarizes ----
let diarCleanup = null;
function wireDiarization() {
  const btn = $('diargo'); const label = $('diarlabel'); const cc = captureController(); let recording = false;
  const setLabel = (t) => { if (label) label.textContent = t; };
  diarCleanup = () => { if (recording) { try { cc.stop(); } catch { /* ignore */ } recording = false; setLabel('Record'); btn.classList.remove('rec'); } };
  btn.addEventListener('click', async () => {
    if (!recording) {
      try { await cc.start(); } catch (e) { $('diarout').textContent = 'could not open the microphone: ' + (e.message || e); return; }
      recording = true; setLabel('Stop'); btn.classList.add('rec');
      $('diarout').textContent = 'recording… tap Stop when done'; setStatus('recording…');
      return;
    }
    const rec = cc.stop(); recording = false; setLabel('Record'); btn.classList.remove('rec');
    if (!rec || !rec.samples.length) { $('diarout').textContent = 'no audio captured'; setStatus('ready'); return; }
    btn.disabled = true; $('diarout').textContent = 'preparing…'; setStatus('diarizing…');
    try {
      await ensureDownloaded('sortformer-4spk', $('diarout'));
      // Pin the ONNX diarization engine — a local rescan can otherwise mis-route
      // this bare .onnx to llama.cpp ("no .gguf found").
      await ra.models.load('sortformer-4spk', { framework: 'onnx', category: 'speakerDiarization' });
      $('diarout').textContent = 'diarizing…';
      const samples16 = rec.rate === 16000 ? rec.samples : raAudio.downsample(rec.samples, rec.rate, 16000);
      const r = await ra.diarization.diarize({ kind: 'float32', samples: samples16, sampleRate: 16000 }, { model: 'sortformer-4spk' });
      const fmt = (ms) => (ms / 1000).toFixed(1) + 's';
      $('diarout').innerHTML = r.segments && r.segments.length
        ? `<div class="figcap">${r.speakerCount} speaker${r.speakerCount === 1 ? '' : 's'} · ${fmt(r.durationMs)}</div>` +
          r.segments.map((s) => `<div class="ragchunk"><div class="meta"><span>Speaker ${s.speakerIndex + 1}</span><span class="ragscore">${fmt(s.startMs)} – ${fmt(s.endMs)}</span></div></div>`).join('')
        : `No speech segments detected (${r.speakerCount} speaker(s)).`;
    } catch (e) { $('diarout').textContent = 'error: ' + e.message; }
    finally { btn.disabled = false; setStatus('ready'); }
  });
}

// ---- semantic segmentation ----
function wireSegmentation() {
  const f = $('segfile');
  f.addEventListener('change', () => {
    $('seggo').disabled = !f.files.length;
    $('segfname').textContent = f.files[0] ? f.files[0].name : 'No image selected';
  });
  $('seggo').addEventListener('click', async () => {
    const file = f.files[0];
    if (!file) return;
    $('seggo').disabled = true; $('segout').textContent = 'preparing…'; setStatus('segmenting…');
    const canvas = $('segcanvas');
    try {
      await ensureDownloaded('segformer-b0-ade20k', $('segout'));
      await ra.models.load('segformer-b0-ade20k', { framework: 'onnx', category: 'semanticSegmentation' });
      $('segout').textContent = 'segmenting…';
      const img = await createImageBitmap(file);
      // Decode to raw RGB (drop alpha), capped to 512px so the model input is sane.
      const scale = Math.min(1, 512 / Math.max(img.width, img.height));
      const w = Math.max(1, Math.round(img.width * scale)), h = Math.max(1, Math.round(img.height * scale));
      const off = document.createElement('canvas'); off.width = w; off.height = h;
      const octx = off.getContext('2d'); octx.drawImage(img, 0, 0, w, h);
      const rgba = octx.getImageData(0, 0, w, h).data;
      const rgb = new Uint8Array(w * h * 3);
      for (let i = 0, j = 0; i < rgba.length; i += 4, j += 3) { rgb[j] = rgba[i]; rgb[j + 1] = rgba[i + 1]; rgb[j + 2] = rgba[i + 2]; }
      const r = await ra.segmentation.segment(
        { kind: 'rawRgb', data: rgb, width: w, height: h },
        { model: 'segformer-b0-ade20k', includeDiagnosticImage: true }
      );
      if (r.diagnosticRgba && r.diagnosticRgba.length >= r.width * r.height * 4) {
        canvas.width = r.width; canvas.height = r.height; canvas.style.display = 'block';
        const px = new Uint8ClampedArray(r.diagnosticRgba.buffer, r.diagnosticRgba.byteOffset, r.width * r.height * 4);
        canvas.getContext('2d').putImageData(new ImageData(px, r.width, r.height), 0, 0);
      } else { canvas.style.display = 'none'; }
      const cls = (r.classSummaries || []).slice().sort((a, b) => b.fraction - a.fraction).slice(0, 12);
      $('segout').innerHTML = cls.length
        ? cls.map((c) => `<div class="ragchunk"><div class="meta"><span>${escapeHtml(c.label || ('class ' + c.classId))}</span><span class="ragscore">${(c.fraction * 100).toFixed(1)}%</span></div></div>`).join('')
        : 'No classes detected.';
    } catch (e) { $('segout').textContent = 'error: ' + e.message; canvas.style.display = 'none'; }
    finally { $('seggo').disabled = false; setStatus('ready'); }
  });
}

// ---- headless self-test ----
async function selfTest() {
  const log = (s) => window.runanywhereTest.log(s + '\n');
  try {
    log('[selftest] commons ' + ra.version);
    let reply = '';
    for await (const ev of ra.llm.generateStream(buildMessages([], 'Say hello in one short sentence.'), { model: selectedModel('llm'), maxOutputTokens: 24 })) {
      if (!ev.isFinal && !ev.isThinking) reply += ev.token;
    }
    if (!reply.trim()) throw new Error('empty chat reply');
    log('[selftest] chat OK: ' + JSON.stringify(reply.trim().slice(0, 70)));

    const obj = await runStructured('Marie Curie was a 66 year old Polish physicist who loved chemistry.');
    if (typeof obj.name !== 'string' || typeof obj.age !== 'number' || !Array.isArray(obj.interests)) throw new Error('structured shape wrong');
    log('[selftest] structured OK: ' + JSON.stringify(obj));

    const tools = await runTools('What time is it right now?');
    if (!tools.toolCalls || !tools.toolCalls.length) throw new Error('no tool call');
    log('[selftest] tools OK: ' + tools.toolCalls.map((c) => c.name).join(','));

    const close = await runEmbeddings('a cat sat on the mat', 'a kitten rested on the rug');
    const far = await runEmbeddings('a cat sat on the mat', 'the stock market fell today');
    if (!(close > far)) throw new Error('embedding ordering wrong');
    log(`[selftest] embeddings OK: close=${close.toFixed(3)} far=${far.toFixed(3)}`);

    await refreshStatus();
    if (!CATALOG['qwen3.5-0.8b']) throw new Error('catalog missing');
    log('[selftest] models OK: ' + Object.keys(CATALOG).length + ' catalog entries, ' + downloadedIds.size + ' downloaded');

    const image = new URLSearchParams(location.search).get('image');
    if (image) { const c = await runVision(image); if (!c || c.length < 3) throw new Error('empty caption'); log('[selftest] vision OK: ' + JSON.stringify(c.slice(0, 70))); }
    else log('[selftest] vision SKIPPED (no image)');

    if (!(await runVad())) throw new Error('vad did not detect speech');
    log('[selftest] vad OK (speech detected)');

    log('[selftest] ALL PASS');
    window.runanywhereTest.done(true);
  } catch (e) { log('[selftest] FAIL: ' + (e && e.message)); window.runanywhereTest.done(false); }
}

const IS_SELFTEST = new URLSearchParams(location.search).get('selftest') === '1';
(async () => {
  let backendCfg;
  try { backendCfg = await window.appStore.backendConfig(); } catch { backendCfg = undefined; }
  await ra.initialize({
    apiKey: backendCfg && backendCfg.apiKey,
    baseUrl: backendCfg && backendCfg.baseUrl,
    environment: backendCfg && backendCfg.environment,
  });
  if (!IS_SELFTEST) {
    try {
      const s = await store.loadSettings();
      if (s && typeof s === 'object') settings = store.migrateSettings(s, settings);
    } catch { /* ignore */ }
    try { const c = await store.loadConversations(); if (c && Array.isArray(c.conversations)) { conversations = c.conversations; nextConvId = c.nextConvId || conversations.length + 1; activeId = conversations[0] ? conversations[0].id : null; } } catch { /* ignore */ }
    try { const cm = await store.loadCustomModels(); if (Array.isArray(cm)) customModels = cm; } catch { /* ignore */ }
  }
  await registerAllModels();
  setStatus('ready');
  if (IS_SELFTEST) { setStatus('self-test…'); await selfTest(); } else { wireUi(); }
})().catch((e) => {
  setStatus('error: ' + (e && e.message)); console.error(e);
  if (IS_SELFTEST) { try { window.runanywhereTest.log('[selftest] STARTUP ERROR: ' + (e && e.message) + '\n'); window.runanywhereTest.done(false); } catch { /* ignore */ } }
});
