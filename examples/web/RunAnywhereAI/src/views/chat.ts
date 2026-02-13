/**
 * Chat Tab - Full chat interface matching iOS ChatInterfaceView
 *
 * Features: model overlay, model selection sheet, message bubbles,
 * streaming, thinking mode, typing indicator, input area, toolbar,
 * tool calling toggle with demo tools (matching iOS ToolSettingsView).
 */

import type { TabLifecycle } from '../app';
import { ModelManager, ModelCategory, type ModelInfo } from '../services/model-manager';
import { showModelSelectionSheet } from '../components/model-selection';
import type { ToolValue } from '../../../../../sdk/runanywhere-web/packages/core/src/Public/Extensions/RunAnywhere+ToolCalling';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface ToolCallInfo {
  toolName: string;
  arguments: string;  // JSON string for display
  result?: string;    // JSON string for display
  success: boolean;
  error?: string;
}

interface ChatMessage {
  id: string;
  role: 'user' | 'assistant';
  content: string;
  thinking?: string;
  timestamp: number;
  modelId?: string;
  toolCalls?: ToolCallInfo[];
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

let messages: ChatMessage[] = [];
let isGenerating = false;
let toolsEnabled = false;
let toolsRegistered = false;
/** Cancel callback for the current streaming generation (stored so we can abort on tab switch). */
let cancelGeneration: (() => void) | null = null;
let container: HTMLElement;
let messagesEl: HTMLElement;
let inputEl: HTMLTextAreaElement;
let sendBtn: HTMLButtonElement;
let overlayEl: HTMLElement;
let toolbarModelEl: HTMLElement;
let toolsToggleBtn: HTMLElement;

// ---------------------------------------------------------------------------
// Init
// ---------------------------------------------------------------------------

export function initChatTab(el: HTMLElement): TabLifecycle {
  container = el;
  container.innerHTML = `
    <!-- Toolbar -->
    <div class="toolbar">
      <div class="toolbar-actions">
        <button class="btn btn-icon" id="chat-new-btn" title="New Chat">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="18" height="18"><path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/></svg>
        </button>
      </div>
      <div class="toolbar-model-btn" id="chat-toolbar-model" title="Change Model">
        <svg class="model-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/><polyline points="3.27 6.96 12 12.01 20.73 6.96"/><line x1="12" y1="22.08" x2="12" y2="12"/></svg>
        <span id="chat-toolbar-model-text">Select Model</span>
        <svg class="chevron" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 12 15 18 9"/></svg>
      </div>
      <div class="toolbar-actions">
        <button class="tools-toggle" id="chat-tools-toggle" title="Toggle Tool Calling">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z"/></svg>
          Tools
        </button>
      </div>
    </div>

    <!-- Messages -->
    <div class="scroll-area" id="chat-messages" style="padding-top:var(--space-md);padding-bottom:var(--space-md);">
      <!-- Empty state (shown when no messages) -->
      <div class="chat-empty-state" id="chat-empty-state">
        <div class="empty-logo">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="28" height="28"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>
        </div>
        <h3>Start a conversation</h3>
        <p>Type a message below to get started</p>
        <div class="suggestion-chips" id="chat-suggestions"></div>
      </div>
    </div>

    <!-- Tools badge (shown when tools are enabled) -->
    <div id="chat-tools-badge" style="display:none;padding:var(--space-sm) var(--space-lg) 0;"></div>

    <!-- Input -->
    <div class="chat-input-area">
      <textarea class="chat-input" id="chat-input" placeholder="Message..." rows="1"></textarea>
      <button class="send-btn" id="chat-send-btn" disabled>
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor"><path d="M2.01 21L23 12 2.01 3 2 10l15 2-15 2z"/></svg>
      </button>
    </div>

    <!-- Model Required Overlay -->
    <div class="model-overlay" id="chat-model-overlay">
      <div class="model-overlay-bg" id="chat-floating-bg"></div>
      <div class="model-overlay-content">
        <div class="sparkle-icon">&#10024;</div>
        <h2>Welcome!</h2>
        <p>Start chatting with on-device AI. Everything runs privately in your browser.</p>
        <button class="btn btn-primary btn-lg" id="chat-get-started-btn">Get Started</button>
        <div class="privacy-note">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="14" height="14"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>
          <span>100% Private &mdash; Runs on your device</span>
        </div>
      </div>
    </div>
  `;

  // Build floating circles for overlay
  buildFloatingCircles();

  // Cache references
  messagesEl = container.querySelector('#chat-messages')!;
  inputEl = container.querySelector('#chat-input')!;
  sendBtn = container.querySelector('#chat-send-btn')!;
  overlayEl = container.querySelector('#chat-model-overlay')!;
  toolbarModelEl = container.querySelector('#chat-toolbar-model')!;
  toolsToggleBtn = container.querySelector('#chat-tools-toggle')!;

  // Event listeners
  sendBtn.addEventListener('click', sendMessage);
  inputEl.addEventListener('input', onInputChange);
  inputEl.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      sendMessage();
    }
  });

  container.querySelector('#chat-get-started-btn')!.addEventListener('click', openModelSheet);
  toolbarModelEl.addEventListener('click', openModelSheet);
  toolsToggleBtn.addEventListener('click', toggleTools);
  container.querySelector('#chat-new-btn')!.addEventListener('click', clearChat);

  // Populate initial suggestion chips
  renderSuggestions();

  // Subscribe to model changes
  ModelManager.onChange(onModelsChanged);
  onModelsChanged(ModelManager.getModels());

  // Return lifecycle callbacks for tab-switching cleanup
  return {
    onDeactivate(): void {
      // Cancel any in-flight LLM generation to free the WASM main thread
      if (cancelGeneration) {
        cancelGeneration();
        cancelGeneration = null;
        console.log('[Chat] Tab deactivated — cancelled in-flight generation');
      }
    },
  };
}

