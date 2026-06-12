/**
 * Chat Tab — LLM chat over the V2 proto-byte LLM adapter.
 *
 * Mirrors the iOS chat experience (LLMViewModel + ChatMessageComponents):
 *   - Generation options come from the Settings tab (temperature, maxTokens,
 *     systemPrompt, thinking mode) — iOS parity: LLMViewModel.swift:579-619
 *     getGenerationOptions().
 *   - Thinking content renders as a collapsible section per assistant
 *     message — iOS parity: ChatMessageComponents.swift:87-179.
 *   - Optional tool calling with the same three demo tools as iOS
 *     (get_weather / get_current_time / calculate) — iOS parity:
 *     ToolSettingsView.swift:32-139 + LLMViewModel+ToolCalling.swift.
 *   - Conversation persists to localStorage — minimal mirror of iOS
 *     ConversationStore semantics (save on update, restore on mount).
 *
 * The toolbar model pill + "Get Started" overlay are built by
 * `components/model-selection.ts`. They expose the DOM ids the readiness
 * probe in `main.ts` looks for (`#chat-toolbar-model`, `#chat-model-overlay`,
 * `#chat-get-started-btn`).
 */

import type { TabLifecycle } from '../app';
import {
  ModelCategory,
  RunAnywhere,
  ToolParameterType,
  isSDKException,
  type ToolDefinition,
  type ToolValue,
} from '@runanywhere/web';
import {
  buildGetStartedOverlay,
  buildToolbarModelButton,
  onModelStateChange,
  type OpenSheetOptions,
} from '../components/model-selection';
import { getGenerationSettings } from './settings';
import { escapeHtml } from '../services/escape-html';
import { formatError } from '../services/format-error';

interface ChatToolCallInfo {
  name: string;
  argumentsJson: string;
  resultJson?: string;
  error?: string;
}

interface ChatMessage {
  role: 'user' | 'assistant';
  content: string;
  /** Reasoning content shown in the collapsible "Thinking" section. */
  thinking?: string;
  /** Tool calls + results when the message came from generateWithTools. */
  toolCalls?: ChatToolCallInfo[];
}

// Chat's picker is scoped to LLMs — iOS parity:
// ModelSelectionSheet(context: .llm) used by the chat screen.
const CHAT_SHEET_OPTIONS: OpenSheetOptions = {
  title: 'Select Model',
  filterCategories: [ModelCategory.MODEL_CATEGORY_LANGUAGE],
};

// Minimal localStorage-backed conversation persistence — mirrors iOS
// ConversationStore (Core/Services/ConversationStore.swift) semantics at MVP
// scope: one current conversation, saved on update, restored on mount.
const CONVERSATION_STORAGE_KEY = 'runanywhere-chat-conversation';
// iOS parity: ToolSettingsView.swift:23 persists "toolCallingEnabled".
const TOOLS_ENABLED_STORAGE_KEY = 'runanywhere-tool-calling-enabled';

let container: HTMLElement;
let messages: ChatMessage[] = [];
let isGenerating = false;
let cancelGeneration: (() => void) | null = null;
let toolsEnabled = false;

