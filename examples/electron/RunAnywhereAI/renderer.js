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
  { name: 'get_weather', description: 'Get live current weather for a city. Use only for weather requests.', parameters: { type: 'object', properties: { city: { type: 'string' }, unit: { type: 'string', enum: ['celsius', 'fahrenheit'] } }, required: ['city', 'unit'] } },
  { name: 'set_timer', description: 'Start a real local countdown timer. Use only when the user asks for a timer.', parameters: { type: 'object', properties: { seconds: { type: 'integer' }, label: { type: 'string' } }, required: ['seconds', 'label'] } },
];
const CHAT_TOOLS = [
  ...TOOLS,
  {
    name: 'respond_directly',
    description: 'Use when no weather lookup or timer is required. Do not force a tool for ordinary questions.',
    parameters: { type: 'object', properties: { reason: { type: 'string' } }, required: ['reason'] },
  },
];

// ---- settings + conversations + custom models (persisted via demoStore) ----
let settings = { systemPrompt: 'You are a concise, helpful assistant.', temperature: 0.7, maxTokens: 256, reasoning: false, toolsEnabled: false };
let conversations = [];
let activeId = null;
let nextConvId = 1;
let customModels = []; // [{ id, source, type, label, downloaded }]

// ---- lazily-loaded model handles ----
const handles = {};
const ensure = (k, fn) => (handles[k] ??= fn());
const DEFAULT_LLM = 'gemma-4-12b';
const DEFAULT_VLM = 'gemma-4-e4b';
// The chat's active LLM. Loading another LLM from the Models tab replaces it (the
// backend keeps one loaded at a time), so we track it in loadedById/loadedType too
// to keep the Models badges coherent — exactly one LLM ever shows "loaded".
const llm = () => ensure('llm', async () => {
  const h = await ra.loadLLM(DEFAULT_LLM);
  loadedById[DEFAULT_LLM] = h; loadedType[DEFAULT_LLM] = 'llm';
  return h;
});
const embedder = () => ensure('embedder', () => ra.loadEmbedder('minilm'));
const vlm = () => ensure('vlm', () => ra.loadVLM(DEFAULT_VLM));
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
function toolRunHtml(tool) {
  if (!tool) return '';
  const call = `${tool.name}(${JSON.stringify(tool.arguments || {})})`;
  const result = typeof tool.result === 'string' ? tool.result : JSON.stringify(tool.result, null, 2);
  return `<div class="toolrun"><div class="toolhead">Tool call · ${escapeHtml(tool.name)}</div><div class="toolbody">${escapeHtml(call)}\n${escapeHtml(result || '')}</div></div>`;
}
function assistantBodyHtml(message, streaming = false) {
  return toolRunHtml(message.tool) + assistantHtml(message.content || '', streaming);
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
  const body = m.role === 'assistant' ? assistantBodyHtml(m) : escapeHtml(m.content);
  const metrics = m.metrics ? `<div class="metrics">⚡ ${m.metrics.tokens} tokens · ${m.metrics.tps.toFixed(1)} tok/s · TTFT ${Math.round(m.metrics.ttft)}ms</div>` : '';
  const av = m.role === 'assistant' ? '<img src="../../logo.svg" alt="" />' : 'U';
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
    <div class="logo"><img src="../../logo.svg" alt="" /></div>
    <h3>On-device AI, privately</h3>
    <p>AI runs locally. When enabled, a tool may contact its named data provider.</p>
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
  let sys = settings.systemPrompt;
  // Reasoning mode: ask the model to think in <think></think> first. The SDK's
  // splitThinking (mirrored by assistantHtml) peels that back out for display.
  if (settings.reasoning) sys += '\n\nThink step by step inside <think></think> tags, then give your final answer after the closing tag.';
  let p = sys + '\n\n';
  for (const m of priorMessages) {
    const content = m.role === 'assistant' ? ra.splitThinking(m.content).response : m.content;
    p += (m.role === 'user' ? 'User: ' : 'Assistant: ') + content + '\n';
  }
  return p + 'User: ' + userText + '\nAssistant:';
}
async function fetchJson(url) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10000);
  try {
    const response = await fetch(url, { signal: controller.signal });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    return await response.json();
  } finally {
    clearTimeout(timeout);
  }
}
const WEATHER_CODE = {
  0: 'clear sky', 1: 'mainly clear', 2: 'partly cloudy', 3: 'overcast',
  45: 'fog', 48: 'rime fog', 51: 'light drizzle', 53: 'drizzle', 55: 'heavy drizzle',
  61: 'light rain', 63: 'rain', 65: 'heavy rain', 71: 'light snow', 73: 'snow',
  75: 'heavy snow', 80: 'rain showers', 81: 'rain showers', 82: 'heavy rain showers',
  95: 'thunderstorm', 96: 'thunderstorm with hail', 99: 'thunderstorm with heavy hail',
};
async function executeToolCall(call) {
  if (call.name === 'get_weather') {
    const city = String(call.arguments?.city || '').trim();
    const unit = call.arguments?.unit === 'fahrenheit' ? 'fahrenheit' : 'celsius';
    if (!city) throw new Error('get_weather requires a city');
    const placeUrl = `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(city)}&count=1&language=en&format=json`;
    const placeData = await fetchJson(placeUrl);
    const place = placeData.results?.[0];
    if (!place) throw new Error(`No location found for ${city}`);
    const weatherUrl = new URL('https://api.open-meteo.com/v1/forecast');
    weatherUrl.searchParams.set('latitude', String(place.latitude));
    weatherUrl.searchParams.set('longitude', String(place.longitude));
    weatherUrl.searchParams.set('current', 'temperature_2m,apparent_temperature,weather_code,wind_speed_10m');
    weatherUrl.searchParams.set('temperature_unit', unit);
    weatherUrl.searchParams.set('wind_speed_unit', 'kmh');
    weatherUrl.searchParams.set('timezone', 'auto');
    const data = await fetchJson(weatherUrl.toString());
    const current = data.current;
    if (!current) throw new Error('Weather provider returned no current conditions');
    return {
      location: [place.name, place.admin1, place.country].filter(Boolean).join(', '),
      conditions: WEATHER_CODE[current.weather_code] || `weather code ${current.weather_code}`,
      temperature: `${current.temperature_2m} ${data.current_units?.temperature_2m || (unit === 'fahrenheit' ? '°F' : '°C')}`,
      apparentTemperature: `${current.apparent_temperature} ${data.current_units?.apparent_temperature || (unit === 'fahrenheit' ? '°F' : '°C')}`,
      wind: `${current.wind_speed_10m} ${data.current_units?.wind_speed_10m || 'km/h'}`,
      observedAt: current.time,
    };
  }
  if (call.name === 'set_timer') {
    const seconds = Math.round(Number(call.arguments?.seconds));
    const label = String(call.arguments?.label || 'Timer').trim() || 'Timer';
    if (!Number.isFinite(seconds) || seconds < 1 || seconds > 86400) {
      throw new Error('Timer duration must be between 1 second and 24 hours');
    }
    setTimeout(() => {
      try { new Notification('Timer finished', { body: label }); } catch { /* OS notification is best-effort */ }
    }, seconds * 1000);
    return { status: 'scheduled', label, seconds };
  }
  throw new Error(`Unsupported tool: ${call.name}`);
}
async function chooseChatTool(text) {
  const prompt =
    'Decide whether this user request needs one of the available tools. ' +
    'Choose respond_directly for ordinary conversation or questions that do not require live weather or a timer.\n\n' +
    `User request: ${text}`;
  return ra.generateToolCall(await llm(), prompt, CHAT_TOOLS, { maxTokens: 192, temperature: 0 });
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
    let generationText = text;
    if (settings.toolsEnabled) {
      setStatus('choosing tool…');
      const call = await chooseChatTool(text);
      if (call.name !== 'respond_directly') {
        setStatus(`running ${call.name}…`);
        let toolResult;
        try { toolResult = await executeToolCall(call); }
        catch (error) { toolResult = { error: error.message }; }
        asst.tool = { name: call.name, arguments: call.arguments, result: toolResult };
        bubble.innerHTML = assistantBodyHtml(asst, true);
        generationText =
          `${text}\n\nThe application executed this tool:\n` +
          `${call.name}(${JSON.stringify(call.arguments)})\n` +
          `Tool result: ${JSON.stringify(toolResult)}\n\n` +
          'Answer the user naturally using the tool result. Do not invent values that are not in the result.';
      }
    }
    setStatus('generating…');
    const runGen = async () => {
      asst.content = '';
      const h = await llm();
      await ra.generateStream(h, buildPrompt(prior, generationText), { temperature: settings.temperature, maxTokens: settings.maxTokens }, (e) => {
        if (e.isFinal) { result = e.result; }
        else { asst.content += e.token; bubble.innerHTML = assistantBodyHtml(asst, true); $('chatlog').scrollTop = $('chatlog').scrollHeight; }
      });
    };
    try {
      await runGen();
    } catch (e) {
      // The backend keeps ONE LLM loaded at a time, so loading a model from the
      // Models tab evicts the chat model and our memoized handle goes stale. Drop
      // it and reload the chat model once before surfacing an error.
      if (/no model|not loaded|model.*load/i.test(e.message || '')) {
        delete handles.llm;
        for (const k of Object.keys(loadedById)) if (loadedType[k] === 'llm') forgetLoaded(k); // stale LLM badges
        await runGen();
      } else throw e;
    }
    const clean = ra.splitThinking(asst.content);
    asst.content = settings.reasoning && clean.thinking
      ? `<think>${clean.thinking}</think>${clean.response}`
      : clean.response;
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
      bar.firstElementChild.style.width = '0%';
      const oldError = div.querySelector('.dlerror');
      if (oldError) oldError.remove();
      let resolved;
      try { resolved = await ra.downloadModel(o.source, (p) => { bar.firstElementChild.style.width = (p.percent || 0) + '%'; }); }
      catch (e) {
        const message = (e && e.message) ? e.message : String(e);
        dl.textContent = 'Retry';
        dl.disabled = false;
        bar.style.display = 'none';
        const error = document.createElement('div');
        error.className = 'dlerror';
        error.textContent = message;
        error.title = message;
        error.style.cssText = 'margin-top:9px;color:#fda4af;font-size:12px;line-height:1.4;overflow-wrap:anywhere';
        div.appendChild(error);
        setStatus('download failed');
        console.error(e);
        return;
      }
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
          if (o.type === 'llm') delete handles.llm; // chat reloads its default next time
        } else {
          if (o.type === 'llm') {
            // Backend keeps ONE LLM loaded — unload whichever is active first.
            for (const k of Object.keys(loadedById)) {
              if (loadedType[k] === 'llm') { try { await unloaders.llm(loadedById[k]); } catch { /* already gone */ } forgetLoaded(k); }
            }
            delete handles.llm;
          }
          loadedById[o.key] = await loaders[o.type](o.source);
          loadedType[o.key] = o.type;
          if (o.type === 'llm') handles.llm = Promise.resolve(loadedById[o.key]); // chat now uses this model
        }
      } catch (e) { b.textContent = 'Error'; btns.forEach((x) => (x.disabled = false)); console.error(e); return; }
      renderModels();
    });
    actions.appendChild(b);
  }
  if (o.custom) {
    actions.appendChild(mkbtn('Remove', async () => {
      if (loadedById[o.key]) { try { await unloaders[o.type](loadedById[o.key]); } catch { /* ignore */ } forgetLoaded(o.key); if (o.type === 'llm') delete handles.llm; }
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
      if (entry.heavy) sub += ' <span class="badge heavy">large download</span>';
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
  if ($('setreason')) $('setreason').checked = !!settings.reasoning;
  $('chattools').checked = !!settings.toolsEnabled;
  $('chattoolsstate').textContent = settings.toolsEnabled ? 'on' : 'off';
}
async function saveSettings() {
  settings = {
    systemPrompt: $('setsystem').value,
    temperature: parseFloat($('settemp').value),
    maxTokens: parseInt($('setmax').value, 10) || 256,
    reasoning: !!($('setreason') && $('setreason').checked),
    toolsEnabled: !!$('chattools').checked,
  };
  try { await store.saveSettings(settings); } catch { /* optional */ }
  $('setstatus').textContent = 'saved'; setTimeout(() => ($('setstatus').textContent = ''), 1500);
}

// ---- shared feature helpers (used by UI + self-test) ----
async function runStructured(text) {
  return ra.generateStructured(await llm(), `Extract the person as JSON. Text: "${text}"`, {
    type: 'object',
    properties: { name: { type: 'string' }, age: { type: 'integer' }, interests: { type: 'array', items: { type: 'string' }, maxItems: 5 } },
    required: ['name', 'age', 'interests'],
  }, { maxTokens: 192, temperature: 0 });
}
async function runTools(text) {
  return ra.generateToolCall(await llm(), text, TOOLS, { maxTokens: 192, temperature: 0 });
}
async function runAndExecuteTool(text) {
  const call = await runTools(text);
  return { ...call, result: await executeToolCall(call) };
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
  if (!s) return '';
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
  let raw = '';
  const audio = /\.(wav|mp3|flac|m4a|ogg)$/i.test(imagePath);
  const prompt = audio
    ? 'Transcribe the speech, identify important sounds, and summarize this audio.'
    : 'Describe this image in one sentence.';
  await ra.generateVlm(await vlm(), imagePath, prompt, (t) => {
    raw += t;
    onToken?.(ra.splitThinking(raw).response);
  });
  return ra.splitThinking(raw).response;
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
let stopLiveCamera = () => {};
function wireVision() {
  const vf = $('visionfile');
  const video = $('visioncamera');
  const preview = $('visionpreview');
  const canvas = $('visioncanvas');
  const placeholder = $('cameraplaceholder');
  const cameraSelect = $('cameraselect');
  const start = $('camerastart');
  const capture = $('cameracapture');
  const stop = $('camerastop');
  let cameraStream = null;
  let cameraCapturePath = null;

  const refreshCameraList = async (preferredId = cameraSelect.value) => {
    if (!navigator.mediaDevices?.enumerateDevices) return;
    const devices = await navigator.mediaDevices.enumerateDevices();
    const cameras = devices.filter((device) => device.kind === 'videoinput');
    cameraSelect.innerHTML = '<option value="">Default camera</option>';
    cameras.forEach((camera, index) => {
      const option = document.createElement('option');
      option.value = camera.deviceId;
      option.textContent = camera.label || `Camera ${index + 1}`;
      cameraSelect.appendChild(option);
    });
    cameraSelect.value = cameras.some((camera) => camera.deviceId === preferredId) ? preferredId : '';
  };

  const stopCamera = () => {
    const stream = cameraStream;
    cameraStream = null;
    if (stream) stream.getTracks().forEach((track) => track.stop());
    video.srcObject = null;
    video.classList.remove('active');
    capture.disabled = true;
    stop.disabled = true;
    start.disabled = false;
    if (preview.src) {
      preview.classList.add('active');
      placeholder.style.display = 'none';
    } else {
      placeholder.style.display = '';
    }
  };
  stopLiveCamera = stopCamera;

  const startCamera = async () => {
    if (cameraStream) return;
    $('camerastatus').textContent = 'Requesting camera access…';
    start.disabled = true;
    cameraSelect.disabled = true;
    try {
      const selectedDeviceId = cameraSelect.value;
      cameraStream = await navigator.mediaDevices.getUserMedia({
        video: {
          ...(selectedDeviceId ? { deviceId: { exact: selectedDeviceId } } : {}),
          width: { ideal: 1280 },
          height: { ideal: 720 },
        },
        audio: false,
      });
      const videoTrack = cameraStream.getVideoTracks()[0];
      const activeDeviceId = videoTrack?.getSettings().deviceId || selectedDeviceId;
      preview.classList.remove('active');
      video.srcObject = cameraStream;
      video.classList.add('active');
      placeholder.style.display = 'none';
      await video.play();
      await refreshCameraList(activeDeviceId).catch(() => {});
      videoTrack?.addEventListener('ended', () => {
        if (!cameraStream) return;
        stopCamera();
        $('camerastatus').textContent = 'Camera disconnected. Choose another camera.';
        refreshCameraList().catch(() => {});
      }, { once: true });
      start.disabled = true;
      capture.disabled = false;
      stop.disabled = false;
      $('camerastatus').textContent = 'Camera is live. Capture a frame to analyze it.';
    } catch (error) {
      stopCamera();
      $('camerastatus').textContent = 'error: ' + error.message;
      refreshCameraList().catch(() => {});
    } finally {
      cameraSelect.disabled = false;
    }
  };

  vf.addEventListener('change', () => {
    stopCamera();
    cameraCapturePath = null;
    preview.src = '';
    preview.classList.remove('active');
    placeholder.style.display = '';
    $('visiongo').disabled = !vf.files.length;
    $('visionfname').textContent = vf.files[0] ? vf.files[0].name : 'No media selected';
  });
  start.addEventListener('click', startCamera);
  cameraSelect.addEventListener('change', async () => {
    if (!cameraStream) return;
    stopCamera();
    await startCamera();
  });
  refreshCameraList().catch(() => {});
  navigator.mediaDevices?.addEventListener?.('devicechange', () => refreshCameraList().catch(() => {}));
  capture.addEventListener('click', async () => {
    if (!cameraStream || !video.videoWidth || !video.videoHeight) return;
    capture.disabled = true;
    $('camerastatus').textContent = 'Capturing frame…';
    try {
      canvas.width = video.videoWidth;
      canvas.height = video.videoHeight;
      canvas.getContext('2d').drawImage(video, 0, 0, canvas.width, canvas.height);
      const blob = await new Promise((resolve, reject) => {
        canvas.toBlob((value) => value ? resolve(value) : reject(new Error('Camera capture failed')), 'image/png');
      });
      cameraCapturePath = await store.saveCameraFrame(new Uint8Array(await blob.arrayBuffer()));
      vf.value = '';
      preview.src = canvas.toDataURL('image/png');
      preview.classList.add('active');
      video.classList.remove('active');
      $('visionfname').textContent = 'Live camera frame';
      $('visiongo').disabled = false;
      $('camerastatus').textContent = 'Frame captured. Press Analyze or capture another frame.';
    } catch (error) {
      $('camerastatus').textContent = 'error: ' + error.message;
    } finally {
      capture.disabled = !cameraStream;
    }
  });
  stop.addEventListener('click', stopCamera);
  window.addEventListener('beforeunload', stopCamera);

  $('visiongo').addEventListener('click', async () => {
    const file = vf.files[0];
    let mediaPath = cameraCapturePath;
    if (file) {
      // Electron removed File.path; resolve the on-disk path via webUtils.
      mediaPath = file.path;
      try { if (!mediaPath && store && store.getPathForFile) mediaPath = store.getPathForFile(file); } catch (_) { /* ignore */ }
    }
    if (!mediaPath) { $('visionout').textContent = 'error: choose media or capture a camera frame first'; return; }
    $('visiongo').disabled = true;
    setStatus('analyzing…'); $('visionout').textContent = '…';
    let cap = '';
    try { cap = await runVision(mediaPath, (text) => { cap = text; $('visionout').textContent = cap || '…'; }); }
    catch (e) { $('visionout').textContent = 'error: ' + e.message; }
    finally {
      $('visiongo').disabled = !(vf.files.length || cameraCapturePath);
      setStatus('ready');
    }
  });
}

// ---- tabs ----
function showTab(name) {
  if (name !== 'vision') stopLiveCamera();
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
  const sdkEvents = [];
  const renderEvents = () => {
    $('eventlog').textContent = sdkEvents.length
      ? sdkEvents.map((e) => `${e.type}${e.modality ? ` · ${e.modality}` : ''}${e.id ? ` · ${e.id}` : ''}`).join('\n')
      : 'No events yet.';
    $('eventlog').scrollTop = $('eventlog').scrollHeight;
  };
  ra.onEvent((event) => { sdkEvents.push(event); if (sdkEvents.length > 20) sdkEvents.shift(); renderEvents(); });
  ra.version()
    .then((version) => { $('sdkinfo').textContent = `RunAnywhere ${version} · local runtime ready`; })
    .catch((e) => { $('sdkinfo').textContent = 'Runtime error: ' + e.message; });
  $('eventclear').addEventListener('click', () => { sdkEvents.length = 0; renderEvents(); });

  $('newchat').addEventListener('click', () => { newConversation(); showTab('chat'); $('chatinput').focus(); });
  $('chatsend').addEventListener('click', sendChat);
  $('chatinput').addEventListener('keydown', (e) => { if (e.key === 'Enter') sendChat(); });
  $('chattools').addEventListener('change', async () => {
    settings.toolsEnabled = $('chattools').checked;
    $('chattoolsstate').textContent = settings.toolsEnabled ? 'on' : 'off';
    try { await store.saveSettings(settings); } catch { /* optional */ }
  });

  $('settemp').addEventListener('input', () => ($('settempval').textContent = $('settemp').value));
  $('setsave').addEventListener('click', saveSettings);
  $('setapisave').addEventListener('click', async () => {
    const v = $('setapikey').value.trim(); if (!v) return;
    try { await ra.secureSet('api-key', v); $('setapistatus').textContent = 'Credential saved securely.'; $('setapikey').value = ''; }
    catch (e) { $('setapistatus').textContent = 'error: ' + e.message; }
  });
  $('setapicheck').addEventListener('click', async () => {
    try { $('setapistatus').textContent = (await ra.secureGet('api-key')) == null ? 'No credential is stored.' : 'A credential is stored.'; }
    catch (e) { $('setapistatus').textContent = 'error: ' + e.message; }
  });
  $('setapidelete').addEventListener('click', async () => {
    try { await ra.secureDelete('api-key'); $('setapistatus').textContent = 'Stored credential deleted.'; $('setapikey').value = ''; }
    catch (e) { $('setapistatus').textContent = 'error: ' + e.message; }
  });

  const out = (id, fn) => async () => { setStatus('working…'); $(id).textContent = '…'; try { $(id).textContent = await fn(); } catch (e) { $(id).textContent = 'error: ' + e.message; } setStatus('ready'); };
  $('structgo').addEventListener('click', out('structout', async () => JSON.stringify(await runStructured($('structtext').value), null, 2)));
  $('toolsgo').addEventListener('click', out('toolsout', async () => {
    const run = await runAndExecuteTool($('toolstext').value);
    return `${run.name}(${JSON.stringify(run.arguments)})\n${JSON.stringify(run.result, null, 2)}`;
  }));
  $('embgo').addEventListener('click', out('embout', async () => 'cosine similarity: ' + (await runEmbeddings($('emba').value, $('embb').value)).toFixed(3)));

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

  wireVision();

  wireVoice();
  wireVad();
}

// ---- voice (inline Web Audio) ----
function captureController() {
  let cap = null;
  return {
    async start() {
      if (cap) return;
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
  const btn = $('voicebtn'); const cc = captureController(); let recording = false;
  const begin = async (event) => {
    if (recording || (event && event.button !== 0)) return;
    recording = true;
    btn.classList.add('recording');
    try {
      if (event && btn.setPointerCapture) btn.setPointerCapture(event.pointerId);
      setStatus('listening…');
      await cc.start();
    } catch (e) {
      recording = false;
      btn.classList.remove('recording');
      $('voiceheard').textContent = 'error: ' + e.message;
      setStatus('ready');
    }
  };
  const end = async () => {
    if (!recording) return;
    recording = false;
    btn.classList.remove('recording');
    const rec = cc.stop(); if (!rec) return;
    try {
      setStatus('transcribing…');
      const heard = await ra.transcribe(await stt(), toPcm16At16k(rec.samples, rec.rate));
      $('voiceheard').textContent = heard || '(No speech recognized)';
      if (!heard || !heard.trim()) return;
      let rawReply = ''; $('voicereply').textContent = '';
      setStatus('thinking…');
      await ra.generate(await llm(), `You are concise. Reply in one sentence.\n\n${heard}`, (t) => {
        rawReply += t;
        $('voicereply').textContent = ra.splitThinking(rawReply).response || '…';
      });
      const reply = ra.splitThinking(rawReply).response;
      if (!reply) throw new Error('The model returned an empty reply.');
      $('voicereply').textContent = reply;
      const audio = await ra.synthesize(await tts(), reply);
      setStatus('speaking…');
      const pctx = new AudioContext(); const buf = pctx.createBuffer(1, audio.samples.length, audio.sampleRate); buf.getChannelData(0).set(audio.samples);
      const s = pctx.createBufferSource(); s.buffer = buf; s.connect(pctx.destination);
      await new Promise((r) => { s.onended = () => { pctx.close(); r(); }; s.start(); });
    } catch (e) {
      $('voicereply').textContent = 'error: ' + e.message;
    } finally {
      setStatus('ready');
    }
  };
  btn.addEventListener('pointerdown', begin);
  btn.addEventListener('pointerup', end);
  btn.addEventListener('pointercancel', end);
}
function wireVad() {
  const btn = $('vadbtn'); const cc = captureController(); let vadHandle = null; let frames = 0, speech = 0; let frameQueue = Promise.resolve();
  $('vadth').addEventListener('input', async () => { $('vadthval').textContent = $('vadth').value; if (vadHandle != null) await ra.vadSetThreshold(vadHandle, parseFloat($('vadth').value)); });
  const begin = async (event) => {
    if (vadHandle != null || (event && event.button !== 0)) return;
    try {
      if (event && btn.setPointerCapture) btn.setPointerCapture(event.pointerId);
      setStatus('listening…'); frames = 0; speech = 0; frameQueue = Promise.resolve(); $('vadout').textContent = 'calibrating…';
      vadHandle = await ra.createVad(parseFloat($('vadth').value));
      await cc.start();
      cc.onFrame((f, rate) => {
        const handle = vadHandle;
        if (handle == null) return;
        frameQueue = frameQueue.then(async () => {
          const ratio = rate / 16000, outLen = Math.floor(f.length / ratio), frame = new Float32Array(outLen);
          for (let i = 0; i < outLen; i++) frame[i] = f[Math.floor(i * ratio)];
          const isSpeech = await ra.vadProcess(handle, frame);
          const active = await ra.vadIsActive(handle);
          frames++; if (isSpeech) speech++;
          $('vadout').textContent = (frames < 20 ? 'calibrating… ' : (active ? '🎤 SPEECH ' : '· silence ')) + `(${speech}/${frames} speech frames)`;
        }).catch((e) => { $('vadout').textContent = 'error: ' + e.message; });
      });
    } catch (e) {
      $('vadout').textContent = 'error: ' + e.message;
      if (vadHandle != null) { try { await ra.unloadVad(vadHandle); } catch (_) { /* ignore */ } vadHandle = null; }
      setStatus('ready');
    }
  };
  const end = async () => {
    cc.stop();
    const handle = vadHandle;
    vadHandle = null;
    if (handle != null) {
      try { await frameQueue; await ra.unloadVad(handle); }
      catch (e) { $('vadout').textContent = 'error: ' + e.message; }
    }
    setStatus('ready');
  };
  $('vadreset').addEventListener('click', async () => {
    if (vadHandle == null) { $('vadout').textContent = 'Start listening, then reset the live detector.'; return; }
    try { await frameQueue; await ra.vadReset(vadHandle); frames = 0; speech = 0; $('vadout').textContent = 'detector reset'; }
    catch (e) { $('vadout').textContent = 'error: ' + e.message; }
  });
  btn.addEventListener('pointerdown', begin);
  btn.addEventListener('pointerup', end);
  btn.addEventListener('pointercancel', end);
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
    const visibleReply = ra.splitThinking(reply).response;
    if (!visibleReply) throw new Error('empty chat reply');
    if (/channel|^thought\b/i.test(visibleReply)) throw new Error('chat protocol markers leaked');
    log('[selftest] chat OK: ' + JSON.stringify(visibleReply.slice(0, 70)));

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
    if (!cat[DEFAULT_LLM] || !cat[DEFAULT_VLM]) throw new Error('Gemma catalog entries missing');
    const status = await ra.modelStatus();
    log('[selftest] models OK: ' + Object.keys(cat).length + ' catalog entries, Gemma 12B downloaded=' + status[DEFAULT_LLM].downloaded);

    const image = new URLSearchParams(location.search).get('image');
    if (image) { const c = await runVision(image); if (!c || c.length < 3) throw new Error('empty caption'); log('[selftest] vision OK: ' + JSON.stringify(c.slice(0, 70))); }
    else log('[selftest] vision SKIPPED (no image)');

    const logoResponse = await fetch('runanywhere-logo.png');
    if (!logoResponse.ok) throw new Error('app logo could not be loaded');
    const cameraPath = await store.saveCameraFrame(new Uint8Array(await logoResponse.arrayBuffer()));
    if (!/latest-capture\.png$/i.test(cameraPath || '')) throw new Error('camera capture IPC returned an invalid path');
    log('[selftest] camera capture IPC OK');
    if (!navigator.mediaDevices?.enumerateDevices) throw new Error('camera enumeration API unavailable');
    const cameraDevices = (await navigator.mediaDevices.enumerateDevices()).filter((device) => device.kind === 'videoinput');
    log(`[selftest] camera selection API OK: ${cameraDevices.length} video input(s) visible`);

    const secret = 'sk-demo-secret-12345';
    if ((await runSecure('demo-selftest-key', secret)) !== secret) throw new Error('secure store failed');
    log('[selftest] secure store OK (encrypted round-trip)');

    const spoken = await ra.synthesize(await tts(), 'Hello from RunAnywhere on Windows.');
    if (!spoken || spoken.sampleRate < 8000 || !spoken.samples || spoken.samples.length < spoken.sampleRate / 2) {
      throw new Error('tts returned invalid audio');
    }
    const heard = await ra.transcribe(await stt(), toPcm16At16k(spoken.samples, spoken.sampleRate));
    if (!heard || !heard.trim()) throw new Error('stt returned an empty transcript');
    log(`[selftest] speech OK: ${(spoken.samples.length / spoken.sampleRate).toFixed(2)}s TTS -> ${JSON.stringify(heard.trim())}`);

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
