// RunAnywhere demo (renderer) — a product-grade sample: conversation history +
// persistence, markdown chat with per-message metrics (generateStream), a Models
// panel (grouped catalog + add-any-model + download + load/unload + storage), a
// Settings panel (system prompt / temperature / max-tokens / encrypted API key),
// and workbenches for structured output, tools, vision, embeddings, voice, VAD,
// speaker diarization, and semantic segmentation. Feature helpers are shared
// with the headless self-test.
const ra = window.runanywhere;
const store = window.appStore;
const $ = (id) => document.getElementById(id);
const setStatus = (s) => { $('status').textContent = s; $('statuswrap').classList.toggle('busy', s !== 'ready'); };
// Escape quotes too: md() builds an <a href="…"> from (escaped) text, so an
// unescaped " in a link URL would break out of the attribute.
const escapeHtml = (s) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const fmtSize = (b) => (b > 1e9 ? (b / 1e9).toFixed(1) + ' GB' : b > 1e6 ? (b / 1e6).toFixed(0) + ' MB' : (b / 1e3).toFixed(0) + ' KB');
const fmtMB = (mb) => (mb >= 1000 ? (mb / 1000).toFixed(1) + ' GB' : mb + ' MB');

// Built-in tools the model can call. Every one answers from something this
// machine actually knows — the clock, the runtime, the battery, arithmetic — so
// a tool call that succeeds is never a fabricated answer dressed as a lookup.
// `execute` runs locally; commons drives the loop and calls back into here.
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
      // Arithmetic only — never eval() model output.
      if (!/^[\d\s+\-*/().%]+$/.test(src)) return { error: 'unsupported expression (digits and + - * / ( ) only)' };
      try { return { result: String(Function(`"use strict";return (${src})`)()) }; }
      catch { return { error: `could not evaluate '${src}'` }; }
    },
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
// The composer pills are `reasoning` and `tools`, both persisted: a turn toggle
// the user has to re-arm after every restart reads as a bug. `reasoning` is the
// same switch the Settings panel owns, surfaced where it is used.
let settings = { systemPrompt: DEFAULT_SYSTEM_PROMPT, temperature: 0.3, maxTokens: 1024, reasoning: false, tools: false };
let conversations = [];
let activeId = null;
let nextConvId = 1;
let customModels = []; // [{ id, source, type, label, downloaded }]

// 2B rather than 0.8B: at 0.8B the model absorbs the user's facts but
// re-attributes them to itself ("I am 21 years old"). Measured 1/3 vs 3/3 on a
// multi-fact recall probe. 1.2GB is still a small download.
const DEFAULT_LLM = 'qwen3.5-2b';

// ---- per-tab model selection -------------------------------------------------
// `settings.models` is the user's choice per modality, persisted by id. Residency
// is the SDK's: ra.models.load makes a model resident and releases others itself
// when the machine is short of memory. The app used to decide that (model-policy.js,
// deleted) by unloading whatever the current screen did not name, which evicted
// models even on a machine with memory to spare.
const DEFAULT_MODELS = {
  llm: DEFAULT_LLM, vlm: 'qwen3.5-0.8b-vl', embedder: 'minilm', stt: 'whisper-tiny', tts: 'piper-lessac',
  diarization: 'sortformer', segmentation: 'segformer-b0-ade-512',
};
const MODALITY_LABEL = {
  llm: 'Language model', vlm: 'Vision model', embedder: 'Embedding model', stt: 'Speech-to-text',
  tts: 'Text-to-speech', diarization: 'Diarization model', segmentation: 'Segmentation model',
};
// The app groups models by modality; commons keys them by category.
const MODALITY_CATEGORY = {
  llm: 'LANGUAGE', vlm: 'VISION', embedder: 'EMBEDDING', stt: 'SPEECH_TO_TEXT',
  tts: 'TEXT_TO_SPEECH', diarization: 'DIARIZATION', segmentation: 'SEGMENTATION',
};
// Which model chips a tab offers. Presentational only.
const TAB_MODALITIES = {
  chat: ['llm'],
  vision: ['vlm'],
  embeddings: ['embedder'],
  voice: ['stt', 'llm', 'tts'],
  rag: ['embedder', 'llm'],
  structured: ['llm'],
  tools: ['llm'],
  vad: [],
  diarization: ['diarization'],
  segmentation: ['segmentation'],
};
const selectedModel = (m) => (settings.models && settings.models[m]) || DEFAULT_MODELS[m];

// Switch a modality to another model. Persisted so the choice survives a restart;
// nothing loads until a screen asks for it, and commons swaps the resident model
// of that category when it does.
async function selectModel(modality, id) {
  settings.models = { ...(settings.models || {}), [modality]: id };
  try { await store.saveSettings(settings); } catch { /* optional */ }
  renderModelChips();
  if (currentTab === 'models') renderModels();
}