export function initChatTab(el: HTMLElement): TabLifecycle {
  container = el;

  messages = loadConversation();
  toolsEnabled = loadToolsEnabled();

  // Register the demo tools once at chat setup — iOS parity:
  // ToolSettingsViewModel.registerDemoTools (ToolSettingsView.swift:153-159).
  registerDemoTools();

  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title" id="chat-toolbar-title-host"></div>
      <div class="toolbar-actions" id="chat-toolbar-actions-host"></div>
    </div>
    <div class="scroll-area" id="chat-messages"></div>
    <div class="chat-input-area">
      <textarea class="chat-input" id="chat-input" placeholder="Message..." rows="1"></textarea>
      <button class="send-btn" id="chat-send-btn" disabled>
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" width="20" height="20"><path d="M2.01 21L23 12 2.01 3 2 10l15 2-15 2z"/></svg>
      </button>
    </div>
  `;

  // Mount the toolbar model pill in the title slot so the probe finds the
  // #chat-toolbar-model element even when the panel becomes the active tab.
  const titleHost = container.querySelector('#chat-toolbar-title-host') as HTMLElement;
  titleHost.appendChild(buildToolbarModelButton(CHAT_SHEET_OPTIONS));

  // Mount the "Get Started" overlay directly inside the panel host so the
  // readiness probe's overlay visibility check works. The overlay is shown
  // whenever no model is loaded and hidden once a model enters the loaded
  // state.
  container.appendChild(buildGetStartedOverlay(CHAT_SHEET_OPTIONS));

  const messagesEl = container.querySelector('#chat-messages') as HTMLElement;
  const inputEl = container.querySelector('#chat-input') as HTMLTextAreaElement;
  const sendBtn = container.querySelector('#chat-send-btn') as HTMLButtonElement;
  const actionsHost = container.querySelector('#chat-toolbar-actions-host') as HTMLElement;
  const toolsBtn = buildToolsToggleButton();
  const clearBtn = buildClearButton();
  actionsHost.appendChild(toolsBtn);
  actionsHost.appendChild(clearBtn);

  const refreshToolsButton = () => {
    toolsBtn.textContent = toolsEnabled ? 'Tools: On' : 'Tools: Off';
    toolsBtn.classList.toggle('btn-primary', toolsEnabled);
    toolsBtn.classList.toggle('btn-secondary', !toolsEnabled);
    toolsBtn.title = toolsEnabled
      ? 'Tool calling enabled (weather, time, calculator)'
      : 'Enable tool calling (weather, time, calculator)';
  };
  refreshToolsButton();

  const refreshSendButton = () => {
    const hasInput = inputEl.value.trim().length > 0;
    const modelLoaded = isModelLoaded();
    sendBtn.disabled = isGenerating || !hasInput || !modelLoaded;
    // Tooltip clarifies why the button is disabled. The textbox stays
    // enabled so users may compose while a model is loading.
    if (!modelLoaded) {
      sendBtn.title = 'Load a model first';
    } else if (!hasInput) {
      sendBtn.title = 'Type a message to send';
    } else if (isGenerating) {
      sendBtn.title = 'Generation in progress';
    } else {
      sendBtn.title = 'Send';
    }
  };

  inputEl.addEventListener('input', refreshSendButton);
  inputEl.addEventListener('keydown', (event) => {
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault();
      void onSend();
    }
  });
  sendBtn.addEventListener('click', () => {
    void onSend();
  });
  toolsBtn.addEventListener('click', () => {
    toolsEnabled = !toolsEnabled;
    saveToolsEnabled(toolsEnabled);
    refreshToolsButton();
  });
  clearBtn.addEventListener('click', () => {
    if (cancelGeneration) cancelGeneration();
    messages = [];
    clearConversation();
    renderMessages(messagesEl);
  });

  renderMessages(messagesEl);

  // Apply the initial disabled / tooltip state so the Send button reflects
  // "Load a model first" before any user interaction.
  refreshSendButton();

  // Re-render when the model state changes so disabled/enabled states stay
  // consistent with what the toolbar reports.
  const unsubscribeState = onModelStateChange(() => refreshSendButton());

  async function onSend(): Promise<void> {
    const prompt = inputEl.value.trim();
    if (!prompt || isGenerating) return;

    if (!isLLMBackendAvailable()) {
      messages.push({
        role: 'assistant',
        content: 'No LLM backend available. Check the console for backend load errors.',
      });
      renderMessages(messagesEl);
      return;
    }

    inputEl.value = '';
    refreshSendButton();

    messages.push({ role: 'user', content: prompt });
    const assistantMsg: ChatMessage = { role: 'assistant', content: '' };
    messages.push(assistantMsg);
    saveConversation();
    renderMessages(messagesEl);

    isGenerating = true;
    refreshSendButton();

    try {
      if (toolsEnabled) {
        await generateWithToolCalling(prompt, assistantMsg, messagesEl);
      } else {
        await generateStreaming(prompt, assistantMsg, messagesEl);
      }
    } catch (error) {
      assistantMsg.content = formatChatError(error);
      renderLastMessage(messagesEl, assistantMsg);
    } finally {
      cancelGeneration = null;
      isGenerating = false;
      saveConversation();
      refreshSendButton();
    }
  }

  // Tear down the model-state subscription if the panel element ever
  // detaches (e.g. a full app-shell re-render). Kept minimal since the
  // tab framework does not call a dispose hook today.
  const disposeObserver = new MutationObserver(() => {
    if (!container.isConnected) {
      disposeObserver.disconnect();
      unsubscribeState();
    }
  });
  const rootParent = container.parentElement;
  if (rootParent) disposeObserver.observe(rootParent, { childList: true });

  return {
    onDeactivate: () => {
      if (cancelGeneration) cancelGeneration();
    },
  };
}

// ---------------------------------------------------------------------------
// Generation
// ---------------------------------------------------------------------------

/**
 * Build generation options from the Settings tab — iOS parity:
 * LLMViewModel.swift:579-619 getGenerationOptions(). `disableThinking` is the
 * same structured gate as iOS (LLMViewModel.swift:618): suppress the thinking
 * phase only when the loaded model supports thinking AND the user toggle is
 * off — commons applies the model's no-think directive; the app never injects
 * control tokens into prompts.
 */
function buildGenerationOptions(): {
  maxTokens: number;
  temperature: number;
  systemPrompt?: string;
  disableThinking: boolean;
} {
  const settings = getGenerationSettings();
  const systemPrompt = settings.systemPrompt.trim();
  return {
    maxTokens: settings.maxTokens,
    temperature: settings.temperature,
    ...(systemPrompt.length > 0 ? { systemPrompt } : {}),
    disableThinking: loadedModelSupportsThinking() && !settings.thinkingModeEnabled,
  };
}

async function generateStreaming(
  prompt: string,
  assistantMsg: ChatMessage,
  messagesEl: HTMLElement,
): Promise<void> {
  const options = buildGenerationOptions();
  const stream = await RunAnywhere.generateStream({
    prompt,
    ...options,
  });
  cancelGeneration = stream.cancel;

  let raw = '';
  for await (const token of stream.stream) {
    raw += token;
    // Thinking-capable models stream `<think>…</think>` inline; split it
    // into the collapsible section live (iOS receives the split from
    // commons; the Web stream carries raw tokens).
    const split = splitThinking(raw);
    assistantMsg.content = split.content;
    assistantMsg.thinking = split.thinking || undefined;
    renderLastMessage(messagesEl, assistantMsg);
  }

  const result = await stream.result;
  // Prefer the structured thinkingContent from the final result when the
  // backend separates it (same field iOS reads: result.thinkingContent).
  if (result.thinkingContent) {
    assistantMsg.thinking = result.thinkingContent;
    assistantMsg.content = splitThinking(result.text || raw).content;
  }
  renderLastMessage(messagesEl, assistantMsg);
}

/**
 * Tool-calling send path — iOS parity: LLMViewModel+ToolCalling.swift:14-35.
 * The SDK (commons) orchestrates the tool call → execute → respond loop;
 * the app only renders the result.
 */
async function generateWithToolCalling(
  prompt: string,
  assistantMsg: ChatMessage,
  messagesEl: HTMLElement,
): Promise<void> {
  const options = buildGenerationOptions();
  const controller = new AbortController();
  cancelGeneration = () => controller.abort();

  const result = await RunAnywhere.generateWithTools(prompt, {}, {
    signal: controller.signal,
    llmOptions: options,
  });

  const split = splitThinking(result.text);
  assistantMsg.content = split.content;
  assistantMsg.thinking = result.thinkingContent || split.thinking || undefined;
  if (result.toolCalls.length > 0) {
    assistantMsg.toolCalls = result.toolCalls.map((call) => {
      const toolResult = result.toolResults.find(
        (r) => r.name === call.name
          && (!r.toolCallId || !call.id || r.toolCallId === call.id),
      );
      return {
        name: call.name,
        argumentsJson: call.argumentsJson,
        resultJson: toolResult?.resultJson,
        error: toolResult && !toolResult.success ? (toolResult.error || 'failed') : undefined,
      };
    });
  }
  renderLastMessage(messagesEl, assistantMsg);
}

// ---------------------------------------------------------------------------
// Demo tools — iOS parity: ToolSettingsView.swift:32-139 (weather via
// Open-Meteo, system time, safe calculator). Executors receive PARSED args
// (Record<string, ToolValue>) and return Record<string, ToolValue>.
// ---------------------------------------------------------------------------

let demoToolsRegistered = false;

function registerDemoTools(): void {
  if (demoToolsRegistered) return;
  demoToolsRegistered = true;

  RunAnywhere.toolCalling.registerTool(
    toolDefinition(
      'get_weather',
      'Gets the current weather for a given location using Open-Meteo API',
      [stringParameter('location', "City name (e.g., 'San Francisco', 'London', 'Tokyo')")],
    ),
    async (args) => fetchWeather(toolValueString(args.location) ?? 'San Francisco'),
  );

  RunAnywhere.toolCalling.registerTool(
    toolDefinition(
      'get_current_time',
      'Gets the current date, time, and timezone information',
      [],
    ),
    () => {
      const now = new Date();
      return {
        datetime: tv(now.toLocaleString(undefined, { dateStyle: 'full', timeStyle: 'medium' })),
        time: tv(now.toLocaleTimeString(undefined, { hour12: false })),
        timestamp: tv(now.toISOString()),
        timezone: tv(Intl.DateTimeFormat().resolvedOptions().timeZone),
        utc_offset: tv(`UTC${now.getTimezoneOffset() <= 0 ? '+' : '-'}${Math.abs(now.getTimezoneOffset() / 60)}`),
      };
    },
  );

  RunAnywhere.toolCalling.registerTool(
    toolDefinition(
      'calculate',
      'Performs math calculations. Supports +, -, *, /, and parentheses',
      [stringParameter('expression', "Math expression (e.g., '2 + 2 * 3', '(10 + 5) / 3')")],
    ),
    (args): Record<string, ToolValue> => {
      // iOS parity (ToolSettingsView.swift:93-137): accept the expression
      // from common alternative keys, clean unicode operators, evaluate
      // deterministically (no eval()).
      const expression = toolValueString(args.expression)
        ?? toolValueString(args.input)
        ?? toolValueString(args.expr)
        ?? '';
      if (!expression) {
        return { error: tv('Missing expression argument') };
      }
      const cleaned = expression
        .replace(/=/g, '')
        .replace(/x/gi, '*')
        .replace(/×/g, '*')
        .replace(/÷/g, '/')
        .trim();
      const value = safeMathEvaluate(cleaned);
      if (value !== null) {
        return { result: tv(value), expression: tv(expression) };
      }
      return {
        error: tv(`Could not evaluate expression: ${expression}`),
        expression: tv(expression),
      };
    },
  );
}

function toolDefinition(
  name: string,
  description: string,
  parameters: ToolDefinition['parameters'],
): ToolDefinition {
  return {
    name,
    description,
    parameters,
    category: 'Utility',
    metadata: {},
  };
}

function stringParameter(name: string, description: string): ToolDefinition['parameters'][number] {
  return {
    name,
    type: ToolParameterType.TOOL_PARAMETER_TYPE_STRING,
    description,
    required: true,
    enumValues: [],
  };
}

function tv(value: string | number | boolean): ToolValue {
  if (typeof value === 'string') return { stringValue: value };
  if (typeof value === 'number') return { numberValue: value };
  return { boolValue: value };
}

function toolValueString(value: ToolValue | undefined): string | null {
  if (!value) return null;
  if (value.stringValue !== undefined) return value.stringValue;
  if (value.numberValue !== undefined) return String(value.numberValue);
  return null;
}

/**
 * Real weather lookup via Open-Meteo (free, no API key) — iOS parity:
 * WeatherService (ToolSettingsView.swift:333-443). External demo call, not
 * SDK auth/download traffic.
 */
async function fetchWeather(location: string): Promise<Record<string, ToolValue>> {
  const geoUrl = `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(location)}&count=1&language=en&format=json`;
  const geoResponse = await fetch(geoUrl);
  const geo = await geoResponse.json() as {
    results?: Array<{ latitude: number; longitude: number; name?: string }>;
  };
  const first = geo.results?.[0];
  if (!first) {
    return {
      error: tv(`Could not find location: ${location}`),
      location: tv(location),
    };
  }

  const weatherUrl = 'https://api.open-meteo.com/v1/forecast'
    + `?latitude=${first.latitude}&longitude=${first.longitude}`
    + '&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m'
    + '&temperature_unit=fahrenheit&wind_speed_unit=mph';
  const weatherResponse = await fetch(weatherUrl);
  const weather = await weatherResponse.json() as {
    current?: {
      temperature_2m?: number;
      relative_humidity_2m?: number;
      weather_code?: number;
      wind_speed_10m?: number;
    };
  };
  const current = weather.current;
  if (!current) {
    return { error: tv('Could not parse weather data') };
  }

  return {
    location: tv(first.name ?? location),
    temperature: tv(current.temperature_2m ?? 0),
    unit: tv('fahrenheit'),
    humidity: tv(current.relative_humidity_2m ?? 0),
    wind_speed_mph: tv(current.wind_speed_10m ?? 0),
    condition: tv(weatherCodeToCondition(current.weather_code ?? 0)),
  };
}

/** WMO weather code → condition — iOS parity: ToolSettingsView.swift:423-442. */
function weatherCodeToCondition(code: number): string {
  if (code === 0) return 'Clear sky';
  if (code === 1) return 'Mainly clear';
  if (code === 2) return 'Partly cloudy';
  if (code === 3) return 'Overcast';
  if (code === 45 || code === 48) return 'Foggy';
  if (code >= 51 && code <= 55) return 'Drizzle';
  if (code === 56 || code === 57) return 'Freezing drizzle';
  if (code === 61 || code === 63 || code === 65) return 'Rain';
  if (code === 66 || code === 67) return 'Freezing rain';
  if (code === 71 || code === 73 || code === 75) return 'Snow';
  if (code === 77) return 'Snow grains';
  if (code >= 80 && code <= 82) return 'Rain showers';
  if (code === 85 || code === 86) return 'Snow showers';
  if (code === 95) return 'Thunderstorm';
  if (code === 96 || code === 99) return 'Thunderstorm with hail';
  return 'Unknown';
}

// ---------------------------------------------------------------------------
// Safe math evaluator — iOS parity: SafeMathEvaluator
// (ToolSettingsView.swift:455-570). Deterministic recursive-descent parser;
// never uses eval(). Grammar: expr := term (("+"|"-") term)*;
// term := factor (("*"|"/") factor)*; factor := ("+"|"-") factor | primary;
// primary := number | "(" expr ")".
// ---------------------------------------------------------------------------

function safeMathEvaluate(expression: string): number | null {
  let index = 0;

  const skipWhitespace = (): void => {
    while (index < expression.length && /\s/.test(expression[index])) index += 1;
  };
  const peek = (): string | null => {
    skipWhitespace();
    return index < expression.length ? expression[index] : null;
  };
  const match = (char: string): boolean => {
    if (peek() === char) {
      index += 1;
      return true;
    }
    return false;
  };

  const parseNumber = (): number | null => {
    skipWhitespace();
    const start = index;
    let seenDot = false;
    while (index < expression.length) {
      const char = expression[index];
      if (/\d/.test(char)) {
        index += 1;
      } else if (char === '.' && !seenDot) {
        seenDot = true;
        index += 1;
      } else {
        break;
      }
    }
    if (index === start) return null;
    const value = Number(expression.slice(start, index));
    return Number.isFinite(value) ? value : null;
  };

  const parsePrimary = (): number | null => {
    if (match('(')) {
      const value = parseExpression();
      if (value === null || !match(')')) return null;
      return value;
    }
    return parseNumber();
  };

  const parseFactor = (): number | null => {
    if (match('+')) return parseFactor();
    if (match('-')) {
      const value = parseFactor();
      return value === null ? null : -value;
    }
    return parsePrimary();
  };

  const parseTerm = (): number | null => {
    let value = parseFactor();
    if (value === null) return null;
    for (let op = peek(); op === '*' || op === '/'; op = peek()) {
      index += 1;
      const rhs = parseFactor();
      if (rhs === null) return null;
      if (op === '/') {
        if (rhs === 0) return null;
        value /= rhs;
      } else {
        value *= rhs;
      }
    }
    return value;
  };

  const parseExpression = (): number | null => {
    let value = parseTerm();
    if (value === null) return null;
    for (let op = peek(); op === '+' || op === '-'; op = peek()) {
      index += 1;
      const rhs = parseTerm();
      if (rhs === null) return null;
      value = op === '+' ? value + rhs : value - rhs;
    }
    return value;
  };

  const result = parseExpression();
  skipWhitespace();
  if (result === null || index < expression.length || !Number.isFinite(result)) {
    return null;
  }
  return result;
}

// ---------------------------------------------------------------------------
// Conversation persistence (localStorage; mirrors iOS ConversationStore at
// MVP scope — Core/Services/ConversationStore.swift)
// ---------------------------------------------------------------------------

function loadConversation(): ChatMessage[] {
  try {
    const saved = localStorage.getItem(CONVERSATION_STORAGE_KEY);
    if (!saved) return [];
    const parsed = JSON.parse(saved) as { messages?: ChatMessage[] };
    return Array.isArray(parsed.messages) ? parsed.messages : [];
  } catch {
    return [];
  }
}

function saveConversation(): void {
  try {
    localStorage.setItem(
      CONVERSATION_STORAGE_KEY,
      JSON.stringify({ messages, updatedAt: Date.now() }),
    );
  } catch { /* storage may not be available */ }
}

function clearConversation(): void {
  try {
    localStorage.removeItem(CONVERSATION_STORAGE_KEY);
  } catch { /* storage may not be available */ }
}

function loadToolsEnabled(): boolean {
  try {
    return localStorage.getItem(TOOLS_ENABLED_STORAGE_KEY) === 'true';
  } catch {
    return false;
  }
}

function saveToolsEnabled(enabled: boolean): void {
  try {
    localStorage.setItem(TOOLS_ENABLED_STORAGE_KEY, String(enabled));
  } catch { /* storage may not be available */ }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function isLLMBackendAvailable(): boolean {
  try {
    return RunAnywhere.textGeneration.supportsProtoLLM();
  } catch {
    return false;
  }
}

/**
 * True when the C++ lifecycle reports an LLM loaded. Used to gate the chat
 * Send button so users can't click into a silent no-op before loading a
 * model from the toolbar picker.
 */
function isModelLoaded(): boolean {
  try {
    const current = RunAnywhere.currentModel({
      category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
      includeModelMetadata: false,
    });
    return Boolean(current?.modelId);
  } catch {
    return false;
  }
}

/**
 * Whether the loaded LLM supports a thinking phase — read from the registry
 * record, same source iOS uses (LLMViewModel `loadedModelSupportsThinking`).
 */
function loadedModelSupportsThinking(): boolean {
  try {
    const current = RunAnywhere.currentModel({
      category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
      includeModelMetadata: false,
    });
    if (!current?.modelId) return false;
    return RunAnywhere.getModel(current.modelId)?.supportsThinking ?? false;
  } catch {
    return false;
  }
}

/**
 * Split `<think>…</think>` sections out of raw model text. Handles an
 * unterminated `<think>` while tokens are still streaming. iOS receives the
 * split from commons (result.thinkingContent); the Web stream carries raw
 * tokens, so the view performs the same tag split client-side.
 */
function splitThinking(raw: string): { content: string; thinking: string } {
  const thinkingParts: string[] = [];
  const content = raw.replace(
    /<think>([\s\S]*?)(<\/think>|$)/g,
    (_match, inner: string) => {
      if (inner.trim().length > 0) thinkingParts.push(inner.trim());
      return '';
    },
  );
  return { content: content.trim(), thinking: thinkingParts.join('\n\n') };
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

function renderMessages(host: HTMLElement): void {
  if (messages.length === 0) {
    host.innerHTML = `
      <div class="chat-empty-state">
        <h3>Start chatting</h3>
        <p>Type a message below. Generation streams token-by-token through the
        proto-byte LLM adapter.</p>
      </div>
    `;
    return;
  }

  host.innerHTML = messages.map((msg, idx) => `
    <div class="chat-message chat-message--${msg.role}" data-idx="${idx}">
      ${renderMessageBody(msg)}
    </div>
  `).join('');

  host.scrollTop = host.scrollHeight;
}

function renderLastMessage(host: HTMLElement, msg: ChatMessage): void {
  const last = host.lastElementChild;
  if (last) {
    last.innerHTML = renderMessageBody(msg);
  }
  host.scrollTop = host.scrollHeight;
}

function renderMessageBody(msg: ChatMessage): string {
  // Collapsible thinking section — iOS parity:
  // ChatMessageComponents.swift:128-181 (thinkingSection).
  const thinkingSection = msg.role === 'assistant' && msg.thinking
    ? `
      <details class="chat-thinking">
        <summary>Thinking</summary>
        <pre class="chat-thinking-content">${escapeHtml(msg.thinking)}</pre>
      </details>
    `
    : '';

  const toolSection = msg.role === 'assistant' && msg.toolCalls?.length
    ? msg.toolCalls.map((call) => `
        <div class="chat-tool-call">
          <span class="chat-tool-call-name">Tool: ${escapeHtml(call.name)}(${escapeHtml(call.argumentsJson)})</span>
          ${call.error
            ? `<span class="error"> failed: ${escapeHtml(call.error)}</span>`
            : call.resultJson
              ? `<span class="chat-tool-call-result"> &rarr; ${escapeHtml(call.resultJson)}</span>`
              : ''}
        </div>
      `).join('')
    : '';

  const body = msg.content
    ? renderMarkdownLite(msg.content)
    : (msg.thinking
      ? '<span class="chat-bubble-typing">Thinking&hellip;</span>'
      : '<span class="chat-bubble-typing">&hellip;</span>');

  return `${thinkingSection}${toolSection}<div class="chat-bubble">${body}</div>`;
}

/**
 * Minimal markdown rendering on top of escapeHtml (kept dependency-free):
 * fenced code blocks, inline code, and bold. Everything passes through
 * escapeHtml first, so model output can never inject markup.
 */
function renderMarkdownLite(text: string): string {
  const codeBlocks: string[] = [];
  const escaped = escapeHtml(text);
  // Fenced code blocks (tolerates an unterminated fence while streaming).
  let html = escaped.replace(/```[^\n`]*\n?([\s\S]*?)(?:```|$)/g, (_match, code: string) => {
    codeBlocks.push(`<pre class="chat-code"><code>${code.replace(/\n$/, '')}</code></pre>`);
    return `\u0000${codeBlocks.length - 1}\u0000`;
  });
  html = html
    .replace(/`([^`\n]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*\n]+)\*\*/g, '<strong>$1</strong>')
    .replace(/\n/g, '<br>');
  return html.replace(/\u0000(\d+)\u0000/g, (_match, i: string) => codeBlocks[Number(i)]);
}

function formatChatError(error: unknown): string {
  if (isSDKException(error)) {
    return `Error: ${error.message}`;
  }
  return `Error: ${formatError(error)}`;
}

function buildToolsToggleButton(): HTMLButtonElement {
  const btn = document.createElement('button');
  btn.type = 'button';
  btn.id = 'chat-tools-btn';
  btn.className = 'btn btn-secondary';
  return btn;
}

function buildClearButton(): HTMLButtonElement {
  const btn = document.createElement('button');
  btn.type = 'button';
  btn.id = 'chat-clear-btn';
  btn.className = 'btn btn-secondary';
  btn.textContent = 'Clear';
  return btn;
}