// ---------------------------------------------------------------------------
// Floating circles background
// ---------------------------------------------------------------------------

function buildFloatingCircles(): void {
  const bg = container.querySelector('#chat-floating-bg')!;
  const colors = ['#FF5500', '#3B82F6', '#8B5CF6', '#10B981', '#EAB308'];
  for (let i = 0; i < 8; i++) {
    const circle = document.createElement('div');
    circle.className = 'floating-circle';
    const size = 60 + Math.random() * 120;
    circle.style.cssText = `
      width:${size}px; height:${size}px;
      background:${colors[i % colors.length]};
      left:${Math.random() * 100}%;
      top:${Math.random() * 100}%;
      animation-delay:${Math.random() * 4}s;
      animation-duration:${6 + Math.random() * 6}s;
    `;
    bg.appendChild(circle);
  }
}

// ---------------------------------------------------------------------------
// Model Sheet
// ---------------------------------------------------------------------------

function openModelSheet(): void {
  showModelSelectionSheet(ModelCategory.Language);
}

function onModelsChanged(_models: ModelInfo[]): void {
  const loaded = ModelManager.getLoadedModel(ModelCategory.Language);
  const textSpan = toolbarModelEl.querySelector('#chat-toolbar-model-text');
  if (loaded) {
    overlayEl.style.display = 'none';
    if (textSpan) textSpan.textContent = loaded.name;
  } else {
    overlayEl.style.display = '';
    if (textSpan) textSpan.textContent = 'Select Model';
  }
  updateEmptyState();
}

// ---------------------------------------------------------------------------
// Tool Calling Toggle
// ---------------------------------------------------------------------------

async function toggleTools(): Promise<void> {
  toolsEnabled = !toolsEnabled;
  toolsToggleBtn.classList.toggle('active', toolsEnabled);

  if (toolsEnabled && !toolsRegistered) {
    await registerDemoTools();
    toolsRegistered = true;
  }

  // Show/hide tools badge above input
  const badgeEl = container.querySelector('#chat-tools-badge') as HTMLElement;
  if (badgeEl) {
    if (toolsEnabled) {
      badgeEl.style.display = '';
      badgeEl.innerHTML = `
        <span class="tools-badge">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z"/></svg>
          Tools enabled &mdash; weather, time, calculator
        </span>
      `;
    } else {
      badgeEl.style.display = 'none';
      badgeEl.innerHTML = '';
    }
  }

  // Update suggestion chips to reflect tool-specific prompts
  renderSuggestions();

  console.log(`[Chat] Tools ${toolsEnabled ? 'enabled' : 'disabled'}`);
}