// Make the selected model of a modality resident. Chat, vision, structured output
// and tools do not need this — they pass `model:` and the SDK loads — but
// embeddings, diarization and segmentation have no per-request model, and the
// Models tab loads on demand. `ra.models.load` downloads first when the files are
// not there yet, so this is also the download path for those three.
async function loadSelected(modality, options) {
  const id = selectedModel(modality);
  setStatus(`loading ${id}…`);
  try { await ra.models.load(id, options); } finally { setStatus('ready'); }
  return id;
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
// placeholder while the answer is still empty. Answer and reasoning arrive
// already separated (commons classifies each streamed token), so nothing here
// re-parses the text looking for tags.
function assistantHtml(response, thinking, streaming) {
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
  const body =
    m.role === 'assistant' ? assistantHtml(m.content || '…', m.thinking) : escapeHtml(m.content);
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
let generating = false;
async function sendChat() {
  // One generation at a time: a second Enter while streaming would start a
  // concurrent generation against the same resident model.
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
    // The whole conversation goes across as messages. Commons renders it with
    // the model's own chat template, which is what stops a multi-turn chat from
    // collapsing into a single user turn.
    const messages = [{ role: 'system', content: settings.systemPrompt }];
    for (const m of prior) messages.push({ role: m.role, content: m.content });
    messages.push({ role: 'user', content: text });

    let result = null;
    for await (const event of ra.llm.generateStream(messages, {
      model: selectedModel('llm'),
      temperature: settings.temperature,
      maxOutputTokens: settings.maxTokens,
      // Only sent when the user asked to see reasoning. `mode: 'OFF'` is not
      // "the toggle is off" — it makes commons prepend the Qwen "/no_think"
      // control token to the prompt for every non-QHexRT engine
      // (llm_thinking_directive_internal.h). A model outside that family reads
      // it as literal text: LFM2.5-230M answers "\n\n" and stops, which is a
      // one-token empty reply. Leaving it unset asks for nothing and the model
      // behaves normally.
      ...(settings.reasoning ? { reasoning: { mode: 'ON', includeInOutput: true } } : {}),
      // An empty tool list means "no tools this turn"; commons only runs its
      // tool loop when the request actually carries some.
      ...(settings.tools ? {} : { tools: [], toolChoice: 'NONE' }),
    })) {
      if (event.type === 'token') {
        if (event.kind === 'THOUGHT') asst.thinking += event.text;
        else asst.content += event.text;
        bubble.innerHTML = assistantHtml(asst.content, asst.thinking, true);
        $('chatlog').scrollTop = $('chatlog').scrollHeight;
      } else if (event.type === 'completed') {
        result = event.result;
      }
    }
    asst.content = (result ? result.text : asst.content).trim();
    asst.thinking = (result && result.thinkingText) || asst.thinking;
    if (result) {
      asst.metrics = {
        tokens: result.outputTokens,
        tps: result.tokensPerSecond,
        ttft: result.timeToFirstTokenMs,
      };
    }
    bubble.classList.remove('streaming');
    renderChat();
    persist();
  } catch (e) { asst.content = 'error: ' + e.message; renderChat(); }
  finally { generating = false; $('chatsend').disabled = false; setStatus('ready'); }
}

// ---- models panel ----
// Everything here reads commons through ra.models: `list()` is the registry,
// `state().loaded` is what is resident right now, and download / load / unload /
// unregister are one call each. The app keeps no handle table any more.
const svg = (d) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${d}</svg>`;
const TYPE_ICON = {
  llm: svg('<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>'),
  vlm: svg('<rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="9" cy="9" r="2"/><path d="m21 15-5-5L5 21"/>'),
  embedder: svg('<circle cx="5" cy="6" r="2"/><circle cx="19" cy="7" r="2"/><circle cx="12" cy="18" r="2"/><path d="M7 6h10M6 8l5 8M18 9l-5 7"/>'),
  stt: svg('<rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 10a7 7 0 0 0 14 0M12 19v3"/>'),
  tts: svg('<path d="M11 5 6 9H2v6h4l5 4zM19 9a5 5 0 0 1 0 6"/>'),
  diarization: svg('<circle cx="9" cy="7" r="3"/><circle cx="17" cy="9" r="2.5"/><path d="M3 20a6 6 0 0 1 12 0M14 20a5 5 0 0 1 7-3"/>'),
  segmentation: svg('<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M3 12h18M12 3v18"/>'),
};
const TYPE_LABEL = {
  llm: 'Language model', vlm: 'Vision-language', embedder: 'Embeddings', stt: 'Speech-to-text',
  tts: 'Text-to-speech', diarization: 'Diarization', segmentation: 'Segmentation',
};
const GROUP_ORDER = [
  ['llm', 'Language models'], ['vlm', 'Vision-language'], ['stt', 'Speech-to-text'],
  ['tts', 'Text-to-speech'], ['embedder', 'Embeddings'], ['diarization', 'Diarization'],
  ['segmentation', 'Segmentation'],
];
function mkbtn(label, fn) { const b = document.createElement('button'); b.className = 'btn ghost'; b.textContent = label; b.onclick = fn; return b; }
function persistCustom() { try { store.saveCustomModels(customModels); } catch { /* optional */ } }

// Build one model card. `key` is the model id every ra.models verb takes; the
// underlying source (an HF repo, a URL, a path) is commons' business once the
// entry is registered.
function buildCard(o) {
  const loaded = o.loaded;
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
      try {
        for await (const event of ra.models.download(o.key)) {
          if (event.type === 'progress') bar.firstElementChild.style.width = (event.percent || 0) + '%';
          else if (event.type === 'extracting') dl.textContent = 'Extracting…';
        }
      } catch (e) { dl.textContent = 'Failed'; dl.disabled = false; console.error(e); return; }
      renderModels();
    });
    actions.appendChild(dl);
  } else {
    const b = mkbtn(loaded ? 'Unload' : 'Load', async () => {
      // Disable the whole row: Remove during an in-flight Load would drop the card
      // while commons is still bringing a multi-GB model into residency.
      const btns = actions.querySelectorAll('button');
      btns.forEach((x) => (x.disabled = true));
      b.textContent = loaded ? 'Unloading…' : 'Loading…';
      try {
        if (loaded) {
          await ra.models.unload(o.key);
        } else {
          // Loading from here IS selecting: route through the same choke point the
          // per-tab chips use, so the Models tab and the chips can't disagree.
          await selectModel(o.type, o.key);
          await loadSelected(o.type);
        }
      } catch (e) { b.textContent = 'Error'; btns.forEach((x) => (x.disabled = false)); console.error(e); return; }
      renderModels();
    });
    actions.appendChild(b);
  }
  if (o.custom) {
    actions.appendChild(mkbtn('Remove', async () => {
      // Release it and drop its registry row; the files stay (ra.models.delete is
      // what frees disk, and Remove has never meant that here).
      try { await ra.models.unload(o.key); } catch { /* not resident */ }
      try { await ra.models.unregister(o.key); } catch { /* never registered */ }
      customModels = customModels.filter((m) => m.id !== o.key);
      persistCustom();
      // The choice is persisted by id, so a removed model would otherwise leave a
      // dangling id in settings that no longer has a registry row — every later
      // load would fail, across restarts, with no way to recover from the UI.
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

// Registry state keyed by id, plus the ids commons currently holds resident.
// `list()` is the registry (downloaded flag, size on disk) and `state().loaded`
// is residency; the catalog supplies only the display metadata commons has no
// field for — label, licence, parameter count, the "heavy" warning.
async function modelState() {
  const [rows, state] = await Promise.all([ra.models.list(), ra.models.state()]);
  return {
    byId: new Map(rows.map((r) => [r.id, r])),
    loaded: new Set(Object.values(state.loaded).map((m) => m.id)),
  };
}

async function renderModels() {
  const cat = await ensureCatalog();
  const { byId, loaded } = await modelState();
  const el = $('modellist'); el.innerHTML = '';
  const byType = {};
  for (const [id, entry] of Object.entries(cat)) (byType[entry.type] ??= []).push([id, entry]);
  for (const [type, title] of GROUP_ORDER) {
    const items = byType[type];
    if (!items || !items.length) continue;
    const h = document.createElement('div'); h.className = 'mgroup'; h.textContent = title; el.appendChild(h);
    for (const [id, entry] of items) {
      const st = byId.get(id) || { downloaded: false, sizeBytes: 0 };
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
      el.appendChild(buildCard({ key: id, type: entry.type, label: entry.label || id, sub, downloaded: st.downloaded, loaded: loaded.has(id), custom: false }));
    }
  }
  if (customModels.length) {
    const h = document.createElement('div'); h.className = 'mgroup'; h.textContent = 'Your models'; el.appendChild(h);
    for (const m of customModels) {
      // Downloaded state comes off the registry row, which commons reconciles
      // against the store — not from a flag the app persisted and could not
      // notice going stale when the files were deleted underneath it.
      const st = byId.get(m.id) || { downloaded: false, sizeBytes: 0 };
      const bits = [TYPE_LABEL[m.type] || m.type];
      if (st.downloaded && st.sizeBytes) bits.push(fmtSize(st.sizeBytes));
      const sub = `${bits.join(' · ')} · <span class="muted">${escapeHtml(m.source)}</span>`;
      el.appendChild(buildCard({ key: m.id, type: m.type, label: m.label || m.id, sub, downloaded: st.downloaded, loaded: loaded.has(m.id), custom: true }));
    }
  }
}

// Stage every custom entry in commons' registry, so a custom model answers to the
// same ra.models verbs a catalog id does. Best effort per entry: a bad row must
// not stop the rest of the list from working.
async function registerCustomModels() {
  for (const m of customModels) {
    const remote = looksRemote(m.source);
    try {
      await ra.models.register({
        id: m.id,
        name: m.label || m.id,
        category: MODALITY_CATEGORY[m.type],
        ...(remote ? { url: m.source } : { path: m.source }),
      });
    } catch (e) { console.error('could not register', m.id, e); }
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
  const add = async () => {
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
    const entry = { id, source, type, label: deriveLabel(source) };
    try {
      await ra.models.register({
        id,
        name: entry.label,
        category: MODALITY_CATEGORY[type],
        ...(looksRemote(source) ? { url: source } : { path: source }),
      });
    } catch (e) { return flash('Could not add that model: ' + e.message); }
    customModels.unshift(entry);
    persistCustom();
    $('addsrc').value = '';
    renderModels();
    flash('Added to “Your models” — hit Download to fetch it.');
  };
  $('addgo').addEventListener('click', () => { add(); });
  $('addsrc').addEventListener('keydown', (e) => { if (e.key === 'Enter') add(); });
}

// ---- settings ----
function applySettingsToUi() {
  $('setsystem').value = settings.systemPrompt;
  $('settemp').value = settings.temperature; $('settempval').textContent = settings.temperature;
  $('setmax').value = settings.maxTokens;
  syncChatToggles();
}
// Reflect reasoning/tools on the composer pills and on the Settings checkbox,
// which is the same reasoning switch seen from the other side.
function syncChatToggles() {
  const rt = $('reasontoggle'), tt = $('toolstoggle');
  if (rt) rt.classList.toggle('on', !!settings.reasoning);
  if (tt) tt.classList.toggle('on', !!settings.tools);
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
  syncChatToggles();
  try { await store.saveSettings(settings); } catch { /* optional */ }
  $('setstatus').textContent = 'saved'; setTimeout(() => ($('setstatus').textContent = ''), 1500);
}

// ---- shared feature helpers (used by UI + self-test) ----
async function runStructured(text) {
  // Commons constrains decoding to the schema and extracts the document, so the
  // app neither compiles a grammar nor parses JSON out of prose.
  const result = await ra.llm.generateStructured(
    `Extract the person as JSON. Text: "${text}"`,
    {
      type: 'object',
      properties: { name: { type: 'string' }, age: { type: 'integer' }, interests: { type: 'array', items: { type: 'string' }, maxItems: 5 } },
      required: ['name', 'age', 'interests'],
    },
    { model: selectedModel('llm'), temperature: settings.temperature, maxOutputTokens: settings.maxTokens }
  );
  return result.value;
}
// The registry lives in the SDK, so registration happens once rather than the
// tool list being re-sent on every request.
let toolsRegistered = false;
function registerTools() {
  if (toolsRegistered) return;
  for (const { execute, ...definition } of TOOLS) {
    ra.llm.tools.register(definition, (args) => execute(args || {}));
  }
  toolsRegistered = true;
}

// A tool call's arguments, with empty keys and values dropped so a no-argument
// tool reads as `name()` rather than `name({"":""})`.
function fmtArgs(args) {
  const entries = Object.entries(args || {}).filter(([k, v]) => k !== '' && v !== '' && v != null);
  return entries.length ? JSON.stringify(Object.fromEntries(entries)) : '';
}

async function runTools(text) {
  registerTools();
  // Commons runs the whole loop: it picks the tool, calls the executor
  // registered above, feeds the result back, and generates the answer. The app
  // no longer parses a call or dispatches it.
  const result = await ra.llm.generate(text, {
    model: selectedModel('llm'),
    temperature: settings.temperature,
    maxOutputTokens: settings.maxTokens,
    toolChoice: 'REQUIRED',
  });
  const call = result.toolCalls[0];
  if (!call) return { name: '(none)', arguments: {}, result: result.text };
  return {
    name: call.name,
    arguments: call.arguments,
    // Executors return an object, which commons carries back on the call.
    result: call.result ?? '(no result)',
    answer: result.text,
  };
}

// Small transient toast, used by the unhandled-rejection net below.
function flashToast(msg) {
  const el = document.createElement('div');
  el.textContent = msg;
  el.style.cssText = 'position:fixed;left:50%;bottom:28px;transform:translateX(-50%);z-index:200;background:var(--surface-2);border:1px solid var(--line);border-radius:12px;padding:10px 16px;font-size:13.5px;box-shadow:var(--shadow-3);animation:fadeUp .18s var(--ease)';
  document.body.appendChild(el);
  setTimeout(() => el.remove(), 4000);
}
async function runEmbeddings(a, b) {
  // embed() has no per-request model — commons reads whichever embedding model is
  // resident — so the screen makes its choice resident first. One batch call, and
  // the vectors come back in input order with commons' own index on each.
  await loadSelected('embedder');
  const [ea, eb] = await ra.embeddings.embed([a, b]);
  const va = ea.vector, vb = eb.vector;
  let dot = 0, na = 0, nb = 0;
  for (let i = 0; i < va.length; i++) { dot += va[i] * vb[i]; na += va[i] * va[i]; nb += vb[i] * vb[i]; }
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
    // Single SDK entry point — rag.open owns downloading both models,
    // registering them, and creating the native session.
    ragSession = await ra.rag.open(
      { id: 'minilm' },
      { id: selectedModel('llm') || DEFAULT_LLM },
      { topK: 3, chunkSize: 512, chunkOverlap: 64, maxContextTokens: 1024 }
    );
    return ragSession;
  })().catch((e) => {
    ragSessionPromise = null; // allow retry after failure
    throw e;
  });
  return ragSessionPromise;
}
function ragStatsText(s) {
  // Never render nothing — an empty slot beside the buttons reads as a failed load.
  if (!s || !s.documentCount) return 'No documents yet';
  return `${s.documentCount} document${s.documentCount === 1 ? '' : 's'} · ${s.chunkCount} chunk${s.chunkCount === 1 ? '' : 's'} indexed`;
}
function renderRagSources(chunks) {
  const el = $('ragsources');
  if (!chunks || !chunks.length) { el.innerHTML = ''; return; }
  el.innerHTML = '<div class="label" style="margin-top:16px">Sources</div>' + chunks.map((c) => {
    // A v3 Match carries its provenance in metadata; the source document is
    // the one key commons always sets when the chunk came from a named doc.
    const src = c.metadata?.sourceDocument ? escapeHtml(c.metadata.sourceDocument) : 'document';
    const score = typeof c.score === 'number' ? c.score.toFixed(3) : '';
    return `<div class="ragchunk"><div class="meta"><span>${src}</span><span class="ragscore">${score}</span></div><div class="txt">${escapeHtml(c.text || '')}</div></div>`;
  }).join('');
}

async function runVision(imagePath, onToken) {
  // Commons loads the vision model into its lifecycle store and reads it back
  // from there, so there is no handle to hold and no mmproj to pass: the
  // projector rides on the model's registry row.
  let caption = '';
  for await (const event of ra.vlm.generateStream(
    { path: imagePath },
    'Describe this image in one sentence.',
    { model: selectedModel('vlm'), maxOutputTokens: settings.maxTokens, temperature: settings.temperature }
  )) {
    if (event.type === 'token') { caption += event.text; onToken?.(event.text); }
    else if (event.type === 'completed') caption = event.result.text;
  }
  return caption.trim();
}
async function runSecure(key, value) { await ra.secure.set(key, value); const got = await ra.secure.get(key); await ra.secure.delete(key); return got; }
async function runVad() {
  // One buffer in, one verdict out: commons frames it, runs the detector and
  // reports the speech segments it found.
  const n = 16000;
  const tone = new Float32Array(n);
  for (let i = 0; i < n; i++) tone[i] = 0.5 * Math.sin((2 * Math.PI * 300 * i) / 16000);
  const result = await ra.vad.detect(ra.audio.float32(tone, 16000));
  return result.isSpeech;
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
  // Close the mic (and, for voice, the whole pipeline) on the way out of a tab
  // that opened it — a recording that keeps running off-screen is a live mic
  // the user cannot see.
  if (name !== 'voice' && voiceCleanup) voiceCleanup();
  if (name !== 'diarization' && diarCleanup) diarCleanup();
  renderModelChips();
  if (name === 'models') renderModels();
}

// ---- model chip + picker ------------------------------------------------------
// A tab only offers the modalities it actually uses (TAB_MODALITIES, above).
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
let catalogPromise = null;
/** Resolve the catalog once and cache it; callers that need it await this. */
function ensureCatalog() {
  if (catalogCache) return Promise.resolve(catalogCache);
  if (!catalogPromise) {
    catalogPromise = Promise.resolve(ra.catalog())
      .then((c) => { catalogCache = c; return c; })
      .catch((e) => { catalogPromise = null; throw e; });
  }
  return catalogPromise;
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

  const [cat, { byId }] = await Promise.all([ensureCatalog(), modelState()]);
  if (openPicker !== box) return; // closed while loading
  const items = Object.entries(cat).filter(([, e]) => e.type === modality)
    .concat(customModels.filter((m) => m.type === modality).map((m) => [m.id, { label: m.label, type: m.type, custom: true }]));
  const active = selectedModel(modality);

  box.innerHTML = `<div class="phead">${escapeHtml(MODALITY_LABEL[modality])}</div>`;
  for (const [id, entry] of items) {
    const st = byId.get(id) || {};
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
          for await (const event of ra.models.download(id)) {
            if (event.type === 'extracting') { stateEl.textContent = 'Extracting'; continue; }
            if (event.type !== 'progress') continue;
            const pct = Math.round(event.percent || 0);
            stateEl.textContent = pct + '%';
            bar.firstElementChild.style.width = pct + '%';
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
  ensureCatalog().then(() => renderModelChips()).catch(() => {});
  renderModelChips();
  wireModels();
  $('newchat').addEventListener('click', () => { newConversation(); showTab('chat'); $('chatinput').focus(); });
  $('chatsend').addEventListener('click', sendChat);
  $('chatinput').addEventListener('keydown', (e) => { if (e.key === 'Enter') sendChat(); });

  // Composer pills. Reasoning is the same setting the Settings panel owns, so
  // flipping it here persists and the two views never disagree.
  const saveQuiet = () => { Promise.resolve(store.saveSettings(settings)).catch(() => {}); };
  $('reasontoggle').addEventListener('click', () => {
    settings.reasoning = !settings.reasoning;
    syncChatToggles();
    saveQuiet();
  });
  $('toolstoggle').addEventListener('click', () => {
    settings.tools = !settings.tools;
    // Registration is idempotent and cheap; doing it on enable keeps the
    // registry empty for anyone who never turns tools on.
    if (settings.tools) registerTools();
    syncChatToggles();
    saveQuiet();
  });
  syncChatToggles();

  $('settemp').addEventListener('input', () => ($('settempval').textContent = $('settemp').value));
  $('setsave').addEventListener('click', saveSettings);
  $('setapisave').addEventListener('click', async () => {
    const v = $('setapikey').value.trim(); if (!v) return;
    try { await ra.secure.set('api-key', v); $('setstatus').textContent = 'API key stored (encrypted)'; $('setapikey').value = ''; }
    catch (e) { $('setstatus').textContent = 'error: ' + e.message; }
  });

  const out = (id, fn) => async () => { setStatus('working…'); $(id).textContent = '…'; try { $(id).textContent = await fn(); } catch (e) { $(id).textContent = 'error: ' + e.message; } setStatus('ready'); };
  $('structgo').addEventListener('click', out('structout', async () => JSON.stringify(await runStructured($('structtext').value), null, 2)));
  $('toolsgo').addEventListener('click', out('toolsout', async () => {
    const c = await runTools($('toolstext').value);
    const shown = typeof c.result === 'string' ? c.result : JSON.stringify(c.result, null, 2);
    return `${c.name}(${fmtArgs(c.arguments)})
→ ${shown}${c.answer ? `\n\n${c.answer}` : ''}`;
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
      const session = await ragEnsureSession();
      await session.ingest({ text });
      $('ragstats').textContent = ragStatsText(await session.stats());
      $('ragdoc').value = '';
    } catch (e) { $('ragstats').textContent = 'error: ' + e.message; }
    finally { $('ragadd').disabled = false; setStatus('ready'); }
  });
  $('ragclear').addEventListener('click', async () => {
    if (ragSession == null) { $('ragstats').textContent = ''; return; }
    try {
      await ragSession.clear();
      $('ragstats').textContent = ragStatsText(await ragSession.stats());
      $('ragout').textContent = '';
      renderRagSources([]);
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
      const session = await ragEnsureSession();
      const res = await session.query(q, {
        maxOutputTokens: settings.maxTokens,
        temperature: settings.temperature,
      });
      // Render reasoning + answer SEPARATELY (commons already split the
      // thinking out) — do NOT re-wrap in <think> tags, or a literal </think>
      // in retrieved document text would mis-split the answer into the drawer.
      const reason = res.thinkingText
        ? `<details class="reason"><summary>💭 Reasoning</summary><div class="reasonbody">${escapeHtml(res.thinkingText)}</div></details>`
        : '';
      $('ragout').innerHTML = reason + md(res.answer || '');
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

  // The registry is per process, so a persisted "Tools on" has to re-register on
  // every start or the first turn goes out with an empty tool list.
  if (settings.tools) registerTools();

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
    // Tearing down the graph must NEVER throw: a throw here used to escape
    // finishTurn's try block and leave the turn flagged busy forever, which
    // presents as a mic button that silently stops responding. Claim `cap`
    // first so a re-entrant stop() is a no-op rather than a double-close.
    stop() {
      if (!cap) return null;
      const { stream, ctx, node, chunks } = cap;
      cap = null;
      const rate = ctx.sampleRate; // read before close(); the context is unusable after
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
// ---- voice: a 4-state machine (idle | listening | thinking | speaking) --------
// Tap to talk, tap again while it is speaking to interrupt. Commons owns the turn:
// ra.voice.createSession brings up speech-to-text, the language model and the
// voice, opens the microphone, segments speech, decides when a turn has ended, and
// plays the reply. The app sets data-state from the events it gets back and renders
// the transcript. There is no turn loop here any more, and no turn guard: a
// superseded turn is cancelled in commons rather than ignored on arrival.
function wireVoice() {
  const root = $('voiceroot');
  const orb = $('voiceorb');
  const statusEl = $('voicestatus');
  const hintEl = $('voicehint');
  const errEl = $('voiceerror');
  const transcript = $('voicetranscript');

  let session = null;
  let opening = null;
  let state = 'idle';

  const COPY = {
    idle: ['Tap to talk', 'Speech, reasoning and speech-synthesis all run on this device.'],
    listening: ['Listening…', 'Just speak — the turn ends on its own after a short silence.'],
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
  const ORB_STATE = { LISTENING: 'listening', THINKING: 'thinking', SPEAKING: 'speaking' };

  // The event stream is the only thing that moves the orb. `speechStarted` and
  // `speechEnded` describe the USER's voice, not the agent's, so they are left to
  // the transcript rather than the state machine.
  async function consume(active) {
    for await (const event of active.events) {
      if (session !== active) return;
      if (event.type === 'agentStateChanged') {
        const next = ORB_STATE[event.state];
        if (next) setVoiceState(next);
      } else if (event.type === 'userTranscribed') {
        transcript.hidden = false;
        $('voiceheard').textContent = event.text;
        if (event.isFinal) $('voicereply').textContent = '';
      } else if (event.type === 'agentResponse') {
        transcript.hidden = false;
        $('voicereply').textContent = event.text;
      } else if (event.type === 'error') {
        showError(event.message);
        if (!event.recoverable) await stopSession();
      }
    }
  }

  async function startSession() {
    if (opening) return opening;
    clearError();
    transcript.hidden = true;
    setVoiceState('thinking');
    hintEl.textContent = 'Preparing the on-device voice pipeline…';
    opening = (async () => {
      // One entry point. The session downloads and loads all three models, keeps
      // them resident together, and opens the microphone in start().
      const active = await ra.voice.createSession({
        stt: { id: selectedModel('stt') },
        llm: { id: selectedModel('llm') },
        tts: { id: selectedModel('tts') },
      });
      session = active;
      consume(active).catch((e) => { if (session === active) showError(e.message || String(e)); });
      await active.start();
    })();
    try {
      await opening;
    } catch (e) {
      showError('Could not start the voice pipeline: ' + (e.message || e));
      session = null;
      setVoiceState('idle');
    } finally {
      opening = null;
    }
  }

  async function stopSession() {
    const active = session;
    session = null;
    setVoiceState('idle');
    if (active) {
      try { await active.close(); } catch { /* already closed */ }
    }
  }

  // One tap does the right thing for the current state, and every state can act:
  // the failure mode this screen used to have was a mic button that silently
  // stopped responding because a stale flag was never cleared.
  orb.addEventListener('click', async () => {
    try {
      if (!session) { await startSession(); return; }
      if (state === 'speaking') {
        // Barge-in is cooperative rather than detected: the pipeline gates the
        // microphone for the duration of a turn, so this stops local playout and
        // cancels the turn in commons.
        await session.interrupt();
        setVoiceState('listening');
        return;
      }
      await stopSession();
    } catch (e) { showError(e.message || String(e)); }
  });
  orb.addEventListener('keydown', (e) => { if (e.key === ' ' || e.key === 'Enter') { e.preventDefault(); orb.click(); } });

  // Leaving the tab closes the microphone and releases the pipeline; the session
  // cancels whatever turn was in flight on the way out.
  voiceCleanup = () => { stopSession(); };
  setVoiceState('idle');
}
let voiceCleanup = null;
// The workbench hands commons a rolling window of microphone audio and renders
// the verdict. ra.vad.detect takes a whole buffer and does its own framing,
// endpointing and threshold arming, so there is no handle to hold, no per-frame
// call and no separate setThreshold: the slider is just an option on the next
// window. (vad.openStream would be the live shape, but the VadStream it returns
// carries its events on an AsyncQueue whose Symbol.asyncIterator lives on the
// prototype, which contextBridge does not carry into the page.)
const VAD_WINDOW_MS = 300;
function wireVad() {
  const btn = $('vadbtn'); const cc = captureController();
  let pending = []; let listening = false; let inFlight = false; let timer = 0;
  let windows = 0, speech = 0;
  $('vadth').addEventListener('input', () => { $('vadthval').textContent = $('vadth').value; });
  const takeWindow = () => {
    if (!pending.length) return null;
    let n = 0;
    for (const c of pending) n += c.length;
    const merged = new Float32Array(n);
    let o = 0;
    for (const c of pending) { merged.set(c, o); o += c.length; }
    pending = [];
    return merged;
  };
  const poll = async () => {
    // One window at a time: detect() arms the detector for the call, so two
    // overlapping calls would reconfigure it underneath each other.
    if (inFlight) return;
    const window = takeWindow();
    if (!window || window.length < 1600) return;
    inFlight = true;
    try {
      const result = await ra.vad.detect(ra.audio.float32(window, 16000), {
        activationThreshold: parseFloat($('vadth').value),
      });
      if (!listening) return;
      windows++; if (result.isSpeech) speech++;
      $('vadout').textContent =
        (result.isSpeech ? '🎤 SPEECH ' : '· silence ') +
        `(${speech}/${windows} windows, p=${result.probability.toFixed(2)})`;
    } catch (e) { $('vadout').textContent = 'error: ' + e.message; }
    finally { inFlight = false; }
  };
  const begin = async () => {
    if (listening) return;
    listening = true; windows = 0; speech = 0; pending = [];
    setStatus('listening…'); $('vadout').textContent = 'listening…';
    await cc.start();
    cc.onFrame((f, rate) => { pending.push(rate === 16000 ? f : ra.downsample(f, rate, 16000)); });
    timer = setInterval(poll, VAD_WINDOW_MS);
  };
  const end = () => {
    if (!listening) return;
    listening = false;
    clearInterval(timer);
    cc.stop();
    setStatus('ready');
  };
  btn.addEventListener('mousedown', () => { begin(); }); btn.addEventListener('mouseup', end); btn.addEventListener('mouseleave', end);
}

// ---- diarization (who spoke when) ----
// Record, Stop, then hand the whole buffer to commons. `diarize` has no
// per-request model — commons reads whichever diarization model is resident —
// so the screen makes its choice resident first, which is also what downloads
// it on the first run.
const fmtSecs = (ms) => (ms / 1000).toFixed(1) + 's';
let diarCleanup = null;
function wireDiarization() {
  const btn = $('diargo'); const label = $('diarlabel'); const cc = captureController();
  let recording = false;
  const setLabel = (t) => { if (label) label.textContent = t; };
  const stopRecording = () => {
    recording = false;
    setLabel('Record');
    btn.classList.remove('rec');
  };
  // Leaving the tab mid-recording must close the microphone, not leave it open
  // behind a screen the user can no longer see.
  diarCleanup = () => {
    if (!recording) return;
    try { cc.stop(); } catch { /* graph already torn down */ }
    stopRecording();
    setStatus('ready');
  };
  btn.addEventListener('click', async () => {
    if (!recording) {
      try { await cc.start(); } catch (e) { $('diarout').textContent = 'could not open the microphone: ' + (e.message || e); return; }
      recording = true; setLabel('Stop'); btn.classList.add('rec');
      $('diarout').textContent = 'recording… tap Stop when done';
      setStatus('recording…');
      return;
    }
    const rec = cc.stop();
    stopRecording();
    if (!rec || !rec.samples.length) { $('diarout').textContent = 'no audio captured'; setStatus('ready'); return; }
    btn.disabled = true; $('diarout').textContent = 'preparing…';
    try {
      // ONNX is the only backend carrying diarization_ops; pin it so a bare
      // .onnx cannot be routed to llama.cpp by a registry rescan.
      await loadSelected('diarization', { framework: 'ONNX' });
      setStatus('diarizing…'); $('diarout').textContent = 'diarizing…';
      const samples = rec.rate === 16000 ? rec.samples : ra.downsample(rec.samples, rec.rate, 16000);
      const result = await ra.diarization.diarize(ra.audio.float32(samples, 16000));
      const segments = result.segments || [];
      const speakers = [...new Set(segments.map((s) => s.speakerId))];
      $('diarout').innerHTML = segments.length
        ? `<div class="figcap">${result.speakerCount} speaker${result.speakerCount === 1 ? '' : 's'} · ${fmtSecs((samples.length / 16000) * 1000)} recorded</div>` +
          segments.map((s) => {
            const n = speakers.indexOf(s.speakerId) + 1;
            return `<div class="ragchunk"><div class="meta"><span>Speaker ${n}</span><span class="ragscore">${fmtSecs(s.startMs)} – ${fmtSecs(s.endMs)}</span></div></div>`;
          }).join('')
        : `No speech segments detected (${result.speakerCount} speaker${result.speakerCount === 1 ? '' : 's'}).`;
    } catch (e) { $('diarout').textContent = 'error: ' + e.message; }
    finally { btn.disabled = false; setStatus('ready'); }
  });
}

// ---- semantic segmentation ----
// A distinct colour per class id, spaced by the golden angle so neighbouring
// ids never come out as neighbouring hues.
function classRgb(id) {
  const h = ((id * 137.508) % 360) / 60;
  const c = 0.62, x = c * (1 - Math.abs((h % 2) - 1)), m = 0.24;
  const [r, g, b] = h < 1 ? [c, x, 0] : h < 2 ? [x, c, 0] : h < 3 ? [0, c, x]
    : h < 4 ? [0, x, c] : h < 5 ? [x, 0, c] : [c, 0, x];
  return [Math.round((r + m) * 255), Math.round((g + m) * 255), Math.round((b + m) * 255)];
}
// Commons has no image decoder: rac_segmentation_image_t takes decoded pixels,
// so the chosen file is decoded here and handed over as raw RGB. Capped at
// 512px on the long edge, which is what SegFormer B0 was trained at.
async function decodeRawRgb(file, maxEdge = 512) {
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, maxEdge / Math.max(bitmap.width, bitmap.height));
  const width = Math.max(1, Math.round(bitmap.width * scale));
  const height = Math.max(1, Math.round(bitmap.height * scale));
  const off = document.createElement('canvas');
  off.width = width; off.height = height;
  off.getContext('2d').drawImage(bitmap, 0, 0, width, height);
  bitmap.close();
  const rgba = off.getContext('2d').getImageData(0, 0, width, height).data;
  const rgb = new Uint8Array(width * height * 3);
  for (let i = 0, j = 0; i < rgba.length; i += 4, j += 3) {
    rgb[j] = rgba[i]; rgb[j + 1] = rgba[i + 1]; rgb[j + 2] = rgba[i + 2];
  }
  return { rgb, width, height };
}
function paintClassMask(canvas, result) {
  const { classMask, width, height } = result;
  if (!classMask || classMask.length < width * height) { canvas.style.display = 'none'; return; }
  const px = new Uint8ClampedArray(width * height * 4);
  const palette = new Map();
  for (let i = 0; i < width * height; i++) {
    const id = classMask[i];
    let rgb = palette.get(id);
    if (!rgb) { rgb = classRgb(id); palette.set(id, rgb); }
    px[i * 4] = rgb[0]; px[i * 4 + 1] = rgb[1]; px[i * 4 + 2] = rgb[2]; px[i * 4 + 3] = 255;
  }
  canvas.width = width; canvas.height = height; canvas.style.display = 'block';
  canvas.getContext('2d').putImageData(new ImageData(px, width, height), 0, 0);
}
function wireSegmentation() {
  const picker = $('segfile');
  const canvas = $('segcanvas');
  picker.addEventListener('change', () => {
    $('seggo').disabled = !picker.files.length;
    $('segfname').textContent = picker.files[0] ? picker.files[0].name : 'No image selected';
  });
  $('seggo').addEventListener('click', async () => {
    const file = picker.files[0];
    if (!file) return;
    $('seggo').disabled = true; $('segout').textContent = 'preparing…';
    try {
      await loadSelected('segmentation', { framework: 'ONNX' });
      setStatus('segmenting…'); $('segout').textContent = 'segmenting…';
      const { rgb, width, height } = await decodeRawRgb(file);
      const result = await ra.segmentation.segment(ra.image.rawRgb(rgb, width, height));
      paintClassMask(canvas, result);
      const classes = (result.classes || []).slice().sort((a, b) => b.fraction - a.fraction).slice(0, 12);
      $('segout').innerHTML = classes.length
        ? classes.map((c) => {
          const [r, g, b] = classRgb(c.classId);
          const name = c.label || 'class ' + c.classId;
          return '<div class="ragchunk"><div class="meta">' +
            `<span><span style="display:inline-block;width:10px;height:10px;border-radius:3px;margin-right:7px;background:rgb(${r},${g},${b})"></span>${escapeHtml(name)}</span>` +
            `<span class="ragscore">${(c.fraction * 100).toFixed(1)}%</span></div></div>`;
        }).join('')
        : 'No classes detected.';
    } catch (e) { $('segout').textContent = 'error: ' + e.message; canvas.style.display = 'none'; }
    finally { $('seggo').disabled = false; setStatus('ready'); }
  });
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
    for await (const event of ra.llm.generateStream(
      [
        { role: 'system', content: settings.systemPrompt },
        { role: 'user', content: 'Say hello in one short sentence.' },
      ],
      { model: selectedModel('llm'), maxOutputTokens: 24 }
    )) {
      if (event.type === 'token' && event.kind === 'TEXT') reply += event.text;
    }
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

    const cat = await ensureCatalog();
    if (!cat['qwen3.5-0.8b']) throw new Error('catalog missing');
    // The catalog is the app's table; the registry is what commons resolves ids
    // against. A staged entry that never became a row is the failure worth
    // catching here, so read it back through ra.models.
    const { byId } = await modelState();
    const row = byId.get('qwen3.5-0.8b');
    if (!row) throw new Error('catalog entry never reached the registry');
    log('[selftest] models OK: ' + Object.keys(cat).length + ' catalog entries, ' + byId.size + ' registry rows, qwen downloaded=' + row.downloaded);

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
  // Backend creds (telemetry/auth) come from the main process's .env reader; a
  // desktop-control-plane build uses them, an inference-only build ignores them.
  let backendCfg;
  try { backendCfg = await window.appStore.backendConfig(); } catch { backendCfg = undefined; }
  await ra.initialize(undefined, undefined, backendCfg);
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
    // Commons' registry is per process, so a custom entry has to be re-staged on
    // every start the same way the catalog is — otherwise its id resolves to
    // nothing and every later ra.models call on it fails.
    await registerCustomModels();
  }
  setStatus('ready');
  if (IS_SELFTEST) { setStatus('self-test…'); await selfTest(); } else { wireUi(); }
})().catch((e) => {
  setStatus('error: ' + (e && e.message)); console.error(e);
  if (IS_SELFTEST) { try { window.runanywhereTest.log('[selftest] STARTUP ERROR: ' + (e && e.message) + '\n'); window.runanywhereTest.done(false); } catch { /* ignore */ } }
});