/**
 * Register demo tools matching iOS ToolSettingsView:
 * get_weather, get_current_time, calculate
 */
async function registerDemoTools(): Promise<void> {
  const { ToolCalling, toToolValue } = await import(
    '../../../../../sdk/runanywhere-web/packages/core/src/index'
  );

  // 1. get_weather - uses Open-Meteo API (free, no API key)
  ToolCalling.registerTool(
    {
      name: 'get_weather',
      description: 'Gets the current weather for a given location. Returns temperature, condition, humidity, and wind speed.',
      parameters: [
        { name: 'location', type: 'string', description: 'The city name to get weather for (e.g., "San Francisco")', required: true },
      ],
      category: 'Utility',
    },
    async (args): Promise<Record<string, ToolValue>> => {
      const location = args.location?.type === 'string' ? args.location.value : 'San Francisco';
      try {
        // Geocode the location
        const geoRes = await fetch(`https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(location)}&count=1`);
        const geoData = await geoRes.json();
        if (!geoData.results?.length) {
          return { error: toToolValue(`Location not found: ${location}`) };
        }
        const { latitude, longitude, name } = geoData.results[0];

        // Get weather
        const wxRes = await fetch(`https://api.open-meteo.com/v1/forecast?latitude=${latitude}&longitude=${longitude}&current=temperature_2m,relative_humidity_2m,wind_speed_10m,weather_code`);
        const wxData = await wxRes.json();
        const current = wxData.current;

        const conditionMap: Record<number, string> = {
          0: 'Clear sky', 1: 'Mainly clear', 2: 'Partly cloudy', 3: 'Overcast',
          45: 'Foggy', 48: 'Icy fog', 51: 'Light drizzle', 53: 'Drizzle', 55: 'Heavy drizzle',
          61: 'Light rain', 63: 'Rain', 65: 'Heavy rain', 71: 'Light snow', 73: 'Snow', 75: 'Heavy snow',
          80: 'Rain showers', 81: 'Rain showers', 82: 'Heavy showers', 95: 'Thunderstorm',
        };

        return {
          location: toToolValue(name),
          temperature_celsius: toToolValue(current.temperature_2m),
          temperature_fahrenheit: toToolValue(current.temperature_2m * 9 / 5 + 32),
          condition: toToolValue(conditionMap[current.weather_code] ?? 'Unknown'),
          humidity_percent: toToolValue(current.relative_humidity_2m),
          wind_speed_kmh: toToolValue(current.wind_speed_10m),
        };
      } catch (err) {
        return { error: toToolValue(err instanceof Error ? err.message : 'Failed to fetch weather') };
      }
    },
  );

  // 2. get_current_time - returns system time
  ToolCalling.registerTool(
    {
      name: 'get_current_time',
      description: 'Gets the current date and time with timezone information.',
      parameters: [
        { name: 'timezone', type: 'string', description: 'IANA timezone (e.g., "America/New_York"). Defaults to local timezone.', required: false },
      ],
      category: 'Utility',
    },
    async (args) => {
      const tz = args.timezone?.type === 'string' ? args.timezone.value : undefined;
      const now = new Date();
      const options: Intl.DateTimeFormatOptions = {
        weekday: 'long', year: 'numeric', month: 'long', day: 'numeric',
        hour: '2-digit', minute: '2-digit', second: '2-digit',
        ...(tz ? { timeZone: tz } : {}),
      };
      return {
        formatted: toToolValue(now.toLocaleDateString('en-US', options)),
        iso: toToolValue(now.toISOString()),
        timezone: toToolValue(tz ?? Intl.DateTimeFormat().resolvedOptions().timeZone),
        unix_timestamp: toToolValue(Math.floor(now.getTime() / 1000)),
      };
    },
  );

  // 3. calculate - evaluate math expressions
  ToolCalling.registerTool(
    {
      name: 'calculate',
      description: 'Evaluates a mathematical expression and returns the result. Supports basic arithmetic (+, -, *, /, ^), parentheses, and common functions.',
      parameters: [
        { name: 'expression', type: 'string', description: 'The math expression to evaluate (e.g., "2 + 3 * 4", "sqrt(16)", "(10 + 5) / 3")', required: true },
      ],
      category: 'Utility',
    },
    async (args): Promise<Record<string, ToolValue>> => {
      const expr = args.expression?.type === 'string' ? args.expression.value : '';
      try {
        // Safe evaluation using Function constructor with restricted scope
        const sanitized = expr
          .replace(/\^/g, '**')
          .replace(/sqrt\(/g, 'Math.sqrt(')
          .replace(/abs\(/g, 'Math.abs(')
          .replace(/sin\(/g, 'Math.sin(')
          .replace(/cos\(/g, 'Math.cos(')
          .replace(/tan\(/g, 'Math.tan(')
          .replace(/log\(/g, 'Math.log(')
          .replace(/pi/gi, 'Math.PI')
          .replace(/\be\b/g, 'Math.E');

        // Only allow safe characters
        if (!/^[0-9+\-*/().%\s,MathsqrtabsincotaglogPIE]+$/.test(sanitized)) {
          return { error: toToolValue('Invalid expression: contains unsafe characters') };
        }

        // eslint-disable-next-line no-new-func
        const result = new Function(`return (${sanitized})`)();
        return {
          expression: toToolValue(expr),
          result: toToolValue(Number(result)),
        };
      } catch (err) {
        return { error: toToolValue(err instanceof Error ? err.message : 'Evaluation failed') };
      }
    },
  );

  console.log('[Chat] Demo tools registered: get_weather, get_current_time, calculate');
}

// ---------------------------------------------------------------------------
// Empty State & Suggestions
// ---------------------------------------------------------------------------

const GENERAL_SUGGESTIONS = [
  'Tell me a fun fact',
  'Explain quantum computing simply',
  'Write a short poem about coding',
  'What are the benefits of meditation?',
];

const TOOL_SUGGESTIONS = [
  "What's the weather in Tokyo?",
  'What time is it in London?',
  'Calculate 2^10 + 15',
  "What's the weather in San Francisco?",
];

/** Show/hide the empty state based on whether there are messages. */
function updateEmptyState(): void {
  const emptyState = container.querySelector('#chat-empty-state') as HTMLElement | null;
  if (!emptyState) return;
  emptyState.style.display = messages.length === 0 ? '' : 'none';
}

/** Populate suggestion chips (general or tool-specific depending on toggle). */
function renderSuggestions(): void {
  const chipsEl = container.querySelector('#chat-suggestions');
  if (!chipsEl) return;

  const suggestions = toolsEnabled ? TOOL_SUGGESTIONS : GENERAL_SUGGESTIONS;
  chipsEl.innerHTML = suggestions.map(s =>
    `<button class="suggestion-chip">${escapeHtml(s)}</button>`,
  ).join('');

  // Wire up click handlers: fill input and send
  chipsEl.querySelectorAll('.suggestion-chip').forEach((chip, i) => {
    chip.addEventListener('click', () => {
      inputEl.value = suggestions[i];
      onInputChange();
      inputEl.focus();
    });
  });
}

/** Clear all messages and reset to empty state. */
function clearChat(): void {
  if (isGenerating && cancelGeneration) {
    cancelGeneration();
    cancelGeneration = null;
  }
  isGenerating = false;
  messages = [];
  messagesEl.innerHTML = `
    <div class="chat-empty-state" id="chat-empty-state">
      <div class="empty-logo">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="28" height="28"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>
      </div>
      <h3>Start a conversation</h3>
      <p>Type a message below to get started</p>
      <div class="suggestion-chips" id="chat-suggestions"></div>
    </div>
  `;
  renderSuggestions();
  inputEl.value = '';
  onInputChange();
  hideTypingIndicator();
  console.log('[Chat] Conversation cleared');
}

// ---------------------------------------------------------------------------
// Input Handling
// ---------------------------------------------------------------------------

function onInputChange(): void {
  const hasText = inputEl.value.trim().length > 0;
  sendBtn.disabled = !hasText || isGenerating;
  // Auto-resize
  inputEl.style.height = 'auto';
  inputEl.style.height = Math.min(inputEl.scrollHeight, 120) + 'px';
}

// ---------------------------------------------------------------------------
// Send Message
// ---------------------------------------------------------------------------

async function sendMessage(): Promise<void> {
  const text = inputEl.value.trim();
  if (!text || isGenerating) return;

  const loaded = ModelManager.getLoadedModel(ModelCategory.Language);
  if (!loaded) {
    openModelSheet();
    return;
  }

  // Hide empty state on first message
  updateEmptyState();

  // Add user message
  const userMsg: ChatMessage = {
    id: crypto.randomUUID(),
    role: 'user',
    content: text,
    timestamp: Date.now(),
  };
  messages.push(userMsg);
  updateEmptyState();
  renderMessage(userMsg);
  inputEl.value = '';
  onInputChange();

  // Show typing indicator
  isGenerating = true;
  sendBtn.disabled = true;
  showTypingIndicator();

  try {
    if (toolsEnabled) {
      await sendWithToolCalling(text, loaded);
    } else {
      await sendStreaming(text, loaded);
    }
  } catch (err) {
    hideTypingIndicator();

    const errorMessage = err instanceof Error ? err.message : String(err);
    console.error('[Chat] Generation failed:', errorMessage);

    const errorMsg: ChatMessage = {
      id: crypto.randomUUID(),
      role: 'assistant',
      content: `**Error:** ${errorMessage}\n\nPlease make sure a model is downloaded and loaded.`,
      timestamp: Date.now(),
      modelId: loaded.id,
    };
    messages.push(errorMsg);
    renderMessage(errorMsg);
  }

  isGenerating = false;
  sendBtn.disabled = inputEl.value.trim().length === 0;
}

/**
 * Standard streaming generation (no tools).
 */
async function sendStreaming(text: string, loaded: ModelInfo): Promise<void> {
  const { TextGeneration } = await import(
    '../../../../../sdk/runanywhere-web/packages/core/src/index'
  );

  if (!TextGeneration.isModelLoaded) {
    throw new Error('Model not loaded in WASM backend');
  }

  const { stream, result: resultPromise, cancel } = TextGeneration.generateStream(text, {
    maxTokens: 512,
    temperature: 0.7,
  });
  cancelGeneration = cancel;

  hideTypingIndicator();

  const assistantMsg: ChatMessage = {
    id: crypto.randomUUID(),
    role: 'assistant',
    content: '',
    timestamp: Date.now(),
    modelId: loaded.id,
  };
  messages.push(assistantMsg);
  const { bubbleEl, rowEl } = renderStreamingBubble(assistantMsg);

  for await (const token of stream) {
    assistantMsg.content += token;
    bubbleEl.innerHTML = renderMarkdown(assistantMsg.content);
    scrollToBottom();
    await new Promise(r => setTimeout(r, 12));
  }
  cancelGeneration = null;

  const finalResult = await resultPromise;
  console.log(
    `[Chat] Generation complete: ${finalResult.tokensUsed} tokens in ` +
    `${finalResult.latencyMs.toFixed(0)}ms (${finalResult.tokensPerSecond.toFixed(1)} tok/s)`,
  );

  appendMetrics(rowEl, {
    tokens: finalResult.tokensUsed,
    latencyMs: finalResult.latencyMs,
    tokensPerSecond: finalResult.tokensPerSecond,
  });
  scrollToBottom();
}

/**
 * Generation with tool calling enabled.
 */
async function sendWithToolCalling(text: string, loaded: ModelInfo): Promise<void> {
  const { ToolCalling } = await import(
    '../../../../../sdk/runanywhere-web/packages/core/src/index'
  );

  // Show "calling tools" indicator
  const typingEl = document.getElementById('typing-indicator');
  if (typingEl) {
    typingEl.querySelector('.typing-text')!.textContent = 'Thinking with tools...';
  }

  const result = await ToolCalling.generateWithTools(text, {
    maxToolCalls: 3,
    autoExecute: true,
    temperature: 0.3,
    maxTokens: 1024,
  });

  hideTypingIndicator();

  // Build tool call info for display
  const toolCallInfos: ToolCallInfo[] = result.toolCalls.map((tc, i) => {
    const tr = result.toolResults[i];
    const argsPlain: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(tc.arguments)) {
      argsPlain[k] = toolValueToPlain(v);
    }
    const resultPlain: Record<string, unknown> = {};
    if (tr?.result) {
      for (const [k, v] of Object.entries(tr.result)) {
        resultPlain[k] = toolValueToPlain(v);
      }
    }
    return {
      toolName: tc.toolName,
      arguments: JSON.stringify(argsPlain, null, 2),
      result: tr ? JSON.stringify(tr.success ? resultPlain : { error: tr.error }, null, 2) : undefined,
      success: tr?.success ?? false,
      error: tr?.error,
    };
  });

  const assistantMsg: ChatMessage = {
    id: crypto.randomUUID(),
    role: 'assistant',
    content: result.text,
    timestamp: Date.now(),
    modelId: loaded.id,
    toolCalls: toolCallInfos.length > 0 ? toolCallInfos : undefined,
  };
  messages.push(assistantMsg);
  renderMessage(assistantMsg);
}

/**
 * Convert ToolValue to plain JS for display.
 */
function toolValueToPlain(tv: { type: string; value?: unknown }): unknown {
  switch (tv.type) {
    case 'string': return tv.value;
    case 'number': return tv.value;
    case 'boolean': return tv.value;
    case 'null': return null;
    case 'array': return (tv.value as unknown[]).map((v) => toolValueToPlain(v as { type: string; value?: unknown }));
    case 'object': {
      const obj: Record<string, unknown> = {};
      for (const [k, v] of Object.entries(tv.value as Record<string, unknown>)) {
        obj[k] = toolValueToPlain(v as { type: string; value?: unknown });
      }
      return obj;
    }
    default: return tv.value;
  }
}

// ---------------------------------------------------------------------------
// Render Messages
// ---------------------------------------------------------------------------

function renderMessage(msg: ChatMessage): void {
  const row = document.createElement('div');
  row.className = `message-row ${msg.role}`;

  let html = '';

  if (msg.role === 'assistant' && msg.thinking) {
    html += `
      <div class="thinking-section" onclick="this.classList.toggle('expanded')">
        <div class="thinking-header">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="14" height="14"><path d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 1 1 7.072 0l-.548.547A3.374 3.374 0 0 0 12 18.469V19"/></svg>
          <span>Thinking...</span>
        </div>
        <div class="thinking-content">${escapeHtml(msg.thinking)}</div>
      </div>
    `;
  }

  // Tool call pills (before the response text)
  if (msg.toolCalls && msg.toolCalls.length > 0) {
    html += '<div class="tool-calls-container" style="margin-bottom:var(--space-sm);">';
    for (const tc of msg.toolCalls) {
      const statusClass = tc.success ? 'success' : 'error';
      const statusIcon = tc.success
        ? '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="20 6 9 17 4 12"/></svg>'
        : '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>';
      const pillId = `tool-pill-${msg.id}-${tc.toolName}`;
      const detailId = `tool-detail-${msg.id}-${tc.toolName}`;
      html += `
        <span class="tool-call-pill ${statusClass}" id="${pillId}">
          ${statusIcon}
          ${escapeHtml(tc.toolName)}
        </span>
      `;
      html += `
        <div class="tool-call-detail" id="${detailId}" style="display:none;">
          <h4>${escapeHtml(tc.toolName)}</h4>
          <div style="color:var(--text-secondary);font-size:var(--font-size-xs);margin-bottom:4px;">Arguments:</div>
          <pre>${escapeHtml(tc.arguments)}</pre>
          ${tc.result ? `<div style="color:var(--text-secondary);font-size:var(--font-size-xs);margin-bottom:4px;">Result:</div><pre>${escapeHtml(tc.result)}</pre>` : ''}
          ${tc.error ? `<div style="color:var(--color-red);font-size:var(--font-size-xs);">Error: ${escapeHtml(tc.error)}</div>` : ''}
        </div>
      `;
    }
    html += '</div>';
  }

  html += `<div class="message-bubble ${msg.role}">${renderMarkdown(msg.content)}</div>`;

  row.innerHTML = html;
  messagesEl.appendChild(row);

  // Attach click handlers for tool call pills to toggle detail views
  if (msg.toolCalls) {
    for (const tc of msg.toolCalls) {
      const pillId = `tool-pill-${msg.id}-${tc.toolName}`;
      const detailId = `tool-detail-${msg.id}-${tc.toolName}`;
      const pill = row.querySelector(`#${pillId}`);
      const detail = row.querySelector(`#${detailId}`);
      if (pill && detail) {
        pill.addEventListener('click', () => {
          const isVisible = (detail as HTMLElement).style.display !== 'none';
          (detail as HTMLElement).style.display = isVisible ? 'none' : 'block';
        });
      }
    }
  }

  scrollToBottom();
}

/**
 * Create a streaming assistant bubble (starts empty, tokens appended later).
 */
function renderStreamingBubble(msg: ChatMessage): { bubbleEl: HTMLElement; rowEl: HTMLElement } {
  const row = document.createElement('div');
  row.className = 'message-row assistant';

  let html = '';
  if (msg.modelId) {
    const displayName = formatModelName(msg.modelId);
    html += `<div class="model-badge">
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M9.75 3.104v5.714a2.25 2.25 0 0 1-.659 1.591L5 14.5M9.75 3.104c-.251.023-.501.05-.75.082m.75-.082a24.301 24.301 0 0 1 4.5 0m0 0v5.714c0 .597.237 1.17.659 1.591L19.8 15.3M14.25 3.104c.251.023.501.05.75.082M19.8 15.3l-1.57.393A9.065 9.065 0 0 1 12 15a9.065 9.065 0 0 0-6.23.693L5 14.5m14.8.8l1.402 1.402c1.232 1.232.65 3.318-1.067 3.611A48.309 48.309 0 0 1 12 21c-2.773 0-5.491-.235-8.135-.687-1.718-.293-2.3-2.379-1.067-3.61L5 14.5"/></svg>
      ${escapeHtml(displayName)}
    </div>`;
  }
  html += `<div class="message-bubble assistant" id="streaming-bubble-${msg.id}"></div>`;

  row.innerHTML = html;
  messagesEl.appendChild(row);
  scrollToBottom();

  const bubbleEl = row.querySelector<HTMLElement>(`#streaming-bubble-${msg.id}`)!;
  return { bubbleEl, rowEl: row };
}

/**
 * Append a metrics footer below a message bubble.
 */
function appendMetrics(rowEl: HTMLElement, metrics: {
  tokens: number;
  latencyMs: number;
  tokensPerSecond: number;
}): void {
  const metricsEl = document.createElement('div');
  metricsEl.className = 'message-metrics';
  metricsEl.innerHTML = `
    <span class="metric">
      <span class="metric-value">${metrics.tokensPerSecond.toFixed(1)}</span> tok/s
    </span>
    <span class="metric-separator">&middot;</span>
    <span class="metric">
      <span class="metric-value">${metrics.tokens}</span> tokens
    </span>
    <span class="metric-separator">&middot;</span>
    <span class="metric">
      <span class="metric-value">${(metrics.latencyMs / 1000).toFixed(1)}s</span>
    </span>
  `;
  rowEl.appendChild(metricsEl);
}

/**
 * Format a model ID into a shorter, display-friendly name.
 */
function formatModelName(modelId: string): string {
  const loaded = ModelManager.getLoadedModel(ModelCategory.Language);
  if (loaded && loaded.id === modelId) return loaded.name;
  return modelId
    .replace(/-q\d.*$/i, '')
    .replace(/-/g, ' ')
    .replace(/\b\w/g, c => c.toUpperCase());
}

function showTypingIndicator(): void {
  const indicator = document.createElement('div');
  indicator.className = 'message-row assistant';
  indicator.id = 'typing-indicator';
  indicator.innerHTML = `
    <div class="typing-indicator">
      <div class="typing-dots">
        <div class="typing-dot"></div>
        <div class="typing-dot"></div>
        <div class="typing-dot"></div>
      </div>
      <span class="typing-text">AI is thinking...</span>
    </div>
  `;
  messagesEl.appendChild(indicator);
  scrollToBottom();
}

function hideTypingIndicator(): void {
  const indicator = document.getElementById('typing-indicator');
  indicator?.remove();
}

function scrollToBottom(): void {
  messagesEl.scrollTop = messagesEl.scrollHeight;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function escapeHtml(str: string): string {
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function renderMarkdown(text: string): string {
  return escapeHtml(text)
    .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
    .replace(/\*(.*?)\*/g, '<em>$1</em>')
    .replace(/`(.*?)`/g, '<code style="background:rgba(0,0,0,0.2);padding:1px 4px;border-radius:3px;font-family:var(--font-mono);font-size:0.85em;">$1</code>')
    .replace(/\n/g, '<br>');
}
